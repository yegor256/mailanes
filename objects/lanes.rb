# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'lane'
require_relative 'user_error'

# Lanes.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Lanes
  def initialize(owner:, pgsql:)
    @owner = owner
    @pgsql = pgsql
  end

  def empty?
    count.zero?
  end

  def count
    @pgsql.exec('SELECT COUNT(*) FROM lane WHERE owner=$1', [@owner])[0]['count'].to_i
  end

  def all
    @pgsql.exec('SELECT * FROM lane WHERE owner=$1 ORDER BY created DESC', [@owner]).map do |r|
      Lane.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(title = 'unknown')
    yaml = "title: #{title}\n"
    Lane.new(
      id: @pgsql.exec(
        'INSERT INTO lane (owner, yaml) VALUES ($1, $2) RETURNING id',
        [@owner, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def lane(id)
    hash = @pgsql.exec(
      'SELECT * FROM lane WHERE owner=$1 AND id=$2',
      [@owner, id]
    )[0]
    raise UserError, "Lane ##{id} not found @#{@owner} account" if hash.nil?
    Lane.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def letter(id, tbot: Tbot.new)
    hash = @pgsql.exec(
      [
        'SELECT letter.* FROM letter',
        'JOIN lane ON letter.lane = lane.id',
        'WHERE lane.owner=$1 AND letter.id=$2'
      ],
      [@owner, id]
    )[0]
    raise UserError, "Letter ##{id} not found in any lanes owned by @#{@owner}" if hash.nil?
    Letter.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash,
      tbot: tbot
    )
  end
end
