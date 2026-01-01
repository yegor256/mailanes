# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'list'
require_relative 'user_error'

# Lists.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Lists
  def initialize(owner:, pgsql:)
    @owner = owner
    @pgsql = pgsql
  end

  def empty?
    count.zero?
  end

  def count
    @pgsql.exec('SELECT COUNT(*) FROM list WHERE owner=$1', [@owner]).first['count'].to_i
  end

  def all
    found = @pgsql.exec(
      [
        'SELECT list.id, COUNT(recipient.id) AS total_recipients',
        'FROM recipient',
        'JOIN list ON list.id = recipient.list',
        'WHERE list.owner = $1',
        'GROUP BY list.id',
        'ORDER BY list.created DESC'
      ],
      [@owner]
    ).map { |r| List.new(id: r['id'].to_i, pgsql: @pgsql, hash: r) }
    ids = @pgsql.exec('SELECT list.id FROM list WHERE owner=$1', [@owner]).map { |r| r['id'].to_i }
    ids.each do |id|
      found << List.new(id: id, pgsql: @pgsql) unless found.find { |l| l.id == id }
    end
    found
  end

  def add(title = 'noname')
    yaml = "title: #{title}\n"
    List.new(
      id: @pgsql.exec(
        'INSERT INTO list (owner, yaml) VALUES ($1, $2) RETURNING id',
        [@owner, yaml]
      ).first['id'].to_i,
      pgsql: @pgsql
    )
  end

  def list(id)
    hash = @pgsql.exec(
      'SELECT * FROM list WHERE owner=$1 AND id=$2',
      [@owner, id]
    ).first
    raise UserError, "List ##{id} not found in @#{@owner} account" if hash.nil?
    List.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def duplicates_count
    @pgsql.exec(
      '
      SELECT COUNT(*)
      FROM (
        SELECT recipient.email
        FROM recipient
        JOIN list ON list.id = recipient.list
        WHERE list.owner = $1 AND list.stop = false
        GROUP BY recipient.email
        HAVING COUNT(*) > 1
      ) t
      ',
      [@owner]
    ).first['count'].to_i
  end

  def total_recipients
    @pgsql.exec(
      [
        'SELECT COUNT(recipient.email) FROM recipient',
        'JOIN list ON recipient.list = list.id',
        'WHERE list.owner = $1 AND list.stop = false'
      ],
      [@owner]
    ).first['count'].to_i
  end

  # Deactivate them all
  def deactivate_recipients(emails)
    raise UserError, "List of emails can't be empty" if emails.empty?
    values = emails.map { |e| "'#{e.gsub("'", '\\\'')}'" }.join(', ')
    @pgsql.transaction do |t|
      t.exec(
        [
          'UPDATE recipient SET active = false',
          'FROM list',
          'WHERE list.owner = $1 AND recipient.email',
          'IN (', values, ')'
        ],
        [@owner]
      )
      t.exec(
        [
          'INSERT INTO delivery (recipient, details)',
          'SELECT recipient.id, \'Deactivated by the owner of the list\' AS details',
          'FROM recipient, list WHERE recipient.email IN (', values, ')',
          'AND list.owner = $1'
        ],
        [@owner]
      )
    end
  end
end
