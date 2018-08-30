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
require_relative '../objects/deliveries'

class DeliveriesTest < Minitest::Test
  def test_creates_delivery
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner).add
    campaign = Campaigns.new(owner: owner).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new
    delivery = deliveries.add(campaign, letter, recipient)
    delivery.relax(Time.now)
    assert(delivery.id > 0)
    assert_equal(letter.id, delivery.letter.id)
    assert_equal(recipient.id, delivery.recipient.id)
    assert_equal(campaign.id, delivery.campaign.id)
  end

  def test_closes_delivery
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = list.recipients.add('test1@mailanes.com')
    lane = Lanes.new(owner: owner).add
    campaign = Campaigns.new(owner: owner).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new
    delivery = deliveries.add(campaign, letter, recipient)
    assert(delivery.details.empty?)
    msg = 'DONE with it, друг'
    delivery.close(msg)
    assert_equal(msg, delivery.details)
  end
end
