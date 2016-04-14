require "fileutils"
require "digest/sha1"
require "lxc"
require "dev-lxc/container"
require "dev-lxc/server"
require "dev-lxc/cluster"

module DevLXC
  def self.create_platform_image(platform_image_name, lxc_config_path='/var/lib/lxc')
    platform_image = DevLXC::Container.new(platform_image_name, lxc_config_path)
    if platform_image.defined?
      puts "Using existing platform image '#{platform_image.name}'"
      return platform_image
    end
    puts "Creating platform image '#{platform_image.name}'"
    case platform_image.name
    when "p-ubuntu-1004"
      platform_image.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "lucid", "-a", "amd64"])
    when "p-ubuntu-1204"
      platform_image.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "precise", "-a", "amd64"])
    when "p-ubuntu-1404"
      platform_image.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "trusty", "-a", "amd64"])
    when "p-ubuntu-1504"
      platform_image.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "vivid", "-a", "amd64"])
    when "p-centos-5"
      platform_image.create("centos", "btrfs", {}, 0, ["-R", "5"])
    when "p-centos-6"
      platform_image.create("download", "btrfs", {}, 0, ["-d", "centos", "-r", "6", "-a", "amd64"])
    when "p-centos-7"
      platform_image.create("download", "btrfs", {}, 0, ["-d", "centos", "-r", "7", "-a", "amd64"])
      # Centos 7 needs setpcap capabilities
      # ref: https://bugzilla.redhat.com/show_bug.cgi?id=1176816
      # ref: https://bugs.launchpad.net/ubuntu/+source/lxc/+bug/1339781
      # ref: http://vfamilyserver.org/blog/2015/05/centos-7-lxc-container-slow-boot/
      DevLXC.search_file_replace(platform_image.config_file_name, /centos.common.conf/, 'fedora.common.conf')
      platform_image.clear_config
      platform_image.load_config
    end
    unless platform_image.config_item("lxc.mount.auto").nil?
      platform_image.set_config_item("lxc.mount.auto", "proc:rw sys:rw")
    end
    if platform_image.config_item("lxc.network.0.hwaddr").nil?
      hwaddr = '00:16:3e:' + Digest::SHA1.hexdigest(Time.now.to_s).slice(0..5).unpack('a2a2a2').join(':')
      puts "Setting '#{platform_image.name}' platform image's lxc.network.hwaddr to #{hwaddr}"
      platform_image.set_config_item("lxc.network.hwaddr", hwaddr)
    end
    platform_image.save_config
    platform_image.start
    puts "Installing packages in platform image '#{platform_image.name}'"
    case platform_image.name
    when "p-ubuntu-1004"
      # Disable certain sysctl.d files in Ubuntu 10.04, they cause `start procps` to fail
      if File.exist?("#{platform_image.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf")
        FileUtils.mv("#{platform_image.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf",
                     "#{platform_image.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf.orig")
      end
      platform_image.run_command("apt-get update")
      platform_image.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox curl tree openssh-server")
      IO.write("#{platform_image.config_item('lxc.rootfs')}/etc/rc.local", "#!/usr/bin/env bash\n\n/usr/sbin/dpkg-reconfigure openssh-server\n")
      FileUtils.chmod(0755, "#{platform_image.config_item('lxc.rootfs')}/etc/rc.local")
    when "p-ubuntu-1204", "p-ubuntu-1404"
      platform_image.run_command("apt-get update")
      platform_image.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox tree openssh-server")
      IO.write("#{platform_image.config_item('lxc.rootfs')}/etc/rc.local", "#!/usr/bin/env bash\n\n/usr/sbin/dpkg-reconfigure openssh-server\n")
      FileUtils.chmod(0755, "#{platform_image.config_item('lxc.rootfs')}/etc/rc.local")
    when "p-ubuntu-1504"
      platform_image.run_command("apt-get update")
      # install policykit-1 first Ref: https://bugs.launchpad.net/ubuntu/+source/policykit-1/+bug/1447654/
      platform_image.run_command("apt-get install -y policykit-1")
      platform_image.run_command("apt-get install -y standard^ server^ vim-nox emacs24-nox tree openssh-server")
      IO.write("#{platform_image.config_item('lxc.rootfs')}/etc/rc.local", "#!/usr/bin/env bash\n\n/usr/sbin/dpkg-reconfigure openssh-server\n")
      FileUtils.chmod(0755, "#{platform_image.config_item('lxc.rootfs')}/etc/rc.local")
    when "p-centos-5"
      # downgrade openssl temporarily to overcome an install bug
      # reference: http://www.hack.net.br/blog/2014/02/12/openssl-conflicts-with-file-from-package-openssl/
      platform_image.run_command("yum downgrade -y openssl")
      platform_image.run_command("yum install -y @base @core vim-enhanced emacs-nox tree openssh-server")
      FileUtils.mkdir_p("#{platform_image.config_item('lxc.rootfs')}/etc/sudoers.d")
      FileUtils.chmod(0750, "#{platform_image.config_item('lxc.rootfs')}/etc/sudoers.d")
      append_line_to_file("#{platform_image.config_item('lxc.rootfs')}/etc/sudoers", "\n#includedir /etc/sudoers.d\n")
    when "p-centos-6"
      platform_image.run_command("yum install -y @base @core vim-enhanced emacs-nox tree openssh-server")
    when "p-centos-7"
      platform_image.run_command("yum install -y @base @core vim-enhanced emacs-nox tree openssh-server")
    end
    platform_image.run_command("useradd --create-home --shell /bin/bash --password $6$q3FDMpMZ$zfahCxEWHbzuEV98QPzhGZ7fLtGcLNZrbKK7OAYGXmJXZc07WbcxVnDwrMyX/cL6vSp4/IjlrVUZFBp7Orhyu1 dev-lxc")

    FileUtils.mkdir_p("#{platform_image.config_item('lxc.rootfs')}/home/dev-lxc/.ssh")
    FileUtils.chmod(0700, "#{platform_image.config_item('lxc.rootfs')}/home/dev-lxc/.ssh")
    FileUtils.touch("#{platform_image.config_item('lxc.rootfs')}/home/dev-lxc/.ssh/authorized_keys")
    FileUtils.chmod(0600, "#{platform_image.config_item('lxc.rootfs')}/home/dev-lxc/.ssh/authorized_keys")
    platform_image.run_command("chown -R dev-lxc:dev-lxc /home/dev-lxc/.ssh")

    IO.write("#{platform_image.config_item('lxc.rootfs')}/etc/sudoers.d/dev-lxc", "dev-lxc   ALL=NOPASSWD:ALL\n")
    FileUtils.chmod(0440, "#{platform_image.config_item('lxc.rootfs')}/etc/sudoers.d/dev-lxc")
    platform_image.stop
    return platform_image
  end

  def self.assign_ip_address(ipaddress, container_name, hwaddr)
    puts "Assigning IP address #{ipaddress} to '#{container_name}' container's lxc.network.hwaddr #{hwaddr}"
    search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /(^#{hwaddr}|,#{ipaddress}$)/)
    append_line_to_file("/etc/lxc/dhcp-hosts.conf", "#{hwaddr},#{ipaddress}\n")
    reload_dnsmasq
  end

  def self.create_dns_record(api_fqdn, container_name, ipaddress)
    dns_record = "#{ipaddress} #{container_name} #{api_fqdn}\n"
    puts "Creating DNS record: #{dns_record}"
    search_file_delete_line("/etc/lxc/addn-hosts.conf", /^#{ipaddress}\s/)
    append_line_to_file("/etc/lxc/addn-hosts.conf", dns_record)
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
