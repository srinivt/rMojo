require 'sinatra'
require 'dm-core'
require 'sinatra/reloader' if development?
require 'dm-validations'

# This is the rack stuff. Trying OmniAuth instead
# use Rack::Session::Cookie
# require 'rack/openid'
# use Rack::OpenID

DataMapper.setup(:default, "appengine://auto")
DataMapper::Model.raise_on_save_failure = true

class Post
  include DataMapper::Resource

  property :id, Serial
  property :user, User
  property :smiley, Text
  property :message, Text, :required => true
  property :created_at, Time, :default => lambda { |r, p| Time.now }

  validates_presence_of :message
end

get '/' do
  @posts = Post.all(:order => [:created_at.desc])
  erb :home
end

post '/' do
  # handle blank messages
  p = Post.create(:message => params[:message],
              :smiley => params[:smiley] || "sad",
              :created_at => Time.now )
  if p.saved?
    redirect '/'
  else
    flash[:message] = "Give me something to save!!"
    redirect '/'
  end
end

# TODO Authentication

helpers do
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
      return "about #{dist} hours"
    end

    dist /= 24
    if dist <= 0
      return "about 1 day"
    elsif dist <= 30
      return "about a month"
    end

    return "a long time"
  end
end
