# dev-lxc

A tool for building Chef Server clusters and Chef Analytics clusters using LXC containers.

Using [ruby-lxc](https://github.com/lxc/ruby-lxc) it builds servers and optionally installs and
configures many Chef products including a standalone Chef Server or tier Chef Server cluster
composed of a backend and multiple frontends with round-robin DNS resolution.

dev-lxc also has commands to manipulate Chef node containers. For example, dev-lxc can bootstrap a
container by installing Chef Client, configuring it for a Chef Server and running a specified run_list.

The dev-lxc tool is well suited as a tool for support related work, customized cluster builds
for demo purposes, as well as general experimentation and exploration of Chef products

### Features

1. LXC 2.0 Containers - Resource efficient servers with fast start/stop times and standard init
2. Btrfs - Efficient, persistent storage backend provides fast, lightweight container cloning
3. Dnsmasq - DHCP networking and DNS resolution
4. Base Containers - Containers that are built to resemble a traditional server
5. ruby-lxc - Ruby bindings for liblxc
6. YAML - Simple, customizable definition of clusters; No more setting ENV variables
7. Build process closely follows online installation documentation
8. Snapshots - Snapshots are created during the cluster's build process which makes rebuilding
   a cluster very fast.

Its containers, standard init, networking and build process are designed to be similar
to what you would build if you follow the online installation documentation so the end
result is a cluster that is relatively similar to a more traditionally built cluster.

The Btrfs backed snapshots provide a quick clean slate which is helpful especially for
experimenting and troubleshooting. Or it can be used to build a customized cluster
for demo purposes and be able to bring it up quickly and reliably.

If you aren't familiar with using containers please read this introduction.

[LXC 1.0 Introduction](https://www.stgraber.org/2013/12/20/lxc-1-0-blog-post-series/)

## Requirements

* dev-lxc-platform

    The `dev-lxc` tool is designed to be used in a platform built by
    [dev-lxc-platform](https://github.com/jeremiahsnapp/dev-lxc-platform).

    Please follow the dev-lxc-platform usage instructions to create a suitable platform.

    The dev-lxc-platform will automatically install this `dev-lxc` tool.

* Use root user

    Once you login to the Vagrant VM platform you should run `sudo -i` to login as the root user.

## Update dev-lxc gem

Run `chef gem update dev-lxc` inside the Vagrant VM platform to ensure you have the latest version.

## Usage

### Display Help

```
dev-lxc help

dev-lxc help <subcommand>
```

### Shorter Commands are Faster (to type that is :)

The dev-lxc-platform's root user's `~/.bashrc` file has aliased `dl` to `dev-lxc` for ease of use but
for most instructions this README will use `dev-lxc` for clarity.

You only have to type enough of a `dev-lxc` subcommand to make it unique.

For example, the following commands are equivalent:

```
dev-lxc status
dl st
```

```
dev-lxc snapshot
dl sn
```

### Base Containers

The container that is used as the base container for a cluster's containers must exist before
the cluster can be built. The cluster's containers are cloned from the base container using
the btrfs filesystem to very quickly provide a lightweight duplicate of the container.

This container provides the chosen OS platform and version (e.g. b-ubuntu-1404).

A typical LXC container has minimal packages installed so `dev-lxc` makes sure that the
same packages used in Chef's [bento boxes](https://github.com/opscode/bento) are
installed to provide a more typical server environment.
A few additional packages are also installed.

Base containers have openssh-server installed and running with unique SSH Host Keys.

Base containers have a "dev-lxc" user with "dev-lxc" password and passwordless sudo.

*Once this base container is created there is rarely a need to delete it.*

### Create a dev-lxc Base Container

dev-lxc is able to create base containers that have openssh-server installed and running with unique SSH Host Keys.

dev-lxc base containers have a "dev-lxc" user with "dev-lxc" password and passwordless sudo.

You can see a menu of base containers that `dev-lxc` can create by using the following command.

```
dev-lxc create-base-container
```

The initial creation of base containers can take awhile so let's go ahead and start creating
an Ubuntu 14.04 container now.

```
dev-lxc create-base-container b-ubuntu-1404
```

Note: It is possible to pass additional arguments to the underlying LXC create command.
For example:

```
dev-lxc create-base-container b-ubuntu-1404 -o -- '--no-validate --keyserver http://my.key.server.com'
```

### dev-lxc.yml Config Files

dev-lxc uses a YAML configuration file named `dev-lxc.yml` to define a cluster.

The `init` command generates sample config files for various server types.

Let's generate a config for a Chef Server tier topology with one backend and one frontend
along with an Analytics Server, Supermarket Server and a node server.

```
dev-lxc init --chef-tier --analytics --supermarket --nodes > dev-lxc.yml
```

The contents of `dev-lxc.yml` should look like this.

```
# base_container must be the name of an existing container
base_container: b-ubuntu-1404

# list any host directories you want mounted into the servers
#mounts:
#  - /root/dev root/dev

# list any SSH public keys you want added to /home/dev-lxc/.ssh/authorized_keys
#ssh-keys:
#  - /root/dev/clusters/id_rsa.pub

# DHCP reserved (static) IPs must be selected from the IP range 10.0.3.150 - 254

chef-server:
  servers:
    chef.lxc:
      ipaddress: 10.0.3.203
      products:
        chef-server:
        manage:
        push-jobs-server:
        reporting:

analytics:
  servers:
    analytics.lxc:
      ipaddress: 10.0.3.204
      products:
        analytics:

supermarket:
  servers:
    supermarket.lxc:
      ipaddress: 10.0.3.206
      products:
        supermarket:

nodes:
  servers:
    node-1.lxc:
      products:
        chef:
```

As you can see there are four server types represented by five servers.

1. chef-server - chef.lxc
2. analytics - analytics.lxc
3. supermarket - supermarket.lxc
4. nodes - node-1.lxc

The global settings used by each of the server types are the `base_container`, a list of `mounts` and
a list of `ssh-keys`. These settings are described in the config comments.

Be sure to set `base_container` in the `dev-lxc.yml` to an existing container's name.  
This container will be cloned to create each container in the cluster.  
If you don't already have a container to use as a `base_container` then you can follow the instructions in the  
[Create a dev-lxc Base Container section](https://github.com/jeremiahsnapp/dev-lxc#create-a-dev-lxc-base-container) to create one.

It is possible to define different values for `base_container`, `mounts` or `ssh-keys` for a particular server type as
you can see in the following snippet.

```
nodes:
  base_container: b-centos-6
  servers:
    node-1.lxc:
```

IP addresses from the range 10.0.3.150 - 254 can be assigned to the servers. If an IP address
is not specified then a dynamic IP address is assigned when the server starts.

dev-lxc uses the [mixlib-install](https://github.com/chef/mixlib-install) library to download Chef products
to a cache in `/var/dev-lxc` in the host VM. This cache is automatically mounted into each server when it starts.

A list of Chef products to be installed can be defined for each server
using [product names that mixlib-install understands](https://github.com/chef/mixlib-install/blob/master/PRODUCT_MATRIX.md).

The channel and version of the product can be defined also.

Channel can be `current`, `stable` or `unstable` with `stable` as the default.
Version can be `latest` or a version number with `latest` as the default.

For example, the following specifies the `current` channel and version `0.16.1` of the `chefdk` product.

```
nodes:
  servers:
    node-1.lxc:
      products:
        chefdk:
          channel: current
          version: 0.16.1
```

The `package_source` setting can be used to specify a package file on disk.

```
nodes:
  servers:
    node-1.lxc:
      products:
        chefdk:
          package_source: /root/chefdk_0.16.1-1_amd64.deb
```

dev-lxc knows how to automatically configure Chef Server standalone, Chef Server tier topology,
Chef Server HA 2.0 as well as Chef Client, Analytics, Compliance and Supermarket.

If an Analytics server or Supermarket server is defined in the same config file as
a Chef Server then each server will automatically be integrated with that Chef Server.

If a node server with Chef Client or Chef DK installed is defined in the same config file as
a Chef Server then the Chef Client will automatically be configured to use that Chef Server.

Alternatively, values for `chef_server_url`, `validation_client_name` and `validation_key` can
be set in the config file.

```
nodes:
  servers:
    node-1.lxc:
      chef_server_url: https://api.chef.io/organizations/demo
      validation_client_name: demo-validator
      validation_key: /hosted-chef/chef-repo/.chef/demo-validator.pem
      products:
        chef:
```

The dev-lxc.yml config file is very customizable. You can add or remove mounts, products or servers,
change ip addresses, server names, the base_container and more.

#### Cluster status

Run the following command to see the status of the cluster.

```
dev-lxc status
```

This is an example of the output.

```
chef.lxc            NOT_CREATED

analytics.lxc       NOT_CREATED

supermarket.lxc     NOT_CREATED

node-1.lxc          NOT_CREATED
```

#### cluster-view, tks, tls commands

The dev-lxc-platform comes with some commands that create and manage helpful
tmux/byobu sessions to more easily see the state of a cluster.

Running the `cluster-view` command in the same directory as a `dev-lxc.yml` file
creates a tmux/byobu session with the same name as the cluster's directory.

`cluster-view` can also be run with the parent directory of a `dev-lxc.yml` file
as the first argument and `cluster-view` will change to that directory before
creating the tmux/byobu session.

The session's first window is named "cluster".

The left side is for running dev-lxc commands.

The right side updates every 0.5 seconds with the cluster's status provided by `dev-lxc status`.

The session's second window is named "shell". It opens in the same directory as the
cluster's `dev-lxc.yml` file.

The `tls` and `tks` commands are really aliases.

`tls` is an alias for `tmux list-sessions` and is used to see what tmux/byobu sessions
are running.

`tks` is an alias for `tmux kill-session -t` and is used to kill tmux/byobu sessions.
When specifying the session to be killed you only need as many characters of the session
name that are required to make the name unique among the list of running sessions.

I recommend switching to a different running tmux/byobu session before killing the current
tmux/byobu session. Otherwise you will need to reattach to the remaining tmux/byobu session.
Use the keyboard shortcuts Alt-Up/Down to easily switch between tmux/byobu sessions.

#### Start cluster

Starting the cluster the first time takes awhile since it has a lot to download and build.

```
dev-lxc up
```

A test org, users, knife.rb and keys are automatically created in
the bootstrap backend server in `/root/chef-repo/.chef` for testing purposes.

The `knife-opc` plugin is installed in the embedded ruby environment of the
Private Chef and Enterprise Chef server to facilitate the creation of the test
org and user.

#### Create chef-repo

Create a local chef-repo with appropriate knife.rb and pem files.

Use the `-p` option to also get pivotal.pem and pivotal.rb files.

Use the `-f` option to overwrite existing knife.rb and pivotal.rb files.

```
dev-lxc chef-repo
```

Now you can easily use knife to access the cluster.

```
cd chef-repo
knife client list
```

#### Stop and start the cluster

```
dev-lxc halt
dev-lxc up
```

#### Run arbitrary commands in each server

```
dev-lxc run-command chef 'uptime'
```

#### Attach the terminal to a server

Attach the terminal to a server in the cluster that matches the REGEX pattern given.

```
dev-lxc attach chef
```

#### Create a snapshot of the servers

Save the changes in the servers to snapshots with a comment.

```
dev-lxc halt
dev-lxc snapshot -c 'this is a snapshot comment'
```

#### List snapshots

```
dev-lxc snapshot -l
```

#### Restore snapshots

Restore snapshots by name.

Leave out the snapshot name or specify `LAST` to restore the most recent snapshot.

```
dev-lxc snapshot -r
dev-lxc up
```

#### Destroy snapshots

Destroy snapshots by name or destroy all snapshots by specifying `ALL`.

Leave out the snapshot name or specify `LAST` to destroy the most recent snapshots.

```
dev-lxc snapshot -d
```

#### Destroy cluster

Use the following command to destroy the cluster's servers.

```
dev-lxc destroy
```

#### Use commands against specific servers
You can also run most of these commands against a set of servers by specifying a regular expression
that matches a set of server names.

```
dev-lxc <subcommand> [SERVER_NAME_REGEX]
```

For example, to only start the Chef Server you can run the following command.

```
dev-lxc up chef
```

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
mkdir -p /root/dev/clusters/delivery
cd /root/dev/clusters/delivery
dev-lxc init --adhoc > dev-lxc.yml
# edit dev-lxc.yml to have enough adhoc servers for a delivery cluster
cluster-view
dl up
```

### Maintain Uniqueness Across Multiple Clusters

The default cluster configs are already designed to be unique from each other but as you build
more clusters you have to maintain uniqueness across the YAML config files for the following items.

* Server names, `api_fqdn` and `analytics_fqdn`

    Server names should really be unique across all clusters.

    Even when cluster A is shutdown, if cluster B uses the same server names when it is created it
	will use the already existing servers from cluster A.

    `api_fqdn` and `analytics_fqdn` uniqueness only matters when clusters with the same `api_fqdn`
	and `analytics_fqdn` are running.

    If cluster B is started with the same `api_fqdn` or `analytics_fqdn` as an already running cluster A,
	then cluster B will overwrite cluster A's DNS resolution of `api_fqdn` or `analytics_fqdn`.

* IP Addresses

    IP addresses uniqueness only matters when clusters with the same IP's are running.

    If cluster B is started with the same IP's as an already running cluster A, then cluster B
	will overwrite cluster A's DHCP reservation of the IP's but dnsmasq will still refuse to
	assign the IP's to cluster B because they already in use by cluster A. dnsmasq then assigns
	random IP's from the DHCP pool to cluster B leaving it in an unexpected state.

    The `dev-lxc-platform` creates the IP range 10.0.3.150 - 254 for DHCP reserved IP's.

    Use unique IP's from that range when configuring clusters.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
