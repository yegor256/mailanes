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
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/pipeline'
require_relative '../objects/postman'
require_relative '../objects/tbot'

class PipelineTest < Minitest::Test
  def test_picks_letters_for_delivery
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    Pipeline.new(pgsql: test_pgsql).fetch(Postman::Fake.new)
    letter = lane.letters.add
    letter.toggle
    noise = lane.letters.add
    noise.toggle
    post1 = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post1, cycles: 1)
    assert_equal(1, post1.deliveries.count)
    assert(post1.deliveries.find { |d| d.letter.id == letter.id })
    # assert(!post1.deliveries.find { |d| d.letter.id == noise.id })
    post2 = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post2)
    assert(!post2.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_ignores_relaxed_letters
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    first = lane.letters.add
    first.toggle
    first.save_yaml('relax: "1:0:0"')
    post = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post)
    assert(post.deliveries.find { |d| d.letter.id == first.id })
    second = lane.letters.add
    second.toggle
    Pipeline.new(pgsql: test_pgsql).fetch(post)
    assert(!post.deliveries.find { |d| d.letter.id == second.id })
  end

  def test_sends_one_recipient_at_a_time
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test22@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    first = lane.letters.add
    first.toggle
    second = lane.letters.add
    second.toggle
    second.move(-1)
    post = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post, cycles: 1)
    assert(post.deliveries.find { |d| d.letter.id == second.id })
    assert(!post.deliveries.find { |d| d.letter.id == first.id })
  end

  def test_doesnt_send_if_stop_list
    owner = random_owner
    email = 'test90@mailanes.com'
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    assert(!list.stop?)
    list.recipients.add(email)
    stop = Lists.new(owner: owner, pgsql: test_pgsql).add
    stop.save_yaml('stop: true')
    assert(stop.stop?)
    stop.recipients.add(email)
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    post = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post)
    assert(!post.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_send_if_only_a_friend_stopped
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('jeff@mailanes.com')
    stop = Lists.new(owner: owner, pgsql: test_pgsql).add
    stop.save_yaml('stop: true')
    stop.recipients.add('walter@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    post = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post)
    assert(post.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_doesnt_send_from_stopped_list
    owner = random_owner
    email = 'test932@mailanes.com'
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.save_yaml('stop: true')
    assert(list.stop?)
    list.recipients.add(email)
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    post = Postman::Fake.new
    Pipeline.new(pgsql: test_pgsql).fetch(post)
    assert(!post.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_deactivates_letter
    owner = random_owner
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    letter = lane.letters.add
    letter.toggle
    letter.save_yaml('until: 01-01-1970')
    Pipeline.new(pgsql: test_pgsql).deactivate
    assert(!letter.active?)
  end

  def test_exhausts_campaigns
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    Pipeline.new(pgsql: test_pgsql).exhaust
    assert(campaign.exhausted?)
  end

  def test_sends_via_telegram
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test952@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    letter.save_yaml("transport: telegram\ntelegram:\n  chat_id: 1")
    tbot = Tbot::Fake.new
    Pipeline.new(tbot: tbot, pgsql: test_pgsql).fetch(Postman.new)
    assert_equal(1, campaign.deliveries.count)
    assert_equal(1, tbot.sent.count)
    delivery = campaign.deliveries[0]
    assert(1, delivery.details.include?('Telegram chat ID #1'))
  end
end
