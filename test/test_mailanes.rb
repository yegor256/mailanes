# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'glogin/codec'
require_relative 'test__helper'
require_relative '../mailanes'
require_relative '../objects/hex'

module Rack
  module Test
    class Session
      def default_env
        { 'REMOTE_ADDR' => '127.0.0.1', 'HTTPS' => 'on' }.merge(headers_for_env)
      end
    end
  end
end

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_renders_version
    get('/version')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_robots_txt
    get('/robots.txt')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_it_renders_front_page
    get('/hello')
    assert_equal(200, last_response.status, last_response.location)
  end

  def test_it_renders_home_page
    login
    get('/')
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_deactivates_many_recipients
    login
    post('/deactivate-many', 'emails=a@gmail.com%0A2@gmail.com')
    assert_equal(302, last_response.status, last_response.body)
  end

  def test_subscribes_and_unsubscribes
    list = Lists.new(owner: random_owner, pgsql: t_pgsql).add
    email = "0-#{SecureRandom.hex[0..8]}@mailanes.com"
    post("/subscribe?list=#{list.id}&email=#{email}", 'reason=Just+%3A%0Alove+you')
    assert_equal(200, last_response.status, last_response.body)
    assert_equal(1, list.recipients.count)
    recipient = list.recipients.all[0]
    assert_predicate(recipient, :active?)
    assert_includes(recipient.yaml.to_yaml, "email: #{email}", recipient.yaml.to_yaml)
    assert_includes(recipient.yaml.to_yaml, "reason: |-\n  Just :\n  love you", recipient.yaml.to_yaml)
    token = GLogin::Codec.new.encrypt(recipient.id.to_s)
    get("/unsubscribe?token=#{CGI.escape(token)}")
    assert_equal(200, last_response.status, last_response.body)
    recipient = list.recipients.all[0]
    refute_predicate(recipient, :active?)
    post("/subscribe?list=#{list.id}&email=#{email}")
    recipient = list.recipients.all[0]
    assert_equal(200, last_response.status, last_response.body)
    assert_predicate(recipient, :active?)
  end

  def test_adds_new_recipient_for_friend
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.yaml = "friends:\n- jeff"
    login('jeff')
    email = "#{SecureRandom.hex[0..8]}@mailanes.com"
    post("/do-add?id=#{list.id}&email=#{email}")
    assert_equal(302, last_response.status, last_response.body)
    assert_equal(1, list.recipients.count)
  end

  def test_adds_new_recipient
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    email = 'kf04hsy@mailanes.com'
    login(owner)
    post("/do-add?id=#{list.id}&email=#{email}")
    assert_equal(302, last_response.status, last_response.body)
    assert_equal(1, list.recipients.count)
  end

  def test_activate_all_recipients
    owner = random_owner
    login(owner)
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    post("/do-add?id=#{list.id}&email=ut7209@mailanes.com")
    assert_equal(302, last_response.status, last_response.body)
    assert_equal(1, list.recipients.all.size)
    get("/toggle-recipient?list=#{list.id}&id=#{list.recipients.all.first.id}")
    assert_equal(302, last_response.status, last_response.body)
    assert_equal(0, list.recipients.all(active_only: true).count)
    get("/activate-all?id=#{list.id}")
    assert_equal(302, last_response.status, last_response.body)
    assert_equal(1, list.recipients.all(active_only: true).count)
  end

  def test_downloads_friends_list
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.yaml = "friends:\n- jeff"
    login('jeff')
    get("/download-list?list=#{list.id}")
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_some_pages
    owner = random_owner
    login(owner)
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    get('/lists')
    assert_equal(200, last_response.status, last_response.body)
    get("/list?id=#{list.id}")
    assert_equal(200, last_response.status, last_response.body)
    get("/download-list?list=#{list.id}")
    assert_equal(200, last_response.status, last_response.body)
    get("/download-recipients?id=#{list.id}")
    assert_equal(200, last_response.status, last_response.body)
    recipient = list.recipients.add('test-me1@mailanes.com')
    get("/recipient?id=#{recipient.id}")
    assert_equal(200, last_response.status, last_response.body)
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    get('/lanes')
    assert_equal(200, last_response.status, last_response.body)
    get("/lane?id=#{lane.id}")
    assert_equal(200, last_response.status, last_response.body)
    letter = Letters.new(lane: lane, pgsql: t_pgsql).add
    get("/letter?id=#{letter.id}")
    assert_equal(200, last_response.status, last_response.body)
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    get('/campaigns')
    assert_equal(200, last_response.status, last_response.body)
    get("/campaign?id=#{campaign.id}")
    assert_equal(200, last_response.status, last_response.body)
  end

  def test_api_pages
    owner = random_owner
    auth = Hex::FromText.new(owner).to_s
    get("/api?auth=#{auth}")
    assert_equal(200, last_response.status, last_response.body)
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    get("/api/lists/#{list.id}/active_count.json?auth=#{auth}")
    assert_equal(200, last_response.status, last_response.body)
    get("/api/lists/#{list.id}/per_day.json?auth=#{auth}")
    assert_equal(200, last_response.status, last_response.body)
    lane = Lanes.new(owner: owner, pgsql: t_pgsql).add
    campaign = Campaigns.new(owner: owner, pgsql: t_pgsql).add(list, lane)
    get("/api/campaigns/#{campaign.id}/deliveries_count.json?auth=#{auth}")
    assert_equal(200, last_response.status, last_response.body)
  end

  private

  def login(name = 'tester')
    set_cookie("glogin=#{name}|#{name}")
    get('/')
    assert_equal(200, last_response.status, last_response.location)
  end
end
