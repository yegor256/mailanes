# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'yaml'
require 'tempfile'
require_relative 'test__helper'
require_relative '../objects/lists'
require_relative '../objects/recipient'
require_relative '../objects/recipients'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'
require_relative '../objects/deliveries'

class RecipientsTest < Minitest::Test
  def test_creates_recipients
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    recipient = recipients.add('tes.met@mailanes.com')
    assert(recipient.id.positive?)
    assert_equal(1, recipients.all.count)
  end

  def test_add_exclusive_recipient
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    first = lists.add
    jeff = 'jeff7383@mailanes.com'
    sarah = 'sarah8484@mailanes.com'
    j1 = Recipients.new(list: first, pgsql: t_pgsql).add(jeff).id
    s1 = Recipients.new(list: first, pgsql: t_pgsql).add(sarah).id
    second = lists.add
    second.yaml = 'exclusive: true'
    j2 = Recipients.new(list: second, pgsql: t_pgsql).add(jeff).id
    assert(!Recipient.new(id: j1, pgsql: t_pgsql).active?)
    assert(Recipient.new(id: j2, pgsql: t_pgsql).active?)
    assert(Recipient.new(id: s1, pgsql: t_pgsql).active?)
  end

  def test_groups_recipients_by_weeks
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    recipients.add('tiu-1@mailanes.com', source: owner)
    recipients.add('tiu-2@mailanes.com', source: owner)
    assert(1, recipients.weeks(owner).count)
    assert(recipients.weeks(owner)[0][:week])
    assert(recipients.weeks(owner)[0][:total])
    assert(recipients.weeks(owner)[0][:bad])
  end

  def test_fetches_recipients
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    recipients.add('tes-t.0_0@mailanes.com', source: "@#{owner}")
    assert_equal(1, recipients.all(query: "=@#{owner}", limit: -1).count)
  end

  def test_activate_all
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    recipients.add('boom3301@mailanes.com').toggle
    recipients.add('boom3302@mailanes.com')
    recipients.add('boom3303@mailanes.com').toggle
    assert_equal(1, recipients.all(active_only: true).count)
    recipients.activate_all
    assert_equal(3, recipients.all(active_only: true).count)
  end

  def test_count_by_source
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    source = 'xxx'
    recipients.add('tes-7@mailanes.com', source: source)
    assert_equal(1, recipients.count_by_source(source))
  end

  def test_count_per_day
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    recipients.add('tes-672@mailanes.com')
    assert_equal(0.25, recipients.per_day(4))
  end

  def test_bounce_rate
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    first = recipients.add('tes-109@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    letter = lane.letters.add
    deliveries = Deliveries.new(pgsql: t_pgsql)
    deliveries.add(campaign, letter, first)
    second = recipients.add('tes-110@mailanes.com')
    deliveries.add(campaign, letter, second).bounce
    assert_equal(0.5, recipients.bounce_rate)
  end

  def test_upload_recipients
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    Tempfile.open do |f|
      File.write(
        f.path,
        [
          'test@mailanes.com,Jeff,Lebowski',
          'test@mailanes.com,Jeff,Lebowski',
          'test2@mailanes.com,Walter,Sobchak',
          'broken-email,Walter,Sobchak',
          ',Walter,Sobchak'
        ].join("\n")
      )
      recipients.upload(f.path)
    end
    assert_equal(2, recipients.all.count)
  end

  def test_catches_invalid_encoding
    owner = random_owner
    lists = Lists.new(owner: owner, pgsql: t_pgsql)
    list = lists.add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    assert_raises StandardError do
      Tempfile.open do |f|
        File.write(
          f.path,
          [
            "test@mailanes.com,Dude \xAD"
          ].join("\n")
        )
        recipients.upload(f.path)
      end
    end
  end
end
