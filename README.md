# Fluent::Plugin::Hrforecast

[![Build Status](https://travis-ci.org/do-aki/fluent-plugin-hrforecast.svg?branch=master)](https://travis-ci.org/do-aki/fluent-plugin-hrforecast)

[![Coverage Status](https://coveralls.io/repos/do-aki/fluent-plugin-hrforecast/badge.png?branch=master)](https://coveralls.io/r/do-aki/fluent-plugin-hrforecast?branch=master)

fluentd output plugin for HRForecast

## Overview
Fluented output plugin for sending metrics to [HRForecast](https://github.com/kazeburo/HRForecast).
This plugin code was wittern based on [fluent-plugin-growthforecast](https://github.com/tagomoris/fluent-plugin-growthforecast)

## Configuration

### Sample1
Tag is `metrics` and message is `{'field1':10, 'field2':200, 'others':3000}`.

By follow config, send 2 numbers and time specified input plugin to HRForecast.
* send 10 and time to http://hrforecast.local/api/service/section/metrics_field1
* send 200 and time to http://hrforecast.local/api/service/section/metrics_field2

```
<match metrics>
  type hrforecast
  hrfapi_url http://hrforecast.local/api/
  graph_path service/section/${tag}_${key_name}
  name_keys  field1,field2
</match>
```


### Sample2
Tag is `metrics` and message is `{'date_field':'2014/05/23', 'field_hoge':89.3}`.

By follow config, send a floating number and formatted date to HRForecast.
* send 89.3 and '2014-05-23 00:00:00' to http://hrforecast.local/api/service/metrics/hoge

```
<match metrics>
  type hrforecast
  hrfapi_url http://hrforecast.local/api/
  graph_path service/${tag}/${key_name}
  name_key_pattern    ^field_(.*)$
  enable_float_number true
  datetime_key        date_field
  datetime_key_format %Y/%m/%d
  datetime_format     %Y-%m-%d %H:%M:%S
</match>
```


## Options

* __hrfapi_url__ (required)

 URL of HRForecast API base like 'http://hrforecast.local/api/'

* __graph_path__ (required)

 Graph Path of HRForecast API endpoint include service_name, section_name and graph_name separated slash.
 e.g. `service/section/graph`

 You can customize graph_path using `${tag}` and `${key_name}` placeholders.

* __name_keys__ (Either of this or __name_key_pattern__ is required)
 Specify field names of sending number. Separate by comma.

* __name_key_pattern__ (Either of this or __name_keys__ is required)
 Specify field names of sending number.

* __datetime_key__ (default: none)
 Specify field names of sending datetime if you need.

* __datetime_key_format__ (required if specified __datetime_key__)
 Parse format for datetime of field specified datetime_key

* __datetime_format__ (default: %Y-%m-%d %H:%M:%S %z)
 Format of datetime POST parameter.

* __remove_prefix__ (default:none)

* __background_post__ (default:false)

* __ssl__ (default:false)

* __verify_ssl__ (default:false)

* __timeout__ 

* __retry__ (default: true)

* __keepalive__  (default: true)

* __enable_float_number__  (default: false)

* __authentication__ (default:none)

* __username__ (default:empty)

* __password__ (default:empty)


## License
Apache License, Version 2.0

