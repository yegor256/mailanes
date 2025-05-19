# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'test__helper'
require_relative '../objects/decoy'

class DecoyTest < Minitest::Test
  def test_pop3
    skip('It is live test')
    decoy = Decoy.new(
      'outlook.office365.com',
      995,
      'reply@mailanes.com',
      '--skipped--'
    )
    decoy.fetch
  end
end
