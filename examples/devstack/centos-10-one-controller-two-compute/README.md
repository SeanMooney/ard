# DevStack CentOS Stream 10 one controller, two computes

Renders the same logical topology as
[../one-controller-two-compute/](../one-controller-two-compute/) but selects the
CentOS Stream 10 image for DevStack nodes.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_devstack_branch: master
ard_devstack_image: centos-stream-10
ard_topology: one-controller-two-compute
ard_service_profiles:
  - devstack
  - ovn
  - tempest
```

## Topology

```text
+------------+        +-----------+        +-----------+
| controller |        | compute-1 |        | compute-2 |
| CS10 image |        | CS10 image|        | CS10 image|
+------------+        +-----------+        +-----------+
```

Use this when validating image-specific behavior on CentOS Stream 10.
