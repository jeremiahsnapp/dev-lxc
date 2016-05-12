require "json"
require "dev-lxc/container"
require "dev-lxc/cluster"

module DevLXC
  class Server
    attr_reader :server, :base_container_name

    def initialize(name, server_type, cluster_config)
      unless cluster_config[server_type]["servers"].keys.include?(name)
        puts "ERROR: Server '#{name}' is not defined in the cluster config"
        exit 1
      end
      @server_type = server_type
      cluster = DevLXC::Cluster.new(cluster_config)
      @api_fqdn = cluster.api_fqdn
      @analytics_fqdn = cluster.analytics_fqdn
      @compliance_fqdn = cluster.compliance_fqdn
      @supermarket_fqdn = cluster.supermarket_fqdn
      @chef_server_bootstrap_backend = cluster.chef_server_bootstrap_backend
      @analytics_bootstrap_backend = cluster.analytics_bootstrap_backend
      @chef_server_config = cluster.chef_server_config
      @analytics_config = cluster.analytics_config

      @server = DevLXC::Container.new(name)
      @config = cluster_config[@server_type]["servers"][@server.name]
      @ipaddress = @config["ipaddress"]
      @role = @config["role"]
      @role ||= cluster_config[@server_type]['topology']
      @role ||= 'standalone'
      @mounts = cluster_config[@server_type]["mounts"]
      @mounts ||= cluster_config["mounts"]
      @ssh_keys = cluster_config[@server_type]["ssh-keys"]
      @ssh_keys ||= cluster_config["ssh-keys"]
      @base_container_name = cluster_config[@server_type]["base_container"]
      @base_container_name ||= cluster_config["base_container"]
      @packages = cluster_config[@server_type]["packages"]

      if @server_type == 'chef-server'
        if File.basename(@packages["server"]).match(/^(\w+-\w+.*)[_-]((?:\d+\.?){3,})/)
          @chef_server_type = Regexp.last_match[1]
          case @chef_server_type
          when 'chef-server-core'
            @server_ctl = 'chef-server'
          when 'private-chef'
            @server_ctl = 'private-chef'
          when 'chef-server'
            @server_ctl = 'chef-server'
          end
        end
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
      build unless @server.defined?
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

    def snapshot(comment=nil)
      unless @server.defined?
        puts "WARNING: Skipping snapshot of '#{@server.name}' because it does not exist"
        return
      end
      if @server.state != :stopped
        puts "WARNING: Skipping snapshot of '#{@server.name}' because it is not stopped"
        return
      end
      puts "Creating snapshot of container '#{@server.name}'"
      snapname = @server.snapshot
      unless comment.nil?
        snapshot = @server.snapshot_list.select { |sn| sn.first == snapname }
        snapshot_comment_file = snapshot.flatten[1]
        IO.write(snapshot_comment_file, comment) unless snapshot_comment_file.nil?
      end
    end

    def snapshot_destroy(snapname=nil)
      unless @server.defined?
        puts "Skipping container '#{@server.name}' because it does not exist"
        return
      end
      if snapname == "ALL"
        if @server.snapshot_list.empty?
          puts "Container '#{@server.name}' does not have any snapshots"
        else
          @server.snapshot_list.each do |snapshot|
            puts "Destroying snapshot '#{snapshot.first}' of container '#{@server.name}'"
            @server.snapshot_destroy(snapshot.first)
          end
        end
      elsif snapname == "LAST"
        if @server.snapshot_list.empty?
          puts "Container '#{@server.name}' does not have any snapshots"
        else
          snapname = @server.snapshot_list.last.first
          puts "Destroying snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_destroy(snapname)
        end
      else
        snapshot = @server.snapshot_list.select { |sn| sn.first == snapname }
        if snapshot.flatten.empty?
          puts "Container '#{@server.name}' does not have a '#{snapname}' snapshot"
        else
          puts "Destroying snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_destroy(snapname)
        end
      end
    end

    def snapshot_list
      snapshots = Array.new
      return snapshots unless @server.defined?
      @server.snapshot_list.each do |snapshot|
        (snapname, snap_comment_file, snaptime) = snapshot
        snap_comment = IO.read(snap_comment_file).chomp if File.exist?(snap_comment_file)
        snapshots << [snapname, snaptime, snap_comment]
      end
      snapshots
    end

    def snapshot_restore(snapname=nil)
      unless @server.defined?
        puts "WARNING: Skipping container '#{@server.name}' because it does not exist"
        return
      end
      if @server.state != :stopped
        puts "WARNING: Skipping container '#{@server.name}' because it is not stopped"
        return
      end
      if snapname == "LAST"
        if @server.snapshot_list.empty?
          puts "WARNING: Skipping container '#{@server.name}' because it does not have any snapshots"
        else
          snapname = @server.snapshot_list.last.first
          puts "Restoring snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_restore(snapname)
        end
      else
        snapshot = @server.snapshot_list.select { |sn| sn.first == snapname }
        if snapshot.flatten.empty?
          puts "WARNING: Skipping container '#{@server.name}' because it does not have a '#{snapname}' snapshot"
        else
          puts "Restoring snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_restore(snapname)
        end
      end
    end

    def destroy
      if @server.defined?
        hwaddr = @server.config_item("lxc.network.0.hwaddr")
        @server.snapshot_list.each { |snapshot| @server.snapshot_destroy(snapshot.first) }
      end
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

    def build
      puts "Building container '#{@server.name}'"
      if @chef_server_bootstrap_backend && ! DevLXC::Container.new(@chef_server_bootstrap_backend).defined?
        if @server_type == 'supermarket' || (@server_type == 'chef-server' && @role == 'frontend')
          puts "ERROR: The bootstrap backend server '#{@chef_server_bootstrap_backend}' must be built first."
          exit 1
        end
      end
      base_container = DevLXC::Container.new(@base_container_name)
      puts "Cloning base container '#{base_container.name}' into container '#{@server.name}'"
      base_container.clone(@server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
      @server = DevLXC::Container.new(@server.name)
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
      # if base container is centos then `/etc/hosts` file needs to be modified so `hostname -f`
      # provides the FQDN instead of `localhost`
      if @base_container_name.start_with?('b-centos-')
        IO.write("#{@server.config_item('lxc.rootfs')}/etc/hosts", "127.0.0.1 localhost\n127.0.1.1 #{@server.name}\n")
      end
      @server.start
      # Allow adhoc servers time to generate SSH Server Host Keys
      sleep 5 if @server_type == 'adhoc'
      case @server_type
      when 'analytics'
        unless @packages["analytics"].nil?
          @server.install_package(@packages["analytics"])
          configure_analytics
        end
      when 'chef-server'
        unless @packages["server"].nil?
          @server.install_package(@packages["server"])
          configure_server
          create_users if @server.name == @chef_server_bootstrap_backend
          unless @role == 'open-source'
            unless @packages["reporting"].nil?
              @server.install_package(@packages["reporting"])
              configure_reporting
            end
            unless @packages["push-jobs-server"].nil?
              @server.install_package(@packages["push-jobs-server"])
              configure_push_jobs_server
            end
            unless @packages["manage"].nil?
              if %w(standalone frontend).include?(@role)
                @server.install_package(@packages["manage"])
                configure_manage
              end
            end
          end
        end
      when 'compliance'
        @server.install_package(@packages["compliance"]) unless @packages["compliance"].nil?
        configure_compliance
      when 'supermarket'
        @server.install_package(@packages["supermarket"]) unless @packages["supermarket"].nil?
        configure_supermarket
      end
      @server.stop
      puts "Creating snapshot of container '#{@server.name}'"
      @server.snapshot
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
        FileUtils.cp_r("#{LXC::Container.new(@chef_server_bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode",
                       "#{@server.config_item('lxc.rootfs')}/etc", preserve: true)
      end
      run_ctl(@server_ctl, "reconfigure")
    end

    def configure_reporting
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/var/opt/opscode-reporting")
      FileUtils.touch("#{@server.config_item('lxc.rootfs')}/var/opt/opscode-reporting/.license.accepted")
      if @role == 'frontend'
        puts "Copying /etc/opscode-reporting from bootstrap backend '#{@chef_server_bootstrap_backend}'"
        FileUtils.cp_r("#{LXC::Container.new(@chef_server_bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode-reporting",
                       "#{@server.config_item('lxc.rootfs')}/etc", preserve: true)
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
        FileUtils.cp_r("#{LXC::Container.new(@chef_server_bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode-analytics",
                       "#{@server.config_item('lxc.rootfs')}/etc", preserve: true)

        IO.write("#{@server.config_item('lxc.rootfs')}/etc/opscode-analytics/opscode-analytics.rb", @analytics_config)
      when "frontend"
        puts "Copying /etc/opscode-analytics from Analytics bootstrap backend '#{@analytics_bootstrap_backend}'"
        FileUtils.cp_r("#{LXC::Container.new(@analytics_bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode-analytics",
                       "#{@server.config_item('lxc.rootfs')}/etc", preserve: true)
      end
      run_ctl("opscode-analytics", "reconfigure")
    end

    def configure_compliance
      FileUtils.mkdir_p("#{@server.config_item('lxc.rootfs')}/var/opt/chef-compliance")
      FileUtils.touch("#{@server.config_item('lxc.rootfs')}/var/opt/chef-compliance/.license.accepted")
      run_ctl("chef-compliance", "reconfigure")
    end

    def configure_supermarket
      if @chef_server_bootstrap_backend && DevLXC::Container.new(@chef_server_bootstrap_backend).defined?
        chef_server_supermarket_config = JSON.parse(IO.read("#{LXC::Container.new(@chef_server_bootstrap_backend).config_item('lxc.rootfs')}/etc/opscode/oc-id-applications/supermarket.json"))
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
