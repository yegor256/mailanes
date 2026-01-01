# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'test__helper'
require_relative '../objects/hex'

class HexTest < Minitest::Test
  def test_prints
    hex = Hex::FromText.new('How are you?').to_s
    assert_equal('486f772061726520796f753f', hex)
  end

  def test_parses
    text = Hex::ToText.new('486f772061726520796f753f').to_s
    assert_equal('How are you?', text)
  end
end
