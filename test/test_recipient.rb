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
require_relative 'test__helper'
require_relative '../objects/lists'
require_relative '../objects/recipients'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/pipeline'
require_relative '../objects/postman'

class RecipientTest < Minitest::Test
  def test_toggles_recipient
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = Recipients.new(list: list).add('test@mailanes.com')
    assert(recipient.active?)
    recipient.toggle
    assert(!recipient.active?)
    recipient.toggle
    assert(recipient.active?)
  end

  def test_deletes_recipient
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = Recipients.new(list: list).add('test@mailanes.com')
    recipient.delete
    assert(list.recipients.count.zero?)
  end

  def test_toggles_fetched_recipient
    owner = random_owner
    list = Lists.new(owner: owner).add
    id = Recipients.new(list: list).add('test98@mailanes.com').id
    recipient = Recipients.new(list: list).recipient(id)
    assert(recipient.active?)
    recipient.toggle
    assert(!recipient.active?)
    recipient.toggle
    assert(recipient.active?)
  end

  def test_posts_event
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = Recipients.new(list: list).add('te99st@mailanes.com')
    assert_equal(0, recipient.deliveries.count)
    recipient.post_event('he is a good guy')
    assert_equal(1, recipient.deliveries.count)
  end

  def test_moves
    owner = random_owner
    list = Lists.new(owner: owner).add
    target = Lists.new(owner: owner).add
    recipient = Recipients.new(list: list).add('te77st@mailanes.com')
    assert_equal(1, list.recipients.count)
    recipient.move_to(target)
    assert_equal(0, list.recipients.count)
    assert_equal(1, target.recipients.count)
  end

  def test_reads_relax
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = Recipients.new(list: list).add('te89t@mailanes.com')
    assert_equal(0, recipient.relax)
    lane = Lanes.new(owner: owner).add
    campaign = Campaigns.new(owner: owner).add(list, lane)
    campaign.toggle
    first = lane.letters.add
    first.toggle
    first.save_yaml('relax: "1:0:0"')
    post = Postman::Fake.new
    Pipeline.new.fetch(post)
    assert_equal(1, recipient.relax)
  end
end
