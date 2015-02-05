require "yaml"
require 'dev-lxc'
require 'thor'

module DevLXC::CLI
  class Cluster < Thor
    no_commands{
      def get_cluster(config_option)
        config = "dev-lxc.yaml" if File.exists?("dev-lxc.yaml")
        config = config_option unless config_option.nil?
        raise "A cluster config file must be provided" if config.nil?
        ::DevLXC::ChefCluster.new(YAML.load(IO.read(config)))
      end
    }

    desc "init [TOPOLOGY]", "Provide a cluster config file"
    def init(topology=nil)
      topologies = %w(open-source standalone tier)
      if topology.nil? || ! topologies.include?(topology)
        topologies_with_index = topologies.map.with_index{ |a, i| [i+1, *a]}
        print_table topologies_with_index
        selection = ask("Which cluster topology do you want to use?", :limited_to => topologies_with_index.map{|c| c[0].to_s})
        topology = topologies[selection.to_i - 1]
      end
      puts IO.read("#{File.dirname(__FILE__)}/../../files/configs/#{topology}.yaml")
    end

    desc "status", "Show status of a cluster's Chef servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def status
      get_cluster(options[:config]).status
    end

    desc "abspath [ROOTFS_PATH]", "Returns the absolute path to a file for each Chef server in a cluster"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def abspath(rootfs_path)
      puts get_cluster(options[:config]).abspath(rootfs_path).join(" ")
    end

    desc "chef-repo", "Creates a chef-repo in the current directory using files from the cluster's backend /root/chef-repo"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def chef_repo
      get_cluster(options[:config]).chef_repo
    end

    desc "run_command [COMMAND]", "Runs a command in each Chef server in a cluster"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def run_command(command)
      get_cluster(options[:config]).run_command(command)
    end

    desc "start", "Start a cluster's Chef servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def start
      get_cluster(options[:config]).start
    end

    desc "stop", "Stop a cluster's Chef servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def stop
      get_cluster(options[:config]).stop
    end

    desc "destroy", "Destroy a cluster's Chef servers"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    option :unique, :aliases => "-u", :type => :boolean, :desc => "Also destroy the cluster's unique containers"
    option :shared, :aliases => "-s", :type => :boolean, :desc => "Also destroy the cluster's shared container"
    option :platform, :aliases => "-p", :type => :boolean, :desc => "Also destroy the cluster's platform container"
    def destroy
      cluster = get_cluster(options[:config])
      cluster.destroy
      cluster.destroy_container(:unique) if options[:unique]
      cluster.destroy_container(:shared) if options[:shared]
      cluster.destroy_container(:platform) if options[:platform]
    end
  end

  class Server < Thor
    no_commands{
      def get_server(name, config_option)
        config = "dev-lxc.yaml" if File.exists?("dev-lxc.yaml")
        config = config_option unless config_option.nil?
        raise "A cluster config file must be provided" if config.nil?
        ::DevLXC::ChefServer.new(name, YAML.load(IO.read(config)))
      end
    }

    desc "status [NAME]", "Show status of a cluster's Chef server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def status(name)
      get_server(name, options[:config]).status
    end

    desc "abspath [NAME] [ROOTFS_PATH]", "Returns the absolute path to a file in a cluster's Chef server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def abspath(name, rootfs_path)
      puts get_server(name, options[:config]).abspath(rootfs_path)
    end

    desc "run_command [NAME] [COMMAND]", "Runs a command in a cluster's Chef server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def run_command(name, command)
      get_server(name, options[:config]).run_command(command)
    end

    desc "start [NAME]", "Start a cluster's Chef server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def start(name)
      get_server(name, options[:config]).start
    end

    desc "stop [NAME]", "Stop a cluster's Chef server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    def stop(name)
      get_server(name, options[:config]).stop
    end

    desc "destroy [NAME]", "Destroy a cluster's Chef server"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. ./dev-lxc.yaml will be used by default"
    option :unique, :aliases => "-u", :type => :boolean, :desc => "Also destroy the server's unique container"
    option :shared, :aliases => "-s", :type => :boolean, :desc => "Also destroy the server's shared container"
    option :platform, :aliases => "-p", :type => :boolean, :desc => "Also destroy the server's platform container"
    def destroy(name)
      server = get_server(name, options[:config])
      server.destroy
      server.destroy_container(:unique) if options[:unique]
      server.destroy_container(:shared) if options[:shared]
      server.destroy_container(:platform) if options[:platform]
    end
  end

  class DevLXC < Thor
    desc "create [PLATFORM_CONTAINER_NAME]", "Create a platform container"
    def create(platform_container_name=nil)
      platform_container_names = %w(p-ubuntu-1004 p-ubuntu-1204 p-ubuntu-1404 p-centos-5 p-centos-6)
      if platform_container_name.nil? || ! platform_container_names.include?(platform_container_name)
        platform_container_names_with_index = platform_container_names.map.with_index{ |a, i| [i+1, *a]}
        print_table platform_container_names_with_index
        selection = ask("Which platform container do you want to create?", :limited_to => platform_container_names_with_index.map{|c| c[0].to_s})
        platform_container_name = platform_container_names[selection.to_i - 1]
      end
      ::DevLXC.create_platform_container(platform_container_name)
    end

    desc "cluster SUBCOMMAND ...ARGS", "Manage Chef cluster"
    subcommand "cluster", Cluster

    desc "server SUBCOMMAND ...ARGS", "Manage Chef server"
    subcommand "server", Server
  end
end
