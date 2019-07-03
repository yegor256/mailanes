# frozen_string_literal: true

# Copyright (c) 2018-2019 Yegor Bugayenko
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
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    assert(campaign.exists?)
    assert_equal(1, campaign.lists.count)
    assert_equal(list.id, campaign.lists[0].id)
  end

  def test_saves_and_reads_yaml
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.yaml = "title: hello\nspeed: 10\ndecoy:\n  amount: 0.03"
    assert_equal('hello', campaign.title)
  end

  def test_rejects_broken_yaml
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    assert_raises(UserError) do
      campaign.yaml = 'this is not yaml'
    end
  end

  def test_rejects_broken_yaml_syntax
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    assert_raises(UserError) do
      campaign.yaml = 'this is not yaml'
    end
  end

  def test_counts
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    assert_equal(0, campaign.deliveries_count(days: 10))
    assert_equal(0, campaign.recipients_count)
    assert_equal(0, campaign.bounce_count(days: 10))
  end

  def test_adds_and_removes_sources
    owner = random_owner
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(
      Lists.new(owner: owner, pgsql: test_pgsql).add,
      Lanes.new(owner: owner, pgsql: test_pgsql).add
    )
    assert_equal(1, campaign.lists.count)
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    campaign.add(list)
    assert_equal(2, campaign.lists.count)
    campaign.delete(list)
    assert_equal(1, campaign.lists.count)
  end

  def test_merges_into
    owner = random_owner
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    first = Campaigns.new(owner: owner, pgsql: test_pgsql).add(Lists.new(owner: owner, pgsql: test_pgsql).add, lane)
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    deliveries = Deliveries.new(pgsql: test_pgsql)
    deliveries.add(first, lane.letters.add, list.recipients.add('x82@mailanes.com'))
    deliveries.add(first, lane.letters.add, list.recipients.add('x84@mailanes.com'))
    second = Campaigns.new(owner: owner, pgsql: test_pgsql).add(Lists.new(owner: owner, pgsql: test_pgsql).add, lane)
    first.merge_into(second)
    assert_equal(2, second.lists.count)
  end

  def test_reports_in_campaign
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test743@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    Pipeline.new(pgsql: test_pgsql).fetch(Postman::Fake.new, cycles: 10)
    assert_equal(1, campaign.deliveries.count)
  end

  def test_counts_pipeline
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    list.recipients.add('test032@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    assert_equal(1, campaign.pipeline_count)
    Pipeline.new(pgsql: test_pgsql).fetch(Postman::Fake.new, cycles: 10)
    assert_equal(0, campaign.pipeline_count)
  end

  def test_counts_pipeline_in_large_campaign
    skip
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: test_pgsql).add
    total = 5_000
    Dir.mktmpdir do |dir|
      csv = File.join(dir, 'tmp.csv')
      File.write(csv, Array.new(total).map { |i| "speed-test-#{i}@mailanes.com" }.join("\n"))
      list.recipients.upload(csv)
    end
    lane = Lanes.new(owner: owner, pgsql: test_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: test_pgsql).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    letter.toggle
    start = Time.now
    assert_equal(total, campaign.pipeline_count)
    puts "It took #{Time.now - start} seconds"
  end
end
