# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'test__helper'
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/deliveries'

class DeliveryTest < Minitest::Test
  def test_creates_delivery
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new(pgsql: t_pgsql)
    delivery = deliveries.add(campaign, letter, recipient)
    assert(delivery.opened.empty?)
    delivery.just_opened
    assert(!delivery.opened.empty?)
    delivery.unsubscribe
  end
end
