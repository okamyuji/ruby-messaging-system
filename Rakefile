# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

Rake::TestTask.new(:test_unit) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/unit/**/*_test.rb"]
  t.warning = false
end

Rake::TestTask.new(:test_integration) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/integration/**/*_test.rb"]
  t.warning = false
end

Rake::TestTask.new(:test_concurrency) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/concurrency/**/*_test.rb"]
  t.warning = false
end

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--display-cop-names"]
end

desc "Run tests with coverage"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task[:test].invoke
end

desc "Generate YARD documentation"
task :doc do
  sh "yard doc lib/**/*.rb --output-dir doc"
end

desc "Run all checks (rubocop + tests)"
task check: [:rubocop, :test]

task default: :test
