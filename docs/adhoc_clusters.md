### Adhoc Clusters

dev-lxc can also manage an adhoc cluster of servers.

An adhoc cluster is just a set of managed servers cloned from the specified base
container. The servers have SSH server running, a "dev-lxc" user with "dev-lxc" password and
passwordless sudo access.

This is particularly useful when you want to use something else, such as chef-provisioning,
to configure the servers.

The number of servers, their names and their IP addresses can be changed to fit your
particular requirements.

```
mkdir -p /root/clusters/adhoc
dl init --adhoc > /root/clusters/adhoc/dev-lxc.yml
cluster-view /root/clusters/adhoc
dl up
```
