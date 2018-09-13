# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require_relative 'pgsql'
require_relative 'campaign'
require_relative 'letter'
require_relative 'recipient'
require_relative 'deliveries'
require_relative 'tbot'

# Pipeline.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Pipeline
  def initialize(pgsql: Pgsql::TEST, tbot: Tbot.new)
    @pgsql = pgsql
    @tbot = tbot
  end

  def fetch(postman, cycles: 100)
    @pgsql.exec(
      'DELETE FROM delivery WHERE created < $1 AND details = $2',
      [(Time.now - 60 * 60).strftime('%Y-%m-%d %H:%M:%S'), '']
    )
    total = 0
    loop do
      break unless fetch_one(postman)
      total += 1
      break if total >= cycles
    end
  end

  def deactivate
    @pgsql.exec('SELECT * FROM letter WHERE active=true').each do |r|
      letter = Letter.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
      next unless letter.yaml['until'] && Time.parse(letter.yaml['until']) < Time.now
      letter.toggle
      letter.campaigns.each do |c|
        @tbot.notify(
          'deactivate',
          campaign.yaml,
          [
            "The letter ##{letter.id} \"#{letter.title}\" has been deactivated",
            "in the campaign ##{c.id} \"#{c.title}\" due to its UNTIL configuration."
          ].join(' ')
        )
      end
    end
    @pgsql.exec('SELECT * FROM campaign WHERE active=true').each do |r|
      campaign = Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
      next unless campaign.yaml['until'] && Time.parse(campaign.yaml['until']) < Time.now
      campaign.toggle
      @tbot.notify(
        'deactivate',
        campaign.yaml,
        [
          "The campaign ##{campaign.id} has been deactivated because of its UNTIL configuration:",
          "\"#{campaign.title}.\""
        ].join(' ')
      )
    end
  end

  def exhaust
    @pgsql.exec('SELECT * FROM campaign WHERE active = true AND exhausted IS NOT NULL').each do |r|
      campaign = Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
      queue = @pgsql.exec(Pipeline.query(campaign.id)).count
      next if queue.zero?
      @pgsql.exec('UPDATE campaign SET exhausted = NULL WHERE id = $1', [campaign.id])
      @tbot.notify(
        'exhaust',
        campaign.yaml,
        [
          "The campaign ##{campaign.id} is not exhausted anymore (#{queue} recipients in the queue):",
          "[\"#{campaign.title}\"](https://www.mailanes.com/campaign?id=#{campaign.id})."
        ].join(' ')
      )
    end
    @pgsql.exec('SELECT * FROM campaign WHERE active = true AND exhausted IS NULL').each do |r|
      campaign = Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
      next unless @pgsql.exec(Pipeline.query(campaign.id)).empty?
      @pgsql.exec('UPDATE campaign SET exhausted = NOW() WHERE id = $1', [campaign.id])
      @tbot.notify(
        'exhaust',
        campaign.yaml,
        [
          "The campaign ##{campaign.id} has been exhausted:",
          "[\"#{campaign.title}\"](https://www.mailanes.com/campaign?id=#{campaign.id})."
        ].join(' ')
      )
    end
  end

  def self.query(campaign = 0)
    chistory = [
      'SELECT COUNT(id) FROM delivery',
      'WHERE delivery.campaign=c.id',
      'AND delivery.created > NOW() - INTERVAL \'1 DAY\''
    ].join(' ')
    lhistory = [
      'SELECT COUNT(id) FROM delivery',
      'WHERE delivery.letter=letter.id',
      'AND delivery.created > NOW() - INTERVAL \'1 DAY\''
    ].join(' ')
    [
      'SELECT DISTINCT ON (recipient.id)',
      'recipient.id AS rid, c.id AS cid, letter.place, letter.id AS lid,',
      'list.id AS list_id, recipient.email AS email',
      'FROM recipient',
      'JOIN list ON list.id = recipient.list AND list.stop = false',
      'JOIN source ON source.list = list.id',
      'JOIN campaign AS c ON source.campaign = c.id AND c.active = true',
      'JOIN lane ON lane.id = c.lane',
      'JOIN letter ON lane.id = letter.lane AND letter.active = true',
      'LEFT JOIN delivery AS d',
      '  ON d.recipient = recipient.id',
      '    AND d.campaign = c.id',
      '    AND d.letter = letter.id',
      'LEFT JOIN delivery AS r',
      '  ON r.recipient = recipient.id',
      '    AND r.campaign = c.id',
      '    AND r.relax ' + (campaign.zero? ? '> NOW()' : '!= r.relax'),
      'LEFT JOIN recipient AS stop',
      '  ON recipient.email = stop.email',
      '    AND stop.id != recipient.id',
      '    AND stop.active = true',
      '    AND (SELECT COUNT(*) FROM list AS s WHERE s.id=stop.list AND s.owner=list.owner AND s.stop=true) > 0',
      'WHERE d.id IS NULL',
      '  AND r.id IS NULL',
      '  AND stop.id IS NULL',
      '  AND recipient.active=true',
      '  AND (recipient.created < NOW() - INTERVAL \'10 MINUTES\' OR recipient.email LIKE \'%@mailanes.com\')',
      campaign.zero? ? "AND (#{chistory}) < c.speed" : "AND c.id = #{campaign}",
      campaign.zero? ? "AND (#{lhistory}) < letter.speed" : ''
    ].join(' ')
  end

  private

  def fetch_one(postman)
    deliveries = Deliveries.new(pgsql: @pgsql)
    done = false
    @pgsql.exec(Pipeline.query + ' LIMIT 1').each do |r|
      campaign = Campaign.new(id: r['cid'].to_i, pgsql: @pgsql)
      letter = Letter.new(id: r['lid'].to_i, pgsql: @pgsql, tbot: @tbot)
      recipient = Recipient.new(id: r['rid'].to_i, pgsql: @pgsql)
      delivery = deliveries.add(campaign, letter, recipient)
      if letter.yaml['relax']
        time = Time.now
        if letter.yaml['relax'] =~ /^[0-9]+:[0-9]+:[0-9]+$/
          days, hours, minutes = letter.yaml['relax'].split(':')
          time += (days.to_i * 24 * 60 + hours.to_i * 60 + minutes.to_i) * 60
        elsif letter.yaml['relax'] =~ /^[0-9]{2}-[0-9]{2}-[0-9]{4}$/
          time = Time.parse(letter.yaml['relax'])
        end
        delivery.save_relax(time)
      end
      postman.deliver(delivery, tbot: @tbot)
      done = true
    end
    done
  end
end
