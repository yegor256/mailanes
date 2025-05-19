# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

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
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('test-98772@mailanes.com')
    assert_predicate(recipient, :active?)
    recipient.toggle
    refute_predicate(recipient, :active?)
    recipient.toggle
    assert_predicate(recipient, :active?)
  end

  def test_deletes_recipient
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('test-01284@mailanes.com')
    recipient.delete
    assert_predicate(list.recipients.count, :zero?)
  end

  def test_confirms
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('test-04492@mailanes.com')
    assert_predicate(recipient, :confirmed?)
    recipient.confirm!(set: false)
    refute_predicate(recipient, :confirmed?)
    recipient.confirm!(set: true)
    assert_predicate(recipient, :confirmed?)
  end

  def test_toggles_fetched_recipient
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    id = Recipients.new(list: list, pgsql: t_pgsql).add('test98@mailanes.com').id
    recipient = Recipients.new(list: list, pgsql: t_pgsql).recipient(id)
    assert_predicate(recipient, :active?)
    recipient.toggle
    refute_predicate(recipient, :active?)
    recipient.toggle
    assert_predicate(recipient, :active?)
  end

  def test_posts_event
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('te99st@mailanes.com')
    assert_equal(0, recipient.deliveries.count)
    recipient.post_event('he is a good guy')
    assert_equal(1, recipient.deliveries.count)
  end

  def test_moves
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    target = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('te77st@mailanes.com')
    assert_equal(1, list.recipients.count)
    recipient.move_to(target)
    assert_equal(0, list.recipients.count)
    assert_equal(1, target.recipients.count)
  end

  def test_reads_relax
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('te89t@mailanes.com')
    assert_equal(0, recipient.relax)
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    campaign.toggle
    first = lane.letters.add
    first.toggle
    first.yaml = 'relax: "1:0:0"'
    post = Postman::Fake.new
    Pipeline.new(pgsql: t_pgsql).fetch(post)
    assert_equal(1, recipient.relax)
  end

  def test_saves_and_prints_yaml
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = Recipients.new(list: list, pgsql: t_pgsql).add('te085@mailanes.com')
    yaml = "---\nfoo: |\n  hello\n  world\n"
    recipient.yaml = yaml
    assert_equal(yaml, recipient.yaml.to_yaml)
    recipient.yaml = "---\nx: 1"
    assert_equal(1, recipient.yaml['x'])
  end

  def test_changes_email
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    recipient = recipients.add('x76@mailanes.com')
    assert_equal('x76@mailanes.com', recipient.email)
    recipient.email = '467hsh@mailanes.com'
    assert_equal('467hsh@mailanes.com', recipient.email)
    recipient.email = 'another-one@mailanes.com'
    assert_equal('another-one@mailanes.com', recipient.email)
  end
end
