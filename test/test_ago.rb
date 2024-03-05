# frozen_string_literal: true

# Copyright (c) 2018-2024 Yegor Bugayenko
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
require_relative 'test__helper'
require_relative '../objects/ago'

class AgoTest < Minitest::Test
  def test_just_now
    ago = Ago.new(Time.now)
    assert_equal('just now', ago.to_s)
  end

  def test_hour_ago
    assert_equal('1 hour ago', Ago.new(Time.now - (60 * 60)).to_s)
    assert_equal('6 hours ago', Ago.new(Time.now - (5 * 60 * 60) - (60 * 60) - 30).to_s)
    assert_equal('1 week ago', Ago.new(Time.now - (9 * 24 * 60 * 60) - (5 * 60 * 60) - (60 * 60) - 30).to_s)
  end
end
