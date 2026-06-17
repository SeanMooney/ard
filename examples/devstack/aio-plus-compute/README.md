# DevStack all-in-one plus compute

Renders a DevStack controller that also runs compute, plus one additional
compute VM.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_topology: one-controller-one-compute
ard_service_profiles:
  - devstack
  - ovn
  - tempest
```

`one-controller-one-compute` is a compatibility alias for the workload topology
that renders an all-in-one controller and one extra compute.

## Topology

```text
+------------+        +-----------+
| controller |        | compute-1 |
|            |        |           |
| DevStack   |        | DevStack  |
| compute    |        | compute   |
| OVN        |        | OVN       |
| Tempest    |        |           |
+------------+        +-----------+
```
