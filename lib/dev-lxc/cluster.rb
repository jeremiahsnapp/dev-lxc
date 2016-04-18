require "dev-lxc/server"

module DevLXC
  class Cluster
    attr_reader :api_fqdn, :analytics_fqdn, :chef_server_bootstrap_backend, :analytics_bootstrap_backend, :lxc_config_path

    def initialize(cluster_config)
      @cluster_config = cluster_config

      @lxc_config_path = @cluster_config["lxc_config_path"]
      @lxc_config_path ||= "/var/lib/dev-lxc"

      if @cluster_config["adhoc"]
        @adhoc_servers = @cluster_config["adhoc"]["servers"].keys
      end

      if @cluster_config["chef-server"]
        @chef_server_topology = @cluster_config["chef-server"]["topology"]
        @chef_server_topology ||= 'standalone'
        @api_fqdn = @cluster_config["chef-server"]["api_fqdn"]
        @chef_server_servers = @cluster_config["chef-server"]["servers"]
        @chef_server_frontends = Array.new
        @chef_server_servers.each do |name, config|
          case @chef_server_topology
          when 'open-source', 'standalone'
            @chef_server_bootstrap_backend = name if config["role"].nil?
            @api_fqdn ||= @chef_server_bootstrap_backend
          when 'tier'
            @chef_server_bootstrap_backend = name if config["role"] == "backend" && config["bootstrap"] == true
            @chef_server_frontends << name if config["role"] == "frontend"
          end
        end
      end

      if @cluster_config["analytics"]
        @analytics_topology = @cluster_config["analytics"]["topology"]
        @analytics_topology ||= 'standalone'
        @analytics_fqdn = @cluster_config["analytics"]["analytics_fqdn"]
        @analytics_servers = @cluster_config["analytics"]["servers"]
        @analytics_frontends = Array.new
        @analytics_servers.each do |name, config|
          case @analytics_topology
          when 'standalone'
            @analytics_bootstrap_backend = name if config["role"].nil?
            @analytics_fqdn ||= @analytics_bootstrap_backend
          when 'tier'
            @analytics_bootstrap_backend = name if config["role"] == "backend" && config["bootstrap"] == true
            @analytics_frontends << name if config["role"] == "frontend"
          end
        end
      end
    end

    def servers
      adhoc_servers = Array.new
      if @adhoc_servers
        @adhoc_servers.each do |name|
          adhoc_servers << Server.new(name, 'adhoc', @cluster_config)
        end
      end
      chef_servers = Array.new
      chef_servers << Server.new(@chef_server_bootstrap_backend, 'chef-server', @cluster_config) if @chef_server_bootstrap_backend
      if @chef_server_topology == "tier"
        @chef_server_frontends.each do |frontend_name|
          chef_servers << Server.new(frontend_name, 'chef-server', @cluster_config)
        end
      end
      analytics_servers = Array.new
      analytics_servers << Server.new(@analytics_bootstrap_backend, 'analytics', @cluster_config) if @analytics_bootstrap_backend
      if @analytics_topology == "tier"
        @analytics_frontends.each do |frontend_name|
          analytics_servers << Server.new(frontend_name, 'analytics', @cluster_config)
        end
      end
      servers = adhoc_servers + chef_servers + analytics_servers
    end

    def chef_repo(force=false, pivotal=false)
      if @chef_server_bootstrap_backend.nil?
        puts "ERROR: A bootstrap backend Chef Server is not defined in the cluster's config. Please define it first."
        exit 1
      end
      chef_server = Server.new(@chef_server_bootstrap_backend, 'chef-server', @cluster_config)
      if ! chef_server.server.defined?
        puts "ERROR: The '#{chef_server.server.name}' Chef Server does not exist. Please create it first."
        exit 1
      end

      puts "Creating chef-repo with pem files and knife.rb in the current directory"
      FileUtils.mkdir_p("./chef-repo/.chef")

      pem_files = Dir.glob("#{chef_server.realpath('/root/chef-repo/.chef')}/*.pem")
      if pem_files.empty?
        puts "The pem files can not be copied because they do not exist in '#{chef_server.server.name}' Chef Server's `/root/chef-repo/.chef` directory"
      else
        pem_files.delete_if { |pem_file| pem_file.end_with?("/pivotal.pem") } unless pivotal
        FileUtils.cp( pem_files, "./chef-repo/.chef" )
      end

      if @chef_server_topology == "open-source"
        chef_server_url = "https://#{@api_fqdn}"
        validator_name = "chef-validator"
      else
        chef_server_root = "https://#{@api_fqdn}"
        chef_server_url = "https://#{@api_fqdn}/organizations/ponyville"
        validator_name = "ponyville-validator"

        if pivotal
          if File.exists?("./chef-repo/.chef/pivotal.rb") && ! force
            puts "Skipping pivotal.rb because it already exists in `./chef-repo/.chef`"
          else
            pivotal_rb_path = "#{chef_server.realpath('/root/chef-repo/.chef')}/pivotal.rb"
            if File.exists?(pivotal_rb_path)
              pivotal_rb = IO.read(pivotal_rb_path)
              pivotal_rb.sub!(/^chef_server_root .*/, "chef_server_root \"#{chef_server_root}\"")
              pivotal_rb.sub!(/^chef_server_url .*/, "chef_server_url \"#{chef_server_root}\"")
              IO.write("./chef-repo/.chef/pivotal.rb", pivotal_rb)
            else
              puts "The pivotal.rb file can not be copied because it does not exist in '#{chef_server.server.name}' Chef Server's `/root/chef-repo/.chef` directory"
            end
          end
        end
      end

      if File.exists?("./chef-repo/.chef/knife.rb") && ! force
        puts "Skipping knife.rb because it already exists in `./chef-repo/.chef`"
      else
        knife_rb_path = "#{chef_server.realpath('/root/chef-repo/.chef')}/knife.rb"
        if File.exists?(knife_rb_path)
          knife_rb = IO.read(knife_rb_path)
          knife_rb.sub!(/^chef_server_url .*/, "chef_server_url \"#{chef_server_url}\"")
          IO.write("./chef-repo/.chef/knife.rb", knife_rb)
        else
          puts "The knife.rb file can not be copied because it does not exist in '#{chef_server.server.name}' Chef Server's `/root/chef-repo/.chef` directory"
        end
      end
    end

    def chef_server_config
      chef_server_config = %Q(api_fqdn "#{@api_fqdn}"\n)
      if @chef_server_topology == 'tier'
        chef_server_config += %Q(
topology "#{@chef_server_topology}"

server "#{@chef_server_bootstrap_backend}",
  :ipaddress => "#{@chef_server_servers[@chef_server_bootstrap_backend]["ipaddress"]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@chef_server_bootstrap_backend}",
  :ipaddress => "#{@chef_server_servers[@chef_server_bootstrap_backend]["ipaddress"]}"
)
        @chef_server_frontends.each do |frontend_name|
          chef_server_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@chef_server_servers[frontend_name]["ipaddress"]}",
  :role => "frontend"
)
        end
      end
      return chef_server_config
    end

    def analytics_config
      analytics_config = %Q(analytics_fqdn "#{@analytics_fqdn}"
topology "#{@analytics_topology}"
)
      if @analytics_topology == 'tier'
        analytics_config += %Q(
server "#{@analytics_bootstrap_backend}",
  :ipaddress => "#{@analytics_servers[@analytics_bootstrap_backend]["ipaddress"]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@analytics_bootstrap_backend}",
  :ipaddress => "#{@analytics_servers[@analytics_bootstrap_backend]["ipaddress"]}"
)
        @analytics_frontends.each do |frontend_name|
          analytics_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@analytics_servers[frontend_name]["ipaddress"]}",
  :role => "frontend"
)
        end
      end
      return analytics_config
    end

  end
end
