# frozen_string_literal: true

# Copyright (c) 2019 Yegor Bugayenko
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

STDOUT.sync = true

require 'time'
require 'haml'
require 'yaml'
require 'json'
require 'geocoder'
require 'sinatra'
require 'sinatra/cookies'
require 'raven'
require 'glogin'
require 'glogin/codec'
require_relative 'version'
require_relative 'objects/user_error'
require_relative 'objects/owner'
require_relative 'objects/pipeline'
require_relative 'objects/postman'
require_relative 'objects/tbot'
require_relative 'objects/ago'
require_relative 'objects/bounces'
require_relative 'objects/hex'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

configure do
  Haml::Options.defaults[:format] = :xhtml
  config = {
    'github' => {
      'client_id' => '?',
      'client_secret' => '?',
      'encryption_secret' => ''
    },
    'pop3' => {
      'host' => '',
      'login' => '',
      'password' => ''
    },
    'pgsql' => {
      'host' => 'localhost',
      'port' => 0,
      'user' => 'test',
      'dbname' => 'test',
      'password' => 'test'
    },
    'telegram_token' => '',
    'token_secret' => '',
    'sentry' => ''
  }
  config = YAML.safe_load(File.open(File.join(File.dirname(__FILE__), 'config.yml'))) unless ENV['RACK_ENV'] == 'test'
  if ENV['RACK_ENV'] != 'test'
    Raven.configure do |c|
      c.dsn = config['sentry']
      c.release = VERSION
    end
  end
  set :dump_errors, false
  set :show_exceptions, false
  set :config, config
  set :logging, true
  set :server_settings, timeout: 25
  set :glogin, GLogin::Auth.new(
    config['github']['client_id'],
    config['github']['client_secret'],
    'https://www.mailanes.com/github-callback'
  )
  set :codec, GLogin::Codec.new(config['token_secret'])
  set :pgsql, Pgsql.new(
    host: config['pgsql']['host'],
    port: config['pgsql']['port'].to_i,
    dbname: config['pgsql']['dbname'],
    user: config['pgsql']['user'],
    password: config['pgsql']['password']
  )
  set :postman, Postman.new(settings.codec)
  set :tbot, Tbot.new(config['telegram_token'])
  set :bounces, Bounces.new(
    config['pop3']['host'],
    config['pop3']['login'],
    config['pop3']['password'],
    settings.codec,
    pgsql: settings.pgsql
  )
  set :pipeline, Pipeline.new(pgsql: settings.pgsql, tbot: settings.tbot)
  if ENV['RACK_ENV'] != 'test'
    Thread.new do
      settings.tbot.start
    end
    Thread.new do
      loop do
        sleep 60
        start = Time.now
        begin
          settings.pipeline.fetch(settings.postman)
          settings.pipeline.deactivate
          settings.pipeline.exhaust
          settings.bounces.fetch(tbot: settings.tbot)
        rescue StandardError => e
          puts "#{e.message}\n\t#{e.backtrace.join("\n\t")}"
          Raven.capture_exception(e)
        end
        puts "Pipeline done in #{(Time.now - start).round(2)}s"
      end
    end
  end
end

before '/*' do
  @locals = {
    ver: VERSION,
    login_link: settings.glogin.login_uri,
    request_ip: request.ip
  }
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:user] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret'],
        context
      ).to_user
    rescue OpenSSL::Cipher::CipherError => _
      cookies.delete(:glogin)
    end
  end
  if params[:auth]
    @locals[:user] = {
      login: settings.codec.decrypt(Hex::ToText.new(params[:auth]).to_s)
    }
  end
end

get '/github-callback' do
  cookies[:glogin] = GLogin::Cookie::Open.new(
    settings.glogin.user(params[:code]),
    settings.config['github']['encryption_secret'],
    context
  ).to_s
  redirect to('/')
end

get '/logout' do
  cookies.delete(:glogin)
  redirect to('/')
end

get '/hello' do
  haml :hello, layout: :layout, locals: merged(
    title: '/'
  )
end

get '/' do
  haml :index, layout: :layout, locals: merged(
    title: '/',
    lists: owner.lists,
    lanes: owner.lanes,
    campaigns: owner.campaigns
  )
end

get '/lists' do
  mine = owner.lists.all
  haml :lists, layout: :layout, locals: merged(
    title: '/lists',
    lists: owner.lists,
    found: params[:query] && !mine.empty? ? mine[0].recipients.all(query: params[:query], in_list_only: false) : nil
  )
end

post '/add-list' do
  list = owner.lists.add(params[:title])
  flash('/lists', "List ##{list.id} was created")
end

get '/list' do
  list = owner.lists.list(params[:id].to_i)
  haml :list, layout: :layout, locals: merged(
    title: "##{list.id}",
    lists: owner.lists,
    list: list
  )
end

post '/absorb' do
  list = owner.lists.list(params[:id].to_i)
  source = owner.lists.list(params[:list].to_i)
  if params[:dry] == 'dry'
    return haml :absorb, layout: :layout, locals: merged(
      title: "##{list.id}",
      source: source,
      list: list,
      candidates: list.absorb_candidates(source)
    )
  end
  list.absorb(source)
  flash("/list?id=#{list.id}", "Duplicates from the list ##{source.id} have been moved to the list ##{list.id}")
end

post '/save-list' do
  list = owner.lists.list(params[:id].to_i)
  list.save_yaml(params[:yaml])
  flash("/list?id=#{list.id}", "YAML has been saved to the list ##{list.id}")
end

post '/add-recipient' do
  list = owner.lists.list(params[:id].to_i)
  email = params[:email].downcase.strip
  flash("/list?id=#{list.id}", "Recipient with email #{email} already exists") if list.recipients.exists?(email)
  recipient = list.recipients.add(
    email,
    first: params[:first].strip,
    last: params[:last].strip,
    source: "@#{current_user}"
  )
  recipient.post_event("Added to the list ##{list.id} by @#{current_user}")
  flash("/list?id=#{list.id}", "The recipient ##{recipient.id} has been added to the list ##{list.id}")
end

get '/recipient' do
  recipient = Recipient.new(id: params[:id].to_i, pgsql: settings.pgsql)
  list = shared_list(recipient.list.id)
  haml :recipient, layout: :layout, locals: merged(
    title: "##{recipient.id}",
    list: list,
    recipient: recipient,
    targets: owner.lists.all
  )
end

get '/toggle-recipient' do
  list = shared_list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  recipient.toggle
  recipient.post_event((recipient.active? ? 'Activated' : 'Deactivated') + " by @#{current_user}")
  flash("/recipient?id=#{recipient.id}", "The recipient ##{recipient.id} has been toggled")
end

get '/delete-recipient' do
  list = shared_list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  unless recipient.deliveries.empty?
    flash("/recipient?id=#{recipient.id}", "Can't delete it, there were some deliveries")
  end
  recipient.delete
  flash("/list?id=#{list.id}", "The recipient has been deleted from the list ##{list.id}")
end

post '/change-email' do
  list = shared_list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  before = recipient.email
  after = params[:email]
  recipient.change_email(after)
  recipient.post_event("Email changed from #{before} to #{after} by @#{current_user}")
  flash("/recipient?id=#{recipient.id}", "The email has been changed for the recipient ##{recipient.id}")
end

post '/comment-recipient' do
  list = shared_list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  recipient.post_event("#{params[:comment]} / posted by @#{current_user}")
  settings.tbot.notify(
    'comment',
    list.yaml,
    [
      "The recipient ##{recipient.id}/#{params[:email]}",
      "has got a new comment from #{current_user}:\n\n",
      params[:comment]
    ].join(' ')
  )
  flash(
    "/recipient?id=#{recipient.id}",
    "The comment has been posted to the recipient ##{recipient.id}"
  )
end

get '/block-recipient' do
  list = shared_list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  stops = owner.lists.all.select do |s|
    return false unless s.stop?
    return false if s.recipients.exists?(recipient.email)
    s.recipients.add(recipient.email)
    recipient.post_event("It was added to the block list ##{s.id}.")
    true
  end
  flash(
    "/recipient?id=#{recipient.id}",
    "The recipient has been added to #{stops.count} block lists"
  )
end

post '/move-recipient' do
  list = owner.lists.list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  target = owner.lists.list(params[:target].to_i)
  recipient.move_to(target)
  recipient.post_event("Moved from the list ##{list.id} to the list ##{target.id} by @#{current_user}")
  flash(
    "/recipient?id=#{recipient.id}",
    "The recipient ##{recipient.id} has been moved to the list ##{target.id}"
  )
end

post '/upload-recipients' do
  list = shared_list(params[:id].to_i)
  Tempfile.open do |f|
    FileUtils.copy(params[:file][:tempfile], f.path)
    File.delete(params[:file][:tempfile])
    list.recipients.upload(f.path, source: params[:source] || '')
    settings.tbot.notify(
      'upload',
      list.yaml,
      [
        "#{File.readlines(f.path).count} recipients uploaded into",
        "the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
        "by #{current_user}."
      ].join(' ')
    )
  end
  flash(params[:redirect] || "/list?id=#{list.id}", "The CSV has been uploaded to the list ##{list.id}")
end

get '/download-recipients' do
  list = owner.lists.list(params[:id].to_i)
  response.headers['Content-Type'] = 'text/csv'
  response.headers['Content-Disposition'] = "attachment; filename='#{list.title.gsub(/[^a-zA-Z0-9]/, '-')}.csv'"
  list.recipients.csv do
    list.recipients.all(limit: -1)
  end
end

get '/delivery' do
  delivery = owner.deliveries.delivery(params[:id].to_i)
  haml :delivery, layout: :layout, locals: merged(
    title: "##{delivery.id}",
    delivery: delivery
  )
end

get '/delete-delivery' do
  delivery = owner.deliveries.delivery(params[:id].to_i)
  recipient = delivery.recipient
  id = delivery.id
  delivery.delete
  flash("/recipient?id=#{recipient.id}", "Delivery ##{id} has been deleted")
end

get '/lanes' do
  haml :lanes, layout: :layout, locals: merged(
    title: '/lanes',
    lanes: owner.lanes
  )
end

post '/add-lane' do
  lane = owner.lanes.add(params[:title])
  flash('/lanes', "Lane ##{lane.id} has been created")
end

get '/lane' do
  lane = owner.lanes.lane(params[:id].to_i)
  haml :lane, layout: :layout, locals: merged(
    title: "##{lane.id}",
    lane: lane
  )
end

post '/save-lane' do
  lane = owner.lanes.lane(params[:id].to_i)
  lane.save_yaml(params[:yaml])
  flash("/lane?id=#{lane.id}", "The YAML config of the lane ##{lane.id} has been saved")
end

post '/add-letter' do
  lane = owner.lanes.lane(params[:id].to_i)
  letter = lane.letters.add(params[:title])
  flash("/lane?id=#{lane.id}", "The letter ##{letter.id} has been created")
end

get '/letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  haml :letter, layout: :layout, locals: merged(
    title: "##{letter.id}",
    letter: letter,
    lists: owner.lists,
    lanes: owner.lanes
  )
end

get '/letter-up' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.move(+1)
  flash("/lane?id=#{letter.lane.id}", "The letter ##{letter.id} has been UP-moved to the place ##{letter.place}")
end

get '/letter-down' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.move(-1)
  flash("/lane?id=#{letter.lane.id}", "The letter ##{letter.id} has been DOWN-moved to the place ##{letter.place}")
end

post '/save-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.save_liquid(params[:liquid])
  letter.save_yaml(params[:yaml])
  flash("/letter?id=#{letter.id}", "YAML and Liquid have been saved for the letter ##{letter.id}")
end

post '/attach' do
  letter = owner.lanes.letter(params[:id].to_i)
  name = File.basename(params[:file][:filename])
  Tempfile.open do |f|
    FileUtils.copy(params[:file][:tempfile], f.path)
    File.delete(params[:file][:tempfile])
    letter.attach(name, f.path)
  end
  flash("/letter?id=#{letter.id}", "The attachment \"#{name}\" has been added to the letter ##{letter.id}")
end

get '/detach' do
  letter = owner.lanes.letter(params[:letter].to_i)
  name = params[:name]
  letter.detach(name)
  flash("/letter?id=#{letter.id}", "The attachment \"#{name}\" has been removed from the letter ##{letter.id}")
end

get '/download-attachment' do
  letter = owner.lanes.letter(params[:letter].to_i)
  name = params[:name]
  response.headers['Content-Type'] = 'octet/binary'
  response.headers['Content-Disposition'] = "attachment; filename='#{name}'"
  Tempfile.open do |f|
    letter.download(name, f.path)
    File.read(f.path)
  end
end

post '/test-letter' do
  letter = owner.lanes.letter(params[:id].to_i, tbot: settings.tbot)
  list = owner.lists.list(params[:list].to_i)
  recipient = list.recipients.all(active_only: true).sample(1)[0]
  raise UserError, "There are no recipients in the list ##{list.id}" if recipient.nil?
  letter.deliver(recipient, settings.codec)
  flash("/letter?id=#{letter.id}", "Test email has been sent to #{recipient.email}")
end

post '/copy-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  lane = owner.lanes.lane(params[:lane].to_i)
  copy = lane.letters.add(letter.title)
  copy.save_yaml(letter.yaml.to_yaml)
  copy.save_liquid(letter.liquid)
  flash("/letter?id=#{copy.id}", "The letter ##{letter.id} has been copied to the letter ##{copy.id}")
end

get '/toggle-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.toggle
  flash("/letter?id=#{letter.id}", "The letter ##{letter.id} is now #{letter.active? ? 'active' : 'deactivated'}")
end

get '/campaigns' do
  haml :campaigns, layout: :layout, locals: merged(
    title: '/campaigns',
    campaigns: owner.campaigns,
    lists: owner.lists,
    lanes: owner.lanes
  )
end

post '/add-campaign' do
  list = owner.lists.list(params[:list].to_i)
  lane = owner.lanes.lane(params[:lane].to_i)
  campaign = owner.campaigns.add(list, lane, params[:title])
  flash('/campaigns', "The campaign ##{campaign.id} has been created")
end

get '/pipeline' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  haml :pipeline, layout: :layout, locals: merged(
    title: "##{campaign.id}",
    campaign: campaign
  )
end

get '/campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  haml :campaign, layout: :layout, locals: merged(
    title: "##{campaign.id}",
    campaign: campaign,
    campaigns: owner.campaigns,
    lists: owner.lists
  )
end

post '/add-source' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  list = owner.lists.list(params[:list].to_i)
  campaign.add(list)
  flash("/campaign?id=#{campaign.id}", "The list ##{list.id} has been added to the campaign ##{campaign.id}")
end

get '/delete-source' do
  campaign = owner.campaigns.campaign(params[:campaign].to_i)
  list = owner.lists.list(params[:list].to_i)
  campaign.delete(list)
  flash("/campaign?id=#{campaign.id}", "The list ##{list.id} has been removed from the campaign ##{campaign.id}")
end

post '/merge-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  target = owner.campaigns.campaign(params[:target].to_i)
  campaign.merge_into(target)
  flash("/campaign?id=#{target.id}", "The campaign ##{params[:id]} has been merged into the campaign ##{target.id}")
end

post '/save-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  campaign.save_yaml(params[:yaml])
  flash("/campaign?id=#{campaign.id}", "YAML has been saved for the campaign ##{campaign.id}")
end

get '/toggle-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  campaign.toggle
  flash(
    "/campaign?id=#{campaign.id}",
    "The campaign ##{campaign.id} is now #{campaign.active? ? 'active' : 'deactivated'}"
  )
end

get '/add' do
  list = shared_list(params[:list].to_i)
  haml :add, layout: :layout, locals: merged(
    title: '/add',
    list: list
  )
end

get '/weeks' do
  list = shared_list(params[:id].to_i)
  source = '@' + (params[:user] || current_user)
  haml :weeks, layout: :layout, locals: merged(
    title: '/weekly',
    list: list,
    source: source,
    weeks: list.recipients.weeks(source)
  )
end

get '/months' do
  source = '@' + (params[:user] || current_user)
  haml :months, layout: :layout, locals: merged(
    title: '/monthly',
    source: source,
    months: owner.months(source)
  )
end

post '/do-add' do
  list = shared_list(params[:id].to_i)
  email = params[:email].downcase.strip
  flash("/add?list=#{list.id}", "Recipient with email #{email} already exists!") if list.recipients.exists?(email)
  recipient = list.recipients.add(
    email,
    first: params[:first] || '',
    last: params[:last] || '',
    source: "@#{current_user}"
  )
  days = 10
  settings.tbot.notify(
    'add',
    list.yaml,
    [
      "New recipient `#{email}` has been added",
      "by #{current_user} to your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
      "(#{list.recipients.count} emails are there).",
      "There are #{list.recipients.per_day(10).round(2)} emails joining daily (last #{days} days statistics)."
    ].join(' ')
  )
  flash("/add?list=#{list.id}", "The recipient ##{recipient.id} has been added to the list ##{list.id}")
end

get '/download-list' do
  list = shared_list(params[:list].to_i)
  settings.tbot.notify(
    'download',
    list.yaml,
    [
      "Your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
      "has been downloaded by #{current_user}."
    ].join(' ')
  )
  response.headers['Content-Type'] = 'text/csv'
  response.headers['Content-Disposition'] = "attachment; filename='#{list.title.gsub(/[^a-zA-Z0-9]/, '-')}.csv'"
  list.recipients.csv do
    list.recipients.all(query: "=@#{current_user}", limit: -1)
  end
end

post '/subscribe' do
  list = List.new(id: params[:list].to_i, pgsql: settings.pgsql)
  email = params[:email].downcase.strip
  notify = []
  if list.recipients.exists?(email)
    recipient = list.recipients.all(query: '=' + email)[0]
    if recipient.active?
      recipient.post_event(
        [
          'Attempted to subscribe again, but failed.',
          @locals[:user] ? "It was done by #{current_user}." : ''
        ].join(' ')
      )
      return haml :already, layout: :layout, locals: merged(
        title: '/already',
        recipient: recipient,
        list: list,
        token: settings.codec.encrypt(recipient.id.to_s),
        redirect: params[:redirect]
      )
    end
    recipient.toggle
    recipient.post_event(
      [
        'Re-subscribed.',
        @locals[:user] ? "It was done by #{current_user}." : ''
      ].join(' ')
    )
    notify += [
      "A subscriber `#{email}`",
      " (recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id}))",
      " re-entered the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}):"
    ]
  else
    recipient = list.recipients.add(
      email,
      first: params[:first] || '',
      last: params[:last] || '',
      source: params[:source] || ''
    )
    country = Geocoder.search(request.ip).first
    country = country.nil? ? '' : country.country.to_s
    recipient.save_yaml(
      {
        'request_ip' => request.ip.to_s,
        'country' => country,
        'referrer' => request.referer.to_s,
        'user_agent' => request.user_agent.to_s
      }.merge(params).to_yaml
    )
    recipient.post_event(
      [
        'Subscribed.',
        @locals[:user] ? "It was done by #{current_user}." : ''
      ].join(' ')
    )
    notify += [
      "A new subscriber `#{email}` from #{country}",
      " (recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id}))",
      " just got into your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}):"
    ]
  end
  settings.tbot.notify(
    'subscribe',
    list.yaml,
    [
      notify,
      "\n\n```\n#{recipient.yaml.to_yaml}\n```\n\n",
      "There are #{list.recipients.active_count} active subscribers in the list now,",
      " out of #{list.recipients.count} total,",
      " #{list.recipients.per_day.round(2)} joining daily.",
      " More details are [here](https://www.mailanes.com/recipient?id=#{recipient.id})."
    ].flatten.join
  )
  redirect params[:redirect] if params[:redirect]
  haml :subscribed, layout: :layout, locals: merged(
    title: '/subscribed',
    recipient: recipient,
    list: list,
    token: settings.codec.encrypt(recipient.id.to_s)
  )
end

get '/unsubscribe' do
  token = params[:token]
  raise UserError, 'Token is required in order to unsubscribe you' if token.nil?
  id = begin
    settings.codec.decrypt(token).to_i
  rescue OpenSSL::Cipher::CipherError => ex
    raise UserError, "Token is invalid, can\'t unsubscribe: #{ex.message}"
  end
  recipient = Recipient.new(id: id, pgsql: settings.pgsql)
  list = recipient.list
  email = recipient.email
  if recipient.active?
    recipient.toggle
    settings.tbot.notify(
      'unsubscribe',
      list.yaml,
      [
        "The recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
        " with the email `#{email}` has been unsubscribed from your list",
        " [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}).",
        @locals[:user] ? " It was done by #{current_user}." : '',
        params[:d] ? " It was the reaction to [this](http://www.mailanes.com/delivery?id=#{params[:d]})." : '',
        " There are #{list.recipients.active_count} active subscribers in the list still,",
        " out of #{list.recipients.count} total.",
        "This is what we know about the recipient:\n\n```\n#{recipient.yaml.to_yaml}\n```"
      ].join
    )
    recipient.post_event('Unsubscribed' + (@locals[:user] ? " by @#{current_user}" : '') + '.')
  else
    recipient.post_event(
      [
        'Attempted to unsubscribe, while already unsubscribed.',
        @locals[:user] ? "It was done by #{current_user}." : ''
      ].join(' ')
    )
  end
  haml :unsubscribed, layout: :layout, locals: merged(
    title: '/unsubscribed',
    email: email,
    list: list,
    recipient: recipient
  )
end

get '/api' do
  haml :api, layout: :layout, locals: merged(
    title: '/api'
  )
end

get '/api/lists/:id/active_count.json' do
  list = owner.lists.list(params[:id].to_i)
  content_type 'application/json'
  JSON.pretty_generate(
    "list_#{list.id}": {
      'type': 'integer',
      'value': list.recipients.active_count,
      'label': list.title,
      'strategy': 'continuous'
    }
  )
end

get '/api/lists/:id/per_day.json' do
  list = owner.lists.list(params[:id].to_i)
  content_type 'application/json'
  JSON.pretty_generate(
    "list_#{list.id}": {
      'type': 'integer',
      'value': list.recipients.per_day(params[:days] ? params[:days].to_i : 10).round(2),
      'label': list.title,
      'strategy': 'interval'
    }
  )
end

get '/api/campaigns/:id/deliveries_count.json' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  content_type 'application/json'
  JSON.pretty_generate(
    "campaign_#{campaign.id}": {
      'type': 'float',
      'value': campaign.deliveries_count(days: params[:days] ? params[:days].to_i : 1),
      'label': campaign.title,
      'strategy': 'interval'
    }
  )
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nDisallow: /"
end

get '/version' do
  content_type 'text/plain'
  VERSION
end

not_found do
  status 404
  content_type 'text/html', charset: 'utf-8'
  haml :not_found, layout: :layout, locals: merged(
    title: request.url
  )
end

error do
  status 503
  e = env['sinatra.error']
  if e.is_a?(UserError)
    flash('/', e.message)
  else
    Raven.capture_exception(e)
    haml(
      :error,
      layout: :layout,
      locals: merged(
        title: 'error',
        error: "#{e.message}\n\t#{e.backtrace.join("\n\t")}"
      )
    )
  end
end

private

def context
  "#{request.ip} #{request.user_agent} #{VERSION} #{Time.now.strftime('%Y/%m')}"
end

def merged(hash)
  out = @locals.merge(hash)
  out[:local_assigns] = out
  if cookies[:flash_msg]
    out[:flash_msg] = cookies[:flash_msg]
    cookies.delete(:flash_msg)
  end
  out
end

def flash(uri, msg)
  cookies[:flash_msg] = msg
  redirect uri
end

def current_user
  redirect '/hello' unless @locals[:user]
  @locals[:user][:login].downcase
end

def auth_code
  loop do
    code = Hex::FromText.new(settings.codec.encrypt(current_user)).to_s
    return code if code.length < 90
  end
end

def owner
  Owner.new(login: current_user, pgsql: settings.pgsql)
end

def shared_list(id)
  list = List.new(id: id, pgsql: settings.pgsql)
  if list.owner != current_user && !list.friend?(current_user)
    raise UserError, "@#{current_user} doesn't have access to the list ##{list.id}"
  end
  list
end
