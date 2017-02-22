
## dev-lxc

dev-lxc builds and manages clusters of LXC containers and includes the ability to install and configure Chef products.

Cluster management includes the ability to manage snapshots of the containers which makes dev-lxc well suited as a tool for support related work, customized cluster builds for demo purposes, as well as general experimentation and exploration.

### Features

1. LXC Containers - Resource efficient servers with fast start/stop times and standard init
2. Btrfs - Efficient, persistent storage backend provides fast, lightweight container snapshots
3. Dnsmasq - DHCP networking and DNS resolution
4. Base Containers - Containers that are built to resemble a traditional server
5. ruby-lxc - Ruby bindings for liblxc
6. YAML - Simple, flexible definition of clusters
7. Build process closely follows online installation documentation
8. Snapshots - Snapshots are created during the cluster's build process which makes rebuilding
   a cluster very fast.
9. mixlib-install library - Automatically manages a cache of Chef products

Its containers, standard init, networking and build process are designed to be similar
to what you would build if you follow the online installation documentation so the end
result is a cluster that is relatively similar to a more traditionally built cluster.

The Btrfs backed snapshots provide a quick clean slate which is helpful especially for
experimenting and troubleshooting. Or it can be used to build a customized cluster
for demo purposes and be able to bring it up quickly and reliably.

If you aren't familiar with using containers you might be interested in this introduction.

[LXC 1.0 Introduction](https://www.stgraber.org/2013/12/20/lxc-1-0-blog-post-series/)

Additional dev-lxc related documentation can be found in the [docs folder](docs) in this repository.

## Build dev-lxc-platform instance

The dev-lxc tool is used in a system that has been configured by the dev-lxc-platform cookbook.

The easiest way to build a dev-lxc-platform system is to download the dev-lxc-platform repository
and use Test Kitchen to build an AWS EC2 instance or a VirtualBox Vagrant instance.

Follow the instructions in the [dev-lxc-platform README](https://github.com/jeremiahsnapp/dev-lxc-platform) to build
a dev-lxc-platform instance.

## Login to the dev-lxc-platform instance

Login to the dev-lxc-platform instance and switch to the root user to use the dev-lxc tool.

```
cd dev-lxc-platform
kitchen login <ec2 or vagrant>
sudo -i
```

When you are logged in as the root user you should automatically enter a [byobu session](http://byobu.co/).

Byobu makes it easy to manage multiple terminal windows and panes. You can press `F1` to get help which includes a [list of keybindings](http://manpages.ubuntu.com/manpages/wily/en/man1/byobu.1.html#contenttoc8).

The prefix key is set to `Ctrl+o`

Some of the keys that will be most useful to you are:

* To switch between Byobu sessions
  * OS X - `option-Up`, `option-Down`
  * Linux/Windows - `alt-Up`, `alt-Down`
* To switch between windows in a session
  * OS X - `option-Left`, `option-Right`
  * Linux/Windows - `alt-Left`, `alt-Right`
* To switch between panes in a window
  * Linux/OS X/ Windows - `shift-Left`, `shift-Right`, `shift-Up`, `shift-Down`
  * Windows users using Conemu must first disable "Start selection with Shift+Arrow" in "Mark/Copy" under the "Keys & Macro" settings

Note: `Shift-F2` does not create horizontal splits for Windows users. Use the `Ctrl+o |` key binding instead.

## Update dev-lxc gem

Run the following command as the instance's root user if you ever need to upgrade the dev-lxc gem inside the dev-lxc-platform instance.

```
cd dev-lxc-platform
kitchen login <ec2 or vagrant>
sudo -i
chef gem update dev-lxc
```

## Demo: Build Chef Automate Cluster

### Display dev-lxc help

```
dev-lxc help

dev-lxc help <subcommand>
```

### dev-lxc Alias and Subcommands

The dev-lxc command has a `dl` alias for ease of use.

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

### Create Base Container

The [base container](docs/base_containers.md) used for the cluster's containers must be created first. Let's use Ubuntu 14.04 for the base container.

```
dl create b-ubuntu-1404
```

### Create Config File

Create the [dev-lxc.yml config file](docs/configuration.md) for the cluster.

First, create an arbitrary directory to hold the dev-lxc.yml file.

```
mkdir -p /root/work/clusters/automate
```

Then use the `init` subcommand to generate a sample configuration using the available options. Run `dl help init` to see what options are available.

The following command configures a standalone Chef Server, Supermarket server, Compliance server,
Chef Automate server, and a job dispatch runner.

```
dl init --chef --compliance --supermarket --automate --runners -f /root/work/clusters/automate/dev-lxc.yml
```

We can easily append additional configurations to this file. For example, the following command appends an infrastructure node.

```
dl init --nodes -a -f /root/work/clusters/automate/dev-lxc.yml
```

Edit the dev-lxc.yml file:

* Delete the `reporting` product from the Chef Server config since we will be using Chef Automate's Visibility.
* Set the Automate server's `license_path` value to the location of your license file.
* (Optionally) If you built other clusters then you can modify the server names (including the nodes' `chef_server_url`) in this cluster to
  make them [unique from the other clusters](docs/manage_multiple_clusters.md).

### cluster-view

Run the `cluster-view` command to create a Byobu session specifically for this cluster.

The session's first window is named "cluster".

The left pane is useful for running dev-lxc commands.

The right pane updates every 0.5 seconds with the cluster's status provided by `dev-lxc status`.

The session's second window is named "shell". It opens in the same directory as the
cluster's `dev-lxc.yml` file and is useful for attaching to a server to perform system administration tasks.

See the [usage docs](docs/usage.md) for more information about how to close/kill Byobu sessions.

```
cluster-view /root/work/clusters/automate
```

### Specifying a Subset of Servers

Many dev-lxc subcommands can act on a subset of the cluster's servers by specifying a regular expression that matches the desired server names.

For example, the following command will show the status of the infrastructure node.

```
dl status node
```

### Build the Cluster

dev-lxc knows to build the servers in an appropriate order.

It downloads the product packages to a cache location and installs the packages in each server.

It configures each product and creates necessary things such as Chef organizations and users as needed.

```
dl up
```

Note: You also have the option of running the `prepare-product-cache` subcommand which downloads required product packages to the cache.  
This can be helpful when you don't want to start building the cluster yet but you want the package cache ready when you build the cluster later.

### Use the Servers

At this point all of the cluster's servers should be running.

If you enabled dynamic forwarding (SOCKS v5) in your workstation's SSH config file and configured a web browser to use the SOCKS v5 proxy as described in the dev-lxc-platform README.md then you should be able to browse from your workstation to any dev-lxc server that has a web interface using its FQDN.

Since the cluster has a Chef Server you can use the `chef-repo` subcommand to create a chef-repo directory in the host instance that contains a knife.rb and all of the keys for the users and org validator clients that are defined in dev-lxc.yml. This makes it very easy to use tools such as knife or berkshelf.

```
dl chef
cd chef-repo
knife client list
cd ..
```

Since the cluster has a Chef Automate server you can use the `print-automate-credentials` subcommand to see what the login credentials.

```
dl print
```

You can use the `attach` subcommand to login to the root user of a server.

For example, the following command should attach to the Chef Server.

```
dl attach chef
```

Since the cluster has a Chef Server and an infrastructure node dev-lxc made sure it configured the node's chef-client for the Chef Server so it is easy to converge the node.

### Use mitmproxy to view HTTP traffic

Run `mitmproxy` in a terminal on the host instance.

Uncomment the `https_proxy` line in the `chef-repo/.chef/knife.rb` or in a node's `/etc/chef/client.rb` so traffic will be proxied through mitmproxy.

Run chef-client in the node or knife commands from the chef-repo directory and watch the HTTP requests appear in the mitmproxy console.

If you configured your workstation's SSH config file with LocalForward as described in dev-lxc-platform's README then you should be able to configure the web browser to use "127.0.0.1 8080" for HTTP and HTTPS proxies and watch the HTTP requests appear in the mitmproxy console.

### Manage the Cluster

The right pane of the "cluster" window should show `dev-lxc status` output. This shows the status of each server including any existing snapshots.

It is recommended that you stop the servers before restoring or creating snapshots.

```
dl halt
```

You can restore the most recent snapshot of all the servers.

```
dl sn -r
```

You could also restore a specific snapshot by name if you desire.

For example, you could restore the Chef Automate server to the state right after its package was installed but before it was configured.

```
dl sn automate -r snap0
```

You can create snapshots with or without a comment.

```
dl sn -c 'Demo snapshot'
```

You can destroy snapshots.

```
dl sn -d snap2
```

And finally you can destroy the servers and there snapshots.

```
dl d
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
