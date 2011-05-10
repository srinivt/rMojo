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
  
  DataMapper.setup(:default, "mongo://#{EC2_DB}/meta_mojo")
  HostName = EC2_INSTANCE
end

enable :sessions, :logging

configure do
  set :port, 8080
end

HostName = 'localhost:8080' if development?
RPXTokenURL = "http://#{HostName}/rpx"
LoginLink = "https://mojo-jr.rpxnow.com/openid/v2/signin?token_url=#{CGI.escape(RPXTokenURL)}"

class Mojo_User
  User_States = %w(unknown joined left)
  DefaultUserState = 'unknown'
    
  include DataMapper::Resource
  
  property :user, String
  
  if RUBY_PLATFORM == 'java'
    property :id, Serial
    property :user_state, ByteString, :required => true
  else
    property :id, ObjectId
    property :user_state, String, :required => true
  end
  
  property :name, String
  
  property :joined_on, Time, :default => lambda { |r, p| Time.now }
end

class Post
  Smileys = %w(tears sad dry smile biggrin)
  DefaultSmiley = 'smile'
  PostsPerPage = 15
  
  include DataMapper::Resource
  
  if RUBY_PLATFORM == 'java'
    property :id, Serial
    property :smiley, ByteString, :required => true
  else
    property :id, ObjectId
    property :smiley, String, :required => true
  end
  
  property :user, String, :required => true
  property :message, Text, :required => true, :lazy => false
  property :created_at, Time, :default => lambda { |r, p| Time.now }

  #validates_presence_of :message
end

# Friend relation describes relationship of 'friend' to 'user'
# Possible States:
# User->Friend    Friend->User
# nil             nil
# requested       request_pending
# rejected        request_rejected
# accepted        accepted

class Friend
  include DataMapper::Resource
  
  FriendsStates = %w(requested rejected request_pending request_rejected accepted)
  DefaultFriendState = ''
  
  if RUBY_PLATFORM == 'java'
    property :id, Serial
    property :friend_state, ByteString, :required => true
  else
    property :id, ObjectId
    property :friend_state, String, :required => true
  end
  
  property :user, String
  property :friend, String
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
  session[:current_user] = get_user_from_data(resp).user
  redirect "/"
end

get "/logout" do
  session[:current_user] = nil
  redirect "/"
end

def is_a_number?(s)
  s.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true 
end

get '/friend/:friend_id' do
  @scounts = Hash.new
  if logged_in?
    
    @friend_id = params[:friend_id]
    
    friend = Mojo_User.get(@friend_id)
    
    friendship = Friend.first(:user=>current_user, :friend=>friend.user)
    
    #don't let non-friends through
    redirect '/' unless friendship and friendship.friend_state == 'accepted'
    
    @posts = Post.all(:order => [:created_at.desc], :user => friend.user)
    
    @friends = Friend.all(:friend => current_user, :friend_state => 'accepted')
    @pending_friends = Friend.all(:friend => current_user, :friend_state => 'requested')
    @requested_friends = Friend.all(:friend => current_user, :friend_state => 'request_pending')
    @mojo_name = current_user
    @scounts = count_smileys
  end
  erb :home
end

get '/' do
  @scounts = Hash.new
  if logged_in?
    @friend_id = ""
    @posts = Post.all(:order => [:created_at.desc], :user => current_user)
    @friends = Friend.all(:friend => current_user, :friend_state => 'accepted')
    @pending_friends = Friend.all(:friend => current_user, :friend_state => 'requested')
    @requested_friends = Friend.all(:friend => current_user, :friend_state => 'request_pending')
    @mojo_name = current_user
    @scounts = Hash.new #count_smileys
  end
  erb :home
end

get '/accept_friend/:uid' do
  redirect "/" unless logged_in?
  redirect "/" unless params[:uid]!=""
  
  accept_friend = Friend.get(params[:uid]);
  
  if not accept_friend
    redirect "/"
  end
  
  rel_fwd = Friend.first({:user => current_user,:friend => accept_friend.user})
  rel_bkw = Friend.first({:user => accept_friend.user,:friend => current_user})
  
  if rel_bkw.friend_state == 'requested'
    rel_fwd.update({:friend_state => 'accepted'})
    rel_bkw.update({:friend_state => 'accepted'})
  end
  
  redirect "/"
  
end

get '/end_friend/:uid' do
  redirect "/" unless logged_in?
  redirect "/" unless params[:uid]!=""
  
  cancel_friend = Friend.get(params[:uid]);
  
  if not cancel_friend
    redirect "/"
  end
  
  rel_fwd = Friend.first({:user => current_user,:friend => cancel_friend.user})
  rel_bkw = Friend.first({:user => cancel_friend.user,:friend => current_user})
  
  rel_fwd.destroy
  rel_bkw.destroy
  
  redirect "/"
  
end

# requested       request_pending
# rejected        request_rejected
# accepted        accepted
post '/invite' do
  redirect "/" unless logged_in?
  redirect "/" unless params[:friend_email]!=""
  
  mu = Mojo_User.first_or_create({ :user => params[:friend_email]  }, 
		{ :name => "unknown" , :joined_on => Time.now.to_s, :user_state => 'unknown'})
    
  me = Mojo_User.first({:user => current_user})
  
  #first check if there is a pending request on me
  rel_fwd = Friend.first_or_create({:user => current_user,:friend => mu.user},{:friend_state => 'requested'} )
  rel_bkw = Friend.first_or_create({:user => mu.user,:friend => current_user},{:friend_state => 'request_pending'})
  
  if rel_fwd.friend_state == 'rejected'
    rel_fwd.update({:friend_state => 'requested' } )
    rel_fwd.update({:friend_state => 'request_pending'} )
  elsif rel_fwd.friend_state ==  'request_pending'
    rel_fwd.update({:friend_state => 'accepted'} )
    rel_fwd.update({:friend_state => 'accepted'} )
  end
  
  redirect '/'
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
  #return "Not authorized!" unless params[:q] == CRON_ID
  
  if admin_logged_in?(params[:q])
    AWS::S3::Base.establish_connection!(
      :access_key_id     => AMAZON_ACCESS_ID,
      :secret_access_key => AMAZON_SECRET_KEY
    )

    post_json= Post.all.collect do |x| 
      y = x.attributes
          y.delete(:id)
          y
    end.to_json
    
    user_json= Mojo_User.all.collect do |x| 
      y = x.attributes
          y.delete(:id)
          y
    end.to_json
    
    friend_json= Friend.all.collect do |x| 
      y = x.attributes
          y.delete(:id)
          y
    end.to_json
    
	  stamp=Time.now.to_i.to_s
	
	  post_name = "user_" + stamp
    user_name = "post_" + stamp
    friend_name = "friend_" + stamp
  
    AWS::S3::S3Object.store( post_name, post_json, 'meta-mojo-post')
    AWS::S3::S3Object.store( user_name, user_json, 'meta-mojo-user')
    AWS::S3::S3Object.store( friend_name, friend_json, 'meta-mojo-friend')
    "Done!   [#{Time.now}]"
  else
    "You are not an admin!"
  end
end


# Utils for backups
get "/copy_from_s3" do
  #return "Not authorized!" unless params[:q] == CRON_ID
  
  if admin_logged_in?(params[:q])
    AWS::S3::Base.establish_connection!(
      :access_key_id     => AMAZON_ACCESS_ID,
      :secret_access_key => AMAZON_SECRET_KEY
    )

    
    post_bucket = AWS::S3::Bucket.find('meta-mojo-post')
    user_bucket = AWS::S3::Bucket.find('meta-mojo-user')
    friend_bucket = AWS::S3::Bucket.find('meta-mojo-friend')
    
    get_latest(post_bucket)
	
    #post_json = AWS::S3::S3Object.find 'post', 'meta-mojo-post'
    
    
    user_arr = JSON.parse(get_latest(user_bucket))
    Mojo_User.all.destroy  
    
    user_arr.each { |item| Mojo_User.create(item) }

    friend_arr = JSON.parse(get_latest(friend_bucket))
    Friend.all.destroy  
    friend_arr.each  { |item| Friend.create(item) }
    
    post_arr = JSON.parse(get_latest(post_bucket))
    Post.all.destroy  
    post_arr.each { |item| Post.create(item) }
    
    
    "Done!  [#{Time.now}]"
  else
    "You are not an admin!"
  end
end

get '/start_test' do
  perf_email = 'perf_user@mojo.com'
  perf_name = "Mojo Performentor"
  
  Mojo_User.first_or_create(
    { :user => perf_email  }, 
    { :name => perf_name , :joined_on => Time.now.to_s, :user_state => 'joined'})
  
  session[:current_user] = perf_email
  redirect '/'
end

helpers do
  def get_latest(bucket)
    latest_stamp=0
    latest_value=nil
    
    bucket.objects.each do |x|
      stamp = x.key.split('_')[1].to_i
      if stamp > latest_stamp
        latest_value = x.value
        latest_stamp = stamp
      end
    end
    return latest_value
  end 

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
    perf_test? ? "perf_user#{params[:puid]}@mojo.com" : session[:current_user]
  end
  
  def current_user_name
    mu = Mojo_User.first({:user => current_user})
    if mu
      return mu.name
    end
    "none"
  end

  def name_by_user(user)
    if user and user.name != "unknown"
      return user.name
    elsif user
      return user.user
    end
    "none"
  end
  
  def name_by_id(id)
    mu = Mojo_User.get(id)
    name_by_user(mu)
  end
  
  def name_of(email)
    mu = Mojo_User.first({:user => email})
    name_by_user(mu)
  end
  
  def user_of(email)
    Mojo_User.first({:user => email})
  end
  
  def get_user_from_data(info)
    raise "Stat fail" unless info["stat"] == "ok"

    if info["profile"]
      if info["profile"]
        cur_email = info["profile"]["email"]
        cur_name = info["profile"]["name"]['formatted']

        if cur_name.empty?
          cur_name = cur_email
        end

        mu = Mojo_User.first_or_create({ :user => cur_email  }, 
        { :name => cur_name , :joined_on => Time.now.to_s, :user_state => 'joined'})

        if mu.user_state == 'unknown'
          mu.update( {:user_state => 'joined', :name => cur_name } )
        end

        if mu.saved?
          return mu
        else
          raise "Not Saved! - #{mu.errors.inspect}"
        end
      end
    end

    raise "Unknown provider info!"
  end

  def logged_in?
    (not session[:current_user].nil?) || perf_test?
  end
  
  def admin_logged_in?(qid = nil)
    session[:current_user]=="tony.nowatzki@gmail.com" or 
    session[:current_user]=="sr.iniv.t@gmail.com" or
    qid == CRON_ID
    #(RUBY_PLATFORM == 'java' and param[:X-AppEngine-Cron]==true)
  end
  
  def perf_test?
    params[:perf_test] == '1'
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
