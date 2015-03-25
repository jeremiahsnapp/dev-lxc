require "dev-lxc/container"
require "dev-lxc/chef-cluster"

module DevLXC
  class ChefServer
    attr_reader :role, :server, :platform_container_name, :shared_container_name

    def initialize(name, cluster_config)
      unless cluster_config["servers"].keys.include?(name)
        raise "Server #{name} is not defined in the cluster config"
      end
      cluster = DevLXC::ChefCluster.new(cluster_config)
      @server = DevLXC::Container.new(name)
      @config = cluster_config["servers"][@server.name]
      @ipaddress = @config["ipaddress"]
      @role = @config["role"] ? @config["role"] : cluster_config['topology']
      @mounts = cluster_config["mounts"]
      @bootstrap_backend = cluster.bootstrap_backend
      @chef_server_config = cluster.chef_server_config
      @api_fqdn = cluster_config["api_fqdn"]
      @analytics_fqdn = cluster_config["analytics_fqdn"]
      @platform_container_name = cluster_config["platform_container"]
      @packages = cluster_config["packages"]

      if File.basename(@packages["server"]).match(/^(\w+-\w+.*)[_-]((?:\d+\.?){3,})/)
        @chef_server_type = Regexp.last_match[1]
        @chef_server_version = Regexp.last_match[2].gsub(".", "-")
      end

      if @role == 'analytics'
        @shared_container_name = "s#{@platform_container_name[1..-1]}"
        @shared_container_name += "-analytics-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["analytics"].to_s.match(/[_-]((\d+\.?){3,})/)
      else
        @shared_container_name = "s#{@platform_container_name[1..-1]}"
        case @chef_server_type
        when 'chef-server-core'
          @shared_container_name += '-cs'
          @server_ctl = 'chef-server'
        when 'private-chef'
          @shared_container_name += '-ec'
          @server_ctl = 'private-chef'
        when 'chef-server'
          @shared_container_name += '-osc'
          @server_ctl = 'chef-server'
        end
        @shared_container_name += "-#{@chef_server_version}"
        @shared_container_name += "-reporting-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["reporting"].to_s.match(/[_-]((\d+\.?){3,})/)
        @shared_container_name += "-pushy-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["push-jobs-server"].to_s.match(/[_-]((\d+\.?){3,})/)
        @shared_container_name += "-sync-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["sync"].to_s.match(/[_-]((\d+\.?){3,})/)
      end
    end

    def status
      if @server.defined?
        state = @server.state
        ip_addresses = @server.ip_addresses.join(" ") if @server.state == :running
      else
        state = "not_created"
      end
      printf "%25s     %-15s %s\n", @server.name, state, ip_addresses
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
      DevLXC.create_dns_record(@analytics_fqdn, @server.name, @ipaddress) if @role == 'analytics'
      DevLXC.create_dns_record(@api_fqdn, @server.name, @ipaddress) if %w(open-source standalone frontend).include?(@role)
      @server.sync_mounts(@mounts)
      @server.start
    end

    def stop
      hwaddr = @server.config_item("lxc.network.0.hwaddr") if @server.defined?
      @server.stop
      deregister_from_dnsmasq(hwaddr)
    end

    def snapshot(force=nil)
      unless @server.defined?
        puts "WARNING: Skipping snapshot of '#{@server.name}' because it is not created"
        return
      end
      if @server.state != :stopped
        puts "WARNING: Skipping snapshot of '#{@server.name}' because it is not stopped"
        return
      end
      custom_container = DevLXC::Container.new("c-#{@server.name}")
      if custom_container.defined?
        if force
          custom_container.destroy
        else
          puts "WARNING: Skipping snapshot of '#{@server.name}' because a custom base container already exists"
          return
        end
      end
      puts "Cloning container #{@server.name} into custom container #{custom_container.name}"
      @server.clone("#{custom_container.name}", {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
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

    def destroy_container(type)
      case type
      when :custom
        DevLXC::Container.new("c-#{@server.name}").destroy
      when :unique
        DevLXC::Container.new("u-#{@server.name}").destroy
      when :shared
        DevLXC::Container.new(@shared_container_name).destroy
      when :platform
        DevLXC::Container.new(@platform_container_name).destroy
      end
    end

    def create
      if @server.defined?
        puts "Using existing container #{@server.name}"
        return
      end
      custom_container = DevLXC::Container.new("c-#{@server.name}")
      unique_container = DevLXC::Container.new("u-#{@server.name}")
      if custom_container.defined?
        puts "Cloning custom container #{custom_container.name} into container #{@server.name}"
        custom_container.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
        @server = DevLXC::Container.new(@server.name)
        return
      elsif unique_container.defined?
        puts "Cloning unique container #{unique_container.name} into container #{@server.name}"
        unique_container.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
        @server = DevLXC::Container.new(@server.name)
        return
      else
        puts "Creating container #{@server.name}"
        unless @server.name == @bootstrap_backend || DevLXC::Container.new(@bootstrap_backend).defined?
          raise "The bootstrap backend server must be created first."
        end
        shared_container = create_shared_container
        puts "Cloning shared container #{shared_container.name} into container #{@server.name}"
        shared_container.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
        @server = DevLXC::Container.new(@server.name)
        puts "Adding lxc.hook.post-stop hook"
        @server.set_config_item("lxc.hook.post-stop", "/usr/local/share/lxc/hooks/post-stop-dhcp-release")
        @server.save_config
        hwaddr = @server.config_item("lxc.network.0.hwaddr")
        raise "#{@server.name} needs to have an lxc.network.hwaddr entry" if hwaddr.empty?
        DevLXC.assign_ip_address(@ipaddress, @server.name, hwaddr)
        DevLXC.create_dns_record(@analytics_fqdn, @server.name, @ipaddress) if @role == 'analytics'
        DevLXC.create_dns_record(@api_fqdn, @server.name, @ipaddress) if %w(open-source standalone frontend).include?(@role)
        @server.sync_mounts(@mounts)
        @server.start
        configure_analytics if @role == 'analytics'
        unless @role == 'analytics' || @packages["server"].nil?
          configure_server
          create_users if @server.name == @bootstrap_backend
          if %w(standalone frontend).include?(@role) && ! @packages["manage"].nil?
            @server.install_package(@packages["manage"])
            configure_manage
          end
          if %w(standalone backend frontend).include?(@role)
            configure_reporting unless @packages["reporting"].nil?
            configure_push_jobs_server unless @packages["push-jobs-server"].nil?
            configure_chef_server_for_analytics unless ! %w(standalone backend).include?(@role) || @packages["analytics"].nil?
          end
        end
        @server.stop
        puts "Cloning container #{@server.name} into unique container #{unique_container.name}"
        @server.clone("#{unique_container.name}", {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
      end
    end

    def create_shared_container
      shared_container = DevLXC::Container.new(@shared_container_name)
      if shared_container.defined?
        puts "Using existing shared container #{shared_container.name}"
        return shared_container
      end
      platform_container = DevLXC.create_platform_container(@platform_container_name)
      puts "Cloning platform container #{platform_container.name} into shared container #{shared_container.name}"
      platform_container.clone(shared_container.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
      shared_container = DevLXC::Container.new(shared_container.name)

      # Disable certain sysctl.d files in Ubuntu 10.04, they cause `start procps` to fail
      # Enterprise Chef server's postgresql recipe expects to be able to `start procps`
      if platform_container.name == "p-ubuntu-1004"
        if File.exist?("#{shared_container.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf")
          FileUtils.mv("#{shared_container.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf",
                       "#{shared_container.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf.orig")
        end
      end
      unless shared_container.config_item("lxc.mount.auto").nil?
        shared_container.set_config_item("lxc.mount.auto", "proc:rw sys:rw")
        shared_container.save_config
      end
      shared_container.sync_mounts(@mounts)
      shared_container.start
      if @role == 'analytics'
        shared_container.install_package(@packages["analytics"]) unless @packages["analytics"].nil?
      else
        shared_container.install_package(@packages["server"]) unless @packages["server"].nil?
        shared_container.install_package(@packages["reporting"]) unless @packages["reporting"].nil?
        shared_container.install_package(@packages["push-jobs-server"]) unless @packages["push-jobs-server"].nil?
        shared_container.install_package(@packages["sync"]) unless @packages["sync"].nil?
      end
      shared_container.stop
      return shared_container
    end

    def configure_server
      case @role
      when "open-source"
        puts "Creating /etc/chef-server/chef-server.rb"
        FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/etc/chef-server")
        IO.write("#{@server.config_item('lxc.rootfs')}/etc/chef-server/chef-server.rb", @chef_server_config)
        run_ctl(@server_ctl, "reconfigure")
      when "standalone", "backend"
        case @chef_server_type
        when 'private-chef'
          puts "Creating /etc/opscode/private-chef.rb"
          FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/etc/opscode")
          IO.write("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", @chef_server_config)
        when 'chef-server-core'
          puts "Creating /etc/opscode/chef-server.rb"
          FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/etc/opscode")
          IO.write("#{@server.config_item('lxc.rootfs')}/etc/opscode/chef-server.rb", @chef_server_config)
        end
        run_ctl(@server_ctl, "reconfigure")
      when "frontend"
        puts "Copying /etc/opscode from bootstrap backend"
        FileUtils.cp_r("#{LXC::Container.new(@bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode",
                       "#{@server.config_item('lxc.rootfs')}/etc")
        run_ctl(@server_ctl, "reconfigure")
      end
    end

    def configure_reporting
      if @role == 'frontend'
        puts "Copying /etc/opscode-reporting from bootstrap backend"
        FileUtils.cp_r("#{LXC::Container.new(@bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode-reporting",
                       "#{@server.config_item('lxc.rootfs')}/etc")
      end
      run_ctl(@server_ctl, "reconfigure")
      run_ctl("opscode-reporting", "reconfigure")
    end

    def configure_push_jobs_server
      run_ctl("opscode-push-jobs-server", "reconfigure")
      run_ctl(@server_ctl, "reconfigure")
    end

    def configure_manage
      if @chef_server_type == 'private-chef'
        puts "Disabling old opscode-webui in /etc/opscode/private-chef.rb"
        DevLXC.search_file_delete_line("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", /opscode_webui[.enable.]/)
        DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", "\nopscode_webui['enable'] = false\n")
        run_ctl(@server_ctl, "reconfigure")
      end
      run_ctl("opscode-manage", "reconfigure")
    end

    def configure_chef_server_for_analytics
      puts "Configuring for Analytics"
      case @chef_server_type
      when 'private-chef'
        DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb",
          "\noc_id['applications'] = {\n  'analytics' => {\n    'redirect_uri' => 'https://#{@analytics_fqdn}/'\n  }\n}\n")

        DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb",
          "\nrabbitmq['vip'] = '#{@bootstrap_backend}'\nrabbitmq['node_ip_address'] = '0.0.0.0'\n")
      when 'chef-server-core'
        DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/chef-server.rb",
          "\noc_id['applications'] = {\n  'analytics' => {\n    'redirect_uri' => 'https://#{@analytics_fqdn}/'\n  }\n}\n")

        DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/chef-server.rb",
          "\nrabbitmq['vip'] = '#{@bootstrap_backend}'\nrabbitmq['node_ip_address'] = '0.0.0.0'\n")
      end

      run_ctl(@server_ctl, "stop")
      run_ctl(@server_ctl, "reconfigure")
      run_ctl(@server_ctl, "restart")
      run_ctl("opscode-manage", "reconfigure") if @role == 'frontend'
    end

    def configure_analytics
      puts "Copying /etc/opscode-analytics from Chef Server bootstrap backend"
      FileUtils.cp_r("#{LXC::Container.new(@bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode-analytics",
                     "#{@server.config_item('lxc.rootfs')}/etc")

      IO.write("#{@server.config_item('lxc.rootfs')}/etc/opscode-analytics/opscode-analytics.rb",
        "analytics_fqdn '#{@analytics_fqdn}'\ntopology 'standalone'\n")

      run_ctl("opscode-analytics", "reconfigure")
    end

    def run_ctl(component, subcommand)
      puts "Running `#{component}-ctl #{subcommand}` in #{@server.name}"
      @server.run_command("#{component}-ctl #{subcommand}")
    end

    def create_users
      puts "Creating org, user, keys and knife.rb in /root/chef-repo/.chef"
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef")

      case @chef_server_type
      when 'chef-server'
        chef_server_url = "https://127.0.0.1"
        username = "admin"
        validator_name = "chef-validator"

        FileUtils.cp( Dir.glob("#{@server.config_item('lxc.rootfs')}/etc/chef-server/{admin,chef-validator}.pem"), "#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef" )
      when 'private-chef'
        chef_server_url = "https://127.0.0.1/organizations/ponyville"
        username = "rainbowdash"
        validator_name = "ponyville-validator"

        # give time for all services to come up completely
        sleep 60
        pivotal_rb = %Q(
chef_server_root "https://127.0.0.1/"
chef_server_url "https://127.0.0.1/"

node_name "pivotal"
client_key "/etc/opscode/pivotal.pem"

knife[:chef_repo_path] = Dir.pwd
)
        IO.write("#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef/pivotal.rb", pivotal_rb)
        @server.run_command("/opt/opscode/embedded/bin/gem install knife-opc --no-ri --no-rdoc")
        @server.run_command("/opt/opscode/embedded/bin/knife opc org create ponyville ponyville --filename /root/chef-repo/.chef/ponyville-validator.pem -c /root/chef-repo/.chef/pivotal.rb")
        @server.run_command("/opt/opscode/embedded/bin/knife opc user create rainbowdash rainbowdash rainbowdash rainbowdash@noreply.com rainbowdash --filename /root/chef-repo/.chef/rainbowdash.pem -c /root/chef-repo/.chef/pivotal.rb")
        @server.run_command("/opt/opscode/embedded/bin/knife opc org user add ponyville rainbowdash --admin -c /root/chef-repo/.chef/pivotal.rb")
      when 'chef-server-core'
        chef_server_url = "https://127.0.0.1/organizations/ponyville"
        username = "rainbowdash"
        validator_name = "ponyville-validator"

        # give time for all services to come up completely
        sleep 10
        run_ctl(@server_ctl, "org-create ponyville ponyville --filename /root/chef-repo/.chef/ponyville-validator.pem")
        run_ctl(@server_ctl, "user-create rainbowdash rainbowdash rainbowdash rainbowdash@noreply.com rainbowdash --filename /root/chef-repo/.chef/rainbowdash.pem")
        run_ctl(@server_ctl, "org-user-add ponyville rainbowdash --admin")
      end
      knife_rb = %Q(
current_dir = File.dirname(__FILE__)

chef_server_url "#{chef_server_url}"

node_name "#{username}"
client_key "\#{current_dir}/#{username}.pem"

validation_client_name "#{validator_name}"
validation_key "\#{current_dir}/#{validator_name}.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd
)
      IO.write("#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef/knife.rb", knife_rb)
    end
  end
end
