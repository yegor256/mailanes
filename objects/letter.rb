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
require_relative 'campaign'

# Letter.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Letter
  attr_reader :id

  def initialize(id:, pgsql: Pgsql::TEST, hash: {}, tbot: Tbot.new)
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash
    @tbot = tbot
  end

  def lane
    id = @hash['lane'] || @pgsql.exec('SELECT lane FROM letter WHERE id=$1', [@id])[0]['lane']
    Lane.new(
      id: id.to_i,
      pgsql: @pgsql
    )
  end

  def campaigns
    q = [
      'SELECT * FROM campaign',
      'JOIN letter ON letter.lane=campaign.lane',
      'WHERE letter.id=$1'
    ].join(' ')
    @pgsql.exec(q, [@id]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def title
    yaml['title'] || "##{id}"
  end

  def deliveries_count
    @pgsql.exec('SELECT COUNT(id) FROM delivery WHERE letter=$1', [@id])[0]['count'].to_i
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

  def deliver(recipient, codec = GLogin::Codec.new(''), delivery: nil)
    content = markdown(liquid, codec, recipient, delivery)
    if yaml['transport'].nil? || yaml['transport'].casecmp('smtp').zero?
      deliver_smtp(content, recipient, codec, delivery)
    elsif yaml['transport'].casecmp('telegram').zero?
      deliver_telegram(content)
    else
      raise "Unknown transport \"#{yaml['transport']}\" for the letter ##{@id}"
    end
  end

  private

  def deliver_telegram(content)
    chat = lane.yaml['telegram']['chat_id'].to_i
    start = Time.now
    @tbot.post(chat, content)
    [
      "Sent #{content.length} chars in Markdown",
      "to Telegram chat ID ##{chat},",
      "in #{(Time.now - start).round(2)}s"
    ].join(' ')
  end

  def deliver_smtp(content, recipient, codec, delivery)
    html = with_utm(
      Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(content),
      delivery
    )
    text = with_utm(
      Redcarpet::Markdown.new(Redcarpet::Render::StripDown).render(content),
      delivery
    )
    ln = lane
    name = "#{recipient.first.strip} #{recipient.last.strip}".strip
    to = recipient.email
    to = "#{name} <#{recipient.email}>" unless name.empty?
    to = (yaml['to'] || ln.yaml['to'] || to).strip
    from = (yaml['from'] || ln.yaml['from']).strip
    cc = yaml['cc'] || ln.yaml['cc'] || []
    bcc = yaml['bcc'] || ln.yaml['bcc'] || []
    subject = (yaml['subject'] || ln.yaml['subject'] || '').strip
    if yaml['quote']
      quote = lane.letters.letter(yaml['quote'].to_i)
      appendix = markdown(quote.liquid, codec, recipient, delivery)
      time = Time.now - 60 * 60 * 24 * 7
      html += [
        "On #{time.strftime('%a %b %e')} at #{time.strftime('%I:%M %p')} #{from} wrote:<br/>",
        '<blockquote style="margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex">',
        with_utm(
          Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(appendix),
          delivery
        ),
        '</blockquote>'
      ].join
      text += with_utm(
        Redcarpet::Markdown.new(Redcarpet::Render::StripDown).render(appendix),
        delivery
      ).split("\n").map { |t| '> ' + t }.join("\n")
      raise "There is no subject in the letter ##{quote.id}" unless quote.yaml['subject']
      subject = 'Re: ' + quote.yaml['subject'].strip
    end
    mail = Mail.new do
      from from
      to to
      cc.each { |a| cc a }
      bcc.each { |a| bcc a }
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
    raise "SMTP is not configured in the Lane ##{ln.id}" unless ln.yaml['smtp']
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

  def markdown(lqd, codec, recipient, delivery)
    template = Liquid::Template.parse(lqd)
    token = codec.encrypt(recipient.id.to_s)
    template.render(
      'id' => recipient.id,
      'list_id' => recipient.list.id,
      'email' => recipient.email,
      'first' => recipient.first.empty? ? nil : recipient.first,
      'last' => recipient.last.empty? ? nil : recipient.last,
      'token' => token,
      'unsubscribe' => [
        "https://www.mailanes.com/unsubscribe?token=#{CGI.escape(token)}",
        delivery.nil? ? '' : "&d=#{delivery.id}"
      ].join,
      'profile' => "https://www.mailanes.com/recipient?id=#{recipient.id}&list=#{recipient.list.id}"
    )
  end

  def with_utm(text, delivery)
    text.gsub(%r{(https?://[a-zA-Z0-9%-_./&?]+)}) do |u|
      r = u + (u.include?('?') ? '&' : '?')
      r += 'utm_source=mailanes.com&utm_medium=email&utm_campaign='
      r += delivery.nil? ? '0' : delivery.campaign.id.to_s
      r
    end
  end
end
