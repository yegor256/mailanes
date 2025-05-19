# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

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
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new(pgsql: t_pgsql)
    delivery = deliveries.add(campaign, letter, recipient)
    delivery.save_relax(Time.now)
    assert_predicate(delivery.id, :positive?)
    assert_equal(letter.id, delivery.letter.id)
    assert_equal(recipient.id, delivery.recipient.id)
    assert_equal(campaign.id, delivery.campaign.id)
  end

  def test_closes_delivery
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = list.recipients.add('test1@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new(pgsql: t_pgsql)
    delivery = deliveries.add(campaign, letter, recipient)
    assert_empty(delivery.details)
    msg = 'DONE with it, друг'
    delivery.close(msg)
    assert_equal(msg, delivery.details)
  end

  def test_deletes_delivery
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = list.recipients.add('test1@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new(pgsql: t_pgsql)
    delivery = deliveries.add(campaign, letter, recipient)
    delivery.delete
  end
end
