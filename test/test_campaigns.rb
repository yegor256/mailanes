# frozen_string_literal: true

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
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'

class CampaignsTest < Minitest::Test
  def test_creates_campaigns
    owner = random_owner
    lists = Lists.new(owner: owner)
    list = lists.add
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    campaigns = Campaigns.new(owner: owner)
    campaign = campaigns.add(list, lane)
    assert(campaign.id.positive?)
    assert_equal(1, campaigns.all.count)
  end

  def test_counts_deliveries
    owner = random_owner
    lists = Lists.new(owner: owner)
    list = lists.add
    recipient = list.recipients.add('zz8d9s@mailanes.com')
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letter = lane.letters.add
    campaigns = Campaigns.new(owner: owner)
    campaign = campaigns.add(list, lane)
    assert_equal(0, campaigns.total_deliveries)
    deliveries = Deliveries.new
    deliveries.add(campaign, letter, recipient)
    assert_equal(1, campaigns.total_deliveries)
    deliveries.add(campaign, letter, list.recipients.add('zz8dffs@mailanes.com'))
    assert_equal(2, campaigns.total_deliveries)
    assert_equal(0, campaigns.total_bounced)
  end
end
