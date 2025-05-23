# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'net/pop'
require 'loog'
require_relative 'recipient'
require_relative 'tbot'
require_relative 'hex'

# Fetch all bounces and deactivate recipients.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Bounces
  def initialize(host, port, login, password, codec, pgsql:, log: Loog::NULL)
    @host = host
    @port = port
    @login = login
    @password = password
    @pgsql = pgsql
    @codec = codec
    @log = log
  end

  def fetch(tbot: Tbot.new)
    action = lambda do |m|
      body = m.pop
      match(body, /X-Mailanes-Recipient: (?<id>[0-9]+):(?<encrypted>[a-f0-9=\n]+)(?:(?<did>[0-9]+))?/, tbot)
      match(body, /Subject: MAILANES:(?<id>[0-9]+):(?<encrypted>[a-f0-9=\n]+)(?:(?<did>[0-9]+))?/, tbot)
      @log.info("Message #{m.unique_id} processed and deleted")
      m.delete
    end
    @host.is_a?(String) ? fetch_pop(action) : fetch_array(action)
  end

  private

  def fetch_pop(action)
    start = Time.now
    total = 0
    Net::POP3.enable_ssl
    Net::POP3.start(@host, @port, @login, @password) do |pop|
      pop.each_mail do |m|
        action.call(m)
        total += 1
        GC.start if (total % 10).zero?
      end
    end
    @log.info("#{total} bounce emails processed in #{format('%.02f', Time.now - start)}s")
  rescue Net::ReadTimeout => e
    @log.info("Failed to process bounce emails: #{e.message}")
  end

  def fetch_array(action)
    @host.each do |m|
      action.call(m)
    end
  end

  def match(body, regex, tbot, delivery: false)
    body.scan(regex).each do |id, encrypted, did|
      next if id.nil? || encrypted.nil?
      begin
        plain = id.to_i
        sign = Hex::ToText.new(encrypted.gsub("=\n", '').gsub(/=.+/, '')).to_s
        decoded = @codec.decrypt(sign).to_i
        raise "Invalid signature #{encrypted} for recipient ID ##{plain}" unless plain == decoded
        recipient = Recipient.new(id: plain, pgsql: @pgsql)
        if recipient.bounced?
          tbot.notify(
            'error',
            recipient.list.yaml,
            '⚠️ Something is wrong! The recipient',
            "[##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
            'has already been bounced once,',
            "but we just received a new bounce report to their email `#{recipient.email}`,",
            "in the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id});",
            'this may be happen due to some internal mistake,',
            'please [report it](https://github.com/yegor256/mailanes)'
          )
        end
        recipient.toggle(msg: 'Deactivated because the email bounced back') if recipient.active?
        if did
          Delivery.new(id: did.to_i, pgsql: @pgsql).bounce
          recipient.post_event("SMTP delivery ##{did} bounced back:\n#{body[0..1024]}")
        else
          delivery = recipient.deliveries(limit: 1)[0]
          raise "The recipient #{recipient.id} has no deliveries" if delivery.nil?
          delivery.bounce
          recipient.post_event("Unrecognized SMTP delivery bounced back:\n#{body[0..1024]}")
        end
        list = recipient.list
        rate = list.recipients.bounce_rate
        tbot.notify(
          'bounce',
          recipient.list.yaml,
          "👎 The email `#{recipient.email}` to recipient",
          "[##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
          'bounced back, that\'s why we deactivated it in the list',
          "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}).",
          "Bounce rate of the list is #{(rate * 100).round(2)}% (#{rate > 0.05 ? 'too high!' : 'it is OK'})."
        )
        @log.info("Recipient ##{recipient.id}/#{recipient.email} from \"#{recipient.list.title}\" bounced :(")
      rescue StandardError => e
        @log.error("Unclear message from ##{plain} in the inbox while matching against #{regex}: \
#{e.message}\n\t#{e.backtrace.join("\n\t")}:\n#{body}")
      end
    end
  end
end
