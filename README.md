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

Playbook to test Microshift deployment on Fedora CoreOS
-------------------------------------------------------

```
- hosts: microshift
  gather_facts: true
  vars:
    user_name: microshift
    install_olm: false
    manage_firewall: false
    microshift_install_type: ostree
    crio_install_type: ostree
    crio_log_level: debug
  roles:
    - ensure_microshift
```

Bootstrap OpenShift crc in a vm
-------------------------------

This should create ``~/.ssh/id_ed25519_stack`` SSH key to login to VM as a stack user:
```
molecule destroy -s shift-stack
molecule create -s shift-stack
molecule converge -s shift-stack
```
Verify login to CRC VM and RHCOS k8s worker node.
```
cd ~/.cache/molecule/ansible_role_devstack/shift-stack
vagrant ssh crc

[stack@crc ~]$ ssh -i ~/.crc/machines/crc/id_ecdsa core@`crc ip`
```

Configure localhost to access deployed OpenShift crc
----------------------------------------------------
> **NOTE**: This overwrites ``~/.kube/config`` !

Install shuttle first.

```
inv=~/.cache/molecule/ansible_role_devstack/shift-stack/inventory/ansible_inventory.yml
IP=$(ansible -i $inv -m debug -a 'var=hostvars["crc"].ansible_host' crc | sed -rn 's/.*ansible_host": "(.*)"/\1/p')
echo `ssh -i ~/.ssh/id_ed25519_stack stack@$IP tail -1 /etc/hosts | tail -1` | sudo tee -a /etc/host
ansible -b -i $inv  -m slurp -a "src=/home/stack/.kube/config" crc | sed -r 's/crc \| SUCCESS => //' | jq -r '.content' | base64 -d > ~/.kube/config
ansible -b -i $inv  -m shell -a "cd /home/stack/.crc/bin/oc; tar hcvf - oc | gzip -v4 > oc.tar.gz" crc
ansible -b -i $inv  -m slurp -a "src=/home/stack/.crc/bin/oc/oc.tar.gz" crc | sed -r 's/crc \| SUCCESS => //' | jq -r '.content' | base64 -d > oc.tar.gz
tar xzf oc.tar.gz
sudo install -o root -g root -m 0755 oc /usr/local/bin/oc
sudo -E sshuttle -r stack@$IP -x $IP 0.0.0.0/0 -vv --ssh-cmd 'ssh -i $HOME/.ssh/id_ed25519_stack'
oc login -u kubeadmin -p  `ssh -i ~/.ssh/id_ed25519_stack stack@$IP crc console --credentials | awk '/oc login -u kubeadmin/ {if ($0) print $12}'` https://api.crc.testing:6443
```

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
