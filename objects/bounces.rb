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

  def fetch
    pop = Net::POP3.new(@host)
    pop.start(@login, @password)
    pop.each_mail do |m|
      body = m.pop
      puts body
      match = body.match(%r{X-Mailanes-Recipient: ([a-zA-Z0-9=+/]+)})
      unless match.nil?
        begin
          id = @codec.decrypt(match[1]).to_i
          recipient = Recipient.new(id, pgsql: @pgsql)
          recipient.toggle if recipient.active?
          recipient.post_event(body[0..1024])
          puts "Recipient ##{recipient.id}/#{recipient.email} bounced :("
        rescue StandardError => _
          puts 'Unclear message in the inbox...'
        end
      end
      m.delete
    end
    pop.finish
  end
end
