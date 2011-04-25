require 'sinatra'
require 'dm-core'
require 'sinatra/reloader' if development?
require 'dm-validations'
require 'appengine-apis/urlfetch'
require 'appengine-apis/datastore'
require 'json'
require 'cgi'

# This is the rack stuff. Trying OmniAuth instead
use Rack::Session::Cookie
require 'rack/openid'
use Rack::OpenID

enable :sessions

DataMapper.setup(:default, "appengine://auto")
DataMapper::Model.raise_on_save_failure = true

# RPXTokenURL = 'http://mojo-jr.appspot.com/rpx'  # appspot
RPXTokenURL = 'http://localhost:8080/rpx'

LoginLink = "https://mojo-jr.rpxnow.com/openid/v2/signin?token_url=#{CGI.escape(RPXTokenURL)}"

class Post
  Smileys = %w(tears sad dry smile biggrin)
  DefaultSmiley = 'smile'
  
  include DataMapper::Resource

  property :id, Serial
  property :user, User, :required => true
  property :smiley, ByteString, :required => true
  property :message, Text, :required => true
  property :created_at, Time, :default => lambda { |r, p| Time.now }

  validates_presence_of :message
end

post '/rpx' do
  api_key = '50909eae58912fec7bd2983493eb82062348a872'

  if params[:token].nil?
    return "<h1> Maaaaaaaaaaaa! Please allow me <a href='/'>access</a>! </h1>"
  end

  url = 'https://rpxnow.com/api/v2/auth_info'
  query = { 
    :token => params[:token], 
    :format => "json",
    :apiKey => api_key
  }

  resp = JSON.load(AppEngine::URLFetch.fetch(url, 
    :method => 'post',
    :payload => query.map { |k,v|
      "#{CGI::escape k.to_s}=#{CGI::escape v.to_s}"
    }.join('&')
  ).body)

  session[:current_user] = email_from_data(resp)

  # What is the email 
  # set the user id in session!!
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
  # handle blank messages
  p = Post.create(:message => params[:message],
              :user => current_user,
              :smiley => params[:smiley] || Post::DefaultSmiley,
              :created_at => Time.now )
  if p.saved?
    redirect '/'
  else
    flash[:message] = "Give me something to save!!"
    redirect '/'
  end
end

helpers do
  def count_smileys
    h = Hash.new
    Post::Smileys.each do |s|
      q = AppEngine::Datastore::Query.new('Posts')
      q = q.filter("user", '==', current_user).filter("smiley", '==', s)
      h[s] = q.count
    end
    return h
  end
  
  def current_user
    session[:current_user]
  end

  def email_from_data(info)
    puts info.to_yaml

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
