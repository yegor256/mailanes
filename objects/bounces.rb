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
    pop = Net::POP3.new(@host)
    pop.start(@login, @password)
    pop.each_mail do |m|
      body = m.pop
      match = body.match(%r{X-Mailanes-Recipient: ([0-9]+):([a-zA-Z0-9=+/]+)})
      unless match.nil?
        begin
          plain = match[1].to_i
          decoded = @codec.decrypt(match[2]).to_i
          raise "#{plain} != #{decoded}" if plain != decoded
          recipient = Recipient.new(id: decoded, pgsql: @pgsql)
          recipient.toggle if recipient.active?
          recipient.bounce
          recipient.post_event(body[0..1024])
          list = recipient.list
          tbot.notify(
            recipient.list.yaml,
            [
              "The email #{recipient.email} to recipient",
              "[##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id}&list=#{list.id})",
              'bounced back, that\'s why we deactivated it in the list',
              "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})."
            ].join(' ')
          )
          puts "Recipient ##{recipient.id}/#{recipient.email} bounced :("
        rescue StandardError => e
          puts "Unclear message from ##{plain} in the inbox\n#{e.message}\n\t#{e.backtrace.join("\n\t")}:\n#{body}"
        end
      end
      puts "Message #{m.unique_id} processed and deleted"
      m.delete
    end
    pop.finish
  end
end
