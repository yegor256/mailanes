# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

ENV['RACK_ENV'] = 'test'

require 'simplecov'
require 'simplecov-cobertura'
unless SimpleCov.running || ENV['PICKS']
  SimpleCov.command_name('test')
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::CoberturaFormatter
    ]
  )
  SimpleCov.minimum_coverage 60
  SimpleCov.minimum_coverage_by_file 20
  SimpleCov.start do
    add_filter 'test/'
    add_filter 'vendor/'
    add_filter 'target/'
    track_files 'lib/**/*.rb'
    track_files '*.rb'
  end
end

require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]
Minitest.load :minitest_reporter

require 'loog'
require 'pgtk/pool'
require 'yaml'

module Minitest
  class Test
    def random_owner
      require 'securerandom'
      "u#{SecureRandom.hex[0..8]}-#{(Time.now.to_f * 1000).to_i}"
    end

    def t_log
      @t_log ||= ENV['TEST_VERBOSE_LOG'] ? Loog::VERBOSE : Loog::NULL
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
