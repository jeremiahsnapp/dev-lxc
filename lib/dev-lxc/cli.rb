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
    option :base, :aliases => "-b", :type => :boolean, :desc => "Destroy the cluster's base containers also"
    def destroy
      cluster = get_cluster(options[:config])
      cluster.destroy
      cluster.destroy_base_containers if options[:base]
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
    option :base, :aliases => "-b", :type => :boolean, :desc => "Destroy the server's base containers also"
    def destroy(name)
      server = get_server(name, options[:config])
      server.destroy
      server.destroy_base_containers if options[:base]
    end
  end

  class DevLXC < Thor
    desc "create [BASE_PLATFORM]", "Create a base platform"
    def create(base_platform=nil)
      base_platforms = %w(b-ubuntu-1004 b-ubuntu-1204 b-centos-5 b-centos-6)
      if base_platform.nil? || ! base_platforms.include?(base_platform)
        base_platforms_with_index = base_platforms.map.with_index{ |a, i| [i+1, *a]}
        print_table base_platforms_with_index
        selection = ask("Which base platform do you want to create?", :limited_to => base_platforms_with_index.map{|c| c[0].to_s})
        base_platform = base_platforms[selection.to_i - 1]
      end
      ::DevLXC.create_base_platform(base_platform)
    end

    desc "cluster SUBCOMMAND ...ARGS", "manage Chef cluster"
    subcommand "cluster", Cluster

    desc "server SUBCOMMAND ...ARGS", "manage Chef server"
    subcommand "server", Server
  end
end
