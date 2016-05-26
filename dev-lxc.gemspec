# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dev-lxc/version'

Gem::Specification.new do |spec|
  spec.name          = "dev-lxc"
  spec.version       = DevLXC::VERSION
  spec.authors       = ["Jeremiah Snapp"]
  spec.email         = ["jeremiah@getchef.com"]
  spec.description   = %q{A tool for building Chef server clusters using LXC containers}
  spec.summary       = spec.description
  spec.licenses	     = "Apache2"
  spec.homepage      = "https://github.com/jeremiahsnapp/dev-lxc"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake", "~> 0"
  spec.add_runtime_dependency "mixlib-install", "~> 0"
  spec.add_runtime_dependency "thor", "~> 0"
  spec.add_runtime_dependency "ruby-lxc", "~> 1.2.0"
end
