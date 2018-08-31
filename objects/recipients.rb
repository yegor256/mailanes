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

  def all(limit: 100)
    @pgsql.exec('SELECT * FROM recipient WHERE list=$1 ORDER BY created DESC LIMIT $2', [@list.id, limit]).map do |r|
      Recipient.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def count
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1', [@list.id])[0]['count']
  end

  def exists?(email)
    !@pgsql.exec('SELECT id FROM recipient WHERE list=$1 AND email=$2', [@list.id, email.downcase.strip]).empty?
  end

  def add(email, first: '', last: '', source: '')
    raise "Invalid email #{email}" unless email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
    Recipient.new(
      id: @pgsql.exec(
        'INSERT INTO recipient (list, email, first, last, source) VALUES ($1, $2, $3, $4, $5) RETURNING id',
        [@list.id, email.downcase.strip, first.strip, last.strip, source.downcase.strip]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def recipient(id)
    Recipient.new(id: id, pgsql: @pgsql)
  end

  def upload(file, source: '')
    deliveries = Deliveries.new(pgsql: @pgsql)
    CSV.foreach(file) do |row|
      next if row[0].nil?
      next if exists?(row[0])
      recipient = add(row[0], first: row[1] || '', last: row[2] || '', source: source)
      if row[3]
        row[3].strip.split(';').each do |dlv|
          c, l = dlv.strip.split('/')
          deliveries.add(
            Campaign.new(id: c.to_i, pgsql: @pgsql),
            Letter.new(id: l.to_i, pgsql: @pgsql),
            recipient
          ).close('CSV upload')
        end
      end
    end
  end
end
