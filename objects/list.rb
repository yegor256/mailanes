# frozen_string_literal: true

# Copyright (c) 2018-2022 Yegor Bugayenko
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

require 'yaml'
require_relative 'recipients'
require_relative 'campaign'
require_relative 'yaml_doc'

# List.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2022 Yegor Bugayenko
# License:: MIT
class List
  attr_reader :id

  def initialize(id:, pgsql:, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
  end

  def recipients
    hash = {}
    hash['total'] = @hash['total_recipients'].to_i if @hash.key?('total_recipients')
    Recipients.new(list: self, pgsql: @pgsql, hash: hash)
  end

  def title
    yaml['title'] || 'unknown'
  end

  def yaml
    YamlDoc.new(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM list WHERE id=$1', [@id])[0]['yaml']
    ).load
  end

  def yaml=(yaml)
    @pgsql.exec('UPDATE list SET yaml=$1 WHERE id=$2', [YamlDoc.new(yaml).save, @id])
    yml = YamlDoc.new(yaml).load
    stop = yml['stop'] || false
    @pgsql.exec('UPDATE list SET stop=$1 WHERE id=$2', [stop, @id])
    @hash = {}
  end

  # Confirm required for all new subscribers?
  def confirmation_required?
    yaml['confirmation_required']
  end

  def owner
    @hash['owner'] || @pgsql.exec('SELECT owner FROM list WHERE id=$1', [@id])[0]['owner']
  end

  def stop?
    (@hash['stop'] || @pgsql.exec('SELECT stop FROM list WHERE id=$1', [@id])[0]['stop']) == 't'
  end

  def friend?(login)
    friends = yaml['friends']
    return false unless friends.is_a?(Array)
    friends.map(&:downcase).include?(login)
  end

  def created
    Time.parse(
      @hash['created'] || @pgsql.exec('SELECT created FROM list WHERE id=$1', [@id])[0]['created']
    )
  end

  def campaigns
    q = [
      'SELECT campaign.* FROM campaign',
      'JOIN source ON source.campaign = campaign.id',
      'WHERE source.list = $1',
      'ORDER BY campaign.created DESC'
    ].join(' ')
    @pgsql.exec(q, [@id]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def deliveries_count
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'JOIN recipient ON recipient.id=delivery.recipient',
        'JOIN list ON recipient.list=list.id',
        'WHERE list.id=$1'
      ].join(' '),
      [@id]
    )[0]['count'].to_i
  end

  def opened_count
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM recipient',
        'JOIN delivery ON recipient.id = delivery.recipient AND delivery.opened != \'\'',
        'WHERE recipient.list = $1'
      ].join(' '),
      [@id]
    )[0]['count'].to_i
  end

  def absorb_counts
    q = [
      'SELECT * FROM',
      '  (SELECT *, (SELECT COUNT(1) FROM recipient AS s',
      '    JOIN recipient AS t ON s.email = t.email AND s.list != t.list',
      '    AND s.list = list.id AND t.list = $2) AS total',
      '    FROM list',
      '    WHERE owner = $1 AND list.stop = false) AS x',
      'WHERE total > 0'
    ].join(' ')
    @pgsql.exec(q, [owner, @id]).map do |r|
      {
        list: List.new(id: r['id'].to_i, pgsql: @pgsql, hash: r),
        total: r['total'].to_i
      }
    end
  end

  def absorb_candidates(list)
    q = [
      'SELECT s.id AS s_id, s.list AS s_list, s.email AS s_email,',
      't.id AS t_id, t.list AS t_list, t.email AS t_email',
      'FROM recipient AS s',
      'JOIN recipient AS t ON s.email = t.email AND s.list != t.list',
      'AND s.list = $1 AND t.list = $2'
    ].join(' ')
    @pgsql.exec(q, [list.id, @id]).map do |r|
      {
        from: Recipient.new(
          id: r['s_id'].to_i, pgsql: @pgsql, hash: {
            'id': r['s_id'].to_i,
            'list': r['s_list'].to_i,
            'email': r['s_email']
          }
        ),
        to: Recipient.new(
          id: r['t_id'].to_i, pgsql: @pgsql, hash: {
            'id': r['t_id'].to_i,
            'list': r['t_list'].to_i,
            'email': r['t_email']
          }
        )
      }
    end
  end

  # Take duplicate recipients from this list and merge them
  # into itself
  def absorb(list)
    @pgsql.transaction do |t|
      t.exec(
        [
          'DELETE FROM delivery WHERE id IN',
          '(SELECT id FROM delivery',
          '  JOIN (SELECT s.id AS from, t.id AS to FROM recipient AS s',
          '      JOIN recipient AS t ON s.email = t.email AND s.list != t.list',
          '      AND s.list = $1 AND t.list = $2) AS r',
          '    ON r.to = delivery.recipient',
          '  WHERE (SELECT COUNT(*) FROM delivery AS d',
          '    WHERE d.campaign = delivery.campaign',
          '    AND d.letter = delivery.letter',
          '    AND d.recipient = r.from) > 0)'
        ].join(' '),
        [list.id, @id]
      )
      t.exec(
        [
          'UPDATE delivery SET recipient = alt.to FROM',
          '(SELECT s.id AS from, t.id AS to FROM recipient AS s',
          '  JOIN recipient AS t ON s.email = t.email AND s.list != t.list',
          '  AND s.list = $1 AND t.list = $2) AS alt',
          'WHERE recipient = alt.from'
        ].join(' '),
        [list.id, @id]
      )
      t.exec(
        [
          'DELETE FROM recipient WHERE id IN',
          '(SELECT s.id FROM recipient AS s',
          '  JOIN recipient AS t ON s.email = t.email AND s.list != t.list',
          '  AND s.list = $1 AND t.list = $2)'
        ].join(' '),
        [list.id, @id]
      )
    end
  end
end
