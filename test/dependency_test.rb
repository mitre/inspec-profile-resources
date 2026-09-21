require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'inspec'

# Deliberately do not require libraries/virtualization.rb here: this test must
# exercise InSpec's resource-pack dependency loader rather than a direct load.
class DependencyTest < Minitest::Test
  def test_consumer_loads_shared_virtualization_resource
    assert_consumer_loads_shared_resource
  end

  def test_consumer_loads_with_builtin_virtualization_already_loaded
    require 'inspec/resources/virtualization'
    builtin = Inspec::Resources::Virtualization
    parent_class = builtin.superclass

    assert_consumer_loads_shared_resource

    assert_same builtin, Inspec::Resources::Virtualization
    assert_same parent_class, builtin.superclass
  end

  def test_independent_consumers_load_in_the_same_process
    2.times { assert_consumer_loads_shared_resource }
  end

  private

  def assert_consumer_loads_shared_resource
    Dir.mktmpdir('virtualization-consumer-') do |directory|
      pack = File.expand_path('..', __dir__)
      metadata = {
        'name' => 'virtualization-consumer',
        'version' => '0.1.0',
        'depends' => [{ 'name' => 'inspec-profile-resources', 'path' => pack }]
      }
      File.write(File.join(directory, 'inspec.yml'), metadata.to_yaml)
      FileUtils.mkdir_p(File.join(directory, 'controls'))
      File.write(File.join(directory, 'controls', 'shared_resource.rb'), <<~RUBY)
        control 'shared-virtualization' do
          impact 0.5
          describe virtualization do
            it { should respond_to(:container_system?) }
            it { should_not be_container_system }
          end
          describe virtualization.method(:container_system?).source_location.first do
            it { should eq 'libraries/virtualization.rb' }
          end
          describe virtualization.respond_to?(:detect_kubernetes_container, true) do
            it { should eq true }
          end
        end
      RUBY

      config = Inspec::Config.mock(
        reporter: ['json'], report: true, vendor_cache: File.join(directory, 'vendor'),
        create_lockfile: false
      )
      runner = Inspec::Runner.new(config)
      runner.backend.backend.mock_os(name: 'ubuntu', family: 'debian', release: '20.04', arch: 'x86_64')
      runner.backend.backend.platform.instance_variable_set(:@uuid, 'virtualization-test-target')
      runner.add_target(directory)
      assert_equal 0, runner.run, runner.report.inspect
      results = runner.report.fetch(:profiles).flat_map { |profile| profile[:controls] || [] }
                      .select { |control| control[:id] == 'shared-virtualization' }
                      .flat_map { |control| control[:results] }
      assert_equal 4, results.length
      assert results.all? { |result| result[:status] == 'passed' }, results.inspect
    end
  end
end
