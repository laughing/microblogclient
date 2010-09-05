require 'rubygems'
require 'haml'
require 'json'
require 'pit'
require 'sinatra'
require 'twitter'

class AllMicroBlogClient
  def initialize(_arr=[])
    @clients = _arr.compact
  end

  def friends_timeline
    statuses = { }
    @clients.each { |c|
      statuses[c.class] = c.friends_timeline(5)
    }
    statuses
  end
  
  def update(message)
    @clients.each { |c| c.update(message) }
  end
  
  # def getFriendsTimeLine
  #   @clients.each { |c|
  #     puts "\n----- %s Friends Time Line -----" % c.class
  #     c.friends_timeline(10).each { |status|
  #       print_status(status)
  #     }
  #   }
  # end
  
  # def getReplies
  #   @clients.each { |c|
  #     puts "\n----- %s Friends Time Line -----" % c.class
  #     c.replies(10).each { |status|
  #       print_status(status)
  #     }
  #   }
  # end
  
  # def postTweet(message)
  #   @clients.each { |c| c.update(message) }
  # end

  # def print_status(status)
  #   puts "%-12s : %s" % [status['user']['screen_name'], status['text'].gsub(/\n/, ' ')]
  # end
end

class Client
  @@update_uri = "/statuses/update.json?status=%s"
  @@friends_timeline_uri = "/statuses/friends_timeline.json"
  @@replies_uri = "/statuses/replies.json"

  def initialize(username, password, host)
    @username = username
    @password = password
    @host = host
  end

  def update(status)
    Net::HTTP.version_1_2
    req = Net::HTTP::Post.new(@@update_uri % URI.escape(status))
    req.basic_auth(@username, @password)
    Net::HTTP.start(@host, 80) { |http| response = http.request(req) }
  end
  
  def friends_timeline(count=20)
    Net::HTTP.version_1_2
    req = Net::HTTP::Get.new(@@friends_timeline_uri)
    req.basic_auth(@username, @password)
    statuses = Net::HTTP.start(@host, 80) { |http| JSON(http.request(req).body) }
    statuses[0..(count - 1)].compact
  end
  
  def replies(count=20)
    Net::HTTP.version_1_2
    req = Net::HTTP::Get.new(@@replies_uri)
    req.basic_auth(@username, @password)
    statuses = Net::HTTP.start(@host, 80) { |http| JSON(http.request(req).body) }
    statuses[0..(count - 1)].compact
  end
end

class MyTwitter < Client
  def initialize(c_token, c_secret, a_token, a_secret)
    oauth = Twitter::OAuth.new(c_token, c_secret)
    oauth.authorize_from_access(a_token, a_secret)
    @client = Twitter::Base.new(oauth)
  end
  
  def update(message)
    @client.update(message)
  end

  def friends_timeline(count=20)
    @client.friends_timeline[0..(count - 1)].compact
  end
  
  def replies(count=20)
    @client.mentions[0..(count - 1)].compact
  end
end

class Wassr < Client
  def initialize(username, password)
    super(username, password, 'api.wassr.jp')
  end
  
  def friends_timeline(count=20)
    Net::HTTP.version_1_2
    req = Net::HTTP::Get.new("/statuses/friends_timeline.json?id=%s" % @username)
    req.basic_auth(@usename, @password)
    statuses = Net::HTTP.start(@host, 80) { |http| JSON(http.request(req).body) }
    statuses[0..(count - 1)].compact
  end  
end

def base_url
  default_port = (request.scheme == "http") ? 80 : 443
  port = (request.port == default_port) ? "" : ":#{request.port.to_s}"
  "#{request.scheme}://#{request.host}#{port}"
end

def twitter_consumer
  Pit.get('microblogclient_web', :require => { 
                     'c_token' => 'your twitter ctoken',
                     'c_secret' => 'your twitter csercret',
                   })
end

def wassr_info
Pit.get('wassr', :require => {
                   'username' => 'your wassr username',
                   'password' => 'your wassr password'})
end

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

configure do
  use Rack::Session::Cookie, :secret => Digest::SHA1.hexdigest(rand.to_s)
end

before do
  config = twitter_consumer
  if session[:access_token]
    #oauth = Twitter::OAuth.new(config['c_token'], config['c_secret'])
    #oauth.authorize_from_access(session[:access_token], session[:access_token_secret])
    #@twitter = Twitter::Base.new(oauth)
    twitter = MyTwitter.new(config['c_token'], config['c_secret'], session[:access_token], session[:access_token_secret])
    config = wassr_info
    wassr = Wassr.new(config['username'], config['password'])
    @ambc = AllMicroBlogClient.new([wassr, twitter])
  else
    @ambc = nil
  end
end

get '/' do
  haml :index
end

get '/request_token' do
  config = twitter_consumer
  callback_url = "%s/access_token" % base_url
  oauth = Twitter::OAuth.new(config['c_token'], config['c_secret'], :sign_in => base_url)

  request_token = oauth.consumer.get_request_token(:oauth_callback => callback_url)
  session[:request_token] = request_token.token
  session[:request_token_secret] = request_token.secret

  redirect request_token.authorize_url
end

get '/access_token' do
  config = twitter_consumer
  oauth = Twitter::OAuth.new(config['c_token'], config['c_secret'])
  begin
    access_token = oauth.authorize_from_request(session[:request_token], session[:request_token_secret], params[:oauth_verifier])
  rescue
    
  end
  session[:access_token] = access_token[0]
  session[:access_token_secret] = access_token[1]
  
  haml :success
end

get '/timeline' do
  redirect '/' unless @ambc
  haml :timeline
end

put '/update' do
  @ambc.update(params[:tweet])
  redirect '/timeline'
end

__END__
@@ layout
%html
  %head
    %meta{ :charset => 'utf-8'}
  %body
    != yield
@@ index
%a{ :href => '/request_token' } OAuth Login
@@ success
%p oauth success!
%a{ :href => '/timeline' } go timeline
@@ timeline
%form{ :method => 'POST', :action => '/update' }
  %input{ :type => 'hidden', :name => '_method', :value => 'PUT' }
  %textarea{ :name => 'tweet', :cols => '20', :rows => '2' }
  %input{ :type => 'submit' }
- @ambc.friends_timeline.each do |k, v|
  %p= k
  %ol
  - v.each do |status|
    %li= "%s: %s" % [status['user']['screen_name'], status['text']]

