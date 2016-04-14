# dev-lxc Change Log

## 1.5.0 (2015-04-14)

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
