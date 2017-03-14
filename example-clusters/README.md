The files in this directory are working examples of cluster dev-lxc.yml files. You can upload them to separate directories in your dev-lxc-platform instance, rename each file to `dev-lxc.yml` and run `dl up` to build each cluster.

## automate

Cluster build time: 19 minutes

Download the [automate_dev-lxc.yml](automate_dev-lxc.yml) file to the dev-lxc-platform filesystem.

The `automate` cluster needs the `delivery.license` file copied to an appropriate location on dev-lxc-platform's filesystem.

The following is an example of `dl status` for this cluster.

```
chef.lxc            RUNNING         10.0.3.203
  |_ snap0 2017:03:08 19:32:08 dev-lxc build: products installed
  |_ snap1 2017:03:08 19:50:24 dev-lxc build: completed

compliance.lxc      RUNNING         10.0.3.205
  |_ snap0 2017:03:08 19:32:39 dev-lxc build: products installed
  |_ snap1 2017:03:08 19:50:20 dev-lxc build: completed

supermarket.lxc     RUNNING         10.0.3.206
  |_ snap0 2017:03:08 19:33:15 dev-lxc build: products installed
  |_ snap1 2017:03:08 19:50:18 dev-lxc build: completed

automate.lxc        RUNNING         10.0.3.200
  |_ snap0 2017:03:08 19:33:55 dev-lxc build: products installed
  |_ snap1 2017:03:08 19:50:14 dev-lxc build: completed

runner-1.lxc        RUNNING         10.0.3.87
  |_ snap0 2017:03:08 19:50:02 dev-lxc build: completed

node-1.lxc          RUNNING         10.0.3.90
  |_ snap0 2017:03:08 19:34:16 dev-lxc build: products installed
  |_ snap1 2017:03:08 19:50:01 dev-lxc build: completed
```

The following command was used to create the `automate_dev-lxc.yml` file.

```
dl init --chef --compliance --supermarket --automate --runners --nodes --product-versions reporting:none
```

## chef-backend

Cluster build time: 12 minutes

Download the [chef-backend_dev-lxc.yml](chef-backend_dev-lxc.yml) file to the dev-lxc-platform filesystem.

The following is an example of `dl status` for this cluster.

```
Chef Server FQDN: chef-ha.lxc

chef-backend1.lxc      RUNNING         10.0.3.208
  |_ snap0 2017:03:13 20:19:03 dev-lxc build: products installed
  |_ snap1 2017:03:13 20:27:27 dev-lxc build: backend cluster configured but frontend not bootstrapped
  |_ snap2 2017:03:13 20:33:41 dev-lxc build: completed

chef-backend2.lxc      RUNNING         10.0.3.209
  |_ snap0 2017:03:13 20:19:39 dev-lxc build: products installed
  |_ snap1 2017:03:13 20:27:24 dev-lxc build: backend cluster configured but frontend not bootstrapped
  |_ snap2 2017:03:13 20:33:30 dev-lxc build: completed

chef-backend3.lxc      RUNNING         10.0.3.210
  |_ snap0 2017:03:13 20:20:16 dev-lxc build: products installed
  |_ snap1 2017:03:13 20:27:22 dev-lxc build: backend cluster configured but frontend not bootstrapped
  |_ snap2 2017:03:13 20:33:26 dev-lxc build: completed

chef-frontend1.lxc     RUNNING         10.0.3.211
  |_ snap0 2017:03:13 20:21:32 dev-lxc build: products installed
  |_ snap1 2017:03:13 20:33:23 dev-lxc build: completed

node-1-ha.lxc          RUNNING         10.0.3.87
  |_ snap0 2017:03:13 20:22:52 dev-lxc build: products installed
  |_ snap1 2017:03:13 20:33:16 dev-lxc build: completed
```

The following command and described modifications were used to create the `chef-backend_dev-lxc.yml` file.

```
dl init --chef-backend --nodes
```

The nodes' `chef_server_url` hostname was changed to `chef-ha.lxc` and the node's hostname was changed to `node-1-ha.lxc`.

## tier

Cluster build time: 14 minutes

Download the [tier_dev-lxc.yml](tier_dev-lxc.yml) file to the dev-lxc-platform filesystem.

The following is an example of `dl status` for this cluster.

```
Chef Server FQDN: chef-tier.lxc

chef-be.lxc         RUNNING         10.0.3.201
  |_ snap0 2017:03:07 21:48:04 dev-lxc build: products installed
  |_ snap1 2017:03:07 22:00:45 dev-lxc build: completed

chef-fe1.lxc        RUNNING         10.0.3.202
  |_ snap0 2017:03:07 21:49:16 dev-lxc build: products installed
  |_ snap1 2017:03:07 22:00:42 dev-lxc build: completed

analytics.lxc       RUNNING         10.0.3.204
  |_ snap0 2017:03:07 21:49:34 dev-lxc build: products installed
  |_ snap1 2017:03:07 22:00:38 dev-lxc build: completed

node-1-tier.lxc     RUNNING         10.0.3.87
  |_ snap0 2017:03:07 21:49:48 dev-lxc build: products installed
  |_ snap1 2017:03:07 22:00:26 dev-lxc build: completed
```

The following command and described modifications were used to create the `tier_dev-lxc.yml` file.

```
dl init --chef-tier --analytics --nodes
```

The nodes' `chef_server_url` hostname was changed to `chef-tier.lxc` and the node's hostname was changed to `node-1-tier.lxc`.

## external

Cluster build time: 5 minutes

Download the [external_dev-lxc.yml](external_dev-lxc.yml) file to the dev-lxc-platform filesystem.

The `external` cluster needs the [postgres-partial.rb](conf-files/chef-server/postgres-partial.rb), [elasticsearch-partial.rb](conf-files/chef-server/elasticsearch-partial.rb) and [ldap-partial.rb](conf-files/chef-server/ldap-partial.rb) files copied to an appropriate location on dev-lxc-platform's filesystem.

Run the following commands as the dev-lxc-platform's root user to create new external postgres, elasticsearch and ldap servers for the `external` cluster.

```
docker rm my-postgres -f
docker rm my-elasticsearch -f
docker rm my-ldap -f

docker run --name my-postgres -d -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword postgres
docker run --name my-elasticsearch -d -p 9200:9200 -e "http.host=0.0.0.0" -e "transport.host=127.0.0.1" elasticsearch:2.3
docker run --name my-ldap -d -p 389:389 -e SLAPD_PASSWORD=mysecretpassword -e SLAPD_DOMAIN=ldap.example.org dinkel/openldap
```

The following is an example of `dl status` for this cluster.

```
chef-external.lxc       RUNNING         10.0.3.233
  |_ snap0 2017:03:14 19:51:33 dev-lxc build: products installed
  |_ snap1 2017:03:14 19:55:23 dev-lxc build: completed

node-1-external.lxc     RUNNING         10.0.3.87
  |_ snap0 2017:03:14 19:52:08 dev-lxc build: products installed
  |_ snap1 2017:03:14 19:55:11 dev-lxc build: completed
```

The following command and described modifications were used to create the `external_dev-lxc.yml` file.

```
dl init --chef --nodes --product-versions push-jobs-server:none reporting:none
```

The Chef server's hostname was changed to `chef-external.lxc` and its IP address was changed to `10.0.3.233`

Paths to the `postgres-partial.rb`, `elasticsearch-partial.rb` and `ldap-partial.rb` files were added to the Chef server's `chef-server.rb_partials` list.

The nodes' `chef_server_url` hostname was changed to `chef-external.lxc` and the node's hostname was changed to `node-1-external.lxc`.
