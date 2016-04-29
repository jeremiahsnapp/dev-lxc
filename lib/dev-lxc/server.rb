require "json"
require "dev-lxc/container"
require "dev-lxc/cluster"

module DevLXC
  class Server
    attr_reader :server, :platform_image_name, :platform_image_options, :shared_image_name

    def initialize(name, server_type, cluster_config)
      unless cluster_config[server_type]["servers"].keys.include?(name)
        puts "ERROR: Server '#{name}' is not defined in the cluster config"
        exit 1
      end
      @server_type = server_type
      cluster = DevLXC::Cluster.new(cluster_config)
      @lxc_config_path = cluster.lxc_config_path
      @api_fqdn = cluster.api_fqdn
      @analytics_fqdn = cluster.analytics_fqdn
      @compliance_fqdn = cluster.compliance_fqdn
      @supermarket_fqdn = cluster.supermarket_fqdn
      @chef_server_bootstrap_backend = cluster.chef_server_bootstrap_backend
      @analytics_bootstrap_backend = cluster.analytics_bootstrap_backend
      @chef_server_config = cluster.chef_server_config
      @analytics_config = cluster.analytics_config

      @server = DevLXC::Container.new(name, @lxc_config_path)
      @config = cluster_config[@server_type]["servers"][@server.name]
      @ipaddress = @config["ipaddress"]
      @role = @config["role"]
      @role ||= cluster_config[@server_type]['topology']
      @role ||= 'standalone'
      @mounts = cluster_config[@server_type]["mounts"]
      @mounts ||= cluster_config["mounts"]
      @ssh_keys = cluster_config[@server_type]["ssh-keys"]
      @ssh_keys ||= cluster_config["ssh-keys"]
      @platform_image_name = cluster_config[@server_type]["platform_image"]
      @platform_image_name ||= cluster_config["platform_image"]
      @platform_image_options = cluster_config[@server_type]["platform_image_options"]
      @platform_image_options ||= cluster_config["platform_image_options"]
      @packages = cluster_config[@server_type]["packages"]

      case @server_type
      when 'adhoc', 'compliance', 'supermarket'
        @shared_image_name = ''
      when 'analytics'
        @shared_image_name = "s#{@platform_image_name[1..-1]}"
        @shared_image_name += "-analytics-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["analytics"].to_s.match(/[_-]((\d+\.?){3,})/)
      when 'chef-server'
        if File.basename(@packages["server"]).match(/^(\w+-\w+.*)[_-]((?:\d+\.?){3,})/)
          @chef_server_type = Regexp.last_match[1]
          @chef_server_version = Regexp.last_match[2].gsub(".", "-")
        end

        @shared_image_name = "s#{@platform_image_name[1..-1]}"
        case @chef_server_type
        when 'chef-server-core'
          @shared_image_name += '-cs'
          @server_ctl = 'chef-server'
        when 'private-chef'
          @shared_image_name += '-ec'
          @server_ctl = 'private-chef'
        when 'chef-server'
          @shared_image_name += '-osc'
          @server_ctl = 'chef-server'
        end
        @shared_image_name += "-#{@chef_server_version}"
        @shared_image_name += "-reporting-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["reporting"].to_s.match(/[_-]((\d+\.?){3,})/)
        @shared_image_name += "-pushy-#{Regexp.last_match[1].gsub(".", "-")}" if @packages["push-jobs-server"].to_s.match(/[_-]((\d+\.?){3,})/)
      end
    end

    def realpath(rootfs_path)
      "#{@server.config_item('lxc.rootfs')}#{rootfs_path}" if @server.defined?
    end

    def run_command(command)
      if @server.running?
        puts "Running '#{command}' in '#{@server.name}'"
        @server.run_command(command)
      else
        puts "'#{@server.name}' is not running"
      end
    end

    def start
      create
      hwaddr = @server.config_item("lxc.network.0.hwaddr")
      DevLXC.assign_ip_address(@ipaddress, @server.name, hwaddr)
      unless @role == 'backend'
        case @server_type
        when 'analytics'
          DevLXC.create_dns_record(@analytics_fqdn, @server.name, @ipaddress)
        when 'chef-server'
          DevLXC.create_dns_record(@api_fqdn, @server.name, @ipaddress)
        when 'compliance'
          DevLXC.create_dns_record(@compliance_fqdn, @server.name, @ipaddress)
        when 'supermarket'
          DevLXC.create_dns_record(@supermarket_fqdn, @server.name, @ipaddress)
        end
      end
      @server.sync_mounts(@mounts)
      @server.start
      @server.sync_ssh_keys(@ssh_keys)
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
      custom_image = DevLXC::Container.new("c-#{@server.name}", @lxc_config_path)
      if custom_image.defined?
        if force
          custom_image.destroy
        else
          puts "WARNING: Skipping snapshot of '#{@server.name}' because a custom image already exists"
          return
        end
      end
      puts "Creating snapshot of container '#{@server.name}' in custom image '#{custom_image.name}'"
      @server.clone("#{custom_image.name}", {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
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

    def destroy_image(type)
      case type
      when :custom
        DevLXC::Container.new("c-#{@server.name}", @lxc_config_path).destroy
      when :unique
        DevLXC::Container.new("u-#{@server.name}", @lxc_config_path).destroy
      when :shared
        DevLXC::Container.new(@shared_image_name, @lxc_config_path).destroy
      when :platform
        DevLXC::Container.new(@platform_image_name, @lxc_config_path).destroy
      end
    end

    def create
      if @server.defined?
        puts "Using existing container '#{@server.name}'"
        return
      end
      custom_image = DevLXC::Container.new("c-#{@server.name}", @lxc_config_path)
      unique_image = DevLXC::Container.new("u-#{@server.name}", @lxc_config_path)
      if custom_image.defined?
        puts "Cloning custom image '#{custom_image.name}' into container '#{@server.name}'"
        custom_image.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
        @server = DevLXC::Container.new(@server.name, @lxc_config_path)
        return
      elsif unique_image.defined?
        puts "Cloning unique image '#{unique_image.name}' into container '#{@server.name}'"
        unique_image.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
        @server = DevLXC::Container.new(@server.name, @lxc_config_path)
        return
      else
        puts "Creating container '#{@server.name}'"
        if %w(adhoc compliance supermarket).include?(@server_type)
          if @server_type == 'supermarket' && (@chef_server_bootstrap_backend && ! DevLXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).defined?)
            puts "ERROR: The bootstrap backend server '#{@chef_server_bootstrap_backend}' must be created first."
            exit 1
          end
          platform_image = DevLXC.create_platform_image(@platform_image_name, @platform_image_options, @lxc_config_path)
          puts "Cloning platform image '#{platform_image.name}' into container '#{@server.name}'"
          platform_image.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
        else
          unless @server.name == @chef_server_bootstrap_backend || DevLXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).defined?
            puts "ERROR: The bootstrap backend server '#{@chef_server_bootstrap_backend}' must be created first."
            exit 1
          end
          shared_image = create_shared_image
          puts "Cloning shared image '#{shared_image.name}' into container '#{@server.name}'"
          shared_image.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
        end
        @server = DevLXC::Container.new(@server.name, @lxc_config_path)
        puts "Deleting SSH Server Host Keys"
        FileUtils.rm_f(Dir.glob("#{@server.config_item('lxc.rootfs')}/etc/ssh/ssh_host*_key*"))
        puts "Adding lxc.hook.post-stop hook"
        @server.set_config_item("lxc.hook.post-stop", "/usr/local/share/lxc/hooks/post-stop-dhcp-release")
        @server.save_config
        hwaddr = @server.config_item("lxc.network.0.hwaddr")
        if hwaddr.empty?
          puts "ERROR: '#{@server.name}' needs to have an lxc.network.hwaddr entry"
          exit 1
        end
        DevLXC.assign_ip_address(@ipaddress, @server.name, hwaddr)
        unless @role == 'backend'
          case @server_type
          when 'analytics'
            DevLXC.create_dns_record(@analytics_fqdn, @server.name, @ipaddress)
          when 'chef-server'
            DevLXC.create_dns_record(@api_fqdn, @server.name, @ipaddress)
          when 'compliance'
            DevLXC.create_dns_record(@compliance_fqdn, @server.name, @ipaddress)
          when 'supermarket'
            DevLXC.create_dns_record(@supermarket_fqdn, @server.name, @ipaddress)
          end
        end
        @server.sync_mounts(@mounts)
        # if platform image is centos then `/etc/hosts` file needs to be modified so `hostname -f`
        # provides the FQDN instead of `localhost`
        if @platform_image_name.start_with?('p-centos-')
          IO.write("#{@server.config_item('lxc.rootfs')}/etc/hosts", "127.0.0.1 localhost\n127.0.1.1 #{@server.name}\n")
        end
        @server.start
        # Allow adhoc servers time to generate SSH Server Host Keys
        sleep 5 if @server_type == 'adhoc'
        case @server_type
        when 'compliance'
          @server.install_package(@packages["compliance"]) unless @packages["compliance"].nil?
        when 'supermarket'
          @server.install_package(@packages["supermarket"]) unless @packages["supermarket"].nil?
        end
        configure_analytics if @server_type == 'analytics'
        configure_compliance if @server_type == 'compliance'
        configure_supermarket if @server_type == 'supermarket'
        if @server_type == 'chef-server' && ! @packages["server"].nil?
          configure_server
          create_users if @server.name == @chef_server_bootstrap_backend
          if %w(standalone frontend).include?(@role) && ! @packages["manage"].nil?
            @server.install_package(@packages["manage"])
            configure_manage
          end
          unless @role == 'open-source'
            configure_reporting unless @packages["reporting"].nil?
            configure_push_jobs_server unless @packages["push-jobs-server"].nil?
          end
        end
        @server.stop
        puts "Cloning container '#{@server.name}' into unique image '#{unique_image.name}'"
        @server.clone("#{unique_image.name}", {:flags => LXC::LXC_CLONE_SNAPSHOT|LXC::LXC_CLONE_KEEPMACADDR})
      end
    end

    def create_shared_image
      shared_image = DevLXC::Container.new(@shared_image_name, @lxc_config_path)
      if shared_image.defined?
        puts "Using existing shared image '#{shared_image.name}'"
        return shared_image
      end
      platform_image = DevLXC.create_platform_image(@platform_image_name, @platform_image_options, @lxc_config_path)
      puts "Cloning platform image '#{platform_image.name}' into shared image '#{shared_image.name}'"
      platform_image.clone(shared_image.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
      shared_image = DevLXC::Container.new(shared_image.name, @lxc_config_path)
      puts "Deleting SSH Server Host Keys"
      FileUtils.rm_f(Dir.glob("#{shared_image.config_item('lxc.rootfs')}/etc/ssh/ssh_host*_key*"))

      # Disable certain sysctl.d files in Ubuntu 10.04, they cause `start procps` to fail
      # Enterprise Chef server's postgresql recipe expects to be able to `start procps`
      if platform_image.name == "p-ubuntu-1004"
        if File.exist?("#{shared_image.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf")
          FileUtils.mv("#{shared_image.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf",
                       "#{shared_image.config_item('lxc.rootfs')}/etc/sysctl.d/10-console-messages.conf.orig")
        end
      end
      unless shared_image.config_item("lxc.mount.auto").nil?
        shared_image.set_config_item("lxc.mount.auto", "proc:rw sys:rw")
        shared_image.save_config
      end
      shared_image.sync_mounts(@mounts)
      shared_image.start
      case @server_type
      when 'analytics'
        shared_image.install_package(@packages["analytics"]) unless @packages["analytics"].nil?
      when 'chef-server'
        shared_image.install_package(@packages["server"]) unless @packages["server"].nil?
        shared_image.install_package(@packages["reporting"]) unless @packages["reporting"].nil?
        shared_image.install_package(@packages["push-jobs-server"]) unless @packages["push-jobs-server"].nil?
      end
      shared_image.stop
      return shared_image
    end

    def configure_server
      case @role
      when "open-source"
        puts "Creating /etc/chef-server/chef-server.rb"
        FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/etc/chef-server")
        IO.write("#{@server.config_item('lxc.rootfs')}/etc/chef-server/chef-server.rb", @chef_server_config)
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
      when "frontend"
        puts "Copying /etc/opscode from bootstrap backend '#{@chef_server_bootstrap_backend}'"
        FileUtils.cp_r("#{LXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).config_item('lxc.rootfs')}/etc/opscode",
                       "#{@server.config_item('lxc.rootfs')}/etc")
      end
      run_ctl(@server_ctl, "reconfigure")
    end

    def configure_reporting
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/var/opt/opscode-reporting")
      FileUtils.touch("#{@server.config_item('lxc.rootfs')}/var/opt/opscode-reporting/.license.accepted")
      if @role == 'frontend'
        puts "Copying /etc/opscode-reporting from bootstrap backend '#{@chef_server_bootstrap_backend}'"
        FileUtils.cp_r("#{LXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).config_item('lxc.rootfs')}/etc/opscode-reporting",
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
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/var/opt/chef-manage")
      FileUtils.touch("#{@server.config_item('lxc.rootfs')}/var/opt/chef-manage/.license.accepted")
      if @chef_server_type == 'private-chef'
        puts "Disabling old opscode-webui in /etc/opscode/private-chef.rb"
        DevLXC.search_file_delete_line("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", /opscode_webui[.enable.]/)
        DevLXC.append_line_to_file("#{@server.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", "\nopscode_webui['enable'] = false\n")
        run_ctl(@server_ctl, "reconfigure")
      end
      run_ctl("opscode-manage", "reconfigure")
    end

    def configure_analytics
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/var/opt/opscode-analytics")
      FileUtils.touch("#{@server.config_item('lxc.rootfs')}/var/opt/opscode-analytics/.license.accepted")
      case @role
      when "standalone", "backend"
        puts "Copying /etc/opscode-analytics from Chef Server bootstrap backend '#{@chef_server_bootstrap_backend}'"
        FileUtils.cp_r("#{LXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).config_item('lxc.rootfs')}/etc/opscode-analytics",
                       "#{@server.config_item('lxc.rootfs')}/etc")

        IO.write("#{@server.config_item('lxc.rootfs')}/etc/opscode-analytics/opscode-analytics.rb", @analytics_config)
      when "frontend"
        puts "Copying /etc/opscode-analytics from Analytics bootstrap backend '#{@analytics_bootstrap_backend}'"
        FileUtils.cp_r("#{LXC::Container.new(@analytics_bootstrap_backend, @lxc_config_path).config_item('lxc.rootfs')}/etc/opscode-analytics",
                       "#{@server.config_item('lxc.rootfs')}/etc")
      end
      run_ctl("opscode-analytics", "reconfigure")
    end

    def configure_compliance
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/var/opt/chef-compliance")
      FileUtils.touch("#{@server.config_item('lxc.rootfs')}/var/opt/chef-compliance/.license.accepted")
      run_ctl("chef-compliance", "reconfigure")
    end

    def configure_supermarket
      if @chef_server_bootstrap_backend && DevLXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).defined?
        chef_server_supermarket_config = JSON.parse(IO.read("#{LXC::Container.new(@chef_server_bootstrap_backend, @lxc_config_path).config_item('lxc.rootfs')}/etc/opscode/oc-id-applications/supermarket.json"))
        supermarket_config = {
          'chef_server_url' => "https://#{@api_fqdn}/",
          'chef_oauth2_app_id' => chef_server_supermarket_config['uid'],
          'chef_oauth2_secret' => chef_server_supermarket_config['secret'],
          'chef_oauth2_verify_ssl' => false
        }
        FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/etc/supermarket")
        IO.write("#{@server.config_item('lxc.rootfs')}/etc/supermarket/supermarket.json", JSON.pretty_generate(supermarket_config))
      end
      run_ctl("supermarket", "reconfigure")
    end

    def run_ctl(component, subcommand)
      puts "Running `#{component}-ctl #{subcommand}` in '#{@server.name}'"
      @server.run_command("#{component}-ctl #{subcommand}")
    end

    def create_users
      puts "Creating org, user, keys and knife.rb in /root/chef-repo/.chef"
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef")

      case @chef_server_type
      when 'chef-server'
        chef_server_url = "https://127.0.0.1"
        admin_username = "admin"
        validator_name = "chef-validator"

        FileUtils.cp( Dir.glob("#{@server.config_item('lxc.rootfs')}/etc/chef-server/{admin,chef-validator}.pem"), "#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef" )
      when 'private-chef', 'chef-server-core'
        chef_server_root = "https://127.0.0.1"
        chef_server_url = "https://127.0.0.1/organizations/demo"
        admin_username = "mary-admin"
        username = "joe-user"
        validator_name = "demo-validator"

        FileUtils.cp( "#{@server.config_item('lxc.rootfs')}/etc/opscode/pivotal.pem", "#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef" )

        pivotal_rb = %Q(
current_dir = File.dirname(__FILE__)

chef_server_root "#{chef_server_root}"
chef_server_url "#{chef_server_root}"

node_name "pivotal"
client_key "\#{current_dir}/pivotal.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd

ssl_verify_mode :verify_none
)
        IO.write("#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef/pivotal.rb", pivotal_rb)
      end

      knife_rb = %Q(
current_dir = File.dirname(__FILE__)

chef_server_url "#{chef_server_url}"

node_name "#{admin_username}"
client_key "\#{current_dir}/#{admin_username}.pem"
)

      knife_rb += %Q(
#node_name "#{username}"
#client_key "\#{current_dir}/#{username}.pem"
) unless username.nil?

      knife_rb += %Q(
validation_client_name "#{validator_name}"
validation_key "\#{current_dir}/#{validator_name}.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd

ssl_verify_mode :verify_none
)
      IO.write("#{@server.config_item('lxc.rootfs')}/root/chef-repo/.chef/knife.rb", knife_rb)

      case @chef_server_type
      when 'private-chef'
        # give time for all services to come up completely
        sleep 60
        @server.run_command("/opt/opscode/embedded/bin/gem install knife-opc --no-ri --no-rdoc")
        @server.run_command("/opt/opscode/embedded/bin/knife opc org create demo demo --filename /root/chef-repo/.chef/demo-validator.pem -c /root/chef-repo/.chef/pivotal.rb")
        @server.run_command("/opt/opscode/embedded/bin/knife opc user create mary-admin mary admin mary-admin@noreply.com mary-admin --filename /root/chef-repo/.chef/mary-admin.pem -c /root/chef-repo/.chef/pivotal.rb")
        @server.run_command("/opt/opscode/embedded/bin/knife opc org user add demo mary-admin --admin -c /root/chef-repo/.chef/pivotal.rb")
        @server.run_command("/opt/opscode/embedded/bin/knife opc user create joe-user joe user joe-user@noreply.com joe-user --filename /root/chef-repo/.chef/joe-user.pem -c /root/chef-repo/.chef/pivotal.rb")
        @server.run_command("/opt/opscode/embedded/bin/knife opc org user add demo joe-user -c /root/chef-repo/.chef/pivotal.rb")
      when 'chef-server-core'
        # give time for all services to come up completely
        sleep 10
        run_ctl(@server_ctl, "org-create demo demo --filename /root/chef-repo/.chef/demo-validator.pem")
        run_ctl(@server_ctl, "user-create mary-admin mary admin mary-admin@noreply.com mary-admin --filename /root/chef-repo/.chef/mary-admin.pem")
        run_ctl(@server_ctl, "org-user-add demo mary-admin --admin")
        run_ctl(@server_ctl, "user-create joe-user joe user joe-user@noreply.com joe-user --filename /root/chef-repo/.chef/joe-user.pem")
        run_ctl(@server_ctl, "org-user-add demo joe-user")
      end
    end
  end
end
