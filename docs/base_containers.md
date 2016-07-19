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
