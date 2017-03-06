
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

## Byobu keybindings

Byobu makes it easy to manage multiple terminal windows and panes. You can press `F1` to get help which includes a [list of keybindings](http://manpages.ubuntu.com/manpages/wily/en/man1/byobu.1.html#contenttoc8).

`C-` refers to the keyboard's `Control` key.
`M-` refers to the keyboard's `Meta` key which is the `Alt` key on a PC keyboard and the `Option` key on an Apple keyboard.

The prefix key is set to `C-o`

Some of the keyboard shortcuts that will be most useful to you are:

* `M-Up`, `M-Down` - switch between Byobu sessions
* `M-Left`, `M-Right` - switch between windows in a session
* `shift-Left`, `shift-Right`, `shift-Up`, `shift-Down` - switch between panes in a window
  * Windows users using Conemu must first disable "Start selection with Shift+Arrow" in "Mark/Copy" under the "Keys & Macro" settings
* `C-o C-s` - synchronize panes
* `C-o z` - zoom into and out of a pane
* `C-o M-1` - evenly split panes horizontally
* `C-o M-2` - evenly split panes vertically
* `M-pageup`, `M-pagedown` - page up/down in scrollback

Note: `Shift-F2` does not create horizontal splits for Windows users. Use the `C-o |` key binding instead.

## Update dev-lxc gem

Run the following command as the instance's root user if you ever need to upgrade the dev-lxc gem inside the dev-lxc-platform instance.

```
cd dev-lxc-platform
kitchen login <ec2 or vagrant>
sudo -i
chef gem update dev-lxc
```

## dl Command and Subcommands

`dl` is the dev-lxc command line tool.

`dl` subcommands and some options can be auto-completed by pressing the `Tab` key.

You only have to type enough of a `dl` subcommand to make it unique.

For example, the following commands are equivalent:

```
dl help
dl he
```

## Display dev-lxc help

```
dl help

dl help <subcommand>
```

## Demo: Build Chef Automate Cluster

### Create Base Container

Create an Ubuntu 14.04 base container for the cluster's containers.

```
dl create b-ubuntu-1404
```

### Create Config File

Create a directory to hold the dev-lxc.yml file.

```
mkdir -p /root/clusters/automate
```

The following command creates a dev-lxc.yml file that defines a standalone Chef Server, Supermarket server, Compliance server,
Chef Automate server a Job Dispatch Runner and an infrastructure node.

```
dl init --chef --compliance --supermarket --automate --runners --nodes > /root/clusters/automate/dev-lxc.yml
```

Copy your delivery.license file to the `/root/clusters` directory.

### cluster-view

Run the `cluster-view` command to create a Byobu (tmux) session specifically for this cluster.

```
cluster-view /root/clusters/automate
```

The session's first window is named "cluster".

The left pane is useful for running dev-lxc commands.

The right pane updates every 0.5 seconds with the cluster's status provided by `dl status`.

The session's second window is named "shell". It opens in the same directory as the
cluster's `dev-lxc.yml` file and is useful for attaching to a server to perform system administration tasks.

See the [usage docs](docs/usage.md) for more information about how to close/kill Byobu sessions.

### Build the Cluster

```
dl up
```

### Use the Servers

At this point all of the cluster's servers should be running.

Since the cluster has a Chef Server and an infrastructure node dev-lxc made sure it configured the node's chef-client for the Chef Server so it is easy to converge the node.

You can use the `attach` subcommand to login to the root user of a server. For example, the following commands should attach to node-1.lxc, start a chef-client run and exit the node.

```
dl attach node
chef-client
exit
```

Since the cluster has a Chef Server you can use the `chef-repo` subcommand to create a `.chef` directory in the host instance that contains a knife.rb and all of the keys for the users and org validator clients that are defined in dev-lxc.yml. This makes it very easy to use tools such as knife or berkshelf.

```
dl chef-repo
# set `username` to `mary-admin` and `orgname` to `demo` in `.chef/knife.rb`
knife client list
```

Since the cluster has a Chef Automate server you can use the `print-automate-credentials` subcommand to see the login credentials.

```
dl print
```

If you enabled dynamic forwarding (SOCKS v5) in your workstation's SSH config file and configured a web browser to use the SOCKS v5 proxy as described in the dev-lxc-platform README.md then you should be able to browse from your workstation to any server that has a web interface using its FQDN. For example, browse to https://automate.lxc and login with the credentials that you just displayed in the previous step.

### Manage the Cluster

The right pane of the "cluster" window should show `dl status` output. This shows the status of each server including any existing snapshots.

It is recommended that you stop the servers before restoring or creating snapshots.

```
dl halt
```

You can restore the most recent snapshot of all the servers.

```
dl snapshot -r
```

You could also restore a specific snapshot by name if you desire.

For example, you could restore the Chef Automate server to the state right after its package was installed but before it was configured.

```
dl snapshot automate -r snap0
```

You can create snapshots with or without a comment.

```
dl snapshot -c 'Demo snapshot'
```

You can destroy snapshots.

```
dl snapshot -d snap2
```

Generally speaking, a cluster can be reused for a long time especially since snapshots easily allow you to restore the cluster to its initial build state. However, if you really want to destroy the servers and their snapshots you can use the `destroy` subcommand.

```
dl destroy
```

## More Documentation

For more in-depth documentation please see the pages in the [docs folder](docs).

## Example dev-lxc.yml files

See the files in [example-clusters](example-clusters).

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
