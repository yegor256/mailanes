# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'

# Yaml Document.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class YamlDoc
  def initialize(text)
    @text = text
  end

  def empty?
    load.empty?
  end

  def load
    hash = YAML.safe_load(@text)
    hash = {} unless hash.is_a?(Hash)
    hash
  rescue StandardError
    {}
  end

  def save
    hash = YAML.safe_load(@text)
    raise 'Invalid YAML document' unless hash.is_a?(Hash)
    hash.to_yaml
  rescue StandardError => e
    raise UserError, "Can't parse the provided YAML: #{e.message}"
  end
end
