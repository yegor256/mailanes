# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/lanes'

class LanesTest < Minitest::Test
  def test_creates_lanes
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    title = 'To celebrate, друг!'
    lane = lanes.add(title)
    assert_predicate(lane.id, :positive?)
    assert_equal(1, lanes.all.count)
    assert_equal(title, lanes.all[0].title)
  end

  def test_fetches_letter
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    lane = lanes.add
    id = lane.letters.add.id
    letter = lanes.letter(id)
    assert_equal(id, letter.id)
  end

  def test_fetches_absent_letter
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    assert_raises(UserError) do
      lanes.letter(1000)
    end
  end

  def test_fetches_absent_lane
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    assert_raises(UserError) do
      lanes.lane(1000)
    end
  end
end
