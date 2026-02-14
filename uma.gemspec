require_relative './lib/uma/version'

Gem::Specification.new do |s|
  s.name        = 'Uma'
  s.summary     = 'Uma is a Ruby app server'
  s.version       = Uma::VERSION
  s.licenses      = ['MIT']
  s.author        = 'Sharon Rosner'
  s.email         = 'sharon@noteflakes.com'
  s.files         = `git ls-files`.split

  s.homepage      = 'https://github.com/digital-fabric/uma'
  s.metadata      = {
    'homepage_uri' => 'https://github.com/digital-fabric/uma',
    'documentation_uri' => 'https://www.rubydoc.info/gems/uma',
    'changelog_uri' => 'https://github.com/digital-fabric/uma/blob/main/CHANGELOG.md'
  }
  s.rdoc_options  = ['--title', 'Extralite', '--main', 'README.md']
  s.extra_rdoc_files = ['README.md']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.4'
  s.executables = ['syntropy']

  s.add_dependency 'uringmachine',  '>=0.26.0'

  s.add_dependency 'logger'

  s.add_development_dependency 'minitest',  '~>6.0.1'
  s.add_development_dependency 'rake',      '~>13.3.1'
end
