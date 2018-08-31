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
require_relative '../objects/list'
require_relative '../objects/lists'

class ListTest < Minitest::Test
  def test_reads_list
    owner = random_owner
    lists = Lists.new(owner: owner)
    title = 'How are you?'
    id = lists.add(title).id
    list = List.new(id: id)
    assert_equal(title, list.title)
  end

  def test_sets_stop_status
    owner = random_owner
    list = Lists.new(owner: owner).add
    assert(!list.stop?)
    list.save_yaml('stop: true')
    assert(list.stop?)
    list.save_yaml('stop: false')
    assert(!list.stop?)
  end

  def test_counts_deliveries
    owner = random_owner
    list = Lists.new(owner: owner).add
    assert_equal(0, list.deliveries_count)
  end
end
