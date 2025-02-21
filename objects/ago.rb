# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'time'
require 'time_difference'

# The "time ago" piece of text.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Ago
  def initialize(time)
    @time = time
  end

  # Turn it into a string.
  def to_s
    diff = TimeDifference.between(@time, Time.now).humanize
    if diff.nil?
      'just now'
    else
      "#{diff.split(' ', 3).take(2).join(' ').downcase.gsub(/[^a-z0-9 ]/, '')} ago"
    end
  end
end
