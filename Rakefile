require 'rubocop/rake_task'

namespace :inspec do
  desc 'Validate the InSpec resource pack'
  task :check do
    sh 'bundle exec cinc-auditor check .'
  end
end

RuboCop::RakeTask.new(:lint) do |task|
  task.options += %w[--display-cop-names --no-color --parallel]
end

desc 'Run profile validation and lint'
task pre_commit_checks: ['inspec:check', :lint]
