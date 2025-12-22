# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'delivery'
require_relative 'user_error'

# Deliveries.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Deliveries
  def initialize(pgsql:)
    @pgsql = pgsql
  end

  def add(campaign, letter, recipient)
    id = @pgsql.exec(
      'INSERT INTO delivery (campaign, letter, recipient) VALUES ($1, $2, $3) RETURNING id',
      [campaign.id, letter.id, recipient.id]
    )
    raise UserError, "Failed to add delivery for C:##{campaign}/L:#{letter}/R:#{recipient}" if id.empty?
    Delivery.new(
      id: id[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def delivery(id)
    hash = @pgsql.exec('SELECT * FROM delivery WHERE id=$1', [id]).first
    raise UserError, "Delivery ##{id} not found" if hash.nil?
    Delivery.new(
      id: id,
      pgsql: @pgsql,
      hash: hash
    )
  end
end
