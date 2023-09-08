# frozen_string_literal: true

# Copyright (c) 2018-2023 Yegor Bugayenko
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

require_relative 'list'
require_relative 'user_error'
require_relative 'yaml_doc'

# Recipient.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2023 Yegor Bugayenko
# License:: MIT
class Recipient
  attr_reader :id

  def initialize(id:, pgsql:, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    raise 'ID has to be larger than zero' if id.zero?
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
  end

  def list
    hash = @pgsql.exec(
      'SELECT list.* FROM list JOIN recipient ON recipient.list=list.id WHERE recipient.id=$1',
      [@id]
    )[0]
    raise UserError, "Recipient #{@id} is outside of the list?" if hash.nil?
    List.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def yaml
    YamlDoc.new(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM recipient WHERE id=$1', [@id])[0]['yaml']
    ).load
  end

  def yaml=(yaml)
    @pgsql.exec('UPDATE recipient SET yaml=$1 WHERE id=$2', [YamlDoc.new(yaml).save, @id])
    @hash = {}
  end

  def email=(email)
    @pgsql.exec('UPDATE recipient SET email=$1 WHERE id=$2', [email, @id])
    @hash = {}
  end

  def email
    @hash['email'] || @pgsql.exec('SELECT email FROM recipient WHERE id=$1', [@id])[0]['email']
  end

  def confirm!(set: true)
    @pgsql.transaction do |t|
      t.exec('UPDATE recipient SET confirmed = $1 WHERE id=$2', [set, @id])
      t.exec('INSERT INTO delivery (recipient, details) VALUES ($1, $2)', [@id, 'Confirmed'])
    end
    @hash = {}
  end

  def confirmed?
    (@hash['confirmed'] || @pgsql.exec('SELECT confirmed FROM recipient WHERE id=$1', [@id])[0]['confirmed']) == 't'
  end

  def toggle(msg: nil)
    msg = "#{active? ? 'Dectivated' : 'Activated'} by the owner of the list" if msg.nil?
    @pgsql.transaction do |t|
      t.exec('UPDATE recipient SET active=NOT(active) WHERE id=$1', [@id])
      t.exec(
        'INSERT INTO delivery (recipient, details) VALUES ($1, $2)',
        [@id, msg]
      )
    end
    @hash = {}
  end

  def delete
    @pgsql.exec('DELETE FROM recipient WHERE id=$1', [@id])
    @hash = {}
  end

  def active?
    (@hash['active'] || @pgsql.exec('SELECT active FROM recipient WHERE id=$1', [@id])[0]['active']) == 't'
  end

  # Amount of days to wait until something new can
  # be delivered to this guy (can be zero)
  def relax
    max = @pgsql.exec('SELECT MAX(relax) FROM delivery WHERE recipient = $1', [@id])[0]['max']
    relax = max.nil? ? Time.now : Time.parse(max)
    ((relax - Time.now) / (24 * 60 * 60)).round.to_i
  end

  def first
    @hash['first'] || @pgsql.exec('SELECT first FROM recipient WHERE id=$1', [@id])[0]['first']
  end

  def last
    @hash['last'] || @pgsql.exec('SELECT last FROM recipient WHERE id=$1', [@id])[0]['last']
  end

  def source
    @hash['source'] || @pgsql.exec('SELECT source FROM recipient WHERE id=$1', [@id])[0]['source']
  end

  def created
    Time.parse(
      @hash['created'] || @pgsql.exec('SELECT created FROM recipient WHERE id=$1', [@id])[0]['created']
    )
  end

  def post_event(msg)
    @pgsql.exec('INSERT INTO delivery (recipient, details) VALUES ($1, $2)', [@id, msg.strip])
  end

  def move_to(target)
    @pgsql.transaction do |t|
      t.exec('UPDATE recipient SET list = $1 WHERE id = $2', [target.id, @id])
      t.exec(
        'INSERT INTO delivery (recipient, details) VALUES ($1, $2)',
        [@id, "Moved from list ##{list.id} to list ##{target.id}"]
      )
    end
  end

  def bounced?
    d = @pgsql.exec('SELECT bounced FROM delivery WHERE recipient = $1 AND bounced IS NOT NULL', [@id])[0]
    return false if d.nil?
    !d['bounced'].nil?
  end

  def deliveries(limit: 50)
    q = [
      'SELECT * FROM delivery',
      'WHERE delivery.recipient=$1',
      'ORDER BY delivery.created DESC',
      'LIMIT $2'
    ]
    @pgsql.exec(q, [@id, limit]).map do |r|
      Delivery.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end
end
