# frozen_string_literal: true

# Copyright (c) 2018-2024 Yegor Bugayenko
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

require 'glogin/codec'
require_relative 'tbot'

# Postman.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2024 Yegor Bugayenko
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
