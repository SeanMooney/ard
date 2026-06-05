Role Name
=========

A brief description of the role goes here.

Requirements
------------

Any pre-requisites that may not be covered by Ansible itself or the role should be mentioned here. For instance, if the role uses the EC2 module, it may be a good idea to mention in this section that the boto package is required.

Role Variables
--------------

A description of the settable variables for this role should go here, including any variables that are in defaults/main.yml, vars/main.yml, and any variables that can/should be set via parameters to the role. Any variables that are read from other roles and/or the global scope (ie. hostvars, group vars, etc.) should be mentioned here as well.

Dependencies
------------

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: username.rolename, x: 42 }

Top-level Molecule DevStack scenarios
-------------------------------------

Top-level ``molecule/`` scenarios are full ARD/libvirt-backed DevStack
deployments. They use Molecule's default/delegated driver to call the ARD
provider playbooks directly; they do not use Vagrant.

Available scenarios:

* ``default``: two-node DevStack master on Debian 13 genericcloud
  (``controller`` + ``compute1``).
* ``one-controller-two-compute``: same as ``default`` plus ``compute2``;
  ``nova-compute`` is disabled on the controller.
* ``stable-2026.1``: two-node DevStack ``stable/2026.1`` on Ubuntu 24.04 cloud
  images.

Run a full scenario test from the repository root:

```
uv run molecule test -s default
uv run molecule test -s one-controller-two-compute
uv run molecule test -s stable-2026.1
```

For an incremental and cheaper validation loop, create the VMs first and verify
SSH before converging DevStack:

```
uv run molecule create -s default
uv run ansible -i molecule/default/deployment/inventory.yaml all -m ping
uv run molecule converge -s default
uv run molecule verify -s default
uv run molecule destroy -s default
```

Scenario deployment workspaces live under ``molecule/<scenario>/deployment``.
Generated files such as ``inventory.yaml``, ``provider-state.yaml``, and
``rendered/`` are runtime artifacts and should not be committed.

Role molecule tests
-------------------

The uv-managed development environment includes Molecule and the Podman
Molecule plugin. Role-level Molecule scenarios live under
``ansible/roles/*/molecule`` and are intended to avoid Vagrant for role unit
coverage. Use containers for roles that do not need full VM semantics; reserve
ARD libvirt-backed scenarios for roles that need a real VM, systemd, cloud-init,
libvirt, or DevStack node behavior.

Run all role-level Molecule scenarios from the repository root:

```
make molecule-test
```

Run one role-level scenario from the repository root:

```
make molecule-role-ensure_kustomize
```

You can also run a role scenario from the role directory. Activate the uv venv
first, then run Molecule directly or via the role-local make target:

```
source ../../../.venv/bin/activate
cd ansible/roles/ensure_kustomize
molecule test
# or
make molecule-test
```

Top-level ``molecule/`` scenarios are larger deployment scenarios and are not
part of this role-level test workflow.

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
