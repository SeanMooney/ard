#!/bin/bash
[[ -e ".venv" ]] || python3 -m venv .venv
. .venv/bin/activate
pip install bindep
set -x
which dpkg && bindep -b | xargs sudo apt install
which rpm && bindep -b | xargs dnf apt install
pip install ansible libvirt-python molecule molecule-vagrant python-vagrant
vagrant plugin install vagrant-libvirt
set +x
