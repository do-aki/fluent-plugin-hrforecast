require 'helper'

class HRForecastTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def create_driver(conf, tag='test.metrics')
    Fluent::Test::OutputTestDriver.new(Fluent::HRForecastOutput, tag).configure(conf)
  end

  def test_config_default
    d = create_driver(%q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys field1,field2,field3=>otherfield
    ])
    assert_equal 'http://127.0.0.1:5125/api/', d.instance.hrfapi_url
    assert_equal '127.0.0.1', d.instance.instance_eval{ @host }
    assert_equal 5125, d.instance.instance_eval{ @port }
    assert_equal 'service/metrics/${tag}_${key_name}', d.instance.graph_path
    assert_equal _={'field1'=>'field1', 'field2'=>'field2', 'field3'=>'otherfield'}, d.instance.name_keys
    assert_equal '%Y-%m-%d %H:%M:%S %z', d.instance.datetime_format
    assert_nil d.instance.datetime_key
    assert_nil d.instance.datetime_key_format
    assert_nil d.instance.remove_prefix
    assert_equal 'http://127.0.0.1:5125/api/service/metrics/test.data1_field1', d.instance.format_url('test.data1', 'field1')
  end

  def test_config_name_key_pattern
    config = %q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service/metrics/${tag}_${key_name}
      remove_prefix    test
      name_key_pattern ^(field|key)\d+$
    ]

    d = create_driver(config)
    assert_equal Regexp.new('^(field|key)\d+$'), d.instance.name_key_pattern
  end

  def test_config_remove_prefix
    config = %q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service/metrics/${tag}_${key_name}
      remove_prefix test
      name_keys     field
    ]

    d = create_driver(config)
    assert_equal 'test', d.instance.remove_prefix
    assert_equal 'test.', d.instance.instance_eval{ @removed_prefix_string }
  end

  def test_bad_config_invalid_hrfapi_url
    config = %q[
      hrfapi_url  http://example.com/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
    ]
    assert_raise(Fluent::ConfigError) {
      d = create_driver(config)
    }
  end

  def test_bad_config_invalid_graph_path
    config = %q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service//${tag}_${key_name}
      name_keys  field1,field2,otherfield
    ]
    assert_raise(Fluent::ConfigError) {
      d = create_driver(config)
    }
  end

  def test_bad_config_missing_name_keys
    config = %q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service/metrics/${tag}_${key_name}
    ]
    assert_raise(Fluent::ConfigError) {
      d = create_driver(config)
    }
  end

  def test_bad_config_specify_both
    config = %q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
      name_key_pattern ^field.*$
    ]
    assert_raise(Fluent::ConfigError) {
      d = create_driver(config)
    }
  end

  def test_bad_config_missing_datetime_key_format
    config = %q[
      hrfapi_url  http://127.0.0.1:5125/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
      datetime_key time_field
    ]
    assert_raise(Fluent::ConfigError) {
      d = create_driver(config)
    }
  end
end



class HRForecastWithDummryServerTest < Test::Unit::TestCase

  def setup
    require 'net/http'
    @server = DummyServer.new
  end

  def teardown
    @server.shutdown
  end

  def create_driver(conf, tag='test.metrics')
    Fluent::Test::OutputTestDriver.new(Fluent::HRForecastOutput, tag).configure(conf)
  end
  
  def test_0dummyserver
    res = Net::HTTP.start('127.0.0.1', @server.port) {|http|
      http.request(Net::HTTP::Get.new('/'))
    }

    assert_equal '200', res.code
    assert_equal 'running', res.body
  end

  def test_0dummyserver_invalid_request
    res = Net::HTTP.start('127.0.0.1', @server.port) {|http|
      http.request(Net::HTTP::Get.new('/api'))
    }

    assert_equal '405', res.code
    assert_equal 'invalid request method', res.body
  end

  def test_0dummyserver_auth_failure
    @server.setAuth('user', 'pass')

    res = Net::HTTP.start('127.0.0.1', @server.port) {|http|
      http.request(Net::HTTP::Post.new('/api'))
    }

    assert_equal '403', res.code
  end
  
  def basic_assertion(config, wait_post_thread=false)
    time = Time.now()
    d = create_driver(config, 'test.metrics')

    d.run do
      d.emit({'field1' => 50, 'field2'=> 20, 'field3' => 10, 'otherfield' => 1}, time)
      sleep 0.3 if wait_post_thread
    end

    assert_equal 3, @server.posted.size
    v1st = @server.posted[0]
    v2nd = @server.posted[1]
    v3rd = @server.posted[2]
    time_str = time.strftime('%Y-%m-%d %H:%M:%S %z')


    assert_equal '50', v1st[:data][:number]
    assert_equal time_str, v1st[:data][:datetime]
    assert_nil v1st[:auth]
    assert_equal 'service/metrics/test.metrics_field1', v1st[:path]

    assert_equal '20', v2nd[:data][:number]
    assert_equal time_str, v1st[:data][:datetime]
    assert_equal 'service/metrics/test.metrics_field2', v2nd[:path]

    assert_equal '1', v3rd[:data][:number]
    assert_equal time_str, v1st[:data][:datetime]
    assert_equal 'service/metrics/test.metrics_otherfield', v3rd[:path]
  end

  def test_emit
    basic_assertion %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
    ]
  end

  def test_emit_pattern
    basic_assertion %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_key_pattern ^(?:field[1|2])|(?:field)$
    ]
  end

  def test_non_keepalive
    basic_assertion %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
      keepalive  false
    ]
  end

  def test_threading
    basic_assertion %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
      background_post true
    ], true
  end

  def test_threading_non_keepalive
    basic_assertion %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
      background_post true
      keepalive  false
    ], true
  end

  def test_graphpath
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path ${tag}/${key_name}_${tag}/${tag}_${key_name}
      name_keys  field
    ]

    d = create_driver(config, 'tag')
    d.run do
      d.emit({'field' => 50, 'otherfield' => 10})
    end

    assert_equal 1, @server.posted.size
    v1 = @server.posted[0]

    assert_equal '50', v1[:data][:number]
    assert_equal 'tag/field_tag/tag_field', v1[:path]
  end

  def test_remove_tag
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field
      remove_prefix removed
    ]

    d = create_driver(config, 'removed.tag')
    d.run do
      d.emit({'field' => 50, 'otherfield' => 10})
    end

    assert_equal 1, @server.posted.size
    v1 = @server.posted[0]

    assert_equal '50', v1[:data][:number]
    assert_equal 'service/metrics/tag_field', v1[:path]
  end

  def test_enable_float_number
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field
      enable_float_number true
    ]

    d = create_driver(config, 'removed.tag')
    d.run do
      d.emit({'field' => 50.1, 'otherfield' => 10})
    end

    assert_equal 1, @server.posted.size
    v1 = @server.posted[0]

    assert_equal '50.1', v1[:data][:number]
  end

  def test_name_keys_mapping
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field1=>name,field2
    ]

    d = create_driver(config, 'test.metrics')
    d.run do
      d.emit({'field1' => 50, 'field2' => 20, 'otherfield' => 10})
    end

    assert_equal 2, @server.posted.size
    v1 = @server.posted[0]
    v2 = @server.posted[1]

    assert_equal '50', v1[:data][:number]
    assert_equal 'service/metrics/test.metrics_name', v1[:path]

    assert_equal '20', v2[:data][:number]
    assert_equal 'service/metrics/test.metrics_field2', v2[:path]
  end

  def test_name_pattern_mapping
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_key_pattern  field(\\d)
    ]

    d = create_driver(config, 'test.metrics')
    d.run do
      d.emit({'field1' => 50, 'field2' => 20, 'otherfield' => 10})
    end

    assert_equal 2, @server.posted.size
    v1 = @server.posted[0]
    v2 = @server.posted[1]

    assert_equal '50', v1[:data][:number]
    assert_equal 'service/metrics/test.metrics_1', v1[:path]

    assert_equal '20', v2[:data][:number]
    assert_equal 'service/metrics/test.metrics_2', v2[:path]
  end

  def test_datetime_format
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field
      datetime_format %Y%m%d
    ]

    time = Time.now()
    d = create_driver(config, 'tag')
    d.run do
      d.emit({'field' => 50}, time)
    end

    assert_equal 1, @server.posted.size
    v1 = @server.posted[0]

    assert_equal '50', v1[:data][:number]
    assert_equal time.strftime('%Y%m%d'), v1[:data][:datetime]
  end

  def test_datetime_key
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field
      datetime_format %Y%m%d
      datetime_key time_field
      datetime_key_format %Y/%m/%d
    ]

    d = create_driver(config, 'tag')
    d.run do
      d.emit({'time_field' => '2014/05/18', 'field' => 50})
    end

    assert_equal 1, @server.posted.size
    v1 = @server.posted[0]

    assert_equal '50', v1[:data][:number]
    assert_equal '20140518', v1[:data][:datetime]
  end

  def test_auth
    @server.setAuth('user1', 'password!')

    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field
      authentication basic
      username   user1
      password  password!
    ]

    d = create_driver(config, 'tag')
    d.run do
      d.emit({'field' => 50})
    end

    assert_equal 1, @server.posted.size
  end


  def test_bad_connection
    config = %[
      hrfapi_url  http://127.0.0.1:#{@server.port}/api/
      graph_path service/metrics/${tag}_${key_name}
      name_keys  field
      timeout    1
    ]
    @server.shutdown

    assert_nothing_raised do
      d = create_driver(config, 'removed.tag')
      d.run do
        d.emit({'field' => 50, 'otherfield' => 10})
      end
    end

  end
end
