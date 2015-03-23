require "fileutils"
require "digest/sha1"
require "lxc"
require "dev-lxc/container"
require "dev-lxc/chef-server"
require "dev-lxc/chef-cluster"

module DevLXC
  def self.create_platform_container(platform_container_name)
    platform_container = DevLXC::Container.new(platform_container_name)
    if platform_container.defined?
      puts "Using existing platform container #{platform_container.name}"
      return platform_container
    end
    puts "Creating platform container #{platform_container.name}"
    case platform_container.name
    when "p-ubuntu-1004"
      platform_container.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "lucid", "-a", "amd64"])
    when "p-ubuntu-1204"
      platform_container.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "precise", "-a", "amd64"])
    when "p-ubuntu-1404"
      platform_container.create("download", "btrfs", {}, 0, ["-d", "ubuntu", "-r", "trusty", "-a", "amd64"])
    when "p-centos-5"
      platform_container.create("centos", "btrfs", {}, 0, ["-R", "5"])
    when "p-centos-6"
      platform_container.create("download", "btrfs", {}, 0, ["-d", "centos", "-r", "6", "-a", "amd64"])
    end
    unless platform_container.config_item("lxc.mount.auto").nil?
      platform_container.set_config_item("lxc.mount.auto", "proc:rw sys:rw")
    end
    hwaddr = '00:16:3e:' + Digest::SHA1.hexdigest(Time.now.to_s).slice(0..5).unpack('a2a2a2').join(':')
    puts "Setting #{platform_container.name} platform container's lxc.network.0.hwaddr to #{hwaddr}"
    platform_container.set_config_item("lxc.network.0.hwaddr", hwaddr)
    platform_container.save_config
    platform_container.start
    puts "Installing packages in platform container #{platform_container.name}"
    case platform_container.name
    when "p-ubuntu-1004"
      # Disable certain sysctl.d files in Ubuntu 10.04, they cause `start procps` to fail
      if File.exist?("#{platform_container.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf")
        FileUtils.mv("#{platform_container.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf",
                     "#{platform_container.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf.orig")
      end
      platform_container.run_command("apt-get update")
      platform_container.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox curl tree")
    when "p-ubuntu-1204", "p-ubuntu-1404"
      platform_container.run_command("apt-get update")
      platform_container.run_command("apt-get install -y standard^ server^ vim-nox emacs23-nox tree")
    when "p-centos-5"
      # downgrade openssl temporarily to overcome an install bug
      # reference: http://www.hack.net.br/blog/2014/02/12/openssl-conflicts-with-file-from-package-openssl/
      platform_container.run_command("yum downgrade -y openssl")
      platform_container.run_command("yum install -y @base @core vim-enhanced emacs-nox tree")
    when "p-centos-6"
      platform_container.run_command("yum install -y @base @core vim-enhanced emacs-nox tree")
    end
    platform_container.stop
    return platform_container
  end

  def self.assign_ip_address(ipaddress, container_name, hwaddr)
    puts "Assigning IP address #{ipaddress} to #{container_name} container's lxc.network.hwaddr #{hwaddr}"
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
