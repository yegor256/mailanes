# frozen_string_literal: true

# Copyright (c) 2018-2019 Yegor Bugayenko
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
require_relative 'recipient'
require_relative 'deliveries'
require_relative 'user_error'

# Recipients.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2019 Yegor Bugayenko
# License:: MIT
class Recipients
  # All emails have to match this
  REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.freeze

  def initialize(list:, pgsql:)
    @list = list
    @pgsql = pgsql
  end

  def all(query: '', limit: 100, active_only: false, in_list_only: true)
    q = [
      'SELECT recipient.* FROM recipient',
      'JOIN list ON list.id = recipient.list AND list.owner = $1',
      'WHERE',
      /^=\d+$/.match?(query) ? 'recipient.id = $2 :: INTEGER' : '(' + [
        'email LIKE $2',
        'OR first LIKE $2',
        'OR last LIKE $2',
        'OR recipient.yaml LIKE $2',
        'OR source LIKE $2'
      ].join(' ') + ')',
      in_list_only ? "AND recipient.list = #{@list.id}" : '',
      active_only ? 'AND recipient.active = true' : '',
      'ORDER BY recipient.created DESC',
      limit.positive? ? 'LIMIT $3' : ''
    ].join(' ')
    like = "%#{query}%"
    like = query[1..-1] if query.start_with?('=')
    @pgsql.exec(q, [@list.owner, like] + (limit.positive? ? [limit] : [])).map do |r|
      Recipient.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def count
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1', [@list.id])[0]['count'].to_i
  end

  def active_count
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1 AND active=true', [@list.id])[0]['count'].to_i
  end

  def bounce_rate
    q = [
      'SELECT COUNT(recipient.id) FROM recipient',
      'JOIN delivery ON delivery.recipient = recipient.id',
      'WHERE list = $1'
    ].join(' ')
    sent = @pgsql.exec(q, [@list.id])[0]['count'].to_i
    bounced = @pgsql.exec(q + ' AND bounced IS NOT NULL', [@list.id])[0]['count'].to_i
    sent.zero? ? 0 : bounced.to_f / sent
  end

  def count_by_source(source)
    @pgsql.exec('SELECT COUNT(id) FROM recipient WHERE list=$1 AND source=$2', [@list.id, source])[0]['count'].to_i
  end

  def exists?(email)
    !@pgsql.exec('SELECT id FROM recipient WHERE list=$1 AND email=$2', [@list.id, email.downcase.strip]).empty?
  end

  def add(email, first: '', last: '', source: '')
    raise UserError, "Invalid email #{email.inspect}" unless email =~ Recipients::REGEX
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
    raise UserError, "Recipient ##{id} not found in the list ##{@list.id}" if hash.nil?
    Recipient.new(id: id, pgsql: @pgsql, hash: hash)
  end

  def weeks(source)
    @pgsql.exec(
      [
        'SELECT CONCAT(DATE_PART(\'year\', recipient.created), \'/\',',
        '  DATE_PART(\'week\', recipient.created)) AS week,',
        'COUNT(recipient.*) AS total,',
        'COUNT(recipient.*) FILTER (WHERE bounced IS NOT NULL) as bad',
        'FROM recipient',
        'LEFT JOIN delivery ON recipient.id = delivery.recipient',
        'WHERE list = $1 AND source = $2',
        'GROUP BY week',
        'ORDER BY week DESC'
      ].join(' '),
      [@list.id, source.downcase.strip]
    ).map { |r| { week: r['week'], total: r['total'].to_i, bad: r['bad'].to_i } }
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
    line = 1
    File.readlines(file).each do |t|
      begin
        t =~ //
      rescue StandardError => e
        raise UserError, "Encoding error in line ##{line} (#{e.message}): \"#{t}\""
      end
      line += 1
    end
    pos = 0
    CSV.foreach(file) do |row|
      pos += 1
      GC.start if (pos % 1000).zero?
      next if row[0].nil?
      next if exists?(row[0])
      next unless row[0] =~ Recipients::REGEX
      recipient = add(row[0], first: row[1] || '', last: row[2] || '', source: source)
      next unless row[3]
      row[3].strip.split(';').each do |dlv|
        c, l = dlv.strip.split('/')
        campaign = Campaign.new(id: c.to_i, pgsql: @pgsql)
        raise "Campaign ##{c} doesn't exist" unless campaign.exists?
        letter = Letter.new(id: l.to_i, pgsql: @pgsql)
        raise "Letter ##{l} doesn't exist" unless letter.exists?
        deliveries.add(campaign, letter, recipient).close('CSV upload')
      end
    rescue StandardError => e
      raise UserError, "Can't upload line ##{line}: #{e.message}"
    end
  end

  def csv
    CSV.generate(headers: true) do |csv|
      csv << [
        'Email',
        'First name',
        'Last name',
        'Source',
        'Created',
        'Active',
        'Bounced'
      ]
      yield().each do |r|
        csv << [
          r.email, r.first, r.last, r.source,
          r.created.utc.iso8601,
          r.active? ? 'yes' : 'no',
          r.bounced? ? 'yes' : 'no'
        ]
      end
    end
  end
end
