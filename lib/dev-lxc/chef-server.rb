require "dev-lxc/container"
require "dev-lxc/chef-cluster"

module DevLXC
  class ChefServer
    attr_reader :base_platform, :base_server_name

    def initialize(name, cluster_config)
      unless cluster_config["servers"].keys.include?(name)
        raise "Server #{name} is not defined in the cluster config"
      end
      cluster = DevLXC::ChefCluster.new(cluster_config)
      @server = DevLXC::Container.new(name)
      @config = cluster_config["servers"][@server.name]
      @ipaddress = @config["ipaddress"]
      case cluster.topology
      when "open-source", "standalone"
        @role = cluster.topology
      when "tier", "ha"
        @role = "bootstrap_backend" if @server.name == cluster.bootstrap_backend
        @role = "secondary_backend" if @server.name == cluster.secondary_backend
        @role = "frontend" if cluster.frontends.include?(@server.name)
      end
      @mounts = cluster_config["mounts"]
      @bootstrap_backend = cluster.bootstrap_backend
      @chef_server_config = cluster.chef_server_config
      @api_fqdn = cluster.api_fqdn
      @base_platform = cluster_config["base_platform"]
      @packages = cluster_config["packages"]

      @base_server_name = @base_platform
      @base_server_name += "-ec-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["server"].to_s.match(/private-chef[_-]((\d+\.?){3,})-/)
      @base_server_name += "-osc-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["server"].to_s.match(/chef-server[_-]((\d+\.?){3,})-/)
      @base_server_name += "-reporting-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["reporting"].to_s.match(/[_-]((\d+\.?){3,})-/)
      @base_server_name += "-pushy-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["push-jobs-server"].to_s.match(/[_-]((\d+\.?){3,})-/)
    end

    def status
      if @server.defined?
        state = @server.state
        ip_addresses = @server.ip_addresses.join(" ") if @server.state == :running
      else
        state = "not_created"
      end
      printf "%20s     %-15s %s\n", @server.name, state, ip_addresses
    end

    def abspath(rootfs_path)
      "#{@server.config_item('lxc.rootfs')}#{rootfs_path}" if @server.defined?
    end

    def run_command(command)
      if @server.running?
        puts "Running '#{command}' in #{@server.name}"
        @server.run_command(command)
      else
        puts "#{@server.name} is not running"
      end
    end

    def start
      create
      hwaddr = @server.config_item("lxc.network.0.hwaddr")
      DevLXC.assign_ip_address(@ipaddress, @server.name, hwaddr)
      DevLXC.create_dns_record(@api_fqdn, @server.name, @ipaddress) if %w(open-source standalone frontend).include?(@role)
      @server.sync_mounts(@mounts)
      @server.start
    end

    def stop
      hwaddr = @server.config_item("lxc.network.0.hwaddr") if @server.defined?
      @server.stop
      deregister_from_dnsmasq(hwaddr)
    end

    def destroy
      hwaddr = @server.config_item("lxc.network.0.hwaddr") if @server.defined?
      @server.destroy
      deregister_from_dnsmasq(hwaddr)
    end

    def deregister_from_dnsmasq(hwaddr)
      DevLXC.search_file_delete_line("/etc/lxc/addn-hosts.conf", /^#{@ipaddress}\s/)
      DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /,#{@ipaddress}$/)
      unless hwaddr.nil?
        DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /^#{hwaddr}/)
      end
      DevLXC.reload_dnsmasq
    end

    def destroy_base_container(type)
      case type
      when :unique
        DevLXC::Container.new("b-#{@server.name}").destroy
      when :shared
        DevLXC::Container.new(@base_server_name).destroy
      when :platform
        DevLXC::Container.new(@base_platform).destroy
      end
    end

    def create
      if @server.defined?
        puts "Using existing container #{@server.name}"
        return
      end
      server_clone = DevLXC::Container.new("b-#{@server.name}")
      if server_clone.defined?
        puts "Cloning container #{server_clone.name} into container #{@server.name}"
        server_clone.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
        @server = DevLXC::Container.new(@server.name)
        return
      else
        puts "Creating container #{@server.name}"
        unless %w(open-source standalone).include?(@role) || @server.name == @bootstrap_backend || DevLXC::Container.new(@bootstrap_backend).defined?
          raise "The bootstrap backend server must be created first."
        end
        base_server = create_base_server
        puts "Cloning container #{base_server.name} into container #{@server.name}"
        base_server.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
        @server = DevLXC::Container.new(@server.name)
        puts "Adding lxc.hook.post-stop hook"
        @server.set_config_item("lxc.hook.post-stop", "/usr/local/share/lxc/hooks/post-stop-dhcp-release")
        @server.save_config
        hwaddr = @server.config_item("lxc.network.0.hwaddr")
        raise "#{@server.name} needs to have an lxc.network.hwaddr entry" if hwaddr.empty?
        DevLXC.assign_ip_address(@ipaddress, @server.name, hwaddr)
        DevLXC.create_dns_record(@api_fqdn, @server.name, @ipaddress) if %w(open-source standalone frontend).include?(@role)
        @server.sync_mounts(@mounts)
        @server.start
        configure_server unless @packages["server"].nil?
        create_users if %w(standalone bootstrap_backend).include?(@role)
        if %w(standalone bootstrap_backend secondary_backend frontend).include?(@role)
          configure_reporting unless @packages["reporting"].nil?
          configure_push_jobs_server unless @packages["push-jobs-server"].nil?
        end
        if %w(standalone frontend).include?(@role) && ! @packages["manage"].nil?
          @server.install_package(@packages["manage"])
          configure_manage
        end
        @server.stop
        puts "Cloning container #{@server.name} into b-#{@server.name}"
        @server.clone("b-#{@server.name}", {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
      end
    end

    def create_base_server
      base_server = DevLXC::Container.new(@base_server_name)
      if base_server.defined?
        puts "Using existing container #{base_server.name}"
        return base_server
      end
      base_platform = DevLXC.create_base_platform(@base_platform)
      puts "Cloning container #{base_platform.name} into container #{base_server.name}"
      base_platform.clone(base_server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
      base_server = DevLXC::Container.new(base_server.name)

      # Rename procps in Ubuntu platforms because Enterprise Chef server < 11.0.0
      # postgres recipe will use it even though it does not work in an LXC container
      @packages["server"].to_s.match(/private-chef[_-](\d+)\.(\d+\.?){2,}-/)
      if base_platform.name.include?("ubuntu") && Regexp.last_match[1].to_i < 11
        FileUtils.mv("#{base_server.config_item('lxc.rootfs')}/etc/init.d/procps",
                     "#{base_server.config_item('lxc.rootfs')}/etc/init.d/procps.orig")
      end
      # TODO when LXC 1.0.2 is released the following test can be done using #config_item("lxc.mount.auto")
      unless IO.readlines(base_server.config_file_name).select { |line| line.start_with?("lxc.mount.auto") }.empty?
        base_server.set_config_item("lxc.mount.auto", "proc:rw sys:rw")
        base_server.save_config
      end
      base_server.sync_mounts(@mounts)
      base_server.start
      base_server.install_package(@packages["server"]) unless @packages["server"].nil?
      base_server.install_package(@packages["reporting"]) unless @packages["reporting"].nil?
      base_server.install_package(@packages["push-jobs-server"]) unless @packages["push-jobs-server"].nil?
      base_server.stop
      return base_server
    end

    def configure_server
      case @role
      when "open-source"
        puts "Creating /etc/chef-server/chef-server.rb"
        FileUtils.mkdir("#{@server.config_item('lxc.rootfs')}/etc/chef-server")
        IO.write("#{@server.config_item('lxc.rootfs')}/etc/chef-server/chef-server.rb", @chef_server_config)
        run_ctl("chef-server", "reconfigure")
      when "standalone", "bootstrap_backend"
        puts "Creating /etc/opscode/private-chef.rb"
        FileUtils.mkdir("#{@server.config_item('lxc.rootfs')}/etc/opscode")
        IO.write("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", @chef_server_config)
        run_ctl("private-chef", "reconfigure")
      when "secondary_backend", "frontend"
        puts "Copying /etc/opscode from bootstrap backend"
        FileUtils.cp_r("#{LXC::Container.new(@bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode",
                       "#{@server.config_item('lxc.rootfs')}/etc")
        run_ctl("private-chef", "reconfigure")
      end
    end

    def configure_reporting
      if %w(secondary_backend frontend).include?(@role)
        puts "Copying /etc/opscode-reporting from bootstrap backend"
        FileUtils.cp_r("#{LXC::Container.new(@bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode-reporting",
                       "#{@server.config_item('lxc.rootfs')}/etc")
      end
      run_ctl("private-chef", "reconfigure")
      run_ctl("opscode-reporting", "reconfigure")
    end

    def configure_push_jobs_server
      run_ctl("opscode-push-jobs-server", "reconfigure")
      if %w(bootstrap_backend secondary_backend).include?(@role)
        run_ctl("private-chef", "reconfigure")
      end
      run_ctl("private-chef", "restart opscode-pushy-server")
    end

    def configure_manage
      puts "Disabling old opscode-webui in /etc/opscode/private-chef.rb"
      DevLXC.search_file_delete_line("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", /opscode_webui[.enable.]/)
      DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", "\nopscode_webui['enable'] = false\n")
      run_ctl("private-chef", "reconfigure")
      run_ctl("opscode-manage", "reconfigure")
    end

    def run_ctl(component, subcommand)
      puts "Running `#{component}-ctl #{subcommand}` in #{@server.name}"
      @server.run_command("#{component}-ctl #{subcommand}")
    end

    def create_users
      puts "Creating users, keys and knife config files"
      FileUtils.mkdir_p(["#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/recipes",
                         "#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/templates/default",
                        "#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/libraries"])
      FileUtils.cp("#{File.dirname(__FILE__)}/../../files/create_users/default.rb", "#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/recipes")
      DevLXC.search_file_replace("#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/recipes/default.rb", /chef\.lxc/, @api_fqdn)
      FileUtils.cp("#{File.dirname(__FILE__)}/../../files/create_users/knife.rb.erb", "#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/templates/default")
      FileUtils.cp("#{File.dirname(__FILE__)}/../../files/create_users/create_users.rb", "#{@server.config_item('lxc.rootfs')}/cookbooks/create_users/libraries")
      IO.write("#{@server.config_item('lxc.rootfs')}/cookbooks/solo.rb", "cookbook_path '/cookbooks'")
      @server.run_command("/opt/opscode/embedded/bin/chef-solo -c /cookbooks/solo.rb -o create_users -l info")
      FileUtils.rm_r("#{@server.config_item('lxc.rootfs')}/cookbooks")
    end
  end
end
