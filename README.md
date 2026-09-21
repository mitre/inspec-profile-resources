# InSpec Profile Development Resources

Shared resources and libraries for MITRE InSpec and CINC Auditor profiles.
This repository follows the resource-pack layout of
[inspec-k8s-node](https://github.com/mitre/inspec-k8s-node): metadata in
`inspec.yml`, reusable resources in `libraries/`, and no compliance controls.

The repository is named `inspec-profile-resources` so it can grow beyond the
current virtualization resource without tying the package to one technology.

The library provides the `container_system?` predicate and Kubernetes
detection helpers. It preserves the existing
`system`, `role`, `virtual_system?`, and `physical_system?` interfaces. This
pack currently declares Linux support; the inherited Windows implementation
has not been validated for this pack.

## Use from another profile

Add this dependency to the consuming profile's `inspec.yml`:

```yaml
depends:
  - name: inspec-profile-resources
    git: https://github.com/mitre/inspec-profile-resources.git
    branch: main
```

Remove the consuming profile's local `libraries/virtualization.rb` after
adding the dependency so it does not shadow the shared resource. Existing
container applicability checks can then use:

```ruby
only_if('This control is Not Applicable to containers', impact: 0.0) do
  !virtualization.container_system?
end
```

Retain any existing SSH, sudo, or waiver conditions when replacing a container
predicate. For example:

```ruby
only_if('Not applicable to containers without sudo', impact: 0.0) do
  !virtualization.container_system? || command('sudo').exist?
end
```

Resources are loaded through the dependency; `include_controls` is unnecessary
because this pack has no controls. Once published, install dependencies with
`inspec vendor` (or `cinc-auditor vendor`). Pin a reviewed commit or release tag
instead of `main` when reproducible dependency versions are required.

For local development, replace the Git dependency with:

```yaml
depends:
  - name: inspec-profile-resources
    path: ../inspec-profile-resources
```

## Container detection

`container_system?` requires both a recognized container system and the `guest`
role. A host running container software is not itself treated as a container.
The recognized systems match the RHEL 9 implementation:

```text
container-other docker kubepods linux-vserver lxc lxc-libvirt openvz
podman pouch proot rkt systemd-nspawn wsl
```

Kubernetes detection checks service-account mount paths,
Kubernetes markers in `/proc/self/mountinfo`, and `KUBERNETES_SERVICE_HOST` in
`/proc/1/environ`. It runs before the Docker marker check, allowing a Kubernetes
container to be reported as `kubepods` even when `/.dockerenv` exists. These are
environment heuristics, not Kubernetes API queries.

## Development

Use Ruby 3.1 or later for the pinned InSpec 5 development runtime.

```sh
bundle install
bundle exec ruby test/virtualization_test.rb
bundle exec ruby test/dependency_test.rb
```

The first test exercises container classification and detection with target
fixtures. The second loads a temporary consuming profile through an actual
InSpec dependency and verifies that the shared resource overrides the built-in
resource. Neither test requires Docker or a running Kubernetes cluster.

## License

Licensed under Apache-2.0. See [LICENSE.md](LICENSE.md) and [NOTICE.md](NOTICE.md).
