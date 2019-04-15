# frozen_string_literal: true

# Copyright (c) 2019 Yegor Bugayenko
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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/lanes'

class LanesTest < Minitest::Test
  def test_creates_lanes
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: test_pgsql)
    title = 'To celebrate, друг!'
    lane = lanes.add(title)
    assert(lane.id.positive?)
    assert_equal(1, lanes.all.count)
    assert_equal(title, lanes.all[0].title)
  end

  def test_fetches_letter
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: test_pgsql)
    lane = lanes.add
    id = lane.letters.add.id
    letter = lanes.letter(id)
    assert_equal(id, letter.id)
  end

  def test_fetches_absent_letter
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: test_pgsql)
    assert_raises(UserError) do
      lanes.letter(1000)
    end
  end

  def test_fetches_absent_lane
    owner = random_owner
    lanes = Lanes.new(owner: owner, pgsql: test_pgsql)
    assert_raises(UserError) do
      lanes.lane(1000)
    end
  end
end
