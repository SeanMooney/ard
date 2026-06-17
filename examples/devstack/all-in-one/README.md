# DevStack all-in-one

Renders a single-node DevStack deployment.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_topology: all-in-one
ard_service_profiles:
  - devstack
  - ovn
  - tempest
```

## Topology

```text
+------------+
| controller |
|            |
| DevStack   |
| compute    |
| OVN        |
| Tempest    |
+------------+
```

Use this when you need the smallest DevStack environment for provider/render
validation or quick workload checks.
