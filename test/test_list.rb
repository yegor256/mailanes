# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/list'
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/deliveries'

class ListTest < Minitest::Test
  def test_reads_list
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    title = 'How are you?'
    id = lists.add(title).id
    list = List.new(id: id, pgsql: t_pgsql)
    assert_equal(title, list.title)
  end

  def test_checks_for_existence
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    id = lists.add('boom').id
    list = List.new(id: id, pgsql: t_pgsql)
    assert_predicate(list, :exists?)
  end

  def test_checks_for_non_existence
    list = List.new(id: 99_999, pgsql: t_pgsql)
    refute_predicate(list, :exists?)
  end

  def test_finds_friends
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    list.yaml = "friends:\n- Jeff\n- john10"
    assert(list.friend?('jeff'))
    refute(list.friend?('john'))
  end

  def test_sets_stop_status
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    refute_predicate(list, :stop?)
    list.yaml = 'stop: true'
    assert_predicate(list, :stop?)
    list.yaml = 'stop: false'
    refute_predicate(list, :stop?)
  end

  def test_counts_deliveries
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    assert_equal(0, list.deliveries_count)
  end

  def test_counts_opens
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    assert_equal(0, list.opened_count)
  end

  def test_absorbs_duplicates
    t_pgsql.exec('DELETE FROM delivery')
    owner = random_owner
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    letter = lane.letters.add
    lists = Lists.new(owner: random_owner, pgsql: t_pgsql)
    first = lists.add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(first, lane)
    second = lists.add
    campaign.add(second)
    dup = 'ab1@mailanes.com'
    recipient = first.recipients.add(dup)
    deliveries = Deliveries.new(pgsql: t_pgsql)
    deliveries.add(campaign, letter, recipient)
    deliveries.add(Campaigns.new(owner: owner, pgsql: t_pgsql).add(first, lane), letter, recipient)
    deliveries.add(campaign, letter, second.recipients.add(dup))
    deliveries.add(campaign, letter, second.recipients.add('ab2@mailanes.com'))
    assert_equal(1, first.absorb_candidates(second).count)
    assert_equal(recipient.id, first.absorb_candidates(second)[0][:to].id)
    assert_equal(second.id, first.absorb_counts[0][:list].id)
    first.absorb(second)
    assert_equal(1, first.recipients.count)
    assert_equal(1, second.recipients.count)
  end
end
