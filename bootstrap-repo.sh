#!/bin/bash
[[ -e ".venv" ]] || python3 -m venv .venv
. .venv/bin/activate
pip install bindep
set -x
which dpkg && bindep -b | xargs sudo apt install
which rpm && bindep -b | xargs dnf apt install
#pip install ansible=2.9
pip install ansible\<5 ansible-core\<2.12.0 \
libvirt-python molecule molecule-vagrant python-vagrant netaddr
vagrant plugin install vagrant-libvirt
set +x
