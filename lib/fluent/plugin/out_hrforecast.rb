
class Fluent::HRForecastOutput < Fluent::Output
  Fluent::Plugin.register_output('hrforecast', self)


  def initialize
    super
    require 'net/http'
    require 'uri'
    require 'resolve/hostname'
  end

  config_param :hrfapi_url, :string
  config_param :graph_path, :string

  config_param :name_keys, :string, :default => nil
  config_param :name_key_pattern, :string, :default => nil

  config_param :datetime_key, :string, :default => nil
  config_param :datetime_key_format, :string, :default => nil
  config_param :datetime_format, :string, :default => '%Y-%m-%d %H:%M:%S %z'

  config_param :remove_prefix, :string, :default => nil

  config_param :background_post, :bool, :default => false

  config_param :ssl, :bool, :default => false
  config_param :verify_ssl, :bool, :default => false

  config_param :timeout, :integer, :default => nil # default 60secs
  config_param :retry, :bool, :default => true
  config_param :keepalive, :bool, :default => true
  config_param :enable_float_number, :bool, :default => false

  config_param :authentication, :string, :default => nil # nil or 'none' or 'basic'
  config_param :username, :string, :default => ''
  config_param :password, :string, :default => '', :secret => true

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def configure(conf)
    super

    if @hrfapi_url !~ %r|/api/\z|
      raise Fluent::ConfigError, "hrfapi_url must end with /api/"
    end
    if @graph_path !~ %r|\A[^/]+/[^/]+/[^/]+\z|
      raise Fluent::ConfigError, "graph_path #{@graph_path}  must be like 'service/section/${tag}_${key_name}'"
    end

    if @name_keys.nil? and @name_key_pattern.nil?
      raise Fluent::ConfigError, "missing both of name_keys and name_key_pattern"
    end
    if not @name_keys.nil? and not @name_key_pattern.nil?
      raise Fluent::ConfigError, "cannot specify both of name_keys and name_key_pattern"
    end

    if not @datetime_key.nil? and @datetime_key_format.nil?
      raise Fluent::ConfigError, "missing datetime_key_format"
    end

    url = URI.parse(@hrfapi_url)
    @host = url.host
    @port = url.port

    if @name_keys
      @name_keys = Hash[
        @name_keys.split(',').map{|k|
          k.split('=>',2).tap{|kv|
            kv.push(kv[0]) if kv.size == 1
          }
        }
      ]
    end

    if @name_key_pattern
      @name_key_pattern = Regexp.new(@name_key_pattern)
    end

    if @remove_prefix
      @removed_prefix_string = @remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    @auth = case @authentication
            when 'basic' then :basic
            else
              :none
            end
    @resolver = Resolve::Hostname.new(:system_resolver => true)
  end

  class PostThread
    attr :queue

    def initialize(plugin)
      require 'thread'
      @queue = Queue.new
      @plugin = plugin
      @thread = Thread.new do
        begin
          post(@queue.deq) while true
        ensure
          post(@queue.deq) while not @queue.empty?
        end
      end
    end

    def post(events)
      begin
        @plugin.post_events(events) if events.size > 0
      rescue => e
        @plugin.log.warn "HTTP POST in background Error occures to HRforecast server", :error_class => e.class, :error => e.message
      end
    end

    def shutdown
      @thread.terminate
      @thread.join
    end
  end

  def start
    super

    @post_thread = nil
    if @background_post
      @post_thread = PostThread.new(self)
    end
  end

  def shutdown
    if @post_thread
      @post_thread.shutdown
    end
    super
  end

  def placeholder_mapping(tag, name)
    if @remove_prefix and
        ( (tag.start_with?(@removed_prefix_string) and tag.length > @removed_length) or tag == @remove_prefix)
      tag = tag[@removed_length..-1]
    end
    {'${tag}' => tag, '${key_name}' => name}
  end

  def format_url(tag, name)
    graph_path = @graph_path.gsub(/(\${[_a-z]+})/, placeholder_mapping(tag, name))
    return @hrfapi_url + URI.escape(graph_path)
  end

  def make_http_connection()
    http = Net::HTTP.new(@resolver.getaddress(@host), @port)
    if @timeout
      http.open_timeout = @timeout
      http.read_timeout = @timeout
    end
    if @ssl
      http.use_ssl = true
      unless @verify_ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
    http
  end

  def make_post_request(tag, name, value, time)
    url = URI.parse(format_url(tag,name))
    req = Net::HTTP::Post.new(url.path)
    if @auth and @auth == :basic
      req.basic_auth(@username, @password)
    end
    req['Host'] = url.host
    req['Connection'] = 'Keep-Alive' if @keepalive
    req.set_form_data({
      'number' => @enable_float_number ? value.to_f : value.to_i,
      'datetime' => Time.at(time).strftime(@datetime_format),
    })
    req
  end

  def post_events(events)
    return if events.size < 1

    requests = events.map do |e|
      make_post_request(e[:tag], e[:name], e[:value], e[:time])
    end

    http = make_http_connection()
    requests.each do |req|
      begin
        http.start unless http.started?
        res = http.request(req)
        unless res and res.is_a?(Net::HTTPSuccess)
          log.warn "failed to post to HRforecast: #{host}:#{port}#{req.path}, post_data: #{req.body} code: #{res && res.code}"
        end
      rescue IOError, EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT, SystemCallError
        log.warn "net/http POST raises exception: #{$!.class}, '#{$!.message}'"
        http.finish if http.started?
      end
      if not @keepalive and http.started?
        http.finish
      end
    end
  end

  def decide_time(time, record)
    if @datetime_key && record[@datetime_key]
      time = Time.strptime(record[@datetime_key], @datetime_key_format)
    end
    time
  end

  def emit(tag, es, chain)
    events = []
    if @name_keys
      es.each {|time,record|
        time = decide_time(time, record)
        @name_keys.each {|key, name|
          if value = record[key]
            events.push({:tag => tag, :name => name, :value => value, :time => time})
          end
        }
      }
    else # for name_key_pattern
      es.each {|time,record|
        time = decide_time(time, record)
        record.keys.each {|key|
          if @name_key_pattern.match(key) and record[key]
            name = Regexp.last_match(1) || key
            events.push({:tag => tag, :name => name, :value => record[key], :time => time})
          end
        }
      }
    end

    if @post_thread
      @post_thread.queue << events
    else
      begin
        post_events(events)
      rescue => e
        log.warn "HTTP POST Error occures to HRforecast server", :error_class => e.class, :error => e.message
        raise if @retry
      end
    end

    chain.next
  end
end

