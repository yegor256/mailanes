# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'glogin/codec'
require_relative 'tbot'

# Postman.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Postman
  # Doing nothing, just closing
  class Fake
    attr_reader :deliveries

    def initialize
      @deliveries = []
    end

    def deliver(delivery, tbot: Tbot.new)
      raise if tbot.nil?
      @deliveries << delivery
    end
  end

  def initialize(codec = GLogin::Codec.new)
    @codec = codec
  end

  def deliver(delivery, tbot: Tbot.new)
    letter = delivery.letter(tbot: tbot)
    recipient = delivery.recipient
    log = ''
    begin
      log = letter.deliver(recipient, @codec, delivery: delivery)
    rescue StandardError => e
      log = "#{e.class.name} #{e.message}; #{e.backtrace.join('; ')}"
      tbot.notify(
        'error', delivery.campaign.yaml,
        "⚠️ We just failed to deliver letter [##{letter.id}](https://www.mailanes.com/letter?id=#{letter.id})",
        "to the recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
        "because of the error of type `#{e.class.name}`: #{e.message.inspect};",
        "you may find more details [here](https://www.mailanes.com/delivery?id=#{delivery.id})"
      )
    end
    delivery.close(log)
  end
end
