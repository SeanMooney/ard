************************************
ARD libvirt scenario requirements
************************************

This scenario uses Molecule's default/delegated driver to call the ARD
libvirt provider playbooks. It creates one controller and two compute nodes.
It does not require Vagrant.

Run
===

.. code-block:: bash

    uv run molecule create -s one-controller-two-compute
    uv run molecule converge -s one-controller-two-compute
    uv run molecule verify -s one-controller-two-compute
    uv run molecule destroy -s one-controller-two-compute
