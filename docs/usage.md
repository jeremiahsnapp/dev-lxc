## Usage

### dl Command and Subcommands

`dl` is the dev-lxc command line tool.

`dev-lxc` subcommands and some options can be auto-completed by pressing the `Tab` key.

You only have to type enough of a `dev-lxc` subcommand to make it unique.

For example, the following commands are equivalent:

```
dl help
dl he
```

### Display dev-lxc help

```
dl help

dl help <subcommand>
```

### Configure a cluster

See the [configuration docs](docs/configuration.md) to learn how to use the `dl init` command to create and configure a `dev-lxc.yml` file.

### cluster-view, tks, tls commands

The dev-lxc-platform comes with some commands that create and manage helpful
tmux/byobu sessions to more easily see the state of a cluster.

Running the `cluster-view` command in the same directory as a `dev-lxc.yml` file
creates a tmux/byobu session with the same name as the cluster's directory.

`cluster-view` can also be run with the parent directory of a `dev-lxc.yml` file
as the first argument and `cluster-view` will change to that directory before
creating the tmux/byobu session.

The session's first window is named "cluster".

The left side is for running dev-lxc commands.

The right side updates every 0.5 seconds with the cluster's status provided by `dl status`.

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

### Cluster status

Run the following command to see the status of the cluster.

```
dl status
```

This is an example of the output.

```
chef.lxc            NOT_CREATED

analytics.lxc       NOT_CREATED

supermarket.lxc     NOT_CREATED

node-1.lxc          NOT_CREATED
```

### Specifying a Subset of Servers

Many dev-lxc subcommands can act on a subset of the cluster's servers by specifying a regular expression that matches the desired server names.

For example, the following command will show the status of the Chef Server.

```
dl status chef
```

### Start cluster

Starting the cluster the first time takes awhile since it has a lot to download and build.

```
dl up
```

A test org, users, knife.rb and keys are automatically created in
the bootstrap backend server in `/root/chef-repo/.chef` for testing purposes.

The `knife-opc` plugin is installed in the embedded ruby environment of the
Private Chef and Enterprise Chef server to facilitate the creation of the test
org and user.

Note: You also have the option of running the `prepare-product-cache` subcommand which downloads required product packages to the cache.  
This can be helpful when you don't want to start building the cluster yet but you want the package cache ready when you build the cluster later.

```
dl prepare-product-cache
```

### Print Chef Automate Credentials

If the cluster has a Chef Automate server you can use the `print-automate-credentials` subcommand to see what the login credentials.

```
dl print-automate-credentials
```

### Create chef-repo

Create a `.chef` directory in the current directory with appropriate knife.rb and pem files.

Use the `-p` option to also get pivotal.pem and pivotal.rb files.

Use the `-f` option to overwrite existing knife.rb and pivotal.rb files.

```
dl chef-repo
```

Now you can easily use knife to access the cluster.

```
knife client list
```

### Stop and start the cluster

```
dl halt
dl up
```

### Run arbitrary commands in each server

```
dl run-command chef 'uptime'
```

### Attach the terminal to a server

Attach the terminal to a server in the cluster that matches the REGEX pattern given.

```
dl attach chef
```

### Create a snapshot of the servers

Save the changes in the servers to snapshots with a comment.

```
dl halt
dl snapshot -c 'this is a snapshot comment'
```

### List snapshots

```
dl snapshot -l
```

### Restore snapshots

Restore snapshots by name.

Leave out the snapshot name or specify `LAST` to restore the most recent snapshot.

```
dl snapshot -r
dl up
```

### Destroy snapshots

Destroy snapshots by name or destroy all snapshots by specifying `ALL`.

Leave out the snapshot name or specify `LAST` to destroy the most recent snapshots.

```
dl snapshot -d
```

### Destroy cluster

Use the following command to destroy the cluster's servers.

```
dl destroy
```

### Show Calculated Configuration

Mostly for debugging purposes you have the ability to print the calculated cluster configuration.

```
dl show-config
```
