# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'test__helper'
require_relative '../objects/decoy'

class DecoyTest < Minitest::Test
  def test_pop3
    skip
    decoy = Decoy.new(
      'pop.secureserver.net',
      995,
      'decoy@mailanes.com',
      '----'
    )
    decoy.fetch
  end
end
