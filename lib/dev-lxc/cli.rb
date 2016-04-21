require "yaml"
require 'dev-lxc'
require 'thor'

module DevLXC::CLI
  class DevLXC < Thor

    no_commands{
      def get_cluster(config_file=nil)
        config_file ||= "dev-lxc.yml"
        if ! File.exists?(config_file)
          puts "ERROR: Cluster config file '#{config_file}' does not exist."
          puts "       Create a `./dev-lxc.yml` file or specify the path using `--config`."
          exit 1
        end
        ::DevLXC::Cluster.new(YAML.load(IO.read(config_file)))
      end

      def match_server_name_regex(server_name_regex)
        get_cluster(options[:config]).servers.select { |s| s.server.name =~ /#{server_name_regex}/ }
      end

      def print_elapsed_time(elapsed_time)
        printf "dev-lxc is finished. (%im %.2fs)\n", elapsed_time / 60, elapsed_time % 60
      end
    }

    desc "create [PLATFORM_IMAGE_NAME]", "Create a platform image"
    option :options, :aliases => "-o", :desc => "Specify additional options for the lxc create"
    def create(platform_image_name=nil)
      start_time = Time.now
      platform_image_names = %w(p-ubuntu-1204 p-ubuntu-1404 p-ubuntu-1504 p-centos-5 p-centos-6 p-centos-7)
      if platform_image_name.nil? || ! platform_image_names.include?(platform_image_name)
        platform_image_names_with_index = platform_image_names.map.with_index{ |a, i| [i+1, *a]}
        print_table platform_image_names_with_index
        selection = ask("Which platform image do you want to create?", :limited_to => platform_image_names_with_index.map{|c| c[0].to_s})
        platform_image_name = platform_image_names[selection.to_i - 1]
      end
      ::DevLXC.create_platform_image(platform_image_name, options[:options])
      puts
      print_elapsed_time(Time.now - start_time)
    end

    desc "install-chef-client [CONTAINER_NAME]", "Install Chef Client in container"
    option :version, :aliases => "-v", :desc => "Specify the version of Chef Client to install"
    def install_chef_client(container_name)
      start_time = Time.now
      container = ::DevLXC::Container.new(container_name)
      container.install_chef_client(options[:version])
      puts
      print_elapsed_time(Time.now - start_time)
    end

    desc "configure-chef-client [CONTAINER_NAME]", "Configure Chef Client in container"
    option :chef_server_url, :aliases => "-s", :desc => "Specify the URL of the Chef Server"
    option :validation_client_name, :aliases => "-u", :desc => "Specify the name of the validation client"
    option :validation_key, :aliases => "-k", :desc => "Specify the path to the validation key"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def configure_chef_client(container_name)
      start_time = Time.now
      chef_server_url = options[:chef_server_url]
      validation_client_name = options[:validation_client_name]
      validation_key = options[:validation_key]
      if chef_server_url.nil? && validation_client_name.nil? && validation_key.nil?
        cluster = get_cluster(options[:config])
        chef_server_bootstrap_backend = ::DevLXC::Container.new(cluster.chef_server_bootstrap_backend, cluster.lxc_config_path)
        unless chef_server_bootstrap_backend.defined?
          puts "ERROR: Can not copy validation key because Chef Server '#{chef_server_bootstrap_backend.name}' is not created."
          exit 1
        end
        chef_server_url = "https://#{cluster.api_fqdn}/organizations/demo"
        validation_client_name = 'demo-validator'
        validation_key = "#{chef_server_bootstrap_backend.config_item('lxc.rootfs')}/root/chef-repo/.chef/demo-validator.pem"
      elsif chef_server_url.nil? || validation_client_name.nil? || validation_key.nil?
        puts "ERROR: All of the --chef-server-url, --validation-client-name and --validation-key options must be set or left unset. Do not set only some of these options."
        exit 1
      end
      container = ::DevLXC::Container.new(container_name)
      container.configure_chef_client(chef_server_url, validation_client_name, validation_key)
      puts
      print_elapsed_time(Time.now - start_time)
    end

    desc "bootstrap-container [BASE_CONTAINER_NAME] [CONTAINER_NAME]", "Bootstrap Chef Client in container"
    option :version, :aliases => "-v", :desc => "Specify the version of Chef Client to install"
    option :run_list, :aliases => "-r", :desc => "Specify the Chef Client run_list"
    option :chef_server_url, :aliases => "-s", :desc => "Specify the URL of the Chef Server"
    option :validation_client_name, :aliases => "-u", :desc => "Specify the name of the validation client"
    option :validation_key, :aliases => "-k", :desc => "Specify the path to the validation key"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def bootstrap_container(base_container_name=nil, container_name)
      start_time = Time.now
      chef_server_url = options[:chef_server_url]
      validation_client_name = options[:validation_client_name]
      validation_key = options[:validation_key]
      if chef_server_url.nil? && validation_client_name.nil? && validation_key.nil?
        cluster = get_cluster(options[:config])
        chef_server_bootstrap_backend = ::DevLXC::Container.new(cluster.chef_server_bootstrap_backend, cluster.lxc_config_path)
        unless chef_server_bootstrap_backend.defined?
          puts "ERROR: Can not copy validation key because Chef Server '#{chef_server_bootstrap_backend.name}' is not created."
          exit 1
        end
        chef_server_url = "https://#{cluster.api_fqdn}/organizations/demo"
        validation_client_name = 'demo-validator'
        validation_key = "#{chef_server_bootstrap_backend.config_item('lxc.rootfs')}/root/chef-repo/.chef/demo-validator.pem"
      elsif chef_server_url.nil? || validation_client_name.nil? || validation_key.nil?
        puts "ERROR: All of the --chef-server-url, --validation-client-name and --validation-key options must be set or left unset. Do not set only some of these options."
        exit 1
      end
      container = ::DevLXC::Container.new(container_name)
      container.bootstrap_container(base_container_name, options[:version], options[:run_list], chef_server_url, validation_client_name, validation_key)
      puts
      print_elapsed_time(Time.now - start_time)
    end

    desc "init [UNIQUE_STRING]", "Provide a cluster config file with optional uniqueness in server names and FQDNs"
    option :open_source, :type => :boolean, :desc => "Standalone Old Open Source Chef Server"
    option :tiered_chef, :type => :boolean, :desc => "Tiered Chef Server"
    option :chef, :type => :boolean, :desc => "Standalone Chef Server"
    option :analytics, :type => :boolean, :desc => "Analytics Server"
    option :compliance, :type => :boolean, :desc => "Compliance Server"
    option :supermarket, :type => :boolean, :desc => "Supermarket Server"
    option :adhoc, :type => :boolean, :desc => "Adhoc Servers"
    def init(unique_string=nil)
      header = %Q(## platform_image can be one of the following:
## p-centos-5, p-centos-6, p-centos-7, p-ubuntu-1204, p-ubuntu-1404 or p-ubuntu-1504

## platform_image_options can be set to provide additional arguments to the LXC create command.
## reference arg examples: https://github.com/lxc/lxc/blob/lxc-2.0.0/templates/lxc-download.in#L200-L207
## for example:
## platform_image_options: --no-validate --keyserver http://my.key.server.com

## Make sure all mount source directories exist in the LXC host

## Make sure all package paths are correct

## All FQDNs and server names must end with the `.lxc` domain

## DHCP reserved (static) IPs must be selected from the IP range 10.0.3.150 - 254

## topology can be one of the following:
## standalone (default), tier or open-source (for the old open source 11 chef server)

platform_image: p-ubuntu-1404
mounts:
  - /root/dev root/dev
)
      open_source_packages = %Q(  packages:
    server: /root/dev/chef-packages/osc/chef-server_11.1.6-1_amd64.deb
)
      chef_server_packages = %Q(  packages:
    server: /root/dev/chef-packages/cs/chef-server-core_12.5.0-1_amd64.deb
    manage: /root/dev/chef-packages/manage/chef-manage_2.2.1-1_amd64.deb
    reporting: /root/dev/chef-packages/reporting/opscode-reporting_1.5.6-1_amd64.deb
    push-jobs-server: /root/dev/chef-packages/push-jobs-server/opscode-push-jobs-server_1.1.6-1_amd64.deb
)
      analytics_packages = %Q(  packages:
    analytics: /root/dev/chef-packages/analytics/opscode-analytics_1.3.1-1_amd64.deb
)
      compliance_packages = %Q(  packages:
    compliance: /root/dev/chef-packages/compliance/chef-compliance_1.1.2-1_amd64.deb
)
      supermarket_packages = %Q(  packages:
    supermarket: /root/dev/chef-packages/supermarket/supermarket_2.5.2-1_amd64.deb
)
      open_source_config = %Q(
chef-server:
#{open_source_packages.chomp}
  api_fqdn: chef.lxc
  topology: open-source
  servers:
    osc-chef.lxc:
      ipaddress: 10.0.3.200
)
      tiered_chef_config = %Q(
chef-server:
#{chef_server_packages.chomp}
  topology: tier
  api_fqdn: chef.lxc
  servers:
    chef-be.lxc:
      ipaddress: 10.0.3.201
      role: backend
      bootstrap: true
    chef-fe1.lxc:
      ipaddress: 10.0.3.202
      role: frontend
)
      chef_config = %Q(
chef-server:
#{chef_server_packages.chomp}
  servers:
    chef.lxc:
      ipaddress: 10.0.3.203
)
      analytics_config = %Q(
analytics:
#{analytics_packages.chomp}
  servers:
    analytics.lxc:
      ipaddress: 10.0.3.204
)
      compliance_config = %Q(
compliance:
#{compliance_packages.chomp}
  servers:
    compliance.lxc:
      ipaddress: 10.0.3.205
)
      supermarket_config = %Q(
supermarket:
#{supermarket_packages.chomp}
  servers:
    supermarket.lxc:
      ipaddress: 10.0.3.206
)
      adhoc_config = %Q(
adhoc:
  servers:
    adhoc.lxc:
      ipaddress: 10.0.3.207
)
      config = header
      config += open_source_config if options[:open_source]
      config += chef_config if options[:chef]
      config += tiered_chef_config if options[:tiered_chef]
      config += analytics_config if options[:analytics]
      config += compliance_config if options[:compliance]
      config += supermarket_config if options[:supermarket]
      config += adhoc_config if options[:adhoc]
      unless unique_string.nil?
        config_hash = YAML.load(config.gsub(/^#/, ''))
        config.gsub!(/api_fqdn:\s+#{config_hash['api_fqdn']}/, "api_fqdn: #{unique_string}#{config_hash['api_fqdn']}")
        config.gsub!(/analytics_fqdn:\s+#{config_hash['analytics_fqdn']}/, "analytics_fqdn: #{unique_string}#{config_hash['analytics_fqdn']}")
        %w(chef-server analytics compliance supermarket adhoc).each do |server_type|
          if config_hash[server_type]
            config_hash[server_type]['servers'].keys.each do |server_name|
              config.gsub!(/ #{server_name}:/, " #{unique_string}#{server_name}:")
            end
          end
        end
      end
      puts config
    end

    desc "global-status", "Show status of all dev-lxc images and servers"
    def global_status
      containers = Array.new
      LXC::list_containers({config_path: '/var/lib/dev-lxc'}).map { |c| containers << ::DevLXC::Container.new(c, '/var/lib/dev-lxc').status }
      max_container_name_length = containers.max_by { |c| c['name'].length }['name'].length unless containers.empty?
      containers.each { |c| printf "%#{max_container_name_length}s     %-15s %s\n", c['name'], c['state'], c['ip_addresses'] }
    end

    desc "status [SERVER_NAME_REGEX]", "Show status of servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def status(server_name_regex=nil)
      cluster = get_cluster(options[:config])
      puts "Chef Server FQDN: #{cluster.api_fqdn}\n" if cluster.api_fqdn
      puts "Analytics FQDN:   #{cluster.analytics_fqdn}\n" if cluster.analytics_fqdn
      puts "Compliance FQDN:  #{cluster.compliance_fqdn}\n" if cluster.compliance_fqdn
      puts "Supermarket FQDN: #{cluster.supermarket_fqdn}\n" if cluster.supermarket_fqdn
      puts
      servers = Array.new
      match_server_name_regex(server_name_regex).map { |s| servers << s.server.status }
      max_server_name_length = servers.max_by { |s| s['name'].length }['name'].length unless servers.empty?
      servers.each { |s| printf "%#{max_server_name_length}s     %-15s %s\n", s['name'], s['state'], s['ip_addresses'] }
    end

    desc "realpath [SERVER_NAME_REGEX] [ROOTFS_PATH]", "Returns the real path to a file in each server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def realpath(server_name_regex=nil, rootfs_path)
      realpath = Array.new
      match_server_name_regex(server_name_regex).map { |s| realpath << s.realpath(rootfs_path) }
      puts realpath.compact
    end

    desc "attach [SERVER_NAME_REGEX]", "Attach the terminal to a single server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def attach(server_name_regex)
      servers = match_server_name_regex(server_name_regex)
      if servers.length > 1
        puts "ERROR: The following servers matched '#{server_name_regex}'"
        servers.map { |s| puts "       #{s.server.name}" }
        puts "       Please specify a single server to attach to"
        exit 1
      elsif servers.empty?
        puts "ERROR: No servers matched '#{server_name_regex}'"
        puts "       Please specify a single server to attach to"
        exit 1
      end
      server = servers.first.server
      unless server.defined? && server.running?
        puts "ERROR: Server '#{server.name}' is not running"
        exit 1
      end
      attach_opts = {
        wait: true,
        env_policy: LXC::LXC_ATTACH_CLEAR_ENV,
        extra_env_vars: ["LANG=en_US.UTF-8", "TERM=linux", "HOME=#{ENV['HOME']}"]
      }
      shell = ENV['SHELL']
      server.attach(attach_opts) { system(shell) }
    end

    desc "chef-repo", "Creates a chef-repo in the current directory using files from the cluster's backend /root/chef-repo"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :force, :aliases => "-f", :type => :boolean, :desc => "Overwrite any existing knife.rb or pivotal.rb files"
    option :pivotal, :aliases => "-p", :type => :boolean, :desc => "Also copy pivotal.rb and pivotal.pem"
    def chef_repo
      get_cluster(options[:config]).chef_repo(options[:force], options[:pivotal])
    end

    desc "list-images [SERVER_NAME_REGEX]", "List of each servers' images created during the build process"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def list_images(server_name_regex=nil)
      lxc_config_path = get_cluster(options[:config]).lxc_config_path
      images = Hash.new { |h,k| h[k] = Hash.new { |h,k| h[k] = Array.new } }
      match_server_name_regex(server_name_regex).each do |s|
        images[s.platform_image_name][s.shared_image_name] << s.server.name
      end
      images.each_with_index do |(platform_name, shared), images_index|
        shared.each_with_index do |(shared_name, final), shared_index|
          printf "Platform: %27s  %s\n", (LXC::Container.new(platform_name, lxc_config_path).defined? ? "Created" : "Not Created"), platform_name
          unless shared_name.empty?
            puts "|"
            printf "\\_ Shared: %26s  %s\n", (LXC::Container.new(shared_name, lxc_config_path).defined? ? "Created" : "Not Created"), shared_name
          end
          final.each_with_index do |final_name, final_index|
            puts "   |"
            unique_name = "u-#{final_name}"
            printf "   \\_ Unique: %23s  %s\n", (LXC::Container.new(unique_name, lxc_config_path).defined? ? "Created" : "Not Created"), unique_name

            shared_connector = (final_index + 1 < final.length ? "|" : " ")

            custom_name = "c-#{final_name}"
            if LXC::Container.new(custom_name, lxc_config_path).defined?
              printf "   #{shared_connector}  \\_ Custom: %20s  %s\n", "Created", custom_name
              custom_spacing = "   "
              final_width = 11
            else
              final_width = 14
            end
            printf "   #{shared_connector}  #{custom_spacing}\\_ Final Server: %#{final_width}s    %s\n", (LXC::Container.new(final_name, lxc_config_path).defined? ? "Created" : "Not Created"), final_name
          end
          puts if (shared_index + 1 < shared.length) || (images_index + 1 < images.length)
        end
      end
    end

    desc "run-command [SERVER_NAME_REGEX] [COMMAND]", "Runs a command in each server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def run_command(server_name_regex=nil, command)
      start_time = Time.now
      match_server_name_regex(server_name_regex).each { |s| s.run_command(command); puts }
      print_elapsed_time(Time.now - start_time)
    end

    desc "up [SERVER_NAME_REGEX]", "Start servers - This is the default if no subcommand is given"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def up(server_name_regex=nil)
      start_time = Time.now
      match_server_name_regex(server_name_regex).each { |s| s.start; puts }
      print_elapsed_time(Time.now - start_time)
    end

    desc "halt [SERVER_NAME_REGEX]", "Stop servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def halt(server_name_regex=nil)
      start_time = Time.now
      match_server_name_regex(server_name_regex).reverse_each { |s| s.stop; puts }
      print_elapsed_time(Time.now - start_time)
    end

    desc "snapshot [SERVER_NAME_REGEX]", "Create a snapshot of servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :force, :aliases => "-f", :type => :boolean, :desc => "Overwrite existing custom images"
    def snapshot(server_name_regex=nil)
      start_time = Time.now
      non_stopped_servers = Array.new
      existing_custom_images = Array.new
      lxc_config_path = get_cluster(options[:config]).lxc_config_path
      match_server_name_regex(server_name_regex).each do |s|
        non_stopped_servers << s.server.name if s.server.state != :stopped
        existing_custom_images << s.server.name if LXC::Container.new("c-#{s.server.name}", lxc_config_path).defined?
      end
      unless non_stopped_servers.empty?
        puts "ERROR: Aborting snapshot because the following servers are not stopped"
        puts non_stopped_servers
        exit 1
      end
      unless existing_custom_images.empty? || options[:force]
        puts "ERROR: The following servers already have a custom image"
        puts "         Use the `--force` or `-f` option to overwrite existing custom images"
        puts existing_custom_images
        exit 1
      end
      match_server_name_regex(server_name_regex).each { |s| s.snapshot(options[:force]); puts }
      print_elapsed_time(Time.now - start_time)
    end

    desc "destroy [SERVER_NAME_REGEX]", "Destroy servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :custom, :aliases => "-c", :type => :boolean, :desc => "Also destroy the custom images"
    option :unique, :aliases => "-u", :type => :boolean, :desc => "Also destroy the unique images"
    option :shared, :aliases => "-s", :type => :boolean, :desc => "Also destroy the shared images"
    option :platform, :aliases => "-p", :type => :boolean, :desc => "Also destroy the platform images"
    def destroy(server_name_regex=nil)
      start_time = Time.now
      match_server_name_regex(server_name_regex).reverse_each do |s|
        s.destroy
        s.destroy_image(:custom) if options[:custom]
        s.destroy_image(:unique) if options[:unique]
        s.destroy_image(:shared) if options[:shared]
        s.destroy_image(:platform) if options[:platform]
        puts
      end
      print_elapsed_time(Time.now - start_time)
    end

  end
end
