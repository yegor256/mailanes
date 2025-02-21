# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

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
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    lane = lanes.add
    campaigns = Campaigns.new(owner: owner, pgsql: t_pgsql)
    campaign = campaigns.add(list, lane)
    assert(campaign.id.positive?)
    assert_equal(1, campaigns.all.count)
  end

  def test_counts_deliveries
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipient = list.recipients.add('zz8d9s@mailanes.com')
    lanes = Lanes.new(owner: owner, pgsql: t_pgsql)
    lane = lanes.add
    letter = lane.letters.add
    campaigns = Campaigns.new(owner: owner, pgsql: t_pgsql)
    campaign = campaigns.add(list, lane)
    assert_equal(0, campaigns.total_deliveries)
    deliveries = Deliveries.new(pgsql: t_pgsql)
    deliveries.add(campaign, letter, recipient)
    assert_equal(1, campaigns.total_deliveries)
    deliveries.add(campaign, letter, list.recipients.add('zz8dffs@mailanes.com'))
    assert_equal(2, campaigns.total_deliveries)
    assert_equal(0, campaigns.total_bounced)
  end
end
