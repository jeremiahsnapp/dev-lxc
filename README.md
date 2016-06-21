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

1. LXC 1.0 Containers - Resource efficient servers with fast start/stop times and standard init
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

    Consider using `byobu` or `tmux` for a terminal multiplexer as [dev-lxc-platform README
    describes](https://github.com/jeremiahsnapp/dev-lxc-platform#use-a-terminal-multiplexer).

* Setup Mounts and Packages

    As [described below](https://github.com/jeremiahsnapp/dev-lxc#cluster-config-files)
	`dev-lxc` uses a `dev-lxc.yml` config file for each cluster.
	Be sure that you configure the `mounts` and `packages` lists in `dev-lxc.yml` to match your
	particular environment.

    The package paths in dev-lxc's example configs assume that the packages are stored in the
	following directory structure in the dev-lxc-platform VM. I recommend creating that
	directory structure in the physical workstation and configuring dev-lxc-platform's `.knife.yml`
	to mount the structure into `/root/dev` in the dev-lxc-platform VM.

```
/root/dev/chef-packages/
├── analytics
├── cs
├── ec
├── manage
├── osc
├── push-jobs-server
└── reporting
```

## Update dev-lxc gem

Run `gem update dev-lxc` inside the Vagrant VM platform to ensure you have the latest version.

## Usage

### Display Help

```
dev-lxc help

dev-lxc -h

dev-lxc --help

dev-lxc help <subcommand>
```

### Shorter Commands are Faster (to type that is :)

The dev-lxc-platform's root user's `~/.bashrc` file has aliased `dl` to `dev-lxc` for ease of use but
for most instructions in this README I will use `dev-lxc` for clarity.

You only have to type enough of a `dev-lxc` subcommand to make it unique.

The following commands are equivalent:

```
dev-lxc init --chef > dev-lxc.yml
dl i --chef > dev-lxc.yml
```

```
dev-lxc up
dl u
```

```
dev-lxc status
dl st
```

```
dev-lxc destroy
dl d
```

### Build and Manage a Cluster

The following instructions will build a tier Chef Server with an Analytics server
for demonstration purposes.
The size of this cluster uses about 3GB ram and takes awhile for the first
build of the servers. Feel free to try the standalone config first.

#### Define cluster

The following command saves a predefined config to dev-lxc.yml.

Be sure you configure the
[mounts and packages entries](https://github.com/jeremiahsnapp/dev-lxc#cluster-config-files)
appropriately.

```
dev-lxc init --tiered-chef --analytics > dev-lxc.yml
```

Be sure to set `base_container` in the `dev-lxc.yml` to an existing container's name.  
This container will be cloned to create each container in the cluster.  
If you don't already have a container to use as a `base_container` then you can follow the instructions in the  
[Create a dev-lxc Base Container section](https://github.com/jeremiahsnapp/dev-lxc#create-a-dev-lxc-base-container) to create one.

#### Create a dev-lxc Base Container

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

#### Cluster status

Run the following command to see the status of the cluster.

```
dev-lxc status
```

This is an example of the output.

```
Chef Server: chef.lxc
Analytics:   analytics.lxc

      chef-be.lxc     running         10.0.3.201
     chef-fe1.lxc     running         10.0.3.202
    analytics.lxc     running         10.0.3.204
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

The right side is made up of three vertically stacked panes with each pane's content
updating every 0.5 seconds.

* Top - system's memory usage provided by `free -h`
* Middle - cluster's status provided by `dev-lxc status`
* Bottom - to be determined

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

Starting the cluster the first time takes awhile since it has a lot to build.

```
dev-lxc up
```

A test org, user, knife.rb and keys are automatically created in
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
knife ssl fetch
knife client list
```

#### Stop and start the cluster

```
dev-lxc halt
dev-lxc up
```

#### Backdoor access to each server's filesystem

The realpath subcommand can be used to prepend each server's rootfs path to a particular file.

For example, you can use the following command to edit the Chef Servers' chef-server.rb
file without logging into the containers.

```
emacs $(dev-lxc realpath chef /etc/opscode/chef-server.rb)
```

#### Run arbitrary commands in each server

After modifying the chef-server.rb you could use the run-command subcommand to tell the backend and
frontend servers to run `chef-server-ctl reconfigure`.

```
dev-lxc run-command chef 'chef-server-ctl reconfigure'
```

#### Attach the terminal to a server

Attach the terminal to a server in the cluster that matches the REGEX pattern given.

```
dev-lxc attach chef-be
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

For example, to only start the Chef Servers named `chef-be.lxc` and `chef-fe1.lxc`
you can run the following command.

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
cluster-view
dl up
```

### Managing Node Containers

#### Install Chef Client in a Container

Use the `-v` option to specify a particular version of Chef Client.

Use `-v latest` or leave out the `-v` option to install the latest version of Chef Client.

For example, install the latest 11.x version of Chef Client.

```
dev-lxc install-chef-client test-node.lxc -v 11
```

#### Configure Chef Client in a Container

Use the `-s`, `-u`, `-k` options to set `chef_server_url`, `validation_client_name` and
`validation_key` in a container's `/etc/chef/client.rb` and copy the validator's key to
`/etc/chef/validation.pem`.

Or leave the options empty and it will default to using values from the cluster defined
in `dev-lxc.yml`.

```
dev-lxc config-chef-client test-node.lxc
```

#### Bootstrap Chef Client in a Container

Specifying a `BASE_CONTAINER_NAME` will clone the base container into a new container
and bootstrap it. If no `BASE_CONTAINER_NAME` is given then the container to be bootstrapped
needs to already exist.

Use the `-v` option to specify a particular version of Chef Client.

Use the `-s`, `-u`, `-k` options to set `chef_server_url`, `validation_client_name` and
`validation_key` in a container's `/etc/chef/client.rb` and copy the validator's key to
`/etc/chef/validation.pem`.

Or leave the options empty and it will default to using values from the cluster defined
in `dev-lxc.yml`.

Use the `-r` option to specify the run_list for chef-client to use.

```
dev-lxc bootstrap-container test-node.lxc -r my_run_list
```

### Using the dev-lxc library

dev-lxc cli interface can be used as a library.

```
require 'dev-lxc/cli'

ARGV = [ 'up' ]         # start all servers
DevLXC::CLI::DevLXC.start

ARGV = [ 'status' ]        # show status of all servers
DevLXC::CLI::DevLXC.start

ARGV = [ 'run-command', 'uptime' ]   # run `uptime` in all servers
DevLXC::CLI::DevLXC.start

ARGV = [ 'destroy' ]       # destroy all servers
DevLXC::CLI::DevLXC.start
```

dev-lxc itself can also be used as a library

```
require 'yaml'
require 'dev-lxc'

config = YAML.load(IO.read('dev-lxc.yml'))
server = DevLXC::Server.new("chef-fe1.lxc", 'chef-server', config)

server.start               # start chef-fe1.lxc
server.status              # show status of chef-fe1.lxc
server.run_command("chef-server-ctl reconfigure")  # run command in chef-fe1.lxc
server.stop                # stop chef-fe1.lxc
server.destroy             # destroy chef-fe1.lxc
```

## Cluster Config Files

dev-lxc uses a YAML configuration file named `dev-lxc.yml` to define a cluster.

The following command generates sample config files for various cluster topologies.

```
dev-lxc init
```

`dev-lxc init --tiered-chef --analytics > dev-lxc.yml` creates a `dev-lxc.yml` file with the following content:

```
# base_container must be the name of an existing container
base_container: b-ubuntu-1404

# list any host directories you want mounted into the servers
mounts:
  - /root/dev root/dev

# list any SSH public keys you want added to /home/dev-lxc/.ssh/authorized_keys
#ssh-keys:
#  - /root/dev/clusters/id_rsa.pub

# DHCP reserved (static) IPs must be selected from the IP range 10.0.3.150 - 254

chef-server:
  packages:
    server: /root/dev/chef-packages/cs/chef-server-core_12.5.0-1_amd64.deb
    manage: /root/dev/chef-packages/manage/chef-manage_2.2.1-1_amd64.deb
    reporting: /root/dev/chef-packages/reporting/opscode-reporting_1.5.6-1_amd64.deb
    push-jobs-server: /root/dev/chef-packages/push-jobs-server/opscode-push-jobs-server_1.1.6-1_amd64.deb
  topology: tier
  api_fqdn: chef.lxc
  servers:
    chef-be.lxc:
      ipaddress: 10.0.3.201
      role: backend
      bootstrap: true
    chef-fe1.lxc:
      ipaddress: 10.0.3.202
      role: frontend

analytics:
  packages:
    analytics: /root/dev/chef-packages/analytics/opscode-analytics_1.3.1-1_amd64.deb
  servers:
    analytics.lxc:
      ipaddress: 10.0.3.204
```

This config defines a tier cluster consisting of a single backend and a single frontend.

A second frontend is commented out to conserve resources. If you uncomment the second
frontend then both frontends will be created and dnsmasq will resolve the `api_fqdn`
[chef.lxc](chef.lxc) to both frontends using a round-robin policy.

The config file is very customizable. You can add or remove mounts, packages or servers,
change ip addresses, change server names, change the base_container and more.

The `mounts` list describes what directories get mounted from the Vagrant VM platform into
each container. You need to make sure that you configure the mount entries to be
appropriate for your environment.

The same is true for the `packages` list. The paths that are provided in the default configs are just examples.
You need to make sure that you have each package you want to use downloaded to appropriate directories
that will be available to the container when it is started.

I recommend downloading the packages to a directory on your workstation.
Then configure the
[dev-lxc-platform's .kitchen.yml](https://github.com/jeremiahsnapp/dev-lxc-platform#description)
to mount that directory in the Vagrant VM platform.
Then configure the cluster's mount entries in `dev-lxc.yml` to mount the Vagrant VM platform's
directory into each container.

Make sure the mounts and packages represent actual paths that are available in your environment.

### Managing Multiple Clusters

By default, `dev-lxc` looks for a `dev-lxc.yml` file in the present working directory.
You can also specify a particular config file as an option for most dev-lxc commands.

The following is an example of managing multiple clusters while still avoiding specifying
each cluster's config file.

```
mkdir -p ~/clusters/{clusterA,clusterB}
dev-lxc init --tiered-chef > ~/clusters/clusterA/dev-lxc.yml
dev-lxc init --chef > ~/clusters/clusterB/dev-lxc.yml
cd ~/clusters/clusterA && dev-lxc up  # starts clusterA
cd ~/clusters/clusterB && dev-lxc up  # starts clusterB
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

## Base Containers

The container that is used as the base container for a cluster's containers must exist before
the cluster can be built. The cluster's containers are cloned from the base container.

Base containers are cloned using the btrfs filesystem to very quickly provide a lightweight duplicate
of the container.

If you don't already have a container to use as a base container then you can use the instructions in the
[Create a dev-lxc Base Container section](https://github.com/jeremiahsnapp/dev-lxc#create-a-dev-lxc-base-container) to create one.
This container provides the chosen OS platform and version (e.g. b-ubuntu-1404).
A typical LXC container has minimal packages installed so `dev-lxc` makes sure that the
same packages used in Chef's [bento boxes](https://github.com/opscode/bento) are
installed to provide a more typical server environment.
A few additional packages are also installed.

Base containers have openssh-server installed and running with unique SSH Host Keys.

Base containers have a "dev-lxc" user with "dev-lxc" password and passwordless sudo.

*Once this base container is created there is rarely a need to delete it.*

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
