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
require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/lists'

class ListsTest < Minitest::Test
  def test_create_a_list
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    title = 'My friends'
    list = lists.add(title)
    assert(list.id.positive?)
    assert_equal(1, lists.all.count)
    assert_equal(title, lists.all[0].title)
  end

  def test_find_a_list
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    title = 'test me'
    id = lists.add(title).id
    list = lists.list(id)
    assert_equal(title, list.title)
  end

  def test_raises_if_list_not_found
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    assert_raises(UserError) do
      lists.list(7584)
    end
  end

  def test_counts_total_recipients
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    assert_equal(0, lists.total_recipients)
    lists.add.recipients.add('xx1@mailanes.com')
    assert_equal(1, lists.total_recipients)
    lists.add.recipients.add('xx33@mailanes.com')
    lists.add.recipients.add('xx43@mailanes.com')
    assert_equal(3, lists.total_recipients)
  end

  def test_deactivate_many_recipients
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    r1 = lists.add.recipients.add('dm1@mailanes.com')
    r2 = lists.add.recipients.add('dm2@mailanes.com')
    r3 = lists.add.recipients.add('dm3@mailanes.com')
    lists.deactivate_recipients(['dm1@mailanes.com', 'dm2@mailanes.com'])
    assert(!r1.active?)
    assert(!r2.active?)
    assert(r3.active?)
  end

  def test_counts_duplicates
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    first = lists.add
    first.recipients.add('first-11@mailanes.com')
    second = lists.add
    second.recipients.add('first-22@mailanes.com')
    assert_equal(0, lists.duplicates_count)
    second.recipients.add('first-11@mailanes.com')
    assert_equal(1, lists.duplicates_count)
  end
end
