require "dev-lxc/chef-server"

module DevLXC
  class ChefCluster
    attr_reader :api_fqdn, :topology, :bootstrap_backend, :frontends

    def initialize(cluster_config)
      @cluster_config = cluster_config
      @api_fqdn = @cluster_config["api_fqdn"]
      @topology = @cluster_config["topology"]
      @servers = @cluster_config["servers"]
      @frontends = Array.new
      @servers.each do |name, config|
        case @topology
        when 'open-source', 'standalone'
          @bootstrap_backend = name if config["role"].nil?
        when 'tier'
          @bootstrap_backend = name if config["role"] == "backend" && config["bootstrap"] == true
          @frontends << name if config["role"] == "frontend"
        end
      end
    end

    def chef_servers
      chef_servers = Array.new
      chef_servers << ChefServer.new(@bootstrap_backend, @cluster_config)
      if @topology == "tier"
        @frontends.each do |frontend_name|
          chef_servers << ChefServer.new(frontend_name, @cluster_config)
        end
      end
      chef_servers
    end

    def status
      puts "Cluster is available at https://#{@api_fqdn}"
      chef_servers.each { |cs| cs.status }
    end

    def abspath(rootfs_path)
      abspath = Array.new
      chef_servers.each { |cs| abspath << cs.abspath(rootfs_path) }
      abspath.compact
    end

    def chef_repo
      if @topology == "open-source"
        puts "Unable to create a chef-repo for an Open Source Chef Server"
        exit 1
      end
      chef_server = ChefServer.new(@bootstrap_backend, @cluster_config)
      if ! chef_server.server.defined?
        puts "The '#{chef_server.server.name}' Chef Server does not exist. Please create it first."
        exit 1
      end
      puts "Creating chef-repo with pem files and knife.rb in the current directory"
      FileUtils.mkdir_p("./chef-repo/.chef")
      knife_rb = %Q(
current_dir = File.dirname(__FILE__)

chef_server_url "https://#{api_fqdn}/organizations/ponyville"

node_name "rainbowdash"
client_key "\#{current_dir}/rainbowdash.pem"

validation_client_name "ponyville-validator"
validation_key "\#{current_dir}/ponyville-validator.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd
)
      IO.write("./chef-repo/.chef/knife.rb", knife_rb)
      if Dir.glob("#{chef_server.abspath('/root/chef-repo/.chef')}/*.pem").empty?
        puts "The pem files can not be copied because they do not exist in '#{chef_server.server.name}' Chef Server's `/root/chef-repo/.chef` directory"
      else
        FileUtils.cp( Dir.glob("#{chef_server.abspath('/root/chef-repo/.chef')}/*.pem"), "./chef-repo/.chef" )
      end
    end

    def run_command(command)
      chef_servers.each { |cs| cs.run_command(command) }
    end

    def start
      puts "Starting cluster"
      chef_servers.each { |cs| cs.start }
    end

    def stop
      puts "Stopping cluster"
      chef_servers.reverse_each { |cs| cs.stop }
    end

    def destroy
      puts "Destroying cluster"
      chef_servers.reverse_each { |cs| cs.destroy }
    end

    def destroy_container(type)
      case type
      when :unique
        @servers.keys.each do |server_name|
          DevLXC::ChefServer.new(server_name, @cluster_config).destroy_container(:unique)
        end
      when :shared
        DevLXC::ChefServer.new(@servers.keys.first, @cluster_config).destroy_container(:shared)
      when :platform
        DevLXC::ChefServer.new(@servers.keys.first, @cluster_config).destroy_container(:platform)
      end
    end

    def chef_server_config
      chef_server_config = %Q(api_fqdn "#{@api_fqdn}"\n)
      if @topology == 'tier'
        chef_server_config += %Q(
topology "#{@topology}"

server "#{@bootstrap_backend}",
  :ipaddress => "#{@servers[@bootstrap_backend]["ipaddress"]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@bootstrap_backend}",
  :ipaddress => "#{@servers[@bootstrap_backend]["ipaddress"]}"
)
        @frontends.each do |frontend_name|
          chef_server_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@servers[frontend_name]["ipaddress"]}",
  :role => "frontend"
)
        end
      end
      return chef_server_config
    end
  end
end
