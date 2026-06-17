# Provider test single-node

Renders a minimal single-node provider deployment without workload service
profiles.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_topology: all-in-one
ard_service_profiles: []
```

## Topology

```text
+------------+
| controller |
| provider   |
| smoke node |
+------------+
```

Use this for quick provider lifecycle validation before layering on a workload.
