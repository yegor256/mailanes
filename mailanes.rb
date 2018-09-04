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
require 'time_difference'

require_relative 'version'
require_relative 'objects/owner'
require_relative 'objects/pipeline'
require_relative 'objects/postman'
require_relative 'objects/tbot'

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
    'pgsql' => {
      'host' => 'localhost',
      'port' => 0,
      'user' => 'test',
      'dbname' => 'test',
      'password' => 'test'
    },
    'telegram_token' => '',
    'token_secret' => '?',
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
  set :pipeline, Pipeline.new(pgsql: settings.pgsql)
  set :postman, Postman.new(settings.codec)
  set :tbot, Tbot.new(config['telegram_token'])
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
          settings.pipeline.deactivate(settings.tbot)
          settings.pipeline.exhaust(settings.tbot)
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
  haml :lists, layout: :layout, locals: merged(
    title: '/lists',
    lists: owner.lists
  )
end

post '/add-list' do
  owner.lists.add(params[:title])
  redirect '/lists'
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
  redirect "/list?id=#{list.id}"
end

post '/add-recipient' do
  list = owner.lists.list(params[:id].to_i)
  list.recipients.add(
    params[:email],
    first: params[:first],
    last: params[:last],
    source: "@#{current_user}"
  )
  redirect "/list?id=#{list.id}"
end

get '/recipient' do
  list = owner.lists.list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  haml :recipient, layout: :layout, locals: merged(
    title: "##{recipient.id}",
    list: list,
    recipient: recipient
  )
end

get '/toggle-recipient' do
  list = owner.lists.list(params[:list].to_i)
  recipient = list.recipients.recipient(params[:id].to_i)
  recipient.toggle
  redirect "/recipient?list=#{list.id}&id=#{recipient.id}"
end

post '/upload-recipients' do
  list = owner.lists.list(params[:id].to_i)
  Tempfile.open do |f|
    FileUtils.copy(params[:file][:tempfile], f.path)
    File.delete(params[:file][:tempfile])
    list.recipients.upload(f.path)
  end
  redirect "/list?id=#{list.id}"
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
    lists: owner.lists
  )
end

get '/letter-up' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.up
  redirect "/lane?id=#{letter.lane.id}"
end

post '/save-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  letter.save_liquid(params[:liquid])
  letter.save_yaml(params[:yaml])
  redirect "/letter?id=#{letter.id}"
end

post '/test-letter' do
  letter = owner.lanes.letter(params[:id].to_i)
  list = owner.lists.list(params[:list].to_i)
  recipient = list.recipients.all.sample(1)[0]
  raise "There are no recipients in the list ##{list.id}" if recipient.nil?
  letter.deliver(list.recipients.all.sample(1)[0])
  redirect "/letter?id=#{letter.id}"
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

get '/campaign' do
  campaign = owner.campaigns.campaign(params[:id].to_i)
  haml :campaign, layout: :layout, locals: merged(
    title: "##{campaign.id}",
    campaign: campaign
  )
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
  list = List.new(id: params[:list].to_i, pgsql: settings.pgsql)
  if list.owner != current_user && !list.friend?(current_user)
    raise "@#{current_user} doesn't have access to the list ##{list.id}"
  end
  haml :add, layout: :layout, locals: merged(
    title: '/add',
    list: list
  )
end

post '/do-add' do
  list = List.new(id: params[:id].to_i, pgsql: settings.pgsql)
  if list.owner != current_user && !list.friend?(current_user)
    raise "@#{current_user} doesn't have access to the list ##{list.id}"
  end
  list.recipients.add(
    params[:email],
    first: params[:first] || '',
    last: params[:last] || '',
    source: "@#{current_user}"
  )
  settings.tbot.notify(
    list.yaml,
    [
      "New recipient #{params[:email]} has been added",
      "by #{current_user} to your list ##{list.id}: \"#{list.title}\".",
      "There are #{list.recipients.per_day.round(2)} emails joining daily."
    ].join(' ')
  )
  redirect "/add?list=#{list.id}"
end

get '/download-list' do
  list = List.new(id: params[:list].to_i, pgsql: settings.pgsql)
  raise "You don't have access to the list ##{list.id}" unless list.friend?(current_user)
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
    raise "The email #{recipient.email} has already been subscribed to the list ##{list.id}" if recipient.active?
    recipient.toggle
    notify += [
      "A subscriber #{params[:email]} re-entered the list ##{list.id}: \"#{list.title}\"."
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
    notify += [
      "A new subscriber #{params[:email]} (from #{country})",
      "just got into your list ##{list.id}: \"#{list.title}\"."
    ]
  end
  settings.tbot.notify(
    list.yaml,
    (notify + [
      "There are #{list.recipients.active_count} active subscribers in the list now,",
      "out of #{list.recipients.count} total,",
      "#{list.recipients.per_day.round(2)} joining daily.",
      "More details are here: https://www.mailanes.com/recipient?id=#{recipient.id}&list=#{list.id}"
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
  raise "You have already been unsubscribed: #{recipient.email}" unless recipient.active?
  email = recipient.email
  recipient.toggle
  list = recipient.list
  settings.tbot.notify(
    list.yaml,
    [
      "Email #{email} has been unsubscribed from your list ##{list.id}: \"#{list.title}\".",
      params[:delivery] ? "It was the reaction to http://www.mailaines.com/delivery?id=#{params[:delivery]}" : ''
    ].join(' ')
  )
  haml :unsubscribed, layout: :layout, locals: merged(
    title: '/unsubscribed',
    email: email,
    list: list
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
  out
end

def current_user
  redirect '/hello' unless @locals[:user]
  @locals[:user][:login].downcase
end

def owner
  Owner.new(login: current_user, pgsql: settings.pgsql)
end
