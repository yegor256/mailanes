# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require_relative 'campaign'
require_relative 'letter'
require_relative 'recipient'
require_relative 'tbot'

# Delivery.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Delivery
  attr_reader :id

  def initialize(id:, pgsql:, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
  end

  def recipient
    id = @hash['recipient'] || @pgsql.exec('SELECT recipient FROM delivery WHERE id=$1', [@id]).first['recipient']
    Recipient.new(id: id.to_i, pgsql: @pgsql, hash: @hash.slice('bounced'))
  end

  def letter?
    !(@hash['letter'] || @pgsql.exec('SELECT letter FROM delivery WHERE id=$1', [@id]).first['letter']).nil?
  end

  def letter(tbot: Tbot.new)
    id = @hash['letter'] || @pgsql.exec('SELECT letter FROM delivery WHERE id=$1', [@id]).first['letter']
    Letter.new(
      id: id.to_i,
      pgsql: @pgsql,
      tbot: tbot
    )
  end

  def campaign?
    !(@hash['campaign'] || @pgsql.exec('SELECT campaign FROM delivery WHERE id=$1', [@id]).first['campaign']).nil?
  end

  def campaign
    id = @hash['campaign'] || @pgsql.exec('SELECT campaign FROM delivery WHERE id=$1', [@id]).first['campaign']
    Campaign.new(id: id.to_i, pgsql: @pgsql)
  end

  def details
    @hash['details'] || @pgsql.exec(
      'SELECT details FROM delivery WHERE id=$1', [@id]
    ).first['details'].force_encoding('UTF-8')
  end

  def close(details)
    @pgsql.exec('UPDATE delivery SET details=$1 WHERE id=$2', [details, @id])
    @hash = {}
  end

  def created
    Time.parse(
      @hash['created'] || @pgsql.exec('SELECT created FROM delivery WHERE id=$1', [@id]).first['created']
    )
  end

  def save_relax(time)
    @pgsql.exec('UPDATE delivery SET relax=$1 WHERE id=$2', [time.strftime('%Y-%m-%d %H:%M:%S'), @id])
    @hash = {}
  end

  def relax
    @hash['relax'] || @pgsql.exec('SELECT relax FROM delivery WHERE id=$1', [@id]).first['relax']
  end

  def just_opened(details = '')
    @pgsql.exec('UPDATE delivery SET opened = $2 WHERE id=$1', [@id, "#{Time.now.utc.iso8601}: #{details}"])
    @hash = {}
  end

  def opened
    @hash['opened'] || @pgsql.exec('SELECT opened FROM delivery WHERE id=$1', [@id]).first['opened']
  end

  def delete
    @pgsql.exec('DELETE FROM delivery WHERE id=$1', [@id])
  end

  def bounced?
    !(@hash['bounced'] || @pgsql.exec('SELECT bounced FROM delivery WHERE id=$1', [@id]).first['bounced']).nil?
  end

  def bounce
    @pgsql.exec('UPDATE delivery SET bounced=NOW() WHERE id=$1', [@id])
    @hash = {}
  end

  def unsubscribe
    @pgsql.exec('UPDATE delivery SET unsubscribed=NOW() WHERE id=$1', [@id])
    @hash = {}
  end
end
