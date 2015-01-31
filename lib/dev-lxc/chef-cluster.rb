require "dev-lxc/chef-server"

module DevLXC
  class ChefCluster
    attr_reader :api_fqdn, :topology, :bootstrap_backend, :frontends

    def initialize(cluster_config)
      @cluster_config = cluster_config
      @api_fqdn = @cluster_config["api_fqdn"]
      @topology = @cluster_config["topology"]
      @servers = @cluster_config["servers"]
      if @topology == 'tier'
        @bootstrap_backend = @servers.select {|k,v| v["role"] == "backend" && v["bootstrap"] == true}.first.first
        @frontends = @servers.select {|k,v| v["role"] == "frontend"}.keys
      end
    end

    def chef_servers
      chef_servers = Array.new
      case @topology
      when "open-source", "standalone"
        chef_servers << ChefServer.new(@servers.keys.first, @cluster_config)
      when "tier"
        chef_servers << ChefServer.new(@bootstrap_backend, @cluster_config)
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
