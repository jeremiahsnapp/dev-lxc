# dev-lxc 2.0 is Available

Here are some of the new features which provide a significantly simplified and streamlined usage.

* mixlib-install library is used to automatically manage a cache of product packages
* Genuine container snapshot management (make as many snapshots as you want)
* New "nodes" server type which auto configures nodes for a Chef Server in the same cluster
  * Removed all xc-... bash functions because the new "nodes" server type replaces this functionality
* Able to build Chef Server HA 2.0 cluster using chef-backend
* Updated and simplified READMEs
