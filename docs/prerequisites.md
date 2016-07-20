
#### Download and Install Prerequisites

Download and install [VirtualBox](https://www.virtualbox.org/wiki/Downloads).

Download and install [Vagrant](https://www.vagrantup.com/downloads.html).

Install the vagrant-persistent-storage plugin.

```
vagrant plugin install vagrant-persistent-storage
```

Download and install [ChefDK](http://downloads.chef.io/chef-dk/).

#### Download dev-lxc-platform

```
git clone https://github.com/jeremiahsnapp/dev-lxc-platform.git
```

#### Configure .kitchen.yml

The cpus and memory .kitchen.yml values are set high to give enough resources to comfortably run multiple containers.

Configure .kitchen.yml settings such as cpus, memory, synced_folders as desired.

#### Build the dev-lxc-platform VM

This should take less than 15 minutes.

While the VM is being created you are free to open a separate terminal and follow the remaining setup instructions.

```
cd dev-lxc-platform
kitchen converge
```

#### Enable Vagrant Control for VM

Typically we want to be able to shutdown and startup the dev-lxc-platform VM rather than use the usual kitchen model of converge and destroy so we need to enable Vagrant control over the VM for easier management.

Install [direnv](http://direnv.net/) to use the `.envrc` file included in the
dev-lxc-platform repo to automatically set `VAGRANT_CWD` upon entering the top level directory
of the dev-lxc-platform repo.

Vagrant commands run from this directory such as `vagrant up`, `vagrant ssh` and `vagrant halt` will manage the dev-lxc-platform VM.

```
brew install direnv
```

Be sure to follow the [direnv install instructions](http://direnv.net/) to add the appropriate line to your user's shell rc file.

Run the following to approve the `.envrc` file

```
direnv allow
```

#### Setup Networking

Your workstation needs to know how to resolve the .lxc domain that dev-lxc containers use.

For OS X you can run the following command.

```
sudo mkdir -p /etc/resolver
echo nameserver 10.0.3.1 | sudo tee /etc/resolver/lxc
```

Adding a route entry to the workstation enables direct communication between
the workstation and any dev-lxc container.

For OS X run the following command.

The route entry won't survive a workstation reboot. You will have to recreate it as needed.

```
sudo route -n add 10.0.3.0/24 33.33.34.13
```
