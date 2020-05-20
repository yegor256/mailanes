# frozen_string_literal: true

# Copyright (c) 2018-2020 Yegor Bugayenko
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

  def test_subscribes_and_unsubscribes
    list = Lists.new(owner: random_owner, pgsql: t_pgsql).add
    email = "0-#{SecureRandom.hex[0..8]}@mailanes.com"
    post("/subscribe?list=#{list.id}&email=#{email}", 'reason=Just+%3A%0Alove+you')
    assert_equal(200, last_response.status, last_response.body)
    assert_equal(1, list.recipients.count)
    recipient = list.recipients.all[0]
    assert(recipient.active?)
    assert(recipient.yaml.to_yaml.include?("email: #{email}"), recipient.yaml.to_yaml)
    assert(recipient.yaml.to_yaml.include?("reason: |-\n  Just :\n  love you"), recipient.yaml.to_yaml)
    token = GLogin::Codec.new.encrypt(recipient.id.to_s)
    get("/unsubscribe?token=#{CGI.escape(token)}")
    assert_equal(200, last_response.status, last_response.body)
    recipient = list.recipients.all[0]
    assert(!recipient.active?)
    post("/subscribe?list=#{list.id}&email=#{email}")
    recipient = list.recipients.all[0]
    assert_equal(200, last_response.status, last_response.body)
    assert(recipient.active?)
  end

  def test_adds_new_recipient
    owner = random_owner
    list = Lists.new(owner: owner, pgsql: t_pgsql).add
    list.yaml = "friends:\n- jeff"
    login('jeff')
    email = "#{SecureRandom.hex[0..8]}@mailanes.com"
    post("/do-add?id=#{list.id}&email=#{email}")
    assert_equal(302, last_response.status, last_response.body)
    assert_equal(1, list.recipients.count)
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
    set_cookie('glogin=' + name)
    get('/')
    assert_equal(200, last_response.status, last_response.location)
  end
end
