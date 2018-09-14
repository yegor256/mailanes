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
require_relative '../objects/pgsql'
require_relative '../objects/list'
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/deliveries'

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

  def test_absorbs_duplicates
    Pgsql::TEST.exec('DELETE FROM delivery')
    owner = random_owner
    lane = Lanes.new(owner: owner).add
    letter = lane.letters.add
    lists = Lists.new(owner: random_owner)
    first = lists.add
    campaign = Campaigns.new(owner: owner).add(first, lane)
    second = lists.add
    campaign.add(second)
    dup = 'ab1@mailanes.com'
    recipient = first.recipients.add(dup)
    Deliveries.new.add(campaign, letter, recipient)
    Deliveries.new.add(Campaigns.new(owner: owner).add(first, lane), letter, recipient)
    Deliveries.new.add(campaign, letter, second.recipients.add(dup))
    Deliveries.new.add(campaign, letter, second.recipients.add('ab2@mailanes.com'))
    assert_equal(1, first.absorb_candidates(second).count)
    assert_equal(recipient.id, first.absorb_candidates(second)[0][:to].id)
    first.absorb(second)
    assert_equal(1, first.recipients.count)
    assert_equal(1, second.recipients.count)
  end
end
