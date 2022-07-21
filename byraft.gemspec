Gem::Specification.new do |s|
  s.name        = 'byraft'
  s.version     = '0.1.0'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["taekop"]
  s.email       = ["taekop@naver.com"]
  s.homepage    = 'http://github.com/taekop/byraft'
  s.summary     = "Raft Implemention in Ruby"
  s.description = s.summary
  s.license     = 'MIT'

  s.add_dependency 'grpc', '~> 1'

  s.files       = ["lib/byraft.rb"]
end
