#!/bin/bash
[[ -e ".venv" ]] || python3 -m venv .venv
. .venv/bin/activate
pip install bindep wheel
set -x
which dpkg && bindep -b | xargs sudo apt install
which rpm && bindep -b | xargs dnf apt install
#pip install ansible=2.9
pip install ansible\<5 ansible-core\<2.12.0 \
    molecule molecule-vagrant python-vagrant netaddr molecule-openstack openstacksdk
# this fails on nixos so install it seperatly until i figure out why.
pip install libvirt-python
which vagrant && vagrant plugin install vagrant-libvirt
git submodule update --init --recursive
set +x
