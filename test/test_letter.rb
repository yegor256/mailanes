# Copyright (c) 2018 Yegor Bugayenko
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
require_relative '../objects/letters'

class LetterTest < Minitest::Test
  def test_sets_active_to_false
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letter = letters.add
    assert_equal(false, letter.active)
  end

  def test_toggles_active_status
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letter = letters.add
    letter.toggle
    assert_equal(true, letter.active)
    letter.toggle
    assert_equal(false, letter.active)
  end

  def test_creates_and_updates_letter
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letter = letters.add('Hi, dude!')
    %w[first second third].each do |text|
      letter.save_yaml("test: #{text}")
      assert_equal(text, letter.yaml['test'])
      letter.save_liquid(text)
      assert_equal(text, letter.liquid)
    end
  end

  def test_updates_letter_from_fetch
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letters.add
    letter = letters.all[0]
    %w[first second third].each do |text|
      letter.save_yaml("test: #{text}")
      assert_equal(text, letter.yaml['test'])
      letter.save_liquid(text)
      assert_equal(text, letter.liquid)
    end
  end
end
