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
require_relative 'deliveries'

# Recipients.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Recipients
  # All emails have to match this
  REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

  def initialize(list:, pgsql: Pgsql::TEST)
    @list = list
    @pgsql = pgsql
  end

  def all(query: '', limit: 100, active_only: false)
    q = [
      'SELECT * FROM recipient',
      'WHERE list=$1 AND (email LIKE $2 OR first LIKE $2 OR last LIKE $2 OR yaml LIKE $2 OR source LIKE $2)',
      active_only ? 'AND active = true' : '',
      'ORDER BY created DESC',
      limit > 0 ? 'LIMIT $3' : ''
    ].join(' ')
    like = "%#{query}%"
    like = query[1..-1] if query.start_with?('=')
    @pgsql.exec(q, [@list.id, like] + (limit > 0 ? [limit] : [])).map do |r|
      Recipient.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def count
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1', [@list.id])[0]['count'].to_i
  end

  def active_count
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1 AND active=true', [@list.id])[0]['count'].to_i
  end

  def count_by_source(source)
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1 AND source=$2', [@list.id, source])[0]['count'].to_i
  end

  def exists?(email)
    !@pgsql.exec('SELECT id FROM recipient WHERE list=$1 AND email=$2', [@list.id, email.downcase.strip]).empty?
  end

  def add(email, first: '', last: '', source: '')
    raise "Invalid email #{email.inspect}" unless email =~ Recipients::REGEX
    recipient = Recipient.new(
      id: @pgsql.exec(
        'INSERT INTO recipient (list, email, first, last, source) VALUES ($1, $2, $3, $4, $5) RETURNING id',
        [@list.id, email.downcase.strip, first.strip, last.strip, source.downcase.strip]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
    if @list.yaml['exclusive'] && @list.yaml['exclusive'] == 'true'
      @pgsql.exec(
        [
          'UPDATE recipient SET active = false',
          'JOIN list ON list.id = recipient.list',
          'WHERE list.owner = $1 AND list.id != $2'
        ].join(' '),
        [@list.owner, @list.id]
      )
    end
    recipient
  end

  def recipient(id)
    hash = @pgsql.exec(
      'SELECT * FROM recipient WHERE list=$1 AND id=$2',
      [@list.id, id]
    )[0]
    raise "Recipient ##{id} not found in the list ##{@list.id}" if hash.nil?
    Recipient.new(id: id, pgsql: @pgsql, hash: hash)
  end

  def per_day(days = 10)
    total = @pgsql.exec(
      "SELECT COUNT(*) FROM recipient WHERE list=$1 AND created > NOW() - INTERVAL \'#{days} DAYS\'",
      [@list.id]
    )[0]['count'].to_f
    total.zero? ? 0 : total / days
  end

  def upload(file, source: '')
    deliveries = Deliveries.new(pgsql: @pgsql)
    CSV.foreach(file) do |row|
      next if row[0].nil?
      next if exists?(row[0])
      next unless row[0] =~ Recipients::REGEX
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
