require 'rubygems'
require 'sinatra'
require 'json'
require 'cgi'
require 'dm-core'
require 'dm-validations'
require 'aws/s3'

#keys is a secure file!  it is not to be checked in
load File.dirname(__FILE__) + '/keys.rb'

if development?
  require 'ruby-debug' if RUBY_PLATFORM != 'java'
  require 'sinatra/reloader'
end

if RUBY_PLATFORM == 'java'
  require 'appengine-apis/urlfetch'
  require 'appengine-apis/datastore'
  
  DataMapper.setup(:default, "appengine://auto")
  HostName = 'mojo-jr.appspot.com'
else
  require 'httpclient'
  
  DataMapper.setup(:default, "mongo://localhost/meta_mojo")
  HostName = EC2_INSTANCE
end

configure do
  set :port, 8080
end

enable :sessions

HostName = 'localhost:8080' if development?
RPXTokenURL = "http://#{HostName}/rpx"
LoginLink = "https://mojo-jr.rpxnow.com/openid/v2/signin?token_url=#{CGI.escape(RPXTokenURL)}"

class Post
  Smileys = %w(tears sad dry smile biggrin)
  DefaultSmiley = 'smile'
  
  include DataMapper::Resource
  
  # TODO: Clen this up by making the properties inherit from parent?
  if RUBY_PLATFORM == 'java'
    property :id, Serial
    property :user, User, :required => true
    property :smiley, ByteString, :required => true
  else
    property :id, ObjectId
    property :user, String, :required => true
    property :smiley, String, :required => true
  end
  
  property :message, Text, :required => true, :lazy => false
  property :created_at, Time, :default => lambda { |r, p| Time.now }

  validates_presence_of :message
end

post '/rpx' do
  if params[:token].nil?
    return "<h1> Maaaaaaaaaaaa! Please allow me <a href='/'>access</a>! </h1>"
  end

  url = 'https://rpxnow.com/api/v2/auth_info'
  query = { 
    'token' => params[:token], 
    'format' => "json",
    'apiKey' => RPX_API_KEY
  }

  resp = JSON.load(url_fetch(url, query))

  # TODO: other open id providers
  session[:current_user] = email_from_data(resp)
  redirect "/"
end

get "/logout" do
  session[:current_user] = nil
  redirect "/"
end

get '/' do
  @scounts = Hash.new
  if logged_in?
    @posts = Post.all(:order => [:created_at.desc], :user => current_user)
    @scounts = count_smileys
  end
  erb :home
end

post '/' do
  redirect "/" unless logged_in?
  
  if params[:id]
    if (p = Post.get(params[:id]))
      raise "Auth error" unless p.user == current_user
      if !p.update(:message => params[:message], :smiley => params[:smiley])
        raise "Post Can't be saved! - #{p.errors.inspect}"
        redirect '/?error=not-saved'
      end
    end
  else
    # TODO: handle blank messages
    p = Post.create(:message => params[:message],
                :user => current_user,
                :smiley => params[:smiley] || Post::DefaultSmiley,
                :created_at => Time.now.to_s)
  end
  
  if p.saved?
    redirect '/'
  else
    raise "Post Can't be saved! - #{p.errors.inspect}"
    redirect '/?error=not-saved'
  end
end

# Utils for backups
get "/copy_to_s3" do  
  return "Not authorized!" unless params[:q] == CRON_ID
  
  AWS::S3::Base.establish_connection!(
    :access_key_id	 => AMAZON_ACCESS_ID,
    :secret_access_key => AMAZON_SECRET_KEY
  )

  post_json= Post.all.collect do |x| 
    # Hash[x.attributes.reject { |k, v| k.to_s == "id" }]
    y = x.attributes
		y.delete(:id)
		y
  end.to_json
  
  AWS::S3::S3Object.store( "post", post_json, 'meta-mojo')
  "[#{Time.now}] Done!\n"
end

# Utils for backups
get "/copy_from_s3" do
  return "Not authorized!" unless params[:q] == CRON_ID
  
  AWS::S3::Base.establish_connection!(
    :access_key_id	 => AMAZON_ACCESS_ID,
    :secret_access_key => AMAZON_SECRET_KEY
  )

  post_json = AWS::S3::S3Object.find 'post', 'meta-mojo'
  post_arr = JSON.parse(post_json.value)
  
  Post.all.destroy  
  post_arr.each { Post.create(item) }
  "[#{Time.now}] Done!\n"
end


helpers do
  def url_fetch(url, query)
    if RUBY_PLATFORM == 'java'
      AppEngine::URLFetch.fetch(url, 
        :method => 'post',
        :payload => query.map { |k,v|
          "#{CGI::escape k.to_s}=#{CGI::escape v.to_s}"
        }.join('&')
      ).body
    else
      # TODO: Make LoginLink an arg?
      client = HTTPClient.new
      res = client.post(url, query)
      res.body
    end
  end
    
  def count_smileys
    h = Hash.new
    Post::Smileys.each do |s|
      if RUBY_PLATFORM == 'java'
        q = AppEngine::Datastore::Query.new('Posts')
        q = q.filter("user", '==', current_user).filter("smiley", '==', s)
        h[s] = q.count
      else
        h[s] = Post.count(:smiley => s, :user => current_user)
      end      
    end
    return h
  end
  
  def current_user
    session[:current_user]
  end

  def email_from_data(info)
    raise "Stat fail" unless info["stat"] == "ok"

    if info["profile"]
      if info["profile"]["providerName"] == "Google"
        return info["profile"]["email"]
      end
    end

    raise "Unknown provider info!"
  end

  def logged_in?
    not session[:current_user].nil?
  end

  def time_dist(time)
    return "whenever" unless time

    dist = (Time.now - time).round
    if dist <= 180
      return "a few seconds"
    end

    dist /= 60
    if dist <= 10
      return "a few minutes"
    elsif dist <= 45
      return "about #{dist} minutes"
    end

    dist /= 60
    if dist <= 12
      return "about #{dist} hour#{'s' if dist > 1}"
    end

    dist /= 24
    if dist <= 0
      return "about 1 day"
    elsif dist < 7
      return "about #{dist} days"
    elsif dist <= 30
      return "about #{dist / 7} week#{'s' if dist / 7 > 1}"
    elsif dist <= 365
      return "about #{dist / 30} month#{'s' if dist / 30 > 1}"
    end

    return "a long time"
  end
end
