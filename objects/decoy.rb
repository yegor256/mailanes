# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'elapsed'
require 'logger'
require 'net/pop'

# Just delete all emails from POP3 decoy account.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Decoy
  def initialize(host, port, login, password, log: Loog::NULL)
    @host = host
    @port = port
    @login = login
    @password = password
    @log = log
  end

  def fetch
    elapsed(@log, level: Logger::INFO) do
      total = 0
      Net::POP3.enable_ssl
      Net::POP3.start(@host, @port, @login, @password) do |pop|
        pop.each_mail do |m|
          m.delete
          total += 1
          GC.start if (total % 100).zero?
        end
      end
      throw :"#{total} decoy email(s) processed by #{@login.inspect}"
    rescue Net::ReadTimeout => e
      throw :"Failed to process decoy emails: #{e.message}"
    end
  end
end
