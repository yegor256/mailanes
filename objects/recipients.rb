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

require 'csv'
require_relative 'pgsql'
require_relative 'recipient'

# Recipients.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Recipients
  def initialize(list:, pgsql: Pgsql.new)
    @list = list
    @pgsql = pgsql
  end

  def all
    @pgsql.exec('SELECT * FROM recipient WHERE list=$1', [@list.id]).map do |r|
      Recipient.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def count
    all.count
  end

  def add(email, first: '', last: '', source: '')
    Recipient.new(
      id: @pgsql.exec(
        'INSERT INTO recipient (list, email, first, last, source) VALUES ($1, $2, $3, $4, $5) RETURNING id',
        [@list.id, email, first, last, source]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def upload(file, source: '')
    CSV.foreach(file) do |row|
      add(row[0], first: row[1], last: row[2], source: source)
    end
  end
end