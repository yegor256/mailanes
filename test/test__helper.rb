# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.root(File.expand_path(File.join(__dir__, '..')))
SimpleCov.start

require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

require 'yaml'
require 'minitest/autorun'
require 'pgtk/pool'
require 'loog'
module Minitest
  class Test
    def random_owner
      require 'securerandom'
      "u#{SecureRandom.hex[0..8]}-#{(Time.now.to_f * 1000).to_i}"
    end

    def t_log
      @t_log ||= ENV['TEST_QUIET_LOG'] ? Loog::NULL : Loog::VERBOSE
    end

    def t_pgsql
      # rubocop:disable Style/ClassVars
      @@t_pgsql ||= Pgtk::Pool.new(
        Pgtk::Wire::Yaml.new(File.join(__dir__, '../target/pgsql-config.yml')),
        log: t_log
      ).start
      # rubocop:enable Style/ClassVars
    end
  end
end
