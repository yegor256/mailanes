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

require 'yaml'
require 'telebot'

# Telegram Bot.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Tbot
  def initialize(token)
    @token = token
    @client = Telebot::Client.new(token) unless token.empty?
  end

  def start
    return if @token.empty?
    Telebot::Bot.new(@token).run do |client, message|
      client.send_message(
        chat_id: message.chat.id,
        text: "Here is your chat ID: #{message.chat.id}. Use it in your YAML configs."
      )
    end
  end

  def notify(yaml, msg)
    return unless yaml['notify'] && yaml['notify']['telegram']
    post(yaml['notify']['telegram'].to_i, msg)
  end

  def post(chat, msg)
    return if @token.empty?
    @client.send_message(chat_id: chat, text: msg)
  end
end
