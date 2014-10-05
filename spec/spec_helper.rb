$: << File.expand_path('..', __FILE__)
require 'gratan'
require 'tempfile'

IGNORE_USER = /\A(|root)\z/

RSpec.configure do |config|
  config.before(:each) do
    clean_grants
  end
end

def mysql
  client = nil
  retval = nil

  begin
    client = Mysql2::Client.new(host: 'localhost', username: 'root')
    retval = yield(client)
  ensure
    client.close if client
  end

  retval
end

def select_users(client)
  users = []

  client.query('SELECT user, host FROM mysql.user').each do |row|
    users << [row['user'], row['host']]
  end

  users
end

def clean_grants
  mysql do |client|
    select_users(client).each do |user, host|
      next if IGNORE_USER =~ user
      user_host =  "'%s'@'%s'" % [client.escape(user), client.escape(host)]
      client.query("DROP USER #{user_host}")
    end
  end
end

def show_grants
  grants = []

  mysql do |client|
    select_users(client).each do |user, host|
      next if IGNORE_USER =~ user
      user_host =  "'%s'@'%s'" % [client.escape(user), client.escape(host)]

      client.query("SHOW GRANTS FOR #{user_host}").each do |row|
        grants << row.values.first
      end
    end
  end

  grants.sort
end

def client(user_options = {})
  if user_options[:ignore_user]
    user_options[:ignore_user] = Regexp.union(IGNORE_USER, user_options[:ignore_user])
  end

  options = {
    host: 'localhost',
    username: 'root',
    ignore_user: IGNORE_USER,
    logger: Logger.new('/dev/null'),
  }

  if ENV['DEBUG']
    logger = Gratan::Logger.instance
    logger.set_debug(true)

    options.update(
      debug: true,
      logger: logger
    )
  end

  options = options.merge(user_options)
  Gratan::Client.new(options)
end

def apply(client)
  grantfile = yield

  Tempfile.open("#{File.basename __FILE__}.#{$$}") do |f|
    f.puts(grantfile)
    f.flush
    client.apply(f.path)
  end
end