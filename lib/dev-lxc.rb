require "fileutils"
require "digest/sha1"
require "lxc"
require "dev-lxc/container"
require "dev-lxc/server"
require "dev-lxc/cluster"

module DevLXC
  def self.create_base_container(base_container_name, base_container_options)
    base_container = DevLXC::Container.new(base_container_name)
    if base_container.defined?
      puts "Using existing base container '#{base_container.name}'"
      return base_container
    end
    puts "Creating base container '#{base_container.name}'"
    template = "download"
    case base_container.name
    when "b-ubuntu-1204"
      options = ["-d", "ubuntu", "-r", "precise", "-a", "amd64"]
    when "b-ubuntu-1404"
      options = ["-d", "ubuntu", "-r", "trusty", "-a", "amd64"]
    when "b-ubuntu-1604"
      options = ["-d", "ubuntu", "-r", "xenial", "-a", "amd64"]
    when "b-centos-5"
      template = "centos"
      options = ["-R", "5"]
    when "b-centos-6"
      options = ["-d", "centos", "-r", "6", "-a", "amd64"]
    when "b-centos-7"
      options = ["-d", "centos", "-r", "7", "-a", "amd64"]
    end
    options.concat(base_container_options.split) unless base_container_options.nil?
    base_container.create(template, "btrfs", {}, 0, options)

    # if base container is centos then `/etc/hosts` file needs to be modified so `hostname -f`
    # provides the FQDN instead of `localhost`
    if base_container.name.start_with?('b-centos-')
      IO.write("#{base_container.config_item('lxc.rootfs')}/etc/hosts", "127.0.0.1 localhost\n127.0.1.1 #{base_container.name}\n")
    end

    # Centos 7 needs setpcap capabilities
    # ref: https://bugzilla.redhat.com/show_bug.cgi?id=1176816
    # ref: https://bugs.launchpad.net/ubuntu/+source/lxc/+bug/1339781
    # ref: http://vfamilyserver.org/blog/2015/05/centos-7-lxc-container-slow-boot/
    if base_container.name == "b-centos-7"
      DevLXC.search_file_replace(base_container.config_file_name, /centos.common.conf/, 'fedora.common.conf')
      base_container.clear_config
      base_container.load_config
    end

    unless base_container.config_item("lxc.mount.auto").nil?
      base_container.set_config_item("lxc.mount.auto", "proc:rw sys:rw")
    end
    if base_container.config_item("lxc.network.0.hwaddr").nil?
      hwaddr = '00:16:3e:' + Digest::SHA1.hexdigest(Time.now.to_s).slice(0..5).unpack('a2a2a2').join(':')
      puts "Setting '#{base_container.name}' base container's lxc.network.hwaddr to #{hwaddr}"
      base_container.set_config_item("lxc.network.hwaddr", hwaddr)
    end
    base_container.save_config
    base_container.start
    puts "Installing packages in base container '#{base_container.name}'"
    case base_container.name
    when "b-ubuntu-1204", "b-ubuntu-1404"
      base_container.run_command("apt-get update")
      base_container.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox tree openssh-server")
      IO.write("#{base_container.config_item('lxc.rootfs')}/etc/rc.local", "#!/usr/bin/env bash\n\n/usr/sbin/dpkg-reconfigure openssh-server\n")
      FileUtils.chmod(0755, "#{base_container.config_item('lxc.rootfs')}/etc/rc.local")
    when "b-ubuntu-1604"
      base_container.run_command("apt-get update")
      base_container.run_command("apt-get install -y standard^ server^ vim-nox emacs24-nox tree openssh-server")
      IO.write("#{base_container.config_item('lxc.rootfs')}/etc/rc.local", "#!/usr/bin/env bash\n\n/usr/sbin/dpkg-reconfigure openssh-server\n")
      FileUtils.chmod(0755, "#{base_container.config_item('lxc.rootfs')}/etc/rc.local")
    when "b-centos-5"
      # downgrade openssl temporarily to overcome an install bug
      # reference: http://www.hack.net.br/blog/2014/02/12/openssl-conflicts-with-file-from-package-openssl/
      base_container.run_command("yum downgrade -y openssl")
      base_container.run_command("yum install -y @base @core vim-enhanced emacs-nox tree openssh-server")
      FileUtils.mkdir_p("#{base_container.config_item('lxc.rootfs')}/etc/sudoers.d")
      FileUtils.chmod(0750, "#{base_container.config_item('lxc.rootfs')}/etc/sudoers.d")
      append_line_to_file("#{base_container.config_item('lxc.rootfs')}/etc/sudoers", "\n#includedir /etc/sudoers.d\n")
    when "b-centos-6"
      base_container.run_command("yum install -y @base @core vim-enhanced emacs-nox tree openssh-server")
    when "b-centos-7"
      base_container.run_command("yum install -y @base @core vim-enhanced emacs-nox tree openssh-server")
    end
    base_container.run_command("useradd --create-home --shell /bin/bash --password $6$q3FDMpMZ$zfahCxEWHbzuEV98QPzhGZ7fLtGcLNZrbKK7OAYGXmJXZc07WbcxVnDwrMyX/cL6vSp4/IjlrVUZFBp7Orhyu1 dev-lxc")

    FileUtils.mkdir_p("#{base_container.config_item('lxc.rootfs')}/home/dev-lxc/.ssh")
    FileUtils.chmod(0700, "#{base_container.config_item('lxc.rootfs')}/home/dev-lxc/.ssh")
    FileUtils.touch("#{base_container.config_item('lxc.rootfs')}/home/dev-lxc/.ssh/authorized_keys")
    FileUtils.chmod(0600, "#{base_container.config_item('lxc.rootfs')}/home/dev-lxc/.ssh/authorized_keys")
    base_container.run_command("chown -R dev-lxc:dev-lxc /home/dev-lxc/.ssh")

    IO.write("#{base_container.config_item('lxc.rootfs')}/etc/sudoers.d/dev-lxc", "dev-lxc   ALL=NOPASSWD:ALL\n")
    FileUtils.chmod(0440, "#{base_container.config_item('lxc.rootfs')}/etc/sudoers.d/dev-lxc")
    base_container.shutdown
    return base_container
  end

  def self.assign_ip_address(ipaddress, container_name, hwaddr)
    puts "Assigning IP address #{ipaddress} to '#{container_name}' container's lxc.network.hwaddr #{hwaddr}"
    search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /(^#{hwaddr}|,#{ipaddress}$)/)
    append_line_to_file("/etc/lxc/dhcp-hosts.conf", "#{hwaddr},#{ipaddress}\n")
    reload_dnsmasq
  end

  def self.reload_dnsmasq
    system("pkill -HUP dnsmasq")
  end

  def self.search_file_delete_line(file_name, regex)
    IO.write(file_name, IO.readlines(file_name).delete_if {|line| line.match(Regexp.new(regex))}.join)
  end

  def self.append_line_to_file(file_name, line)
    content = IO.readlines(file_name)
    content[-1] = content[-1].chomp + "\n" unless content.empty?
    content << line
    IO.write(file_name, content.join)
  end

  def self.search_file_replace(file_name, regex, replace)
    IO.write(file_name, IO.readlines(file_name).map {|line| line.gsub(Regexp.new(regex), replace)}.join)
  end
end
