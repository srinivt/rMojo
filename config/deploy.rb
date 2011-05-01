load File.dirname(__FILE__) + "/../keys.rb"

set :application, "mojo-jr"
set :repository, "git@github.com:srinivt/rMojo.git" 

ssh_options[:keys] = ["#{ENV['HOME']}/mojo-test.pem"]

set :scm, :git
set :branch, 'master'
set :git_shallow_clone, 1

set :user, 'ubuntu'
set :runner, 'ubuntu'

role :web, EC2_INSTANCE # Your HTTP server, Apache/etc
role :app, EC2_INSTANCE # This may be the same as your `Web` server
role :db,  EC2_INSTANCE, :primary => true # This is where Rails migrations will run

namespace :deploy do
  task :start do; end
  task :stop do; end
  
  after "deploy:update_code", "deploy:remove_gem_file"
  after "deploy:setup", "deploy:own_directory"
  after "deploy:setup", "prepare_machine"
  after "deploy", "setup_cron"
  before "deploy:restart", "deploy:copy_keys_file"
  
  task :own_directory do
    run "#{try_sudo} chown -R ubuntu /u/apps/mojo-jr"
  end
  
  task :prepare_machine do
    # TODO: For now run the script manually at EC2
    # PUt the script at the target machine at /tmp
    # and execute it
  end
  
  task :setup_cron do
    # TODO: setup cron
    # echo "*/4 * * * * "> /etc/cron.daily or something like that
  end
  
  task :copy_keys_file do
    file_name = "keys.rb"
    file = File.dirname(__FILE__) + "/../" + file_name
    put(File.read( file ),"#{latest_release}/#{file_name}", :via => :scp)
  end
  
  desc "For now, disable Gemfile and bundler at EC2. TODO: fix this"
  task :remove_gem_file do
    run "mv #{latest_release}/Gemfile #{latest_release}/.Gemfile"
  end
  
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
  end
  
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)

    # mkdir -p is making sure that the directories are there for some SCM's that don't save empty folders
    run <<-CMD
      rm -rf #{latest_release}/log &&
      mkdir -p #{latest_release}/public &&
      mkdir -p #{latest_release}/tmp &&
      ln -s #{shared_path}/log #{latest_release}/log
    CMD

    if fetch(:normalize_asset_timestamps, true)
      stamp = Time.now.utc.strftime("%Y%m%d%H%M.%S")
      asset_paths = %w(images css).map { |p| "#{latest_release}/public/#{p}" }.join(" ")
      run "find #{asset_paths} -exec touch -t #{stamp} {} ';'; true", :env => { "TZ" => "UTC" }
    end
  end
end