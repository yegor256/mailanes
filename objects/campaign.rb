# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'
require_relative 'lane'
require_relative 'list'
require_relative 'pipeline'
require_relative 'yaml_doc'
require_relative 'user_error'

# Campaign.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Campaign
  attr_reader :id

  def initialize(id:, pgsql:, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
  end

  def add(list)
    @pgsql.exec(
      'INSERT INTO source (list, campaign) VALUES ($1, $2) RETURNING id',
      [list.id, @id]
    ).first
  end

  def delete(list)
    @pgsql.exec(
      'DELETE FROM source WHERE list = $1 AND campaign = $2',
      [list.id, @id]
    ).first
  end

  def lists
    q = 'SELECT list.* FROM list JOIN source ON source.list = list.id WHERE source.campaign = $1'
    @pgsql.exec(q, [@id]).map do |r|
      List.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def lane
    hash = @pgsql.exec(
      'SELECT lane.* FROM lane JOIN campaign ON campaign.lane=lane.id WHERE campaign.id=$1',
      [@id]
    ).first
    Lane.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def decoy
    yaml['decoy'] || { 'amount' => 0 }
  end

  def title
    yaml['title'] || 'unknown'
  end

  def exists?
    !@pgsql.exec('SELECT id FROM campaign WHERE id=$1', [@id]).empty?
  end

  def yaml
    YamlDoc.new(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM campaign WHERE id=$1', [@id]).first['yaml']
    ).load
  end

  def yaml=(yaml)
    @pgsql.exec('UPDATE campaign SET yaml=$1 WHERE id=$2', [YamlDoc.new(yaml).save, @id])
    yml = YamlDoc.new(yaml).load
    if yml['decoy']
      raise UserError, 'Decoy amount must be set' if yml['decoy']['amount'].nil?
      raise UserError, 'Decoy amount must be a number' unless yml['decoy']['amount'].is_a?(Numeric)
      raise UserError, 'Decoy amount must be positive' if yml['decoy']['amount'].zero?
    end
    speed = yml['speed'] ? yml['speed'].to_i : 65_536
    @pgsql.exec('UPDATE campaign SET speed=$1 WHERE id=$2', [speed, @id])
    @hash = {}
  end

  def speed
    (@hash['speed'] || @pgsql.exec('SELECT speed FROM campaign WHERE id=$1', [@id]).first['speed']).to_i
  end

  def active?
    (@hash['active'] || @pgsql.exec('SELECT active FROM campaign WHERE id=$1', [@id]).first['active']) == 't'
  end

  def exhausted?
    !(@hash['exhausted'] || @pgsql.exec('SELECT exhausted FROM campaign WHERE id=$1', [@id]).first['exhausted']).nil?
  end

  def toggle
    @pgsql.exec('UPDATE campaign SET active=not(active) WHERE id=$1', [@id])
    @hash = {}
  end

  def created
    Time.parse(
      @hash['created'] || @pgsql.exec('SELECT created FROM campaign WHERE id=$1', [@id]).first['created']
    )
  end

  def merge_into(target)
    @pgsql.transaction do |t|
      t.exec('UPDATE source SET campaign = $1 WHERE campaign = $2', [target.id, @id])
      t.exec('UPDATE delivery SET campaign = $1 WHERE campaign = $2', [target.id, @id])
      t.exec('DELETE FROM campaign WHERE id = $1', [@id])
    end
    @hash = {}
  end

  def deliveries(limit: 50)
    q = [
      'SELECT delivery.* FROM delivery',
      'WHERE campaign = $1',
      'ORDER BY delivery.created DESC',
      'LIMIT $2'
    ]
    @pgsql.exec(q, [@id, limit]).map do |r|
      Delivery.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def deliveries_count(days: -1)
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'WHERE campaign=$1',
        days.positive? ? "AND delivery.created > NOW() - INTERVAL '#{days} DAYS'" : ''
      ],
      [@id]
    ).first['count'].to_i
  end

  def recipients_count
    @pgsql.exec(
      'SELECT COUNT(*) FROM recipient JOIN source ON source.list = recipient.list WHERE source.campaign=$1',
      [@id]
    ).first['count'].to_i
  end

  def bounce_count(days: -1)
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'JOIN recipient ON delivery.recipient = recipient.id',
        'WHERE campaign = $1 AND bounced IS NOT NULL',
        days.positive? ? "AND delivery.created > NOW() - INTERVAL '#{days} DAYS'" : ''
      ],
      [@id]
    ).first['count'].to_i
  end

  def unsubscribe_count(days: -1)
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'JOIN recipient ON delivery.recipient = recipient.id',
        'WHERE campaign = $1 AND unsubscribed IS NOT NULL',
        days.positive? ? "AND delivery.created > NOW() - INTERVAL '#{days} DAYS'" : ''
      ],
      [@id]
    ).first['count'].to_i
  end

  def pipeline
    @pgsql.exec(Pipeline.query(@id))
  end

  def pipeline_count
    @pgsql.exec(['SELECT COUNT(*) FROM ('] + Pipeline.query(@id) + [') x']).first['count'].to_i
  end
end
