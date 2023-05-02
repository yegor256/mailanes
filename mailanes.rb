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

$stdout.sync = true

require 'geoplugin'
require 'get_process_mem'
require 'glogin'
require 'glogin/codec'
require 'haml'
require 'iri'
require 'json'
require 'loog'
require 'pgtk/pool'
require 'raven'
require 'sinatra'
require 'sinatra/cookies'
require 'time'
require 'total'
require 'yaml'
require 'zache'
require_relative 'objects/ago'
require_relative 'objects/bounces'
require_relative 'objects/hex'
require_relative 'objects/owner'
require_relative 'objects/pipeline'
require_relative 'objects/decoy'
require_relative 'objects/postman'
require_relative 'objects/tbot'
require_relative 'objects/user_error'
require_relative 'version'

if ENV['RACK_ENV'] != 'test'
  require 'rack/ssl'
  use Rack::SSL
end

configure do
  Haml::Options.defaults[:format] = :xhtml
  config = {
    'geoplugin_token' => '?',
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
    'decoy_pop3' => {
      'host' => '',
      'login' => '',
      'password' => ''
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
  set :log, Loog::REGULAR
  set :zache, Zache.new(dirty: true)
  set :glogin, GLogin::Auth.new(
    config['github']['client_id'],
    config['github']['client_secret'],
    'https://www.mailanes.com/github-callback'
  )
  set :codec, GLogin::Codec.new(config['token_secret'])
  if File.exist?('target/pgsql-config.yml')
    set :pgsql, Pgtk::Pool.new(
      Pgtk::Wire::Yaml.new(File.join(__dir__, 'target/pgsql-config.yml')),
      log: settings.log
    )
  else
    set :pgsql, Pgtk::Pool.new(
      Pgtk::Wire::Env.new('DATABASE_URL'),
      log: settings.log
    )
  end
  settings.pgsql.start(4)
  set :postman, Postman.new(settings.codec)
  set :tbot, Tbot.new(config['telegram_token'])
  set :pipeline, Pipeline.new(pgsql: settings.pgsql, tbot: settings.tbot, log: settings.log)
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
          Bounces.new(
            settings.config['pop3']['host'],
            settings.config['pop3']['login'],
            settings.config['pop3']['password'],
            settings.codec,
            pgsql: settings.pgsql,
            log: settings.log
          ).fetch(tbot: settings.tbot)
          Decoy.new(
            settings.config['decoy_pop3']['host'],
            settings.config['decoy_pop3']['login'],
            settings.config['decoy_pop3']['password'],
            log: settings.log
          ).fetch
        rescue StandardError => e
          settings.log.error("#{e.message}\n\t#{e.backtrace.join("\n\t")}")
          Raven.capture_exception(e)
        end
        settings.log.info("Pipeline done in #{(Time.now - start).round(2)}s")
      end
    end
  end
end

before '/*' do
  @locals = {
    ver: VERSION,
    http_start: Time.now,
    iri: Iri.new(request.url),
    login_link: settings.glogin.login_uri,
    request_ip: request.ip,
    mem: settings.zache.get(:mem, lifetime: 60) { GetProcessMem.new.bytes.to_i },
    total_mem: settings.zache.get(:total_mem, lifetime: 60) { Total::Mem.new.bytes }
  }
  cookies[:glogin] = params[:glogin] if params[:glogin]
  if cookies[:glogin]
    begin
      @locals[:user] = GLogin::Cookie::Closed.new(
        cookies[:glogin],
        settings.config['github']['encryption_secret'],
        context
      ).to_user
    rescue OpenSSL::Cipher::CipherError => _e
      cookies.delete(:glogin)
    end
  end
  if params[:auth]
    begin
      @locals[:user] = {
        login: settings.codec.decrypt(Hex::ToText.new(params[:auth]).to_s)
      }
    rescue OpenSSL::Cipher::CipherError => _e
      redirect to('/')
    end
  end
end

get '/github-callback' do
  code = params[:code]
  error(400) if code.nil?
  cookies[:glogin] = GLogin::Cookie::Open.new(
    settings.glogin.user(code),
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
    campaigns: owner.campaigns,
    total: owner.lists.total_recipients,
    delivered: owner.campaigns.total_deliveries(1),
    bounced: owner.campaigns.total_bounced(1)
  )
end

get '/lists' do
  mine = owner.lists.all
  haml :lists, layout: :layout, locals: merged(
    title: '/lists',
    lists: owner.lists,
    dups: owner.lists.duplicates_count,
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
    list: list,
    campaigns: list.campaigns,
    abs: list.absorb_counts,
    rate: list.recipients.bounce_rate,
    total: list.recipients.count,
    active: list.recipients.active_count
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
  list.yaml = params[:yaml]
  flash("/list?id=#{list.id}", "YAML has been saved to the list ##{list.id}")
end

post '/add-recipient' do
  list = owner.lists.list(params[:id].to_i)
  email = params[:email].downcase.strip
  raise UserError, "Recipient with email #{email} already exists" if list.recipients.exists?(email)
  recipient = list.recipients.add(
    email,
    first: params[:first].strip,
    last: params[:last].strip,
    source: "@#{current_user}"
  )
  recipient.post_event("Added to the list ##{list.id} by @#{current_user}")
  flash("/list?id=#{list.id}", "The recipient ##{recipient.id} has been added to the list ##{list.id}")
end

post '/deactivate-many' do
  emails = params[:emails].split("\r")
  owner.lists.deactivate_recipients(emails)
  flash('/lists', "Deactivated #{emails.count} recipients")
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
  raise UserError, "Can't delete it, there were some deliveries" unless recipient.deliveries.empty?
  recipient.delete
  flash("/list?id=#{list.id}", "The recipient has been deleted from the list ##{list.id}")
end

post '/change-email' do
  list = shared_list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  before = recipient.email
  after = params[:email]
  recipient.email = after
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
    "The recipient ##{recipient.id}/#{params[:email]}",
    "has got a new comment from #{current_user}:\n\n",
    params[:comment]
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
    start = Time.now
    Thread.start do
      settings.log.info("Uploading started with #{File.readlines(f.path).count} lines \
in #{File.size(f.path)} bytes...")
      list.recipients.upload(f.path, source: params[:source] || '')
      settings.tbot.notify(
        'upload',
        list.yaml,
        "📥 #{File.readlines(f.path).count} recipients uploaded into",
        "the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
        "by #{current_user} in #{format('%.02f', Time.now - start)}s."
      )
      settings.log.info("Uploading finished with #{File.readlines(f.path).count} lines!")
    rescue StandardError => e
      settings.tbot.notify(
        'upload',
        list.yaml,
        "⚠️ Failed to upload the file of #{File.readlines(f.path).count} lines into",
        "the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
        "in #{format('%.02f', Time.now - start)}s",
        "by #{current_user}:\n\n```\n#{e.class.name}: #{e.message}\n```",
        "\n\nYou may want to [try again](https://www.mailanes.com/list?id=#{list.id})."
      )
      settings.log.info("Uploading failed with #{File.readlines(f.path).count} lines!")
    end
  end
  flash(
    params[:redirect] || "/list?id=#{list.id}",
    "The CSV will be uploaded to the list ##{list.id}, it may take some time..."
  )
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
  lane.yaml = params[:yaml]
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
  letter.move(-1)
  flash("/lane?id=#{letter.lane.id}", "The letter ##{letter.id} has been UP-moved to the place ##{letter.place}")
end

get '/letter-down' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.move(+1)
  flash("/lane?id=#{letter.lane.id}", "The letter ##{letter.id} has been DOWN-moved to the place ##{letter.place}")
end

post '/save-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.liquid = params[:liquid]
  letter.yaml = params[:yaml]
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
rescue Letter::CantDeliver => e
  flash("/letter?id=#{letter.id}", "The email is not sent: #{e.message}")
end

post '/copy-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  lane = owner.lanes.lane(params[:lane].to_i)
  copy = lane.letters.add(letter.title)
  copy.yaml = letter.yaml.to_yaml
  copy.liquid = letter.liquid
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
  campaign.yaml = params[:yaml]
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
  source = "@#{params[:user] || current_user}"
  haml :weeks, layout: :layout, locals: merged(
    title: '/weekly',
    list: list,
    source: source,
    weeks: list.recipients.weeks(source)
  )
end

get '/months' do
  source = "@#{params[:user] || current_user}"
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
    "👍 New recipient `#{email}` has been added",
    "by #{current_user} to your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
    "(#{list.recipients.count} emails are there).",
    "There are #{list.recipients.per_day(10).round(2)} emails joining daily (last #{days} days statistics)."
  )
  flash("/add?list=#{list.id}", "The recipient ##{recipient.id} has been added to the list ##{list.id}")
end

get '/download-list' do
  list = shared_list(params[:list].to_i)
  settings.tbot.notify(
    'download',
    list.yaml,
    "📤 Your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
    "has been downloaded by #{current_user}."
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
    recipient = list.recipients.all(query: "=#{email}")[0]
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
      "👍 A subscriber `#{email}`",
      "(recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id}))",
      "re-entered the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}):"
    ]
  else
    recipient = list.recipients.add(
      email,
      first: params[:first] || '',
      last: params[:last] || '',
      source: params[:source] || ''
    )
    recipient.yaml = {
      'request_ip' => request.ip.to_s,
      'country' => country,
      'referrer' => request.referer.to_s,
      'user_agent' => request.user_agent.to_s
    }.merge(params).to_yaml
    recipient.post_event(
      [
        "Subscribed via #{request.url} from #{request.ip} (#{country}).",
        @locals[:user] ? "It was done by #{current_user}." : ''
      ].join(' ')
    )
    if list.confirmation_required?
      recipient.confirm!(set: false)
      recipient.post_event('The subscriber has to confirm their email, since the list requires so')
    end
    notify += [
      "👍 A new subscriber [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
      "from #{country} just got into your list",
      "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}):"
    ]
  end
  settings.tbot.notify(
    'subscribe',
    list.yaml,
    notify,
    "\n\n```\n#{recipient.yaml.to_yaml.strip}\n```",
    "\n\nThere are #{list.recipients.active_count} active subscribers in the list now,",
    "out of #{list.recipients.count} total,",
    "#{list.recipients.per_day.round(2)} joining daily.",
    "More details are [here](https://www.mailanes.com/recipient?id=#{recipient.id})."
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
  rescue OpenSSL::Cipher::CipherError => e
    raise UserError, "Token is invalid, can't unsubscribe: #{e.message}"
  end
  recipient = Recipient.new(id: id, pgsql: settings.pgsql)
  list = recipient.list
  email = recipient.email
  if recipient.active?
    recipient.toggle
    Delivery.new(id: params[:d].to_i, pgsql: settings.pgsql).unsubscribe if params[:d]
    settings.tbot.notify(
      'unsubscribe',
      list.yaml,
      "😢 The recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
      "with the email `#{email}` has been unsubscribed from your list",
      "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}).",
      @locals[:user] ? "It was done by #{current_user}." : '',
      params[:d] ? "It was the reaction to [this](http://www.mailanes.com/delivery?id=#{params[:d]})." : '',
      "There are #{list.recipients.active_count} active subscribers in the list still,",
      "out of #{list.recipients.count} total.",
      "This is what we know about the recipient:\n\n```\n#{recipient.yaml.to_yaml}\n```"
    )
    recipient.post_event("Unsubscribed#{@locals[:user] ? " by @#{current_user}" : ''}.")
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

get '/opened' do
  token = params[:token]
  return 'The URL is broken' if token.nil?
  id = 0
  begin
    id = settings.codec.decrypt(token).to_i
  rescue OpenSSL::Cipher::CipherError => e
    return "Token is invalid, can't use it: #{e.message}"
  end
  delivery = Delivery.new(id: id, pgsql: settings.pgsql)
  agent = request.env['USER_AGENT'] || 'unknown User-Agent'
  delivery.just_opened("#{request.ip} (#{country}) by #{agent}")
  content_type 'image/png'
  File.read(File.join(__dir__, 'public/logo-64.png'))
end

get '/confirm' do
  token = params[:token]
  raise UserError, 'Token is required in order to confirm you' if token.nil?
  id = begin
    settings.codec.decrypt(token).to_i
  rescue OpenSSL::Cipher::CipherError => e
    raise UserError, "Token is invalid, can't confirm: #{e.message}"
  end
  recipient = Recipient.new(id: id, pgsql: settings.pgsql)
  recipient.confirm!
  settings.tbot.notify(
    'confirm',
    list.yaml,
    "😉 The recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id})",
    "with the email `#{recipient.email}` just confirmed their participation in the list",
    "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})."
  )
  recipient.post_event("Subscription confirmed#{@locals[:user] ? " by @#{current_user}" : ''}.")
  haml :confirmed, layout: :layout, locals: merged(
    title: '/confirmed',
    list: recipient.list,
    recipient: recipient,
    token: settings.codec.encrypt(recipient.id.to_s)
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
      type: 'integer',
      value: list.recipients.active_count,
      label: list.title,
      strategy: 'continuous'
    }
  )
end

get '/api/lists/:id/per_day.json' do
  list = owner.lists.list(params[:id].to_i)
  content_type 'application/json'
  JSON.pretty_generate(
    "list_#{list.id}": {
      type: 'integer',
      value: list.recipients.per_day(params[:days] ? params[:days].to_i : 10).round(2),
      label: list.title,
      strategy: 'interval'
    }
  )
end

get '/api/campaigns/:id/deliveries_count.json' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  content_type 'application/json'
  JSON.pretty_generate(
    "campaign_#{campaign.id}": {
      type: 'float',
      value: campaign.deliveries_count(days: params[:days] ? params[:days].to_i : 1),
      label: campaign.title,
      strategy: 'interval'
    }
  )
end

get '/sql' do
  raise UserError, 'You are not allowed to see this' unless admin?
  query = params[:query] || 'SELECT * FROM list LIMIT 5'
  start = Time.now
  result = settings.pgsql.exec(query)
  haml :sql, layout: :layout, locals: merged(
    title: '/sql',
    query: query,
    result: result,
    lag: Time.now - start
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
    flash('/', e.message, color: 'darkred')
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
  out[:flash_color] = cookies[:flash_color] || 'darkgreen'
  cookies.delete(:flash_color)
  out
end

def flash(uri, msg, color: 'darkgreen')
  cookies[:flash_msg] = msg
  cookies[:flash_color] = color
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

def admin?
  @locals[:user] && current_user == 'yegor256'
end

def country(ip = request.ip)
  settings.zache.get("ip_to_country:#{ip}") do
    # geo = Geoplugin.new(request.ip, ssl: true, key: settings.config['geoplugin_token'])
    # geo.nil? ? '??' : geo.countrycode

    # see this https://github.com/davidesantangelo/geoplugin/issues/1
    '??'
  end
end
