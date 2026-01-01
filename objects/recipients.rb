# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'csv'
require_relative 'recipient'
require_relative 'deliveries'
require_relative 'user_error'

# Recipients.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Recipients
  # All emails have to match this
  REGEX = /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i.freeze

  def initialize(list:, pgsql:, hash: {})
    @list = list
    @pgsql = pgsql
    @hash = hash
  end

  def all(query: '', limit: 100, active_only: false, in_list_only: true)
    q = [
      'SELECT recipient.* FROM recipient',
      'JOIN list ON list.id = recipient.list AND list.owner = $1',
      'WHERE',
      /^=\d+$/.match?(query) ? 'recipient.id = $2 :: INTEGER' : [
        '(',
        'email LIKE $2',
        'OR first LIKE $2',
        'OR last LIKE $2',
        'OR recipient.yaml LIKE $2',
        'OR source LIKE $2',
        ')'
      ].join(' '),
      in_list_only ? "AND recipient.list = #{@list.id}" : '',
      active_only ? 'AND recipient.active = true' : '',
      'ORDER BY recipient.created DESC',
      limit.positive? ? 'LIMIT $3' : ''
    ]
    like = "%#{query}%"
    like = query[1..] if query.start_with?('=')
    @pgsql.exec(q, [@list.owner, like] + (limit.positive? ? [limit] : [])).map do |r|
      Recipient.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def count
    return @hash['total'].to_i if @hash['total']
    @pgsql.exec('SELECT COUNT(*) FROM recipient WHERE list=$1', [@list.id]).first['count'].to_i
  end

  def active_count
    @pgsql.exec('SELECT COUNT(*) FROM recipient WHERE list=$1 AND active=true', [@list.id]).first['count'].to_i
  end

  def activate_all
    @pgsql.transaction do |t|
      t.exec('UPDATE recipient SET active=true WHERE list=$1', [@list.id])
      t.exec(
        [
          'INSERT INTO delivery (recipient, details)',
          'SELECT recipient.id, $2 AS details',
          'FROM recipient JOIN list',
          'ON list.id = recipient.list AND list.id = $1 AND recipient.active = false'
        ],
        [@list.id, 'Re-activated on request of the list owner']
      )
    end
  end

  def bounce_rate
    q = [
      'SELECT COUNT(1) FROM recipient',
      'JOIN delivery ON delivery.recipient = recipient.id',
      'WHERE list = $1'
    ]
    sent = @pgsql.exec(q, [@list.id]).first['count'].to_i
    bounced = @pgsql.exec(q + [' AND bounced IS NOT NULL'], [@list.id]).first['count'].to_i
    sent.zero? ? 0 : bounced.to_f / sent
  end

  def count_by_source(source)
    @pgsql.exec('SELECT COUNT(*) FROM recipient WHERE list=$1 AND source=$2', [@list.id, source]).first['count'].to_i
  end

  def exists?(email)
    !@pgsql.exec('SELECT id FROM recipient WHERE list=$1 AND email=$2', [@list.id, email.downcase.strip]).empty?
  end

  def add(email, first: '', last: '', source: '')
    raise UserError, "Invalid email #{email.inspect}" unless Recipients::REGEX.match?(email)
    recipient = Recipient.new(
      id: @pgsql.exec(
        'INSERT INTO recipient (list, email, first, last, source) VALUES ($1, $2, $3, $4, $5) RETURNING id',
        [@list.id, email.downcase.strip, first.strip, last.strip, source.downcase.strip]
      ).first['id'].to_i,
      pgsql: @pgsql
    )
    if @list.yaml['exclusive']
      @pgsql.transaction do |t|
        updated = t.exec(
          [
            'UPDATE recipient SET active = false',
            'FROM list',
            'WHERE list.id = recipient.list AND list.owner = $1 AND list.id != $2',
            'AND recipient.email = $3',
            'RETURNING recipient.id'
          ],
          [@list.owner, @list.id, email]
        )
        unless updated.empty?
          t.exec(
            [
              'INSERT INTO delivery (recipient, details)',
              'SELECT recipient.id, $4 AS details',
              'FROM recipient JOIN list',
              'ON list.id = recipient.list AND list.owner = $1 AND list.id != $2',
              'AND recipient.email = $3'
            ],
            [
              @list.owner, @list.id, email,
              "This recipient was deactivated because another recipient ##{updated[0]['id']} \
with the same email '#{email}' was added to the list ##{@list.id}, which has EXCLUSIVE flag set"
            ]
          )
        end
      end
      recipient.post_event("Deactivated because of EXCLUSIVE flag in the list ##{@list.id}")
    end
    recipient
  end

  def recipient(id)
    hash = @pgsql.exec(
      'SELECT * FROM recipient WHERE list=$1 AND id=$2',
      [@list.id, id]
    ).first
    raise UserError, "Recipient ##{id} not found in the list ##{@list.id}" if hash.nil?
    Recipient.new(id: id, pgsql: @pgsql, hash: hash)
  end

  def weeks(source)
    @pgsql.exec(
      [
        'SELECT CONCAT(DATE_PART(\'year\', recipient.created), \'/\',',
        '  DATE_PART(\'week\', recipient.created)) AS week,',
        'COUNT(1) AS total,',
        'COUNT(1) FILTER (WHERE bounced IS NOT NULL) as bad',
        'FROM recipient',
        'LEFT JOIN delivery ON recipient.id = delivery.recipient',
        'WHERE list = $1 AND source = $2',
        'GROUP BY week',
        'ORDER BY week DESC'
      ],
      [@list.id, source.downcase.strip]
    ).map { |r| { week: r['week'], total: r['total'].to_i, bad: r['bad'].to_i } }
  end

  def per_day(days = 10)
    total = @pgsql.exec(
      "SELECT COUNT(*) FROM recipient WHERE list=$1 AND created > NOW() - INTERVAL '#{days} DAYS'",
      [@list.id]
    ).first['count'].to_f
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
      next unless Recipients::REGEX.match?(row[0])
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
