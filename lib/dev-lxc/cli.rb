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
        ::DevLXC::Cluster.new(YAML.load(IO.read(config)))
      end

      def match_server_name_regex(server_name_regex)
        get_cluster(options[:config]).servers.select { |s| s.server.name =~ /#{server_name_regex}/ }
      end
    }

    desc "create [PLATFORM_IMAGE_NAME]", "Create a platform image"
    def create(platform_image_name=nil)
      platform_image_names = %w(p-ubuntu-1204 p-ubuntu-1404 p-centos-5 p-centos-6)
      if platform_image_name.nil? || ! platform_image_names.include?(platform_image_name)
        platform_image_names_with_index = platform_image_names.map.with_index{ |a, i| [i+1, *a]}
        print_table platform_image_names_with_index
        selection = ask("Which platform image do you want to create?", :limited_to => platform_image_names_with_index.map{|c| c[0].to_s})
        platform_image_name = platform_image_names[selection.to_i - 1]
      end
      ::DevLXC.create_platform_image(platform_image_name)
    end

    desc "init [TOPOLOGY] [UNIQUE_STRING]", "Provide a cluster config file with optional uniqueness in server names and FQDNs"
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
        config_hash['chef-server']['servers'].keys.each do |server_name|
          config.gsub!(/ #{server_name}:/, " #{unique_string}#{server_name}:")
        end
        config_hash['analytics']['servers'].keys.each do |server_name|
          config.gsub!(/ #{server_name}:/, " #{unique_string}#{server_name}:")
        end
      end
      puts config
    end

    desc "status [SERVER_NAME_REGEX]", "Show status of servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def status(server_name_regex=nil)
      cluster = get_cluster(options[:config])
      puts "Chef Server: https://#{cluster.api_fqdn}\n\n"
      puts "Analytics:   https://#{cluster.analytics_fqdn}\n\n" if cluster.analytics_fqdn
      match_server_name_regex(server_name_regex).each { |s| s.status }
    end

    desc "abspath [SERVER_NAME_REGEX] [ROOTFS_PATH]", "Returns the absolute path to a file in each server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def abspath(server_name_regex=nil, rootfs_path)
      abspath = Array.new
      match_server_name_regex(server_name_regex).map { |s| abspath << s.abspath(rootfs_path) }
      puts abspath.compact.join(" ")
    end

    desc "chef-repo", "Creates a `bootstrap-node` script and chef-repo in the current directory using files from the cluster's backend /root/chef-repo"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def chef_repo
      get_cluster(options[:config]).chef_repo
    end

    desc "list_images [SERVER_NAME_REGEX]", "List of each servers' images created during the build process"
    option :config, :aliases => "-c", :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def list_images(server_name_regex=nil)
      images = Hash.new { |h,k| h[k] = Hash.new { |h,k| h[k] = Array.new } }
      match_server_name_regex(server_name_regex).each do |s|
        images[s.platform_image_name][s.shared_image_name] << s.server.name
      end
      images.each_with_index do |(platform_name, shared), images_index|
        shared.each_with_index do |(shared_name, final), shared_index|
          printf "Platform: %21s  %s\n", (LXC::Container.new(platform_name).defined? ? "Created" : "Not Created"), platform_name
          puts "|"
          printf "\\_ Shared: %20s  %s\n", (LXC::Container.new(shared_name).defined? ? "Created" : "Not Created"), shared_name
          final.each_with_index do |final_name, final_index|
            puts "   |"
            unique_name = "u-#{final_name}"
            printf "   \\_ Unique: %17s  %s\n", (LXC::Container.new(unique_name).defined? ? "Created" : "Not Created"), unique_name

            shared_connector = (final_index + 1 < final.length ? "|" : " ")

            custom_name = "c-#{final_name}"
            if LXC::Container.new(custom_name).defined?
              printf "   #{shared_connector}  \\_ Custom: %14s  %s\n", "Created", custom_name
              custom_spacing = "   "
              final_width = 12
            else
              final_width = 15
            end
            printf "   #{shared_connector}  #{custom_spacing}\\_ Final: %#{final_width}s    %s\n", (LXC::Container.new(final_name).defined? ? "Created" : "Not Created"), final_name
          end
          puts if (shared_index + 1 < shared.length) || (images_index + 1 < images.length)
        end
      end
    end

    desc "run_command [SERVER_NAME_REGEX] [COMMAND]", "Runs a command in each server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def run_command(server_name_regex=nil, command)
      match_server_name_regex(server_name_regex).each { |s| s.run_command(command) }
    end

    desc "up [SERVER_NAME_REGEX]", "Start servers - This is the default if no subcommand is given"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def up(server_name_regex=nil)
      match_server_name_regex(server_name_regex).each { |s| s.start }
    end

    desc "halt [SERVER_NAME_REGEX]", "Stop servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def halt(server_name_regex=nil)
      match_server_name_regex(server_name_regex).reverse_each { |s| s.stop }
    end

    desc "snapshot [SERVER_NAME_REGEX]", "Create a snapshot of servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :force, :aliases => "-f", :type => :boolean, :desc => "Overwrite existing custom images"
    def snapshot(server_name_regex=nil)
      non_stopped_servers = Array.new
      existing_custom_images = Array.new
      match_server_name_regex(server_name_regex).each do |s|
        non_stopped_servers << s.server.name if s.server.state != :stopped
        existing_custom_images << s.server.name if LXC::Container.new("c-#{s.server.name}").defined?
      end
      unless non_stopped_servers.empty?
        puts "WARNING: Aborting snapshot because the following servers are not stopped"
        puts non_stopped_servers
        exit 1
      end
      unless existing_custom_images.empty? || options[:force]
        puts "WARNING: The following servers already have a custom image"
        puts "         Use the `--force` or `-f` option to overwrite existing custom images"
        puts existing_custom_images
        exit 1
      end
      match_server_name_regex(server_name_regex).each { |s| s.snapshot(options[:force]) }
    end

    desc "destroy [SERVER_NAME_REGEX]", "Destroy servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :custom, :aliases => "-c", :type => :boolean, :desc => "Also destroy the custom images"
    option :unique, :aliases => "-u", :type => :boolean, :desc => "Also destroy the unique images"
    option :shared, :aliases => "-s", :type => :boolean, :desc => "Also destroy the shared images"
    option :platform, :aliases => "-p", :type => :boolean, :desc => "Also destroy the platform images"
    def destroy(server_name_regex=nil)
      match_server_name_regex(server_name_regex).reverse_each do |s|
        s.destroy
        s.destroy_image(:custom) if options[:custom]
        s.destroy_image(:unique) if options[:unique]
        s.destroy_image(:shared) if options[:shared]
        s.destroy_image(:platform) if options[:platform]
      end
    end

  end
end
