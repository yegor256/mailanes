# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'English'
require 'rake'
require 'rake/clean'
require 'rubygems'
require 'yaml'

raise "Invalid encoding \"#{Encoding.default_external}\"" unless Encoding.default_external.to_s == 'UTF-8'

ENV['RACK_ENV'] = 'test'

task default: %i[clean test rubocop haml_lint xcop]

require 'rake/testtask'
Rake::TestTask.new(test: %i[pgsql liquibase]) do |test|
  ENV['TEST_VERBOSE_LOG'] = 'true' if ARGV.include?('--verbose')
  Rake::Cleaner.cleanup_files(['coverage'])
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
  test.warning = false
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.fail_on_error = true
end

require 'xcop/rake_task'
Xcop::RakeTask.new(:xcop) do |task|
  task.includes = ['**/*.xml', '**/*.xsl', '**/*.xsd', '**/*.html']
  task.excludes = ['target/**/*', 'coverage/**/*', 'vendor/**/*']
end

require 'pgtk/pgsql_task'
Pgtk::PgsqlTask.new(:pgsql) do |t|
  t.dir = 'target/pgsql'
  t.fresh_start = true
  t.user = 'test'
  t.password = 'test'
  t.dbname = 'test'
  t.yaml = 'target/pgsql-config.yml'
end

require 'pgtk/liquibase_task'
Pgtk::LiquibaseTask.new(:liquibase) do |t|
  t.master = 'liquibase/master.xml'
  t.yaml = ['target/pgsql-config.yml', 'config.yml']
end

require 'haml_lint/rake_task'
HamlLint::RakeTask.new

desc 'Check the quality of config file'
task(:config) do
  YAML.safe_load(File.open('config.yml')).to_yaml
end

task(run: %i[pgsql liquibase]) do
  `rerun -b "RACK_ENV=test rackup"`
end
