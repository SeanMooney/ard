#!/bin/bash
[[ -e ".venv" ]] || python3 -m venv .venv
. .venv/bin/activate
pip install bindep wheel
set -x
which dpkg && bindep -b | xargs sudo apt install
# Don't install weak deps, as that will pull in vagrant-libvirt, which we want
# to install manually later on.
which rpm && bindep -b | xargs sudo dnf -y --setopt=install_weak_deps=False install
#pip install ansible=2.9
pip install ansible\<5 ansible-core\<2.12.0 \
    molecule molecule-vagrant python-vagrant netaddr molecule-openstack openstacksdk
# this fails on nixos so install it seperatly until i figure out why.
pip install libvirt-python
which vagrant && vagrant plugin install vagrant-libvirt
git submodule update --init --recursive
# At least on Fedora, the user running this needs to be in the libvirt group to
# avoid authentication errors when running `molecule create`
if [[ `cat /etc/redhat-release 2> /dev/null` =~ 'Fedora' ]]
then
    if [[ `groups` =~ 'libvirt' ]]
    then
        true
    else
        echo 'You need to be part of the libvirt group for this to work.'
        exit
    fi
fi
set +x
