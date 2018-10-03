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

require 'net/pop'
require_relative 'pgsql'
require_relative 'recipient'
require_relative 'tbot'
require_relative 'hex'

# Fetch all bounces and deactivate recipients.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Bounces
  def initialize(host, login, password, codec, pgsql: Pgsql::TEST)
    @host = host
    @login = login
    @password = password
    @pgsql = pgsql
    @codec = codec
  end

  def fetch(tbot: Tbot.new)
    action = lambda do |m|
      body = m.pop
      match(body, /X-Mailanes-Recipient: ([0-9]+):([a-f0-9=\n]+)/, tbot)
      match(body, /Subject: MAILANES:([0-9]+):([a-f0-9=\n]+)/, tbot)
      puts "Message #{m.unique_id} processed and deleted"
      m.delete
    end
    @host.is_a?(String) ? fetch_pop(action) : fetch_array(action)
  end

  private

  def fetch_pop(action)
    pop = Net::POP3.new(@host)
    pop.start(@login, @password)
    total = 0
    pop.each_mail do |m|
      action.call(m)
      total += 1
    end
    pop.finish
    puts "#{total} bounce emails processed"
  end

  def fetch_array(action)
    @host.each do |m|
      action.call(m)
    end
  end

  def match(body, regex, tbot)
    body.scan(regex).each do |match|
      next if match[0].nil? || match[1].nil?
      begin
        plain = match[0].to_i
        sign = Hex::ToText.new(match[1].gsub("=\n", '').gsub(/\=.+/, '')).to_s
        decoded = @codec.decrypt(sign).to_i
        raise "Invalid signature #{match[1]} for recipient ID ##{plain}" unless plain == decoded
        recipient = Recipient.new(id: plain, pgsql: @pgsql)
        recipient.toggle if recipient.active?
        recipient.bounce
        recipient.post_event("SMTP delivery bounced back:\n#{body[0..1024]}")
        list = recipient.list
        rate = list.recipients.bounce_rate
        tbot.notify(
          'bounce',
          recipient.list.yaml,
          [
            "The email `#{recipient.email}` to recipient",
            "[##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
            'bounced back, that\'s why we deactivated it in the list',
            "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}).",
            "Bounce rate of the list is #{(rate * 100).round(2)}% (#{rate > 0.05 ? 'too high!' : 'it is OK'})."
          ].join(' ')
        )
        puts "Recipient ##{recipient.id}/#{recipient.email} from \"#{recipient.list.title}\" bounced :("
      rescue StandardError => e
        puts "Unclear message from ##{plain} in the inbox:\n#{e.message}\n\t#{e.backtrace.join("\n\t")}:\n#{body}"
      end
    end
  end
end
