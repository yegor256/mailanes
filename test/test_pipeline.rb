# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

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
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    Pipeline.new(pgsql: t_pgsql).fetch(Postman::Fake.new)
    letter = lane.letters.add
    letter.toggle
    noise = lane.letters.add
    noise.toggle
    post1 = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post1, cycles: 1)
    assert_equal(1, post1.deliveries.count)
    assert(post1.deliveries.find { |d| d.letter.id == letter.id })
    # assert(!post1.deliveries.find { |d| d.letter.id == noise.id })
    post2 = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post2)
    refute(post2.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_ignores_relaxed_letters
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    first = lane.letters.add
    first.toggle
    first.yaml = 'relax: "1:0:0"'
    post = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post)
    assert(post.deliveries.find { |d| d.letter.id == first.id })
    second = lane.letters.add
    second.toggle
    Pipeline.new(pgsql: t_pgsql).fetch(post)
    refute(post.deliveries.find { |d| d.letter.id == second.id })
  end

  def test_sends_one_recipient_at_a_time
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test2893--4@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    first = lane.letters.add
    first.toggle
    second = lane.letters.add
    second.toggle
    second.move(-1)
    post = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post, cycles: 1)
    assert(post.deliveries.find { |d| d.letter.id == second.id })
    refute(post.deliveries.find { |d| d.letter.id == first.id })
  end

  def test_doesnt_send_if_stop_list
    owner = random_owner
    email = 'test90@mailanes.com'
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    refute_predicate(list, :stop?)
    list.recipients.add(email)
    stop = Lists.new(owner: owner, pgsql: t_pgsql).add
    stop.yaml = 'stop: true'
    assert_predicate(stop, :stop?)
    stop.recipients.add(email)
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    post = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post)
    refute(post.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_send_if_only_a_friend_stopped
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('jeff@mailanes.com')
    stop = Lists.new(owner: owner, pgsql: t_pgsql).add
    stop.yaml = 'stop: true'
    stop.recipients.add('walter@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    post = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post)
    assert(post.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_doesnt_send_from_stopped_list
    owner = random_owner
    email = 'test932@mailanes.com'
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.yaml = 'stop: true'
    assert_predicate(list, :stop?)
    list.recipients.add(email)
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    post = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post)
    refute(post.deliveries.find { |d| d.letter.id == letter.id })
  end

  def test_deactivates_letter
    owner = random_owner
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    letter = lane.letters.add
    letter.toggle
    letter.yaml = 'until: 01-01-1970'
    Pipeline.new(pgsql: t_pgsql).deactivate
    refute_predicate(letter, :active?)
  end

  def test_exhausts_campaigns
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    Pipeline.new(pgsql: t_pgsql).exhaust
    assert_predicate(campaign, :exhausted?)
  end

  def test_sends_via_telegram
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test952@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    letter.yaml = "transport: telegram\ntelegram:\n  chat_id: 1"
    tbot = Tbot::Fake.new
    Pipeline.new(tbot: tbot, pgsql: t_pgsql).fetch(Postman.new)
    assert_equal(1, campaign.deliveries.count)
    assert_operator(tbot.sent.count, :>=, 1)
    delivery = campaign.deliveries[0]
    assert_includes(delivery.details, 'Telegram chat ID #1')
  end
end
