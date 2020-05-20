# frozen_string_literal: true

# Copyright (c) 2018-2020 Yegor Bugayenko
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
