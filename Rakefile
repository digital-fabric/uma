# frozen_string_literal: true

require 'rake/clean'

task :default => :test
task :test do
  exec 'ruby test/run.rb'
end

task :release do
  require_relative './lib/uma/version'
  version = Uma::VERSION

  puts 'Building uma...'
  `gem build uma.gemspec`

  puts "Pushing uma #{version}..."
  `gem push uma-#{version}.gem`

  puts "Cleaning up..."
  `rm *.gem`
end
