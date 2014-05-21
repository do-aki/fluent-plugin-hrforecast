# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-hrforecast"
  spec.version       = "0.0.1"
  spec.authors       = ["do-aki"]
  spec.email         = ["do.hiroaki@gmail.com"]
  spec.description   = %q{For HRForecast}
  spec.summary       = %q{Fluentd output plugin to post to HRForecast}
  spec.homepage      = "https://github.com/do-aki/fluent-plugin-hrforecast"
  spec.license       = "APLv2"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  #spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "coveralls"
  spec.add_development_dependency "net-empty_port"
  spec.add_runtime_dependency "fluent-plugin-growthforecast"
end
