# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/lane'
require_relative '../objects/lanes'

class LaneTest < Minitest::Test
  def test_reads_yaml
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    id = lanes.add.id
    lane = Lane.new(id: id, pgsql: t_pgsql)
    assert(lane.yaml['title'])
  end

  def test_reads_lane
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    title = 'How are you?'
    id = lanes.add(title).id
    lane = Lane.new(id: id, pgsql: t_pgsql)
    assert_equal(title, lane.title)
  end

  def test_reads_deliveries_count
    owner = random_owner
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    assert_equal(0, lane.deliveries_count)
  end
end
