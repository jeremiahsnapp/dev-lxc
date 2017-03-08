The files in this directory are working examples of cluster dev-lxc.yml files. You can upload them to separate directories in your dev-lxc-platform instance, rename each file to `dev-lxc.yml` and run `dl up` to build each cluster.

### automate

The [automate_dev-lxc.yml](example-clusters/automate_dev-lxc.yml) file was created using the following command.

```
dl init --chef --compliance --supermarket --automate --runners --nodes
```

Cluster build time: 19 minutes

### chef-backend

The [chef-backend_dev-lxc.yml](example-clusters/chef-backend_dev-lxc.yml) file was created using the following command.

The nodes' `chef_server_url` hostname was changed to `chef-ha.lxc` and the node's hostname was changed to `node-1-ha.lxc`.

```
dl init --chef-backend --nodes
```

Cluster build time: 12 minutes

### tier

The [tier_dev-lxc.yml](example-clusters/tier_dev-lxc.yml) file was created using the following command.

The `reporting` product was uncommented for `chef-be.lxc` and `chef-fe1.lxc`.

The nodes' `chef_server_url` hostname was changed to `chef-tier.lxc` and the node's hostname was changed to `node-1-tier.lxc`.

```
dl init --chef-tier --analytics --nodes
```

Cluster build time: 14 minutes
