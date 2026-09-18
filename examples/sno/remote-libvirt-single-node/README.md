# Remote-libvirt standalone SNO

This example creates an 8-vCPU, 16-GiB, 120-GB standalone OpenShift SNO VM on a
remote libvirt execution host. Libvirt and OpenShift client operations use
host-local `qemu:///system` through native Ansible SSH delegation.

Render a deployment workspace:

```shell
make render \
  ARD_DEPLOYMENT=remote-libvirt-sno \
  ARD_WORKLOAD=sno \
  ARD_RENDER_FILE=examples/sno/remote-libvirt-single-node/render.yaml
```

Edit `deployments/remote-libvirt-sno/local-vars.yaml` for the execution host.
Put the OpenShift pull secret in
`deployments/remote-libvirt-sno/pull-secret`; apply restricts it to mode `0600`.
All ARD-owned remote files default to `~/ard/<deployment-name>/` on the
execution host, including images, rendered XML, downloads, unpacked clients,
helpers, command caches and temporary files, installer state, and kubeconfig.
Commands run as the Ansible user; only resolver or SELinux operations that
require host privileges elevate.

Libvirt and systemd-resolved retain their own daemon-managed definitions and
runtime state outside this directory. Use the supported destroy command to
undefine those recorded resources before deleting the deployment directory;
deleting the directory alone is not a replacement for provider cleanup.

Bootstrap the execution host once when SNO tools and scoped DNS are not already
configured:

```shell
uv run ansible-playbook -i dev-host, \
  ansible/playbooks/provider/bootstrap-libvirt-host.yaml \
  -e ansible_user=stack \
  -e ard_libvirt_bootstrap_user=stack \
  -e ard_libvirt_bootstrap_sno=true \
  -e ard_libvirt_bootstrap_scoped_dns=true
```

Lifecycle:

```shell
make apply ARD_DEPLOYMENT=remote-libvirt-sno
make deploy ARD_DEPLOYMENT=remote-libvirt-sno
make verify ARD_DEPLOYMENT=remote-libvirt-sno
make destroy ARD_DEPLOYMENT=remote-libvirt-sno
```

Apply prepares Agent media and defines a powered-off VM. Deploy starts the VM,
waits for installation, verifies the cluster from the execution host, installs
`local-path` as the default StorageClass, tests a PVC write, detaches the ISO,
and validates a disk-only reboot. Local Path Provisioner stores volumes beneath
`/var/opt/local-path-provisioner`; deploy creates the directory and persistently
labels it `container_file_t`. On systems where `/opt` resolves to `/var/opt`, the
underlying filesystem was already writable—the explicit `/var/opt` default and
SELinux label avoid relying on that host-specific alias and label inheritance.
Changing this default configures future volumes; it does not migrate existing
Local Path Provisioner volumes.

Normal destroy preserves protected installer state. Use the explicit clean form
before recreating the same deployment:

```shell
make destroy-clean-generated ARD_DEPLOYMENT=remote-libvirt-sno
```
