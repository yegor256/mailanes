# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'rack/test'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/tbot'

class TbotTest < Minitest::Test
  def test_sends_message
    skip('It is live test')
    tbot = Tbot.new('--put it here--')
    Thread.new do
      tbot.start
    end
  end
end
