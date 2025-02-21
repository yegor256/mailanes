# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'campaign'

# Campaigns.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Campaigns
  def initialize(owner:, pgsql:)
    @owner = owner
    @pgsql = pgsql
  end

  def all
    @pgsql.exec('SELECT * FROM campaign WHERE owner=$1 ORDER BY created DESC', [@owner]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(list, lane, title = 'unknown')
    yaml = "title: #{title}\n"
    campaign = Campaign.new(
      id: @pgsql.exec(
        'INSERT INTO campaign (owner, lane, yaml) VALUES ($1, $2, $3) RETURNING id',
        [@owner, lane.id, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
    campaign.add(list)
    campaign
  end

  def campaign(id)
    hash = @pgsql.exec(
      'SELECT * FROM campaign WHERE id=$1 AND owner=$2',
      [id, @owner]
    )[0]
    Campaign.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def total_deliveries(days = 7)
    @pgsql.exec(
      [
        'SELECT COUNT(1) FROM delivery',
        'JOIN campaign ON delivery.campaign = campaign.id',
        "WHERE campaign.owner = $1 AND delivery.created > NOW() - INTERVAL '#{days} DAYS'"
      ],
      [@owner]
    )[0]['count'].to_i
  end

  def total_bounced(days = 7)
    @pgsql.exec(
      [
        'SELECT COUNT(1) FROM recipient',
        'JOIN list ON recipient.list = list.id',
        'JOIN delivery ON recipient.id = delivery.recipient',
        "WHERE list.owner = $1 AND delivery.bounced > NOW() - INTERVAL '#{days} DAYS'"
      ],
      [@owner]
    )[0]['count'].to_i
  end
end
