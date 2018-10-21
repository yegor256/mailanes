# frozen_string_literal: true

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
require_relative 'list'
require_relative 'user_error'

# Recipient.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Recipient
  attr_reader :id

  def initialize(id:, pgsql: Pgsql::TEST, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    raise 'ID has to be larger than zero' if id.zero?
    @id = id
    @pgsql = pgsql
    @hash = hash
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
    YAML.safe_load(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM recipient WHERE id=$1', [@id])[0]['yaml']
    )
  end

  def save_yaml(yaml)
    YAML.safe_load(yaml)
    @pgsql.exec('UPDATE recipient SET yaml=$1 WHERE id=$2', [yaml, @id])
    @hash = {}
  end

  def change_email(email)
    @pgsql.exec('UPDATE recipient SET email=$1 WHERE id=$2', [email, @id])
    @hash = {}
  end

  def toggle
    @pgsql.exec('UPDATE recipient SET active=NOT(active) WHERE id=$1', [@id])
    @hash = {}
  end

  def delete
    @pgsql.exec('DELETE FROM recipient WHERE id=$1', [@id])
    @hash = {}
  end

  def active?
    (@hash['active'] || @pgsql.exec('SELECT active FROM recipient WHERE id=$1', [@id])[0]['active']) == 't'
  end

  def bounced?
    !(@hash['bounced'] || @pgsql.exec('SELECT bounced FROM recipient WHERE id=$1', [@id])[0]['bounced']).nil?
  end

  def bounce
    @pgsql.exec('UPDATE recipient SET bounced=NOW() WHERE id=$1', [@id])
    @hash = {}
  end

  # Amount of days to wait until something new can
  # be delivered to this guy (can be zero)
  def relax
    max = @pgsql.exec('SELECT MAX(relax) FROM delivery WHERE recipient = $1', [@id])[0]['max']
    relax = max.nil? ? Time.now : Time.parse(max)
    ((relax - Time.now) / (24 * 60 * 60)).round.to_i
  end

  def email
    @hash['email'] || @pgsql.exec('SELECT email FROM recipient WHERE id=$1', [@id])[0]['email']
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

  def move_to(list)
    @pgsql.exec('UPDATE recipient SET list = $1 WHERE id = $2', [list.id, @id])
  end

  def deliveries(limit: 50)
    q = [
      'SELECT * FROM delivery',
      'WHERE delivery.recipient=$1',
      'ORDER BY delivery.created DESC',
      'LIMIT $2'
    ].join(' ')
    @pgsql.exec(q, [@id, limit]).map do |r|
      Delivery.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end
end
