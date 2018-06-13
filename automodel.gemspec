
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "automodel/version"

Gem::Specification.new do |spec|
  spec.name          = "automodel"
  spec.version       = Automodel::VERSION
  spec.authors       = ["Nestor Custodio"]
  spec.email         = ["sakimorix@gmail.com"]

  spec.summary       = %q{Expose all tables and relations in a database as AR models ready for use.}
  spec.homepage      = "https://www.github.com/nestor-custodio/automodel"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
