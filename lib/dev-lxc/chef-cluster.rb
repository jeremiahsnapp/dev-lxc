require "dev-lxc/chef-server"

module DevLXC
  class ChefCluster
    attr_reader :api_fqdn, :topology, :bootstrap_backend, :secondary_backend, :frontends

    def initialize(cluster_config)
      @cluster_config = cluster_config
      @api_fqdn = @cluster_config["api_fqdn"]
      @topology = @cluster_config["topology"]
      @servers = @cluster_config["server"]
      if %w(tier ha).include?(@topology)
        @bootstrap_backend = @servers.select {|k,v| v["role"] == "backend" && v["bootstrap"] == true}.first.first
        @frontends = @servers.select {|k,v| v["role"] == "frontend"}.keys
      end
      if @topology == "ha"
        @secondary_backend = @servers.select {|k,v| v["role"] == "backend" && v["bootstrap"] == nil}.first.first
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
      when "ha"
        chef_servers << ChefServer.new(@bootstrap_backend, @cluster_config)
        chef_servers << ChefServer.new(@secondary_backend, @cluster_config)
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
      abspath.delete_if { |abspath| abspath.nil? }
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
    
    def destroy_base_containers
      @servers.keys.each do |server_name|
        DevLXC::Container.new("b-#{server_name}").destroy
      end
      DevLXC::Container.new(DevLXC::ChefServer.new(@servers.keys.first, @cluster_config).base_server_name).destroy
    end

    def chef_server_config
      chef_server_config = %Q(api_fqdn "#{@api_fqdn}"\n)
      @cluster_config["package"]["server"].to_s.match(/(private-chef|chef-server)[_-](\d+)\.(\d+\.?){2,}-/)
      if Regexp.last_match[2].to_i >= 11
        chef_server_config += %Q(bookshelf["vip"] = "#{@api_fqdn}"\n)
      end
      if %w(tier ha).include?(@topology)
        chef_server_config += %Q(
topology "#{@topology}"

server "#{@bootstrap_backend}",
  :ipaddress => "#{@servers[@bootstrap_backend]["ipaddress"]}",
  :role => "backend",
  :bootstrap => true)

        case @topology
        when "tier"
          chef_server_config += %Q(

backend_vip "#{@bootstrap_backend}",
  :ipaddress => "#{@servers[@bootstrap_backend]["ipaddress"]}"
)
        when "ha"
          backend_vip_name = config["backend_vip"].keys.first
          chef_server_config += %Q(,
  :cluster_ipaddress => "#{@servers[@bootstrap_backend]["cluster_ipaddress"]}"

server "#{@secondary_backend}",
  :ipaddress => "#{@servers[@secondary_backend]["ipaddress"]}",
  :role => "backend",
  :cluster_ipaddress => "#{@servers[@secondary_backend]["cluster_ipaddress"]}

backend_vip "#{backend_vip_name}",
  :ipaddress => "#{config["backend_vip"][backend_vip_name]["ipaddress"]}",
  :device => "#{config["backend_vip"][backend_vip_name]["device"]}",
  :heartbeat_device => "#{config["backend_vip"][backend_vip_name]["heartbeat_device"]}"
)
        end
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
