The files in this directory are working examples of cluster dev-lxc.yml files. You can upload them to separate directories in your dev-lxc-platform instance, rename each file to `dev-lxc.yml` and run `dl up` to build each cluster.

### automate

Cluster build time: 19 minutes

The [automate_dev-lxc.yml](automate_dev-lxc.yml) file was created using the following command.

```
dl init --chef --compliance --supermarket --automate --runners --nodes --product-versions reporting:none
```

### chef-backend

Cluster build time: 12 minutes

The [chef-backend_dev-lxc.yml](chef-backend_dev-lxc.yml) file was created using the following command.

The nodes' `chef_server_url` hostname was changed to `chef-ha.lxc` and the node's hostname was changed to `node-1-ha.lxc`.

```
dl init --chef-backend --nodes
```

### tier

Cluster build time: 14 minutes

The [tier_dev-lxc.yml](tier_dev-lxc.yml) file was created using the following command.

The nodes' `chef_server_url` hostname was changed to `chef-tier.lxc` and the node's hostname was changed to `node-1-tier.lxc`.

```
dl init --chef-tier --analytics --nodes
```
