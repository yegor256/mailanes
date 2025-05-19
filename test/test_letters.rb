# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/lanes'
require_relative '../objects/letters'

class LettersTest < Minitest::Test
  def test_creates_letters
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    lane = lanes.add
    letters = Letters.new(lane: lane, pgsql: t_pgsql)
    letters.add('First')
    letters.add('Second')
    letter = letters.add('Third')
    assert_predicate(letter.id, :positive?)
    assert_equal(3, letters.all.count)
    assert_equal(3, letter.place)
  end
end
