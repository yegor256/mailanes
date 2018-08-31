# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'yaml'
require 'mail'
require 'uuidtools'
require 'liquid'
require 'redcarpet'
require 'redcarpet/render_strip'
require 'glogin/codec'
require_relative 'pgsql'

# Letter.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Letter
  attr_reader :id

  def initialize(id:, pgsql: Pgsql.new, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash
  end

  def lane
    hash = @pgsql.exec(
      'SELECT lane.* FROM lane JOIN letter ON letter.lane=lane.id WHERE letter.id=$1',
      [@id]
    )[0]
    Lane.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def title
    yaml['title'] || "##{id}"
  end

  def delivered_count
    @pgsql.exec('SELECT COUNT(id) FROM delivery WHERE delivery.letter=$1', [@id])[0]['count']
  end

  def active?
    (@hash['active'] || @pgsql.exec('SELECT active FROM letter WHERE id=$1', [@id])[0]['active']) == 't'
  end

  def liquid
    @hash['liquid'] || @pgsql.exec('SELECT liquid FROM letter WHERE id=$1', [@id])[0]['liquid']
  end

  def yaml
    YAML.safe_load(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM letter WHERE id=$1', [@id])[0]['yaml']
    )
  end

  def toggle
    @pgsql.exec('UPDATE letter SET active=not(active) WHERE id=$1', [@id])
    @hash = {}
  end

  def up
    @pgsql.exec('UPDATE letter SET place=place+1 WHERE id=$1', [@id])
    @hash = {}
  end

  def save_liquid(liquid)
    @pgsql.exec('UPDATE letter SET liquid=$1 WHERE id=$2', [liquid, @id])
    @hash = {}
  end

  def save_yaml(yaml)
    YAML.safe_load(yaml)
    @pgsql.exec('UPDATE letter SET yaml=$1 WHERE id=$2', [yaml, @id])
    @hash = {}
  end

  def deliver(recipient, codec = GLogin::Codec.new(''))
    template = Liquid::Template.parse(liquid)
    token = codec.encrypt(recipient.id.to_s)
    markdown = template.render(
      'email' => recipient.email,
      'first' => recipient.first,
      'last' => recipient.last,
      'token' => token,
      'unsubscribe' => "https://www.mailanes.com/unsubscribe?token=#{CGI.escape(token)}",
      'id' => id
    )
    html = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(markdown)
    text = Redcarpet::Markdown.new(Redcarpet::Render::StripDown).render(markdown)
    ln = lane
    name = "#{recipient.first.strip} #{recipient.last.strip}".strip
    to = recipient.email
    to = "#{name} <#{recipient.email}>" unless name.empty?
    from = yaml['from'] || ln.yaml['from']
    subject = yaml['subject'] || ln.yaml['subject']
    mail = Mail.new do
      from from
      to to
      subject subject
      message_id "<#{UUIDTools::UUID.random_create}@mailanes.com>"
      text_part do
        content_type 'text/plain; charset=UTF-8'
        body text
      end
      html_part do
        content_type 'text/html; charset=UTF-8'
        body html
      end
    end
    mail.delivery_method(
      :smtp,
      address: ln.yaml['smtp']['host'],
      port: ln.yaml['smtp']['port'].to_i,
      domain: ln.yaml['smtp']['host'],
      user_name: ln.yaml['smtp']['user'],
      password: ln.yaml['smtp']['password'],
      authentication: 'plain',
      enable_starttls_auto: true
    )
    start = Time.now
    mail.deliver
    [
      "Sent #{html.length} chars in HTML (#{text.length} in plain text)",
      "to #{to} (recipient ##{recipient.id} in list ##{recipient.list.id})",
      "from #{from}, with the subject line \"#{subject}\",",
      "via SMTP at #{ln.yaml['smtp']['host']}:#{ln.yaml['smtp']['port']}",
      "(authenticated as #{ln.yaml['smtp']['user']}),",
      "in #{(Time.now - start).round(2)}s"
    ].join(' ')
  end
end
