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

require 'pg'

# The PostgreSQL connector.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Pgsql
  def initialize(host: 'localhost', port: 0, dbname: 'test', user: 'test', password: 'test')
    @host = host
    port = File.read('target/pgsql.port').to_i if port.zero?
    @port = port
    @dbname = dbname
    @user = user
    @password = password
    @mutex = Mutex.new
  end

  def exec(query, args = [])
    @mutex.synchronize do
      connect.exec_params(query, args) do |res|
        # puts "#{query} #{args}"
        if block_given?
          yield res
        else
          rows = []
          res.each { |r| rows << r }
          rows
        end
      end
    end
  end

  def connect
    @connect ||= PG.connect(dbname: @dbname, host: @host, port: @port, user: @user, password: @password)
  end
end
