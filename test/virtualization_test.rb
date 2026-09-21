require 'minitest/autorun'
require 'ostruct'
require 'inspec'
require_relative '../libraries/virtualization'

class VirtualizationTest < Minitest::Test
  class Target
    def initialize(files: {}, commands: {})
      @files = files
      @commands = commands
    end

    def os
      OpenStruct.new(linux?: true, windows?: false)
    end

    def file(path)
      OpenStruct.new(exist?: @files.key?(path), content: @files.fetch(path, ''))
    end

    def command(cmd)
      result = @commands.fetch(cmd, { exit_status: 1, stdout: '' })
      OpenStruct.new(result.merge(exist?: @commands.key?(cmd)))
    end
  end

  def resource(files: {}, commands: {})
    target = Target.new(files: files, commands: commands)
    instance = Inspec::Resources::Virtualization.allocate
    instance.define_singleton_method(:inspec) { target }
    instance.send(:initialize)
    instance
  end

  def assert_container(instance, system)
    assert_equal system, instance.system
    assert_equal 'guest', instance.role
    assert instance.container_system?
    assert instance.virtual_system?
    refute instance.physical_system?
  end

  def test_bare_metal
    instance = resource
    assert_nil instance.system
    assert_nil instance.role
    assert instance.physical_system?
    refute instance.virtual_system?
    refute instance.container_system?
  end

  def test_docker
    assert_container resource(files: { '/.dockerenv' => '' }), 'docker'
  end

  def test_podman_with_cgroup_v2
    assert_container resource(files: {
                                '/proc/self/cgroup' => '0::/', '/proc/1/environ' => "container=podman\0"
                              }), 'podman'
  end

  def test_kubernetes_cgroup
    assert_container resource(files: { '/proc/self/cgroup' => '1:cpu:/kubepods/pod123' }), 'kubepods'
  end

  %w[/var/run/secrets/kubernetes.io/serviceaccount /run/secrets/kubernetes.io/serviceaccount].each_with_index do |path, index|
    define_method("test_kubernetes_service_account_path_#{index}") do
      assert_container resource(files: { path => '' }), 'kubepods'
    end
  end

  %w[kubepods /var/lib/kubelet/pods/ kubernetes.io~ /var/run/secrets/kubernetes.io/serviceaccount].each_with_index do |marker, index|
    define_method("test_kubernetes_mountinfo_marker_#{index}") do
      assert_container resource(files: { '/proc/self/mountinfo' => "42 21 0:17 / #{marker} rw" }), 'kubepods'
    end
  end

  def test_kubernetes_environment
    assert_container resource(files: { '/proc/1/environ' => "PATH=/bin\0KUBERNETES_SERVICE_HOST=10.0.0.1\0" }), 'kubepods'
  end

  def test_kubernetes_takes_precedence_over_docker_marker
    assert_container resource(files: {
                                '/.dockerenv' => '', '/var/run/secrets/kubernetes.io/serviceaccount' => ''
                              }), 'kubepods'
  end

  def test_unrelated_mountinfo_and_environment_are_not_kubernetes
    instance = resource(files: {
                          '/proc/self/mountinfo' => '42 21 0:17 / /proc rw',
                          '/proc/1/environ' => "PATH=/bin\0HOME=/root\0"
                        })
    refute instance.container_system?
    assert instance.physical_system?
  end

  def test_vmware_guest_is_not_a_container
    instance = resource(files: { '/sys/devices/virtual/dmi/id/product_name' => 'VMware Virtual Platform' })
    assert_equal 'vmware', instance.system
    assert instance.virtual_system?
    refute instance.container_system?
  end

  def test_openvz_host_is_not_a_container
    instance = resource(files: { '/proc/bc/0' => '' })
    assert_equal 'host', instance.role
    refute instance.container_system?
  end

  def test_openvz_guest_is_a_container
    assert_container resource(files: { '/proc/vz' => '' }), 'openvz'
  end

  def test_systemd_failure_is_not_a_container
    refute resource(commands: {
                      'systemd-detect-virt' => { exit_status: 1, stdout: "docker\n" }
                    }).container_system?
  end

  def test_empty_systemd_output_is_not_a_container
    refute resource(commands: {
                      'systemd-detect-virt' => { exit_status: 0, stdout: "\n" }
                    }).container_system?
  end

  Inspec::Resources::Virtualization::CONTAINER_SYSTEMS.each do |system|
    define_method("test_systemd_container_#{system.tr('-', '_')}") do
      assert_container resource(commands: {
                                  'systemd-detect-virt' => { exit_status: 0, stdout: "#{system}\n" }
                                }), system
    end

    define_method("test_container_host_#{system.tr('-', '_')}") do
      instance = resource
      instance.instance_variable_set(:@virtualization_data, { system: system, role: 'host' })
      refute instance.container_system?
    end
  end

  %w[kvm vmware xen hyper-v vbox unknown].each do |system|
    define_method("test_systemd_non_container_#{system.tr('-', '_')}") do
      refute resource(commands: {
                        'systemd-detect-virt' => { exit_status: 0, stdout: "#{system}\n" }
                      }).container_system?
    end
  end
end
