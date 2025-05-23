# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'yaml'
require 'tmpdir'
require_relative 'test__helper'
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/postman'
require_relative '../objects/pipeline'
require_relative '../objects/user_error'

class CampaignTest < Minitest::Test
  def test_iterates_lists
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    assert_predicate(campaign, :exists?)
    assert_equal(1, campaign.lists.count)
    assert_equal(list.id, campaign.lists[0].id)
  end

  def test_saves_and_reads_yaml
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.yaml = "title: hello\nspeed: 10\ndecoy:\n  amount: 0.03"
    assert_equal('hello', campaign.title)
  end

  def test_rejects_broken_yaml
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    assert_raises(UserError) do
      campaign.yaml = 'this is not yaml'
    end
  end

  def test_rejects_broken_yaml_syntax
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    assert_raises(UserError) do
      campaign.yaml = 'this is not yaml'
    end
  end

  def test_counts
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    assert_equal(0, campaign.deliveries_count(days: 10))
    assert_equal(0, campaign.recipients_count)
    assert_equal(0, campaign.bounce_count(days: 10))
  end

  def test_adds_and_removes_sources
    owner = random_owner
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(
      Lists.new(owner: owner, pgsql: t_pgsql).add,
      Lanes.new(owner: owner, pgsql: t_pgsql).add
    )
    assert_equal(1, campaign.lists.count)
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    campaign.add(list)
    assert_equal(2, campaign.lists.count)
    campaign.delete(list)
    assert_equal(1, campaign.lists.count)
  end

  def test_merges_into
    owner = random_owner
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    first = Campaigns.new(owner: owner, pgsql: t_pgsql).add(Lists.new(owner: owner, pgsql: t_pgsql).add, lane)
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    deliveries = Deliveries.new(pgsql: t_pgsql)
    deliveries.add(first, lane.letters.add, list.recipients.add('x82@mailanes.com'))
    deliveries.add(first, lane.letters.add, list.recipients.add('x84@mailanes.com'))
    second = Campaigns.new(owner: owner, pgsql: t_pgsql).add(Lists.new(owner: owner, pgsql: t_pgsql).add, lane)
    first.merge_into(second)
    assert_equal(2, second.lists.count)
  end

  def test_reports_in_campaign
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test743@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    Pipeline.new(pgsql: t_pgsql).fetch(Postman::Fake.new, cycles: 10)
    assert_equal(1, campaign.deliveries.count)
  end

  def test_counts_pipeline
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test032@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    assert_equal(1, campaign.pipeline_count)
    Pipeline.new(pgsql: t_pgsql).fetch(Postman::Fake.new, cycles: 10)
    assert_equal(0, campaign.pipeline_count)
  end

  def test_counts_pipeline_in_large_campaign
    skip('Does not work')
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    total = 5_000
    Dir.mktmpdir do |dir|
      csv = File.join(dir, 'tmp.csv')
      File.write(csv, Array.new(total).map { |i| "speed-test-#{i}@mailanes.com" }.join("\n"))
      list.recipients.upload(csv)
    end
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    start = Time.now
    assert_equal(total, campaign.pipeline_count)
    t_log.info("It took #{Time.now - start} seconds")
  end
end
