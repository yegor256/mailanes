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

require 'net/pop'

# Just delete all emails from POP3 decoy account.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2024 Yegor Bugayenko
# License:: MIT
class Decoy
  def initialize(host, port, login, password, log: Loog::NULL)
    @host = host
    @port = port
    @login = login
    @password = password
    @log = log
  end

  def fetch
    start = Time.now
    Net::POP3.start(@host, @port, @login, @password) do |pop|
      total = 0
      pop.each_mail do |m|
        m.delete
        total += 1
        GC.start if (total % 100).zero?
      end
    end
    @log.info("#{total} decoy emails processed in #{format('%.02f', Time.now - start)}s")
  rescue Net::ReadTimeout => e
    @log.info("Failed to process decoy emails: #{e.message}")
  end
end
