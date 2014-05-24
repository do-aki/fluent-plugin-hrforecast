require 'rubygems'
require 'bundler'
require 'simplecov'
require 'coveralls'

SimpleCov.start

begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missin gems"
  exit e.status_code
end
require 'test/unit'

require 'fluent/test'
unless ENV.has_key?('VERBOSE')
  nulllogger = Object.new
  nulllogger.instance_eval {|obj|
    def method_missing(method, *args)
      # pass
    end
  }
  $log = nulllogger
end

require 'fluent/plugin/out_hrforecast'

class Test::Unit::Testcase
end


class DummyServer

  attr :port
  attr :posted

  def initialize
    require 'net/empty_port'
    @posted = []
    @port = Net::EmptyPort.empty_port
    @auth = nil
    @thread = Thread.new do
      require 'webrick'

      sv = if ENV['VERBOSE']
             WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => @port})
           else
             logger = WEBrick::Log.new('/dev/null', WEBrick::BasicLog::DEBUG)
             WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => @port, :Logger => logger, :AccessLog => []})
           end

      begin
        sv.mount_proc('/api') do |req, res|
          unless req.request_method == 'POST'
            res.status = 405
            res.body = 'invalid request method'
            next
          end

          if @auth
            if req.header['authorization'][0] != @auth
              res.status = 403
              next
            end
          end

          req.path =~ %r|^/api/(.*)$|
          path = Regexp.last_match(1)
          post_param = Hash[req.body.split('&').map{|kv| kv.split('=',2)}]
          datetime = URI.decode_www_form_component(post_param['datetime']) if post_param['datetime']
          @posted.push({
            :path => path,
            :data => {:number => post_param['number'], :datetime => datetime},
          })

          res.status = 200
        end
        sv.mount_proc('/') do |req,res|
          res.status = 200
          res.body = 'running'
        end
        sv.start
      ensure
        sv.shutdown
      end
    end

    Net::EmptyPort.wait(@port, 3)
  end

  def shutdown
    @thread.kill
    @thread.join
  end

  def setAuth(user, password)
    require 'base64'
    @auth = 'Basic ' + Base64.encode64("#{user}:#{password}").chomp
  end
end
