# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'
require_relative 'letters'
require_relative 'yaml_doc'

# Lane.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Lane
  attr_reader :id

  def initialize(id:, pgsql:, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
  end

  def letters
    Letters.new(lane: self, pgsql: @pgsql)
  end

  def title
    yaml['title'] || 'unknown'
  end

  def yaml
    YamlDoc.new(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM lane WHERE id=$1', [@id])[0]['yaml']
    ).load
  end

  def yaml=(yaml)
    @pgsql.exec('UPDATE lane SET yaml=$1 WHERE id=$2', [YamlDoc.new(yaml).save, @id])
    @hash = {}
  end

  def deliveries_count
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'JOIN letter ON letter.id = delivery.letter',
        'WHERE letter.lane = $1'
      ],
      [@id]
    )[0]['count'].to_i
  end
end
