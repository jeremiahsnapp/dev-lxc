require "yaml"
require 'dev-lxc'
require 'thor'

module DevLXC::CLI
  class DevLXC < Thor

    no_commands{
      def get_cluster(config_option)
        config = options[:config]
        config ||= "dev-lxc.yml"
        if ! File.exists?(config)
          puts "ERROR: Cluster config file `config` does not exist."
          puts "       Create a `./dev-lxc.yml` file or specify the path using `-c`."
          exit 1
        end
        ::DevLXC::ChefCluster.new(YAML.load(IO.read(config)))
      end

      def match_server_name_regex(server_name_regex)
        get_cluster(options[:config]).chef_servers.select { |cs| cs.server.name =~ /#{server_name_regex}/ }
      end
    }

    desc "create [PLATFORM_CONTAINER_NAME]", "Create a platform container"
    def create(platform_container_name=nil)
      platform_container_names = %w(p-ubuntu-1204 p-ubuntu-1404 p-centos-5 p-centos-6)
      if platform_container_name.nil? || ! platform_container_names.include?(platform_container_name)
        platform_container_names_with_index = platform_container_names.map.with_index{ |a, i| [i+1, *a]}
        print_table platform_container_names_with_index
        selection = ask("Which platform container do you want to create?", :limited_to => platform_container_names_with_index.map{|c| c[0].to_s})
        platform_container_name = platform_container_names[selection.to_i - 1]
      end
      ::DevLXC.create_platform_container(platform_container_name)
    end

    desc "init [TOPOLOGY]", "Provide a cluster config file"
    def init(topology=nil, unique_string=nil)
      topologies = %w(open-source standalone tier)
      if topology.nil? || ! topologies.include?(topology)
        topologies_with_index = topologies.map.with_index{ |a, i| [i+1, *a]}
        print_table topologies_with_index
        selection = ask("Which cluster topology do you want to use?", :limited_to => topologies_with_index.map{|c| c[0].to_s})
        topology = topologies[selection.to_i - 1]
      end
      config = IO.read("#{File.dirname(__FILE__)}/../../files/configs/#{topology}.yml")
      unless unique_string.nil?
        config_hash = YAML.load(config.gsub(/^#/, ''))
        config.gsub!(/api_fqdn:\s+#{config_hash['api_fqdn']}/, "api_fqdn: #{unique_string}#{config_hash['api_fqdn']}")
        config.gsub!(/analytics_fqdn:\s+#{config_hash['analytics_fqdn']}/, "analytics_fqdn: #{unique_string}#{config_hash['analytics_fqdn']}")
        config_hash['servers'].keys.each do |server_name|
          config.gsub!(/ #{server_name}:/, " #{unique_string}#{server_name}:")
        end
      end
      puts config
    end

    desc "status [SERVER_NAME_REGEX]", "Show status of servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def status(server_name_regex=nil)
      config = options[:config]
      config ||= "dev-lxc.yml"
      if ! File.exists?(config)
        puts "ERROR: Cluster config file `config` does not exist."
        puts "       Create a `./dev-lxc.yml` file or specify the path using `-c`."
        exit 1
      end
      cluster_config = YAML.load(IO.read(config))

      puts "Chef Server is available at https://#{cluster_config['api_fqdn']}"
      puts "Analytics is available at https://#{cluster_config['analytics_fqdn']}" if cluster_config['analytics_fqdn']
      match_server_name_regex(server_name_regex).each { |cs| cs.status }
    end

    desc "abspath [SERVER_NAME_REGEX] [ROOTFS_PATH]", "Returns the absolute path to a file in each server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def abspath(server_name_regex=nil, rootfs_path)
      abspath = Array.new
      match_server_name_regex(server_name_regex).map { |cs| abspath << cs.abspath(rootfs_path) }
      puts abspath.compact.join(" ")
    end

    desc "chef-repo", "Creates a chef-repo in the current directory using files from the cluster's backend /root/chef-repo"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def chef_repo
      get_cluster(options[:config]).chef_repo
    end

    desc "run_command [SERVER_NAME_REGEX] [COMMAND]", "Runs a command in each server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def run_command(server_name_regex=nil, command)
      match_server_name_regex(server_name_regex).each { |cs| cs.run_command(command) }
    end

    desc "start [SERVER_NAME_REGEX]", "Start servers - This is the default if no subcommand is given"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def start(server_name_regex=nil)
      match_server_name_regex(server_name_regex).each { |cs| cs.start }
    end

    # make `start` the default subcommand and pass any arguments to it
    default_task :start
    def method_missing(method, *args)
      args = ["start", method.to_s] + args
      DevLXC.start(args)
    end

    desc "stop [SERVER_NAME_REGEX]", "Stop servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def stop(server_name_regex=nil)
      match_server_name_regex(server_name_regex).reverse_each { |cs| cs.stop }
    end

    desc "destroy [SERVER_NAME_REGEX]", "Destroy servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :unique, :aliases => "-u", :type => :boolean, :desc => "Also destroy the unique containers"
    option :shared, :aliases => "-s", :type => :boolean, :desc => "Also destroy the shared container"
    option :platform, :aliases => "-p", :type => :boolean, :desc => "Also destroy the platform container"
    def destroy(server_name_regex=nil)
      match_server_name_regex(server_name_regex).reverse_each do |cs|
        cs.destroy
        cs.destroy_container(:unique) if options[:unique]
        cs.destroy_container(:shared) if options[:shared]
        cs.destroy_container(:platform) if options[:platform]
      end
    end

  end
end
