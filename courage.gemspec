# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'courage/version'

Gem::Specification.new do |spec|
  spec.name          = 'courage'
  spec.version       = Courage::VERSION
  spec.authors       = ['Bartosz Polaczyk']
  spec.email         = ['polac24@polaczyk.com']
  spec.summary       = %q{Mutation test reports for iOS Swift projects}
  spec.homepage      = 'https://github.com/polac24/courage'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']


  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake", "~> 0"
  spec.add_development_dependency "rspec", "~> 0"
end
