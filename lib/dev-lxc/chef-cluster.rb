require "dev-lxc/chef-server"

module DevLXC
  class ChefCluster
    attr_reader :bootstrap_backend

    def initialize(cluster_config)
      @cluster_config = cluster_config
      @api_fqdn = @cluster_config["api_fqdn"]
      @analytics_fqdn = @cluster_config["analytics_fqdn"]
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
        @analytics_server = name if config["role"] == "analytics"
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
      chef_servers << ChefServer.new(@analytics_server, @cluster_config) if @analytics_server
      chef_servers
    end

    def chef_repo
      chef_server = ChefServer.new(@bootstrap_backend, @cluster_config)
      if ! chef_server.server.defined?
        puts "The '#{chef_server.server.name}' Chef Server does not exist. Please create it first."
        exit 1
      end

      puts "Creating chef-repo with pem files and knife.rb in the current directory"
      FileUtils.mkdir_p("./chef-repo/.chef")

      pem_files = Dir.glob("#{chef_server.abspath('/root/chef-repo/.chef')}/*.pem")
      if pem_files.empty?
        puts "The pem files can not be copied because they do not exist in '#{chef_server.server.name}' Chef Server's `/root/chef-repo/.chef` directory"
      else
        FileUtils.cp( pem_files, "./chef-repo/.chef" )
      end

      if @topology == "open-source"
        chef_server_url = "https://#{@api_fqdn}"
        username = "admin"
        validator_name = "chef-validator"
      else
        chef_server_url = "https://#{@api_fqdn}/organizations/ponyville"
        username = "rainbowdash"
        validator_name = "ponyville-validator"
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
      IO.write("./chef-repo/.chef/knife.rb", knife_rb)

      bootstrap_node = %Q(#!/bin/bash

if [[ -z $1 ]]; then
  echo "Please provide the name of the node to be bootstrapped"
  return 1
fi

xc-start $1

xc-chef-config -s #{chef_server_url} \\
               -u #{validator_name} \\
               -k ./chef-repo/.chef/#{validator_name}.pem

if [[ -n $2 ]]; then
  xc-attach chef-client -r $2
else
  xc-attach chef-client
fi
)
      IO.write("./bootstrap-node", bootstrap_node)
      FileUtils.chmod("u+x", "./bootstrap-node")
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
