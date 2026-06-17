# MicroShift single-node

Renders one MicroShift VM.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_topology: microshift-single-node
ard_service_profiles: []
```

## Topology

```text
+------------+
| microshift |
|            |
| MicroShift |
+------------+
```

Use this to validate the MicroShift workload independently from OKO.
