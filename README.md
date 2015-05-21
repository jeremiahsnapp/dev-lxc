# dev-lxc

A tool for creating Chef Server clusters and Chef Analytics clusters using LXC containers.

Using [ruby-lxc](https://github.com/lxc/ruby-lxc) it builds a standalone Chef Server or
tier Chef Server cluster composed of a backend and multiple frontends with round-robin
DNS resolution. It can also build a standalone or tier Chef Analytics server and connect
it with the Chef Server.

dev-lxc also has commands to manipulate Chef node containers. For example, dev-lxc can bootstrap a
container by installing Chef Client, configuring it for a Chef Server and running a specified run_list.

The dev-lxc tool is well suited as a tool for support related work, customized cluster builds
for demo purposes, as well as general experimentation and exploration of Chef products

### Features

1. LXC 1.0 Containers - Resource efficient servers with fast start/stop times and standard init
2. Btrfs - Efficient, persistent storage backend provides fast, lightweight container cloning
3. Dnsmasq - DHCP networking and DNS resolution
4. Platform Images - Images that are built to resemble a traditional server
5. ruby-lxc - Ruby bindings for liblxc
6. YAML - Simple, customizable definition of clusters; No more setting ENV variables
7. Build process closely follows online installation documentation
8. Images - Images are created during the cluster's build process which makes rebuilding
   a cluster very fast.

Its containers, standard init, networking and build process are designed to be similar
to what you would build if you follow the online installation documentation so the end
result is a cluster that is relatively similar to a more traditionally built cluster.

The Btrfs backed clones provide a quick clean slate which is helpful especially for
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
├── reporting
└── sync
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
dev-lxc init standalone > dev-lxc.yml
dl i standalone > dev-lxc.yml
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

### Create and Manage a Cluster

The following instructions will build a tier Chef Server with a tier Analytics server
for demonstration purposes.
The size of this cluster uses about 3GB ram and takes awhile for the first
build of the servers. Feel free to try the standalone config first.

#### Define cluster

The following command saves a predefined config to dev-lxc.yml.

Be sure you configure the
[mounts and packages entries](https://github.com/jeremiahsnapp/dev-lxc#cluster-config-files)
appropriately.

```
dev-lxc init tier > dev-lxc.yml
```

#### List Images

List of each servers' images created during the build process.

```
dev-lxc list-images
```

#### Cluster status

Run the following command to see the status of the cluster.

```
dev-lxc status
```

This is an example of the output.

```
Chef Server: https://chef.lxc

Analytics:   https://analytics.lxc

      chef-be.lxc     running         10.0.3.203
     chef-fe1.lxc     running         10.0.3.204
 analytics-be.lxc     running         10.0.3.206
analytics-fe1.lxc     running         10.0.3.207
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
* Bottom - list of the cluster's images provided by `dev-lxc list-images`

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

The tool automatically creates images at appropriate times so future creation of the
cluster's servers is very quick.

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

#### Cheap cluster rebuilds

Clones of the servers as they existed immediately after initial installation, configuration and
test org and user creation are available so you can destroy the cluster and "rebuild" it within
seconds effectively starting with a clean slate very easily.

```
dev-lxc destroy
dev-lxc up
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

#### Make a snapshot of the servers

Save the changes in the servers to custom images.

```
dev-lxc halt
dev-lxc snapshot
```

Now the servers can be destroyed and recreated with the same changes captured at the time of the snapshot.

```
dev-lxc destroy
dev-lxc up
```

#### Destroy cluster

Use the following command to destroy the cluster's servers and also destroy their custom, unique and shared
images if you want to build them from scratch.

```
dev-lxc destroy -c -u -s
```

#### Global status of all dev-lxc images and servers

Use the `global-status` command to see the status of all dev-lxc images and servers stored in dev-lxc's
default LXC config_path `/var/lib/dev-lxc`.

```
dev-lxc global-status
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

### Managing Node Containers

#### Manually Create a Platform Image

Platform images can be used for purposes other than building clusters. For example, they can
be used as Chef nodes for testing purposes.

Platform images have openssh-server installed and running with unique SSH Host Keys.

Platform images have a "dev-lxc" user with "dev-lxc" password and passwordless sudo.

You can see a menu of platform images this tool can create by using the following command.

```
dev-lxc create
```

The initial creation of platform images can take awhile so let's go ahead and start creating
an Ubuntu 14.04 image now.

```
dev-lxc create p-ubuntu-1404
```

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

`dev-lxc init tier > dev-lxc.yml` creates a `dev-lxc.yml` file with the following content:

```
## platform_image can be one of the following:
## p-centos-5, p-centos-6, p-ubuntu-1204 or p-ubuntu-1404

## Make sure a mount's source directory exists in the LXC host

## Make sure a package's path is correct

## All FQDNs and server names must end with the `.lxc` domain

## DHCP reserved (static) IPs must be selected from the IP range 10.0.3.150 - 254

## topology can be one of the following:
## standalone, tier or open-source (for the old open source 11 chef server)

chef-server:
  platform_image: p-ubuntu-1404
  mounts:
    - /root/dev root/dev
  packages:
    server: /root/dev/chef-packages/cs/chef-server-core_12.0.7-1_amd64.deb
    manage: /root/dev/chef-packages/manage/opscode-manage_1.11.2-1_amd64.deb
#    reporting: /root/dev/chef-packages/reporting/opscode-reporting_1.2.3-1_amd64.deb
#    push-jobs-server: /root/dev/chef-packages/push-jobs-server/opscode-push-jobs-server_1.1.6-1_amd64.deb
#    sync: /root/dev/chef-packages/sync/chef-sync_1.0.0~rc.6-1_amd64.deb

##   The chef-sync package will only be installed.
##   chef-sync will NOT be configured since we don't know whether it should be a master or replica.

  api_fqdn: chef.lxc
  topology: tier
  servers:
    chef-be.lxc:
      role: backend
      ipaddress: 10.0.3.203
      bootstrap: true
    chef-fe1.lxc:
      role: frontend
      ipaddress: 10.0.3.204
#    chef-fe2.lxc:
#      role: frontend
#      ipaddress: 10.0.3.205

analytics:
  platform_image: p-ubuntu-1404
  mounts:
    - /root/dev root/dev
  packages:
    analytics: /root/dev/chef-packages/analytics/opscode-analytics_1.1.2-1_amd64.deb

  analytics_fqdn: analytics.lxc
  topology: tier
  servers:
    analytics-be.lxc:
      role: backend
      ipaddress: 10.0.3.206
      bootstrap: true
    analytics-fe1.lxc:
      role: frontend
      ipaddress: 10.0.3.207
#    analytics-fe2.lxc:
#      role: frontend
#      ipaddress: 10.0.3.208
```

This config defines a tier cluster consisting of a single backend and a single frontend.

A second frontend is commented out to conserve resources. If you uncomment the second
frontend then both frontends will be created and dnsmasq will resolve the `api_fqdn`
[chef.lxc](chef.lxc) to both frontends using a round-robin policy.

The config file is very customizable. You can add or remove mounts, packages or servers,
change ip addresses, change server names, change the platform_image and more.

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
dev-lxc init tier > ~/clusters/clusterA/dev-lxc.yml
dev-lxc init standalone > ~/clusters/clusterB/dev-lxc.yml
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

    It is easy to provide uniqueness in the server names, `api_fqdn` and `analytics_fqdn`.
	For example, you can use the following command to prefix the servers names with `1234-` when
	generating a cluster's config.

        dev-lxc init tier 1234- > dev-lxc.yml

* IP Addresses

    IP addresses uniqueness only matters when clusters with the same IP's are running.
	
    If cluster B is started with the same IP's as an already running cluster A, then cluster B
	will overwrite cluster A's DHCP reservation of the IP's but dnsmasq will still refuse to
	assign the IP's to cluster B because they already in use by cluster A. dnsmasq then assigns
	random IP's from the DHCP pool to cluster B leaving it in an unexpected state.

    The `dev-lxc-platform` creates the IP range 10.0.3.150 - 254 for DHCP reserved IP's.
	
    Use unique IP's from that range when configuring clusters.

## Images

One of the key things this tool uses is the concept of images.

`dev-lxc` creates images with a "p-", "s-", "u-" or "c-" prefix on the name to distinguish
it as a "platform", "shared", "unique" or "custom" image.

Images are then cloned using the btrfs filesystem to very quickly provide a lightweight duplicate
of the image. This clone is either used to build the next image in the build process or the final
container that will actually be run.

By default, the cluster's images and final server containers are all stored in `/var/lib/dev-lxc`
so they don't clutter the containers stored in the default LXC config_path `/var/lib/lxc`.

The cluster's LXC config_path can be configured by setting `lxc_config_path` at the top of the
`dev-lxc.yml` file to the desired directory.

There are four image categories.

1. Platform Image

    The platform image is the first to get created and is identified by the
	"p-" prefix on the image name.

    `DevLXC#create_platform_image` controls the creation of a platform image.

    This image provides the chosen OS platform and version (e.g. p-ubuntu-1404).
	A typical LXC container has minimal packages installed so `dev-lxc` makes sure that the
	same packages used in Chef's [bento boxes](https://github.com/opscode/bento) are
	installed to provide a more typical server environment.
	A few additional packages are also installed.

    Platform images have openssh-server installed and running with unique SSH Host Keys.

    Platform images have a "dev-lxc" user with "dev-lxc" password and passwordless sudo.

    *Once this platform image is created there is rarely a need to delete it.*

2. Shared Image

    The shared image is the second to get created and is identified by the
	"s-" prefix on the image name.

    `DevLXC::Server#create_shared_image` controls the creation of a shared image.

    Chef packages that are common to all servers in a Chef cluster, such as chef-server-core,
	opscode-reporting, opscode-push-jobs-server and chef-sync are installed using `dpkg` or `rpm`.

    Note the manage package will not be installed at this point since it is not common to all
	servers (i.e. it does not get installed on backend servers).

    The name of this image is built from the names and versions of the Chef packages that
	get installed which makes this image easy to be reused by another cluster that is
	configured to use the same Chef packages.

    *Since no configuration actually happens yet there is rarely a need to delete this image.*

3. Unique Image

    The unique image is the last to get created and is identified by the
	"u-" prefix on the image name.

    `DevLXC::Server#create` controls the creation of a unique image.

    Each unique Chef server (e.g. standalone, backend or frontend) is created.

    * The specified hostname is assigned.
	* dnsmasq is configured to reserve the specified IP address for the image's MAC address.
	* A DNS entry is created in dnsmasq if appropriate.
	* All installed Chef packages are configured.
	* Test users and orgs are created.
	* The opscode-manage package is installed and configured if specified.

    After each server is fully configured a clone of it is made resulting in the server's
	unique image. These unique images make it very easy to quickly recreate
	a Chef cluster from a clean starting point.

4. Custom Image

    The custom image is only created when the `snapshot` command is used and is identified
	by the "c-" prefix on the image name.

    `DevLXC::Server#snapshot` controls the creation of a custom image.

    Custom images can be used to save the changes that have been made in servers.
	Later, when the servers are destroyed and recreated, they will start running with the changes
	that were captured at the time of the snapshot.

### Destroying Images

When using `dev-lxc destroy` to destroy servers you have the option to also destroy any or all of
the four types of images associated with the servers.

The following command will list the options available.

```
dev-lxc help destroy
```

Of course, you can also just use the standard LXC commands to destroy any container.

```
lxc-destroy -n [NAME]
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
