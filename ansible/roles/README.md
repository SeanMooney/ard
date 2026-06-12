# ARD Role Index

Roles are intentionally kept in-place in this phase. This index is for navigation.

## Provider dispatch

- `ard_provider_common`
- `ard_provider_preflight`
- `ard_provider_image`
- `ard_provider_network`
- `ard_provider_node`
- `ard_provider_inventory`
- `ard_provider_destroy`
- `ard_provider_cleanup`

## Provider implementations

- `ard_libvirt_preflight`
- `ard_libvirt_image`
- `ard_libvirt_network`
- `ard_libvirt_node`
- `ard_libvirt_inventory`
- `ard_libvirt_destroy`
- `ard_static_preflight`
- `ard_static_image`
- `ard_static_network`
- `ard_static_node`
- `ard_static_inventory`
- `ard_static_destroy`

- `ard_kubevirt_*` roles remain future work in this phase.

## Deployment and workload integration

- `ard_devstack_config`
- `devstack_config`
- `devstack_common`
- `devstack_controller`
- `devstack_compute`
- `configure_vdpa`

## Utility / helper roles

- `ensure_stack_user`
- `prepare_dev_tools`
- `ensure_kustomize`
- `ensure_crc`
- `ensure_microshift`
- `deploy_install_yamls`
- `print_debug_ip`
