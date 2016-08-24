# dev-lxc Change Log

## 2.2.5 (2016-08-24)

* Print full product cache path in SHA256 error message

## 2.2.4 (2016-08-24)

* Add sha256 check for downloaded packages

## 2.2.3 (2016-07-27)

* Copy validation key when validation_key is set

## 2.2.2 (2016-07-20)

* Don't calculate/install required products if "build: completed" snapshot exists
* Be more explicit about skipping install of chefdk on build nodes

## 2.2.1 (2016-07-20)

* Add --include-products option to show-config command

## 2.2.0 (2016-07-20)

* Make build nodes reregister to Chef Server
* Make build nodes sleep 5s for DNS resolution availability
* Allow build-nodes to use different base_containers than Chef Automate's
* Change default mount point from dev to work

## 2.1.0 (2016-07-19)

* Provide ability to define Chef org for node's chef-client config
* Enable node chef-client configuration at server_type level
* Add show-config subcommand
* Enable setting mounts, ssh_keys and base_container for each server
* Add print-automate-credentials subcommand
* Add prepare-product-cache subcommand
* Add build-nodes
* Add Automate server
* Define Chef Server orgs and users to be created

## 2.0.3 (2016-06-27)

* Use "stable" package channel for chef-backend since Chef HA 2.0 has been GA released

## 2.0.2 (2016-06-24)

* Change secrets.json to chef-backend-secrets.json

## 2.0.1 (2016-06-23)

Remove mixlib-install version constraint

## 2.0.0 (2016-06-23)

* Overhaul README
* Rename tiered-chef to chef-tier
* Change init's chef-backend description
* Remove realpath command
* Remove commands that functionally are replaced by nodes server type
* Add "nodes" server type
* reorder the init config options
* Allow servers to use dynamic IP addresses
* Add --append and --filename to DevLXC::CLI#init
* Rename DevLXC::CLI#create to DevLXC::CLI#create-base-container
* Install knife-opc 0.3.1 in private-chef servers
* Making conditional more readable in DevLXC::CLI#attach
* Add chef-backend build code to DevLXC::Cluster
* Add chef-backend to DevLXC::Cluster#up
* Add chef-backend to DevLXC::Cluster#get_sorted_servers
* Add chef-backend to DevLXC::Cluster#initialize
* Add chef-backend to DevLXC::Cluster#validate_cluster_config
* Add Analytics FQDN to DevLXC::CLI#status
* Add chef-backend option to DevLXC::CLI
* Add --skip-same-version to dpkg install_command
* Add DevLXC::Cluster#up
* Add build related code to DevLXC::Cluster
* Add snapshot list to DevLXC::CLI#status
* Remove unnecessary FQDNs from DevLXC::CLI#status
* Refactor DevLXC::CLI to use new DevLXC::Server capabilities
* Rename non_stopped_servers to running_servers
* Replace DevLXC::Cluster#servers with DevLXC:Cluster#get_sorted_servers
* Refactor DevLXC::Cluster#chef-repo
* Refactor DevLXC::Cluster to use new DevLXC::Cluster.config, DevLXC::Cluster.server_configs and DevLXC::Cluster#get_server
* Add DevLXC::Cluster#get_server method
* Use mixlib-install package management in DevLXC::CLI#init
* Remove packages validation from DevLXC::Cluster#validate_cluster_config
* Add mixlib-install package cache management
* Remove open-source server type
* Completely overhaul DevLXC::Cluster#initialize
* Minor code refactor in #create_dns_record
* Add DevLXC::Server#install_package
* Add DevLXC::Server#status
* Add DevLXC::Server#name
* Rename @server to @container
* Use "running" instead of "not stopped"
* Remove all cluster and build related code from DevLXC::Server
* Overhaul DevLXC::Server#initialize
* Remove usage of #realpath from code
* Minor code reorg in DevLXC::CLI#init
* Move match_server_name_regex functionality into DevLXC::Cluster#servers
* Move validate_cluster_config into DevLXC::Cluster
* Move Centos /etc/hosts fix into base container creation
* Move Centos 7 setpcap related comments
* Add confirmation check to destroy subcommand
* Replace "platform" and "image" terms with "base" and "container"
* Remove init subcommand's unique string option
* Replace some "create" terminology with "build"
* Replace unique images with snapshots
* Replace custom images with genuine snapshot management
* Require that the platform image container must already exist
* Validate dev-lxc.yml platform_image
* Store dev-lxc containers in default LXCPATH /var/lib/lxc
* Remove global-status subcommand
* Remove list-images subcommand
* Remove shared image functionality
* Remove p-ubuntu-1004 platform image
* Preserve permissions and ownership when copying directories to other servers in a cluster
* Update the Reporting package version

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
