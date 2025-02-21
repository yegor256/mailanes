# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require_relative 'test__helper'
require_relative '../objects/ago'

class AgoTest < Minitest::Test
  def test_just_now
    ago = Ago.new(Time.now)
    assert_equal('just now', ago.to_s)
  end

  def test_hour_ago
    assert_equal('1 hour ago', Ago.new(Time.now - (60 * 60)).to_s)
    assert_equal('6 hours ago', Ago.new(Time.now - (5 * 60 * 60) - (60 * 60) - 30).to_s)
    assert_equal('1 week ago', Ago.new(Time.now - (9 * 24 * 60 * 60) - (5 * 60 * 60) - (60 * 60) - 30).to_s)
  end
end
