# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'glogin/codec'
require_relative 'test__helper'
require_relative '../objects/bounces'
require_relative '../objects/hex'
require_relative '../objects/lists'
require_relative '../objects/lanes'
require_relative '../objects/campaigns'

class BouncesTest < Minitest::Test
  def test_deactives_recipients
    skip('It is live test')
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.recipients.add('test@mailanes.com')
    Bounces.new(
      'pop.secureserver.net',
      995,
      'reply@mailanes.com',
      '--',
      GLogin::Codec.new('--'),
      pgsql: t_pgsql
    ).fetch
  end

  def test_deactives_recipients_with_fake_pop
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    Deliveries.new(pgsql: t_pgsql).add(campaign, lane.letters.add, recipient)
    codec = GLogin::Codec.new('some key')
    msg = FakeMsg.new(recipient, codec)
    Bounces.new([msg], 995, '', '', codec, pgsql: t_pgsql).fetch
    assert_predicate(recipient, :bounced?)
  end

  def test_processes_repeated_bounce
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    recipient = list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    deliveries = Deliveries.new(pgsql: t_pgsql)
    deliveries.add(campaign, lane.letters.add, recipient).bounce
    recipient.toggle
    delivery = deliveries.add(campaign, lane.letters.add, recipient)
    codec = GLogin::Codec.new('some key')
    tbot = Tbot::Fake.new
    Bounces.new([FakeMsg.new(recipient, codec)], 995, '', '', codec, pgsql: t_pgsql).fetch(tbot: tbot)
    assert_equal(2, tbot.sent.count)
    assert_includes(tbot.sent.first, 'has already been bounced once')
    assert_includes(tbot.sent.first, "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})")
    assert_predicate(delivery, :bounced?)
    refute_predicate(recipient, :active?)
    assert_includes(recipient.deliveries.first.details, 'Unrecognized SMTP delivery bounced back:')
  end

  class FakeMsg
    def initialize(recipient, codec)
      @recipient = recipient
      @codec = codec
    end

    def pop
      sign = Hex::FromText.new(@codec.encrypt(@recipient.id.to_s)).to_s
      [
        "X-Mailanes-Recipient: #{@recipient.id}:there+is+some+garbage",
        "X-Mailanes-Recipient: #{@recipient.id}:#{sign[0..31]}=",
        "#{sign[32..]}=3D=3D",
        'How are you doing?'
      ].join("\n")
    end

    def delete
      # nothing
    end

    def unique_id
      '1'
    end
  end
end
