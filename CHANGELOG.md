# dev-lxc Change Log

## 1.7.0 (2016-05-04)

* Replace p-ubuntu-1504 with p-ubuntu-1604

## 1.6.3 (2016-05-04)

* Put adhoc servers at the end of the servers list

* Only destroy a shared image if it has a name

* Auto accept license agreements

* Define default package names more cleanly

* Minor update to README.md

## 1.6.2 (2016-04-21)

* Sync SSH public keys to /home/dev-lxc/.ssh/authorized_keys

* Improve 'dev-lxc init' header

* Validate dev-lxc.yml hostnames, mounts, packages and ssh-keys

* Consolidate package paths for simpler updating

## 1.6.1 (2016-04-20)

* Fix for open-source in "dev-lxc init"

## 1.6.0 (2016-04-20)

* Rewrite "dev-lxc init" so its options determine what config gets generated

* Allow mounts, platform_image and platform_image_options to be set globally

* Create demo org and mary-admin and joe-user users

* Add Supermarket server build capability

* Add Compliance server build capability

* Improve "dev-lxc status" output

* Generate Chef Server config in one shot

* Make standalone topology the default for Analytics

* Make standalone topology the default for Chef Server

## 1.5.1 (2016-04-15)

* Add ability to pass options to LXC create calls  
  For example, this lets users pass the following options for more control over the creation process.  
  https://github.com/lxc/lxc/blob/lxc-2.0.0/templates/lxc-download.in#L200-L207

## 1.5.0 (2016-04-14)

* Set lxc.network.hwaddr, if one doesn’t exist, instead of lxc.network.0.hwaddr  
  Fixes a bug that caused containers to get identical hwaddrs and IPs

* Remove chef-sync since it is EOL

* Refactor removal of container config's mount entries  
  Make sure you are using LXC 2.0 which includes a fix that allows the refactor to work

* Make mount section in dev-lxc.yml optional

## 1.4.0 (2015-12-08)

* Add ability to build and use Ubuntu 15.04 and Centos 7 platform containers

* Update versions of Chef packages

* Refactor removal of container config's mount entries

## 1.3.1 (2015-05-21)

* Allow adhoc servers time to generate SSH Server Host Keys

## 1.3.0 (2015-05-21)

* New "adhoc" cluster functionality
* Platform images have openssh-server installed
* Platform images have "dev-lxc" user with "dev-lxc" password and passwordless sudo
* Update Analytics package in templates

## 1.2.2 (2015-05-14)

* Update version of Chef Manage in templates

## 1.2.1 (2015-05-05)

* Fix output spacing in list-images

## 1.2.0 (2015-05-01)

* Change the chef-packages mount point

## 1.1.3 (2015-04-30)

* Fix chef-repo command's description
* Update package versions in config templates

## 1.1.2 (2015-04-22)

* Set `ssl_verify_mode :verify_none` in knife.rb and pivotal.rb

## 1.1.1 (2015-04-22)

* Fix chef_server_url in pivotal.rb

## 1.1.0 (2015-04-21)

* Change "abspath" command name to "realpath"

## 1.0.1 (2015-04-18)

* Fix "abspath" output

## 1.0.0 (2015-04-09)
