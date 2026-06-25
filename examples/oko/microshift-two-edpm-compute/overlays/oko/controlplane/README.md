# OKO Control-Plane Overlay

Place strategic merge patch files in this directory to customize the
OpenStack control-plane resources rendered by ARD.

When `make deploy` runs with `ard_deployment_dir` set (the default for all
`make`-driven workflows), the deploy_oko role detects any `.yaml` files here
and applies them as a kustomize overlay on top of the base control-plane
kustomization.

## Format

Patch files must be valid Kubernetes strategic merge patches targeting
resources in the `openstack` namespace. Any `.yaml` file in this directory
(other than a generated `kustomization.yaml`) is treated as a patch.

The kustomization overlay is auto-generated on the MicroShift host during
deploy; you do not write a `kustomization.yaml` yourself.

## Example: add a custom Keystone domain

Create a file called `controlplane-patch.yaml`:

```yaml
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack
  namespace: openstack
spec:
  keystone:
    template:
      override:
        service:
          metadata:
            annotations:
              my-org/custom: "true"
```

## Tip

You can validate patch files locally with:

```bash
kubectl kustomize deployments/<name>/rendered/oko/base/controlplane
```

after a local render (`make render`) has populated the base directory.
