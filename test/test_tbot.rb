# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/tbot'

class TbotTest < Minitest::Test
  def test_sends_message
    skip
    tbot = Tbot.new('--put it here--')
    Thread.new do
      tbot.start
    end
  end
end
