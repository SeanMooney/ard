************************************
ARD libvirt scenario requirements
************************************

This scenario uses Molecule's default/delegated driver to call the ARD
libvirt provider playbooks. It creates one controller and two compute nodes.
It does not require Vagrant.

Run
===

.. code-block:: bash

    uv run molecule create -s centos-10-one-controller-two-compute
    uv run molecule converge -s centos-10-one-controller-two-compute
    uv run molecule verify -s centos-10-one-controller-two-compute
    uv run molecule destroy -s centos-10-one-controller-two-compute
