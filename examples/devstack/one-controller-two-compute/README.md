# DevStack one controller, two computes

Renders a multi-node DevStack deployment with a dedicated controller and two
compute VMs.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_topology: one-controller-two-compute
ard_service_profiles:
  - devstack
  - ovn
  - tempest
```

## Topology

```text
+------------+        +-----------+
| controller |        | compute-1 |
|            |        |           |
| DevStack   |        | DevStack  |
| controller |        | compute   |
| OVN        |        | OVN       |
| Tempest    |        +-----------+
+------------+
      |
      |             +-----------+
      `-------------| compute-2 |
                    | DevStack  |
                    | compute   |
                    | OVN       |
                    +-----------+
```

Use this for DevStack scenarios that need a controller-only node and multiple
compute hosts.
