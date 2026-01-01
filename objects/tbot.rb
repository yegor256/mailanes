# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'
require 'telebot'

# Telegram Bot.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Tbot
  # Fake one
  class Fake
    attr_reader :sent

    def initialize
      @sent = []
    end

    def notify(_type, _yaml, *msg)
      @sent << msg.join(' ')
    end

    def post(chat, msg)
      @sent << "#{chat}: #{msg}"
    end
  end

  def initialize(token = '')
    @token = token
    @client = Telebot::Client.new(token) unless token.empty?
  end

  def start
    return if @token.empty?
    Telebot::Bot.new(@token).run do |client, message|
      post(
        message.chat.id,
        [
          "Here is your chat ID: #{message.chat.id}.",
          'Use it in your [YAML configs](https://github.com/yegor256/mailanes).'
        ],
        c: client
      )
    end
  end

  def notify(type, yaml, *msg)
    return unless yaml['notify'] && yaml['notify']['telegram']
    return if yaml['notify']['ignore'].is_a?(Array) && yaml['notify']['ignore'].include?(type)
    chat = yaml['notify']['telegram'].to_i
    return unless chat.positive?
    post(chat, msg.flatten.join(' '))
  end

  def post(chat, msg, c: @client)
    return if @token.empty?
    begin
      c.send_message(
        chat_id: chat,
        parse_mode: 'Markdown',
        disable_web_page_preview: true,
        text: msg
      )
    rescue Telebot::Error => e
      raise "#{e.message} when trying to post to Telegram chat ##{chat}: \"#{msg}\""
    end
  end
end
