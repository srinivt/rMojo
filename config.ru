require 'rubygems'
require 'sinatra'

#set :environment, :production
#disable :run, :reload

if RUBY_PLATFORM != 'java'
  FileUtils.mkdir_p 'log' unless File.exists?('log')
  log = File.new("log/sinatra.log", "a")
  $stdout.reopen(log)
  $stderr.reopen(log)
end 

require 'app'

run Sinatra::Application
