# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'lists'
require_relative 'lanes'
require_relative 'campaigns'
require_relative 'deliveries'

# Owner.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Owner
  def initialize(login:, pgsql:)
    @login = login
    @pgsql = pgsql
  end

  def months(source)
    @pgsql.exec(
      [
        'SELECT CONCAT(DATE_PART(\'year\', recipient.created), \'/\',',
        '  DATE_PART(\'month\', recipient.created)) AS month,',
        'COUNT(1) AS total,',
        'COUNT(1) FILTER (WHERE bounced IS NOT NULL) as bad',
        'FROM recipient',
        'LEFT JOIN delivery ON recipient.id = delivery.recipient',
        'WHERE source = $1',
        'GROUP BY month',
        'ORDER BY month DESC'
      ],
      [source.downcase.strip]
    ).map { |r| { month: r['month'], total: r['total'].to_i, bad: r['bad'].to_i } }
  end

  def lists
    Lists.new(owner: @login, pgsql: @pgsql)
  end

  def lanes
    Lanes.new(owner: @login, pgsql: @pgsql)
  end

  def campaigns
    Campaigns.new(owner: @login, pgsql: @pgsql)
  end

  def deliveries
    Deliveries.new(pgsql: @pgsql)
  end
end
