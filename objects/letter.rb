# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'
require 'mail'
require 'uuidtools'
require 'timeout'
require 'pg'
require 'liquid'
require 'loog'
require 'redcarpet'
require 'redcarpet/render_strip'
require 'glogin/codec'
require_relative 'hex'
require_relative 'campaign'
require_relative 'user_error'
require_relative 'yaml_doc'

# Letter.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Letter
  # When can't deliver
  class CantDeliver < StandardError; end

  attr_reader :id

  def initialize(id:, pgsql:, hash: {}, tbot: Tbot.new, log: Loog::NULL)
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
    @tbot = tbot
    @log = log
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
    ]
    @pgsql.exec(q, [@id]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def title
    yaml['title'] || "##{id}"
  end

  def deliveries_count
    @pgsql.exec('SELECT COUNT(*) FROM delivery WHERE letter=$1', [@id])[0]['count'].to_i
  end

  def opened_count
    @pgsql.exec('SELECT COUNT(*) FROM delivery WHERE letter=$1 AND opened != \'\'', [@id])[0]['count'].to_i
  end

  def bounce_count
    @pgsql.exec('SELECT COUNT(*) FROM delivery WHERE letter=$1 AND bounced IS NOT NULL', [@id])[0]['count'].to_i
  end

  def unsubscribe_count
    @pgsql.exec('SELECT COUNT(*) FROM delivery WHERE letter=$1 AND unsubscribed IS NOT NULL', [@id])[0]['count'].to_i
  end

  def exists?
    !@pgsql.exec('SELECT id FROM letter WHERE id=$1', [@id]).empty?
  end

  def active?
    (@hash['active'] || @pgsql.exec('SELECT active FROM letter WHERE id=$1', [@id])[0]['active']) == 't'
  end

  def liquid
    @hash['liquid'] || @pgsql.exec('SELECT liquid FROM letter WHERE id=$1', [@id])[0]['liquid']
  end

  def yaml
    YamlDoc.new(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM letter WHERE id=$1', [@id])[0]['yaml']
    ).load
  end

  def toggle
    @pgsql.exec('UPDATE letter SET active=not(active) WHERE id=$1', [@id])
    @hash = {}
  end

  def place
    (@hash['place'] || @pgsql.exec('SELECT place FROM letter WHERE id=$1', [@id])[0]['place']).to_i
  end

  def move(inc = 1)
    raise "Invalid direction #{inc.inspect}" if inc != 1 && inc != -1
    @pgsql.transaction do |t|
      other = t.exec(
        [
          'SELECT id, place FROM letter',
          "WHERE place #{inc.positive? ? '>' : '<'} $1 AND lane = $2",
          "ORDER BY place #{inc.positive? ? 'ASC' : 'DESC'}"
        ],
        [place, lane.id]
      )[0]
      raise UserError, 'Can\'t move in this direction' if other.nil?
      mine = place
      t.exec('UPDATE letter SET place=$1 WHERE id = $2', [65_536, other['id'].to_i])
      t.exec('UPDATE letter SET place=$1 WHERE id = $2', [other['place'].to_i, @id])
      t.exec('UPDATE letter SET place=$1 WHERE id = $2', [mine, other['id'].to_i])
    end
    @hash = {}
  end

  def liquid=(liquid)
    @pgsql.exec('UPDATE letter SET liquid=$1 WHERE id=$2', [liquid, @id])
    @hash = {}
  end

  def yaml=(yaml)
    @pgsql.exec('UPDATE letter SET yaml=$1 WHERE id=$2', [YamlDoc.new(yaml).save, @id])
    yml = YamlDoc.new(yaml).load
    speed = yml['speed'] ? yml['speed'].to_i : 65_536
    @pgsql.exec('UPDATE letter SET speed=$1 WHERE id=$2', [speed, @id])
    @hash = {}
  end

  def deliver(recipient, codec = GLogin::Codec.new, delivery: nil)
    content = markdown(liquid, codec, recipient, delivery)
    if yaml['transport'].nil? || yaml['transport'].casecmp('smtp').zero?
      deliver_smtp(content, recipient, codec, delivery)
    elsif yaml['transport'].casecmp('telegram').zero?
      deliver_telegram(content)
    else
      raise "Unknown transport \"#{yaml['transport']}\" for the letter ##{@id}"
    end
  end

  def attach(name, file)
    body = File.binread(file)
    @pgsql.exec(
      'INSERT INTO attachment (letter, name, body) VALUES ($1, $2, $3)',
      [@id, name, { value: body, type: 0, format: 1 }]
    )
  end

  def detach(name)
    @pgsql.exec('DELETE FROM attachment WHERE letter = $1 AND name = $2', [@id, name])
  end

  def attachments
    @pgsql.exec('SELECT name FROM attachment WHERE letter = $1', [@id]).map do |r|
      r['name']
    end
  end

  def download(name, file)
    @pgsql.exec('SELECT body FROM attachment WHERE letter = $1 and name = $2', [@id, name], 1).map do |r|
      File.binwrite(file, r['body'])
    end
  end

  private

  def deliver_telegram(content)
    chat = cfg(nil, 'telegram', 'chat_id').to_i
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
    tracking = cfg('on', 'tracking') == true || cfg('on', 'tracking').downcase.strip == 'on'
    if tracking && !delivery.nil?
      html += [
        "<img src=\"https://www.mailanes.com/opened?token=#{CGI.escape(codec.encrypt(delivery.id.to_s))}\"",
        'alt="" width="1" height="1" border="0"',
        'style="height:1px !important; width:1px !important;',
        'border-width:0 !important; margin:0 !important; padding:0 !important;"/>'
      ].join(' ')
    end
    text = Redcarpet::Markdown.new(Redcarpet::Render::StripDown).render(content.gsub("<br/>\n", '<br/>'))
      .gsub("\n", "\n\n")
      .gsub('<br/>', "\n")
    name = "#{recipient.first.strip} #{recipient.last.strip}".strip
    to = recipient.email
    to = "#{name} <#{recipient.email}>" unless name.empty?
    to = cfg(to, 'to').strip
    from = cfg(nil, 'from').strip
    cc = cfg([], 'cc')
    bcc = cfg([], 'bcc')
    subject = cfg('', 'subject').strip
    if yaml['quote']
      quote = lane.letters.letter(yaml['quote'].to_i)
      appendix = markdown(quote.liquid, codec, recipient, delivery)
      time = Time.now - (60 * 60 * 24 * 7)
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
      ).split("\n").map { |t| "> #{t}" }.join("\n")
      raise "There is no subject in the letter ##{quote.id}" unless quote.yaml['subject']
      subject = "Re: #{quote.yaml['subject'].strip}"
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
    bounces = cfg('reply@mailanes.com', 'bounces')
    unless delivery.nil?
      rid = recipient.id
      did = delivery.id
      mail.header['X-Mailanes-Recipient'] = "#{rid}:#{Hex::FromText.new(codec.encrypt(rid.to_s))}:#{did}"
      mail.header['List-Unsubscribe'] = [
        '<https://www.mailanes.com/unsubscribe?',
        unsubscribe(codec, recipient, delivery),
        ">, <mailto:#{bounces}?subject=",
        CGI.escape("MAILANES:#{rid}:#{codec.encrypt(rid.to_s)}:#{did}"),
        '>'
      ].join
      mail.header['List-Id'] = did.to_s
    end
    mail.header['Return-Path'] = bounces
    mail.header['X-Complaints-To'] = bounces
    attachments.each do |a|
      Tempfile.open do |f|
        download(a, f.path)
        mail.add_file(filename: a, content: File.read(f.path))
      end
    end
    mail.delivery_method(
      :smtp,
      address: cfg(nil, 'smtp', 'host'),
      port: cfg(25, 'smtp', 'port').to_i,
      domain: cfg(nil, 'smtp', 'host'),
      user_name: cfg(nil, 'smtp', 'user'),
      password: cfg(nil, 'smtp', 'password'),
      authentication: 'plain',
      enable_starttls_auto: true
    )
    start = Time.now
    Timeout.timeout(15) do
      mail.deliver
      @log.debug("Letter ##{@id} SMTP-sent to #{to} from \"#{recipient.list.title}\" \
in #{format('%.02f', Time.now - start)}")
    rescue Net::SMTPAuthenticationError => e
      raise CantDeliver, e.message
    end
    unless delivery.nil?
      decoy = delivery.campaign.decoy
      total = decoy['amount']
      total = (rand((1 / total).round).zero? ? 1 : 0) if total < 1 && !total.zero?
      total.times do
        fake = mail.dup
        fake.without_attachments!
        fake.to = decoy['address'].gsub('*') { rand(9).to_s }
        fake.cc = nil
        fake.bcc = nil
        fake.html_part = nil
        fake.header['X-Mailanes-Recipient'] = nil
        fake.header['List-Id'] = nil
        fake.header['List-Unsubscribe'] = nil
        fake.header['List-Unsubscribe'] = 'https://www.mailanes.com/'
        Timeout.timeout(15) do
          fake.deliver
        end
        @log.debug("Fake letter SMTP-sent to #{fake.to} from \"#{recipient.list.title}\"")
      end
    end
    [
      "Sent #{html.length} chars in HTML (#{text.length} in plain text)",
      "to #{to} (recipient ##{recipient.id} in list ##{recipient.list.id})",
      "from #{from}, with the subject line \"#{subject}\" via SMTP,",
      "in #{(Time.now - start).round(2)}s"
    ].join(' ')
  rescue Timeout::Error => e
    raise CantDeliver, e.message
  end

  def unsubscribe(codec, recipient, delivery)
    token = codec.encrypt(recipient.id.to_s)
    "token=#{CGI.escape(token)}" + (delivery.nil? ? '' : "&did=#{delivery.id}")
  end

  def markdown(lqd, codec, recipient, delivery)
    template = Liquid::Template.parse(lqd)
    query = unsubscribe(codec, recipient, delivery)
    template.render(
      'id' => recipient.id,
      'list_id' => recipient.list.id,
      'email' => recipient.email,
      'first' => recipient.first.empty? ? nil : recipient.first,
      'last' => recipient.last.empty? ? nil : recipient.last,
      'unsubscribe_query' => query,
      'unsubscribe' => "https://www.mailanes.com/unsubscribe?#{query}",
      'confirm' => "https://www.mailanes.com/confirm?#{query}",
      'profile' => "https://www.mailanes.com/recipient?id=#{recipient.id}"
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

  def cfg(default, *items)
    result = yaml
    items.each do |i|
      result = result[i]
      break if result.nil?
    end
    if result.nil?
      result = lane.yaml
      items.each do |i|
        result = result[i]
        break if result.nil?
      end
    end
    if result.nil?
      if default.nil?
        raise UserError, "\"#{items.join('/')}\" not found in the YAML config \
of the letter ##{id} and of the lane ##{lane.id}; make sure they are confired as explained here: \
https://github.com/yegor256/mailanes"
      end
      result = default
    end
    result
  end
end
