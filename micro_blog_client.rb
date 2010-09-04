#!/usr/bin/ruby -Ku

require 'readline'

require 'net/http'
require 'uri'

require 'rubygems'
require 'pit'
require 'json'
require 'twitter'

class AllMicroBlogClient
  def initialize(_arr=[])
    @clients = _arr
  end
  
  def getFriendsTimeLine
    @clients.each { |c|
      puts "\n----- %s Friends Time Line -----" % c.class
      c.friends_timeline(10).each { |status|
        print_status(status)
      }
    }
  end
  
  def getReplies
    @clients.each { |c|
      puts "\n----- %s Friends Time Line -----" % c.class
      c.replies(10).each { |status|
        print_status(status)
      }
    }
  end
  
  def postTweet(message)
    @clients.each { |c| c.update(message) }
  end

  def print_status(status)
    puts "%-12s : %s" % [status['user']['screen_name'], status['text'].gsub(/\n/, ' ')]
  end
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

config = Pit.get('microblogclient', :require => { 
                   'ctoken' => 'your twitter ctoken',
                   'csecret' => 'your twitter csercret',
                   'atoken' => 'your twitter atoken',
                   'asecret' => 'your twitter asecret'
                 })
twitter = MyTwitter.new(config['ctoken'], config['csecret'], config['atoken'], config['asecret'])

config = Pit.get('wassr', :require => {
                   'username' => 'your wassr username',
                   'password' => 'your wassr password'})
wassr = Wassr.new(config['username'], config['password'])

ambc = AllMicroBlogClient.new([wassr, twitter])

loop do
  input = Readline.readline("\n cmd: Friends time line[f] eXit[xx] \n> ").split(' ')
  if input[0] != nil
    if input[0].length > 2
      ambc.postTweet(input.join(' '))
    else
      getFriendsTimeLineKey = ['friends', 'f']
      getRepliesKey = ['res', 'r', '']
      sendPostKey = ['post', 'p']
      exitKey = ['xx', 'ZZ', 'exit', 'bye']
      case input[0]
      when *getFriendsTimeLineKey
        ambc.getFriendsTimeLine
      when *getRepliesKey
        ambc.getReplies
      when *sendPostKey
        input.shift
        ambc.postTweet(input.join(' '))
      when *exitKey
        puts "bye ;-)"
        break
      end
    end
  else
    ambc.getReplies
  end
end
