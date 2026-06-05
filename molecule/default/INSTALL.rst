************************************
ARD libvirt scenario requirements
************************************

This scenario uses Molecule's default/delegated driver to call the ARD
libvirt provider playbooks. It does not require Vagrant.

Requirements
============

* the uv-managed project environment
* Molecule
* Ansible
* libvirt/qemu access to ``qemu:///system``

Run
===

.. code-block:: bash

    uv run molecule create -s default
    uv run molecule converge -s default
    uv run molecule verify -s default
    uv run molecule destroy -s default
