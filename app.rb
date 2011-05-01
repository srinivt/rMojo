require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'json'
require 'cgi'
require 'dm-core'
require 'dm-validations'
require 'aws/s3'
require 'keys'  #keys is a secure file!  it is not to be checked in

include AWS::S3

AWS::S3::Base.establish_connection!(
  :access_key_id	 => AMAZON_ACCESS_ID,
  :secret_access_key => AMAZON_SECRET_KEY
)

if RUBY_PLATFORM == 'java'
  require 'appengine-apis/urlfetch'
  require 'appengine-apis/datastore'
else
  require 'httpclient'
end

configure do
  set :port, 8080
end

enable :sessions

if RUBY_PLATFORM == "java"
  DataMapper.setup(:default, "appengine://auto")
else
  DB_NAME = 'meta_mojo'
  DataMapper.setup(:default,
    :adapter  => 'mongo',
    :database => DB_NAME
  )
  
  # Placeholder for Mongodb.
  # User object just holds the email address
  class User < String; end
  class ByteString < String; end  
end
# DataMapper::Model.raise_on_save_failure = true

# RPXTokenURL = 'http://mojo-jr.appspot.com/rpx'  # appspot
RPXTokenURL = 'http://localhost:8080/rpx'

LoginLink = "https://mojo-jr.rpxnow.com/openid/v2/signin?token_url=#{CGI.escape(RPXTokenURL)}"

class Post
  Smileys = %w(tears sad dry smile biggrin)
  DefaultSmiley = 'smile'
  
  include DataMapper::Resource
  
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

  session[:current_user] = email_from_data(resp)

  # What is the email 
  # set the user id in session!!
  redirect "/"
end

get "/logout" do
  session[:current_user] = nil
  redirect "/"
end

get "/copy_to_s3" do
  
  text = "<pre>"
  
  post_json= Post.all.collect do |x| 
        y = x.attributes
		y.delete(:id)
		y
  end.to_json
  
  S3Object.store(
    "post",
	post_json,
	'meta-mojo'
  )
  
  #post_arr = JSON.parse(post_json)
 

  
	#post_arr.each() do |item| 
  
    #item.each() do |k,v|
	# 	text+=k.to_s+" " +v.to_s+"\n"  
    #end
	    
	    #Post.create(item) 
	#end
  
  
  text += "</pre>"
  #redirect '/'
  
end

get "/copy_from_s3" do
  post_json = S3Object.find 'post', 'meta-mojo'
  
  post_arr = JSON.parse(post_json.value)
  
  Post.all.destroy
  
  post_arr.each() do |item|
	Post.create(item)
  end
  
  ""
end

get "/delete_all_data" do
  Post.all.destroy
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
  if params[:id]
    p = Post.get(params[:id])
    # TODO: Add authorization to prevent updates to unowned posts
    if p
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
        h[s] = Post.count(:smiley => s)
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
      return "about #{dist} week#{'s' if dist / 7 > 1}"
    elsif dist <= 365
      return "about #{dist / 30} month#{'s' if dist / 30 > 1}"
    end

    return "a long time"
  end
end
