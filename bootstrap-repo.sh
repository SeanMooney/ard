#!/bin/bash
set -x
which dpkg && sudo apt install -y python3-pip
which rpm && sudo dnf -y --setopt=install_weak_deps=False install python3-pip
[[ -e ".venv" ]] || python3 -m venv .venv
. .venv/bin/activate
# allow for using local dev copy of bindep if needed
which bindep || pip install bindep
pip install wheel
which dpkg && bindep -b | xargs sudo apt -y install
# Don't install weak deps, as that will pull in vagrant-libvirt, which we want
# to install manually later on.
which rpm && bindep -b | xargs sudo dnf -y --setopt=install_weak_deps=False install
#pip install ansible=2.9
pip install ansible\<5 ansible-core\<2.12.0 \
    molecule!=3.6.1,!=3.6.0 molecule-vagrant python-vagrant netaddr molecule-openstack openstacksdk
which vagrant && vagrant plugin install vagrant-libvirt
git submodule update --init --recursive
groups | grep -E "libvirt" > /dev/null || \
echo -e "You need to be part of the libvirt group for this to work.\nsudo usermod -a -G libvirt $USER"

set +x
