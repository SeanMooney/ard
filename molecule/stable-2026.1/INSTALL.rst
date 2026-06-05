************************************
ARD libvirt scenario requirements
************************************

This scenario uses Molecule's default/delegated driver to call the ARD
libvirt provider playbooks. It deploys DevStack ``stable/2026.1`` on Ubuntu
24.04 cloud images. It does not require Vagrant.

Run
===

.. code-block:: bash

    uv run molecule create -s stable-2026.1
    uv run molecule converge -s stable-2026.1
    uv run molecule verify -s stable-2026.1
    uv run molecule destroy -s stable-2026.1
