# frozen_string_literal: true

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
    @port = port
    @port = File.read('target/pgsql.port').to_i if port.zero? && File.exist?('target/pgsql.port')
    @dbname = dbname
    @user = user
    @password = password
    @mutex = Mutex.new
    @pool = []
  end

  # Test connection
  TEST = Pgsql.new

  def exec(query, args = [], result = 0)
    connect do |c|
      start = Time.now
      c.exec_params(query, args, result) do |res|
        elapsed = Time.now - start
        if elapsed > 5
          puts "#{query} in #{elapsed.round(2)}s"
          # puts c.exec_params('EXPLAIN ANALYZE ' + query, args).map { |r| r['QUERY PLAN'] }.join("\n")
        end
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
    conn = @mutex.synchronize do
      @pool << PG.connect(dbname: @dbname, host: @host, port: @port, user: @user, password: @password) if @pool.empty?
      @pool.shift
    end
    begin
      yield conn
    rescue PG::Error
      conn = nil
    ensure
      @mutex.synchronize { @pool << conn } unless conn.nil?
    end
  end

  def print(query, args = [])
    rows = exec(query, args)
    if rows.empty?
      puts 'EMPTY'
      return
    end
    puts query + ':'
    puts rows[0].keys.map { |k| format('%-16s', k.to_s) }.join(' ')
    rows.each do |r|
      puts(r.values.map do |v|
        v = 'NULL' if v.nil?
        format('%-16s', v.to_s[0..15])
      end.join(' '))
    end
  end
end
