# OKO Dataplane Overlay

Place strategic merge patch files in this directory to customize the
OpenStack dataplane resources rendered by ARD.

When `make deploy` runs with `ard_deployment_dir` set, the deploy_oko role
detects any `.yaml` files here and applies them as a kustomize overlay on
top of the base dataplane kustomization. Individual resources (Secrets,
ConfigMaps, OpenStackDataPlaneServices) from the base are applied first so
ordering is preserved before the overlay patches the NodeSet and Deployment.

## Format

Patch files must be valid Kubernetes strategic merge patches targeting
resources in the `openstack` namespace. Any `.yaml` file in this directory
(other than a generated `kustomization.yaml`) is treated as a patch.

The kustomization overlay is auto-generated on the MicroShift host during
deploy; you do not write a `kustomization.yaml` yourself.

## Example: increase EDPM node resources in the NodeSet

Create a file called `dataplane-patch.yaml`:

```yaml
apiVersion: dataplane.openstack.org/v1beta1
kind: OpenStackDataPlaneNodeSet
metadata:
  name: openstack-edpm
  namespace: openstack
spec:
  nodeTemplate:
    ansible:
      ansibleVars:
        edpm_network_config_template: |
          ---
          network_config:
            - type: linux_bridge
              name: {{ neutron_physical_bridge_name }}
              use_dhcp: false
              addresses:
                - ip_netmask: {{ ctlplane_ip }}/{{ ctlplane_cidr | ipaddr('prefix') }}
```

## Tip

You can validate patch files locally after a local render with:

```bash
kubectl kustomize deployments/<name>/rendered/oko/base/dataplane
```
