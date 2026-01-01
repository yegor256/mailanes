# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'
require_relative 'test__helper'
require_relative '../objects/decoy'

class DecoyTest < Minitest::Test
  def test_pop3
    skip('It is live test')
    cfg = YAML.load_file('/code/home/assets/mailanes/config.yml')
    pop = cfg['pop3']
    decoy = Decoy.new(
      pop['host'],
      pop['port'].to_i,
      pop['login'],
      pop['password']
    )
    decoy.fetch
  end
end
