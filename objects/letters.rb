# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'letter'
require_relative 'tbot'
require_relative 'user_error'

# Letters.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Letters
  def initialize(lane:, pgsql:)
    @lane = lane
    @pgsql = pgsql
  end

  def count
    @pgsql.exec('SELECT COUNT(*) FROM letter WHERE lane=$1', [@lane.id]).first['count'].to_i
  end

  def all
    @pgsql.exec('SELECT * FROM letter WHERE lane=$1 ORDER BY place, created DESC', [@lane.id]).map do |r|
      Letter.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(title = 'undefined', tbot: Tbot.new)
    yaml = "title: #{title}\n"
    Letter.new(
      id: @pgsql.exec(
        [
          'INSERT INTO letter (lane, yaml, place)',
          'VALUES ($1, $2, 1 + (SELECT COALESCE(MAX(place), 0) FROM letter WHERE lane = $1))',
          'RETURNING id'
        ],
        [@lane.id, yaml]
      ).first['id'].to_i,
      pgsql: @pgsql,
      tbot: tbot
    )
  end

  def letter(id, tbot: Tbot.new)
    hash = @pgsql.exec('SELECT * FROM letter WHERE lane=$1 AND id=$2', [@lane.id, id]).first
    raise UserError, "Letter ##{id} not found in the lane ##{@lane.id}" if hash.nil?
    Letter.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash,
      tbot: tbot
    )
  end
end
