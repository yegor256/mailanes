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

STDOUT.sync = true

require 'time'
require 'haml'
require 'geocoder'
require 'sinatra'
require 'sinatra/cookies'
require 'raven'
require 'glogin'
require 'glogin/codec'

require_relative 'version'
require_relative 'objects/owner'
require_relative 'objects/pipeline'
require_relative 'objects/postman'
require_relative 'objects/tbot'
require_relative 'objects/ago'
require_relative 'objects/bounces'

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
    's3' => {
      'key' => '?',
      'secret' => '?',
      'bucket' => '?'
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
  cookies.delete(:passcode)
  redirect to('/')
end

get '/hello' do
  haml :hello, layout: :layout, locals: merged(
    title: '/'
  )
end

get '/' do
  haml :index, layout: :layout, locals: merged(
    title: '/'
  )
end

get '/lists' do
  mine = owner.lists
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
    list: list
  )
end

post '/save-list' do
  list = owner.lists.list(params[:id].to_i)
  list.save_yaml(params[:yaml])
  flash("/list?id=#{list.id}", "YAML has been saved to the list ##{list.id}")
end

post '/add-recipient' do
  list = owner.lists.list(params[:id].to_i)
  recipient = list.recipients.add(
    params[:email].downcase.strip,
    first: params[:first].strip,
    last: params[:last].strip,
    source: "@#{current_user}"
  )
  recipient.post_event("Added to the list by @#{current_user}")
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
  recipient.post_event("Moved to the list ##{target.id} by @#{current_user}")
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
  content_type 'text/csv'
  CSV.generate do |csv|
    list.recipients.all(limit: -1).each do |r|
      csv << [r.email, r.first, r.last, r.source, r.created.utc.iso8601]
    end
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
  delivery.delete
  redirect "/recipient?id=#{recipient.id}"
end

get '/lanes' do
  haml :lanes, layout: :layout, locals: merged(
    title: '/lanes',
    lanes: owner.lanes
  )
end

post '/add-lane' do
  owner.lanes.add(params[:title])
  redirect '/lanes'
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
  redirect "/lane?id=#{lane.id}"
end

post '/add-letter' do
  lane = owner.lanes.lane(params[:id].to_i)
  lane.letters.add(params[:title])
  redirect "/lane?id=#{lane.id}"
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
  redirect "/lane?id=#{letter.lane.id}"
end

get '/letter-down' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.move(-1)
  redirect "/lane?id=#{letter.lane.id}"
end

post '/save-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.save_liquid(params[:liquid])
  letter.save_yaml(params[:yaml])
  redirect "/letter?id=#{letter.id}"
end

post '/test-letter' do
  letter = owner.lanes.letter(params[:id].to_i, tbot: settings.tbot)
  list = owner.lists.list(params[:list].to_i)
  recipient = list.recipients.all(active_only: true).sample(1)[0]
  raise "There are no recipients in the list ##{list.id}" if recipient.nil?
  letter.deliver(recipient, settings.codec)
  redirect "/letter?id=#{letter.id}"
end

post '/copy-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  lane = owner.lanes.lane(params[:lane].to_i)
  copy = lane.letters.add(letter.title)
  copy.save_yaml(letter.yaml.to_yaml)
  copy.save_liquid(letter.liquid)
  redirect "/letter?id=#{copy.id}"
end

get '/toggle-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.toggle
  redirect "/letter?id=#{letter.id}"
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
  owner.campaigns.add(list, lane, params[:title])
  redirect '/campaigns'
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
  redirect "/campaign?id=#{campaign.id}"
end

post '/merge-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  target = owner.campaigns.campaign(params[:target].to_i)
  campaign.merge_into(target)
  redirect "/campaign?id=#{target.id}"
end

post '/save-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  campaign.save_yaml(params[:yaml])
  redirect "/campaign?id=#{campaign.id}"
end

get '/toggle-campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  campaign.toggle
  redirect "/campaign?id=#{campaign.id}"
end

get '/add' do
  list = shared_list(params[:list].to_i)
  haml :add, layout: :layout, locals: merged(
    title: '/add',
    list: list
  )
end

post '/do-add' do
  list = shared_list(params[:id].to_i)
  list.recipients.add(
    params[:email],
    first: params[:first] || '',
    last: params[:last] || '',
    source: "@#{current_user}"
  )
  settings.tbot.notify(
    'add',
    list.yaml,
    [
      "New recipient `#{params[:email]}` has been added",
      "by #{current_user} to your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}).",
      "There are #{list.recipients.per_day.round(2)} emails joining daily."
    ].join(' ')
  )
  redirect "/add?list=#{list.id}"
end

get '/download-list' do
  list = List.new(id: params[:list].to_i, pgsql: settings.pgsql)
  raise "You don't have access to the list ##{list.id}" unless list.friend?(current_user)
  settings.tbot.notify(
    'download',
    list.yaml,
    [
      "Your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})",
      "has been downloaded by #{current_user}."
    ].join(' ')
  )
  content_type 'text/csv'
  CSV.generate do |csv|
    list.recipients.all(query: "=@#{current_user}", limit: -1).each do |r|
      csv << [r.email, r.first, r.last, r.source, r.created.utc.iso8601]
    end
  end
end

post '/subscribe' do
  list = List.new(id: params[:list].to_i, pgsql: settings.pgsql)
  notify = []
  if list.recipients.exists?(params[:email])
    recipient = list.recipients.all(query: '=' + params[:email])[0]
    if recipient.active?
      recipient.post_event('Attempted to subscribe again, but failed.')
      return haml :already, layout: :layout, locals: merged(
        title: '/already',
        recipient: recipient,
        list: list,
        token: settings.codec.encrypt(recipient.id.to_s),
        redirect: params[:redirect]
      )
    end
    recipient.toggle
    recipient.post_event('Re-subscribed.')
    notify += [
      "A subscriber #{params[:email]}",
      "(recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id}))",
      "re-entered the list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})."
    ]
  else
    recipient = list.recipients.add(
      params[:email],
      first: params[:first] || '',
      last: params[:last] || '',
      source: params[:source] || ''
    )
    country = Geocoder.search(request.ip).first.country
    recipient.save_yaml(
      params.merge(
        request_ip: request.ip,
        country: country,
        referrer: request.referer,
        user_agent: request.user_agent
      ).map { |k, v| "#{k}: #{v}" }.join("\n")
    )
    recipient.post_event('Subscribed.')
    notify += [
      "A new subscriber #{params[:email]} from #{country}",
      "(recipient [##{recipient.id}](https://www.mailanes.com/recipient?id=#{recipient.id}))",
      "just got into your list [\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id})."
    ]
  end
  settings.tbot.notify(
    'subscribe',
    list.yaml,
    (notify + [
      "There are #{list.recipients.active_count} active subscribers in the list now,",
      "out of #{list.recipients.count} total,",
      "#{list.recipients.per_day.round(2)} joining daily.",
      "More details are [here](https://www.mailanes.com/recipient?id=#{recipient.id})."
    ]).join(' ')
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
  id = settings.codec.decrypt(params[:token]).to_i
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
        "with the email #{email} has been unsubscribed from your list",
        "[\"#{list.title}\"](https://www.mailanes.com/list?id=#{list.id}).",
        @locals[:user] ? "It was done by #{current_user}." : '',
        params[:d] ? "It was the reaction to [this](http://www.mailaines.com/delivery?id=#{params[:d]})." : '',
        "There are #{list.recipients.active_count} active subscribers in the list still,",
        "out of #{list.recipients.count} total."
      ].join(' ')
    )
    recipient.post_event('Unsubscribed' + (@locals[:user] ? " by @#{current_user}" : '') + '.')
  else
    recipient.post_event('Attempted to unsubscribe, while already unsubscribed.')
  end
  haml :unsubscribed, layout: :layout, locals: merged(
    title: '/unsubscribed',
    email: email,
    list: list,
    recipient: recipient
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

private

def context
  "#{request.ip} #{request.user_agent} #{VERSION} #{Time.now.strftime('%Y/%m/%d')}"
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

def owner
  Owner.new(login: current_user, pgsql: settings.pgsql)
end

def shared_list(id)
  list = List.new(id: id, pgsql: settings.pgsql)
  if list.owner != current_user && !list.friend?(current_user)
    raise "@#{current_user} doesn't have access to the list ##{list.id}"
  end
  list
end
