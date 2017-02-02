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
        cluster_config = YAML.load(IO.read(config_file))
        ::DevLXC::Cluster.new(cluster_config)
      end

      def print_elapsed_time(elapsed_time)
        printf "dev-lxc is finished. (%im %.2fs)\n", elapsed_time / 60, elapsed_time % 60
      end
    }

    desc "show-config", "Show calculated configuration"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :include_products, :type => :boolean, :desc => "Calculate required products"
    def show_config
      get_cluster(options[:config]).show_config(options[:include_products])
    end

    desc "create-base-container [BASE_CONTAINER_NAME]", "Create a base container"
    option :options, :aliases => "-o", :desc => "Specify additional options for the lxc create"
    def create_base_container(base_container_name=nil)
      start_time = Time.now
      base_container_names = %w(b-ubuntu-1204 b-ubuntu-1404 b-ubuntu-1604 b-centos-5 b-centos-6 b-centos-7)
      if base_container_name.nil? || ! base_container_names.include?(base_container_name)
        base_container_names_with_index = base_container_names.map.with_index{ |a, i| [i+1, *a]}
        print_table base_container_names_with_index
        selection = ask("Which base container do you want to create?", :limited_to => base_container_names_with_index.map{|c| c[0].to_s})
        base_container_name = base_container_names[selection.to_i - 1]
      end
      ::DevLXC.create_base_container(base_container_name, options[:options])
      puts
      print_elapsed_time(Time.now - start_time)
    end

    desc "init", "Provide a cluster config file"
    option :chef, :type => :boolean, :desc => "Standalone Chef Server"
    option :chef_tier, :type => :boolean, :desc => "Chef Server using Tier topology with one backend"
    option :chef_backend, :type => :boolean, :desc => "Chef Server using Chef Backend HA topology with three backends"
    option :nodes, :type => :boolean, :desc => "Node Servers"
    option :analytics, :type => :boolean, :desc => "Analytics Server"
    option :compliance, :type => :boolean, :desc => "Compliance Server"
    option :supermarket, :type => :boolean, :desc => "Supermarket Server"
    option :automate, :type => :boolean, :desc => "Automate Server"
    option :build_nodes, :type => :boolean, :desc => "Build Nodes"
    option :runners, :type => :boolean, :desc => "Runners"
    option :adhoc, :type => :boolean, :desc => "Adhoc Servers"
    option :append, :aliases => "-a", :type => :boolean, :desc => "Do not generate the global config header"
    option :filename, :aliases => "-f", :desc => "Write generated content to FILE rather than standard output."
    def init
      header = %Q(# enable_build_snapshots automatically makes container snapshots at key times during the build process
# default value is `true`
#enable_build_snapshots: true

# base_container must be the name of an existing container
base_container: b-ubuntu-1404

# list any host directories you want mounted into the servers
#mounts:
#  - /root/work root/work

# list any SSH public keys you want added to /home/dev-lxc/.ssh/authorized_keys
#ssh-keys:
#  - /root/work/clusters/id_rsa.pub

# DHCP reserved (static) IPs must be selected from the IP range 10.0.3.150 - 254
)
      chef_tier_config = %Q(
chef-server:
  topology: tier
  api_fqdn: chef.lxc
  users:          # a user's password will be the same as its username
    - mary-admin
    - joe-user
  orgs:
    demo:
      admins:
        - mary-admin
      non-admins:
        - joe-user
  servers:
    chef-be.lxc:
      ipaddress: 10.0.3.201
      role: backend
      bootstrap: true
      products:
        chef-server:
        push-jobs-server:
        reporting:
    chef-fe1.lxc:
      ipaddress: 10.0.3.202
      role: frontend
      products:
        chef-server:
        manage:
        push-jobs-server:
        reporting:
)
      chef_config = %Q(
chef-server:
  users:          # a user's password will be the same as its username
    - mary-admin
    - joe-user
  orgs:
    demo:
      admins:
        - mary-admin
      non-admins:
        - joe-user
  servers:
    chef.lxc:
      ipaddress: 10.0.3.203
      products:
        chef-server:
        manage:
        push-jobs-server:
        reporting:
)
      automate_config = %Q(
automate:
  servers:
    automate.lxc:
      ipaddress: 10.0.3.200
      products:
        delivery:
      license_path: /path/for/automate.license
      chef_org: delivery
      enterprise_name: demo-ent
)
      build_nodes_config = %Q(
build-nodes:
  servers:
    build-node-1.lxc:
      products:
        chefdk:     # downloaded only
)
      runners_config = %Q(
runners:
  servers:
    runner-1.lxc:
      products:
        chefdk:     # downloaded only
)
      analytics_config = %Q(
analytics:
  servers:
    analytics.lxc:
      ipaddress: 10.0.3.204
      products:
        analytics:
)
      compliance_config = %Q(
compliance:
  admin_user: admin         # the password will be the same as the username
  servers:
    compliance.lxc:
      ipaddress: 10.0.3.205
      products:
        compliance:
)
      supermarket_config = %Q(
supermarket:
  servers:
    supermarket.lxc:
      ipaddress: 10.0.3.206
      products:
        supermarket:
)
      adhoc_config = %Q(
adhoc:
  servers:
    adhoc.lxc:
      ipaddress: 10.0.3.207
)
      chef_backend_config = %Q(
chef-backend:
  api_fqdn: chef.lxc
  users:          # a user's password will be the same as its username
    - mary-admin
    - joe-user
  orgs:
    demo:
      admins:
        - mary-admin
      non-admins:
        - joe-user
  servers:
    chef-backend1.lxc:
      ipaddress: 10.0.3.208
      role: backend
      leader: true
      products:
        chef-backend:
    chef-backend2.lxc:
      ipaddress: 10.0.3.209
      role: backend
      products:
        chef-backend:
    chef-backend3.lxc:
      ipaddress: 10.0.3.210
      role: backend
      products:
        chef-backend:
    chef-frontend1.lxc:
      ipaddress: 10.0.3.211
      role: frontend
      bootstrap: true
      products:
        chef-server:
        manage:
)
      nodes_config = %Q(
nodes:
  chef_server_url: https://chef.lxc/organizations/demo
  validation_client_name: demo-validator
  # comment out or remove the validation_key path to use chef-server keys generated by dev-lxc
  validation_key: # /path/for/ORG-validator.pem
  servers:
    node-1.lxc:
      products:
        chef:
)
      config = ""
      config += header unless options[:append]
      config += chef_config if options[:chef]
      config += chef_tier_config if options[:chef_tier]
      config += analytics_config if options[:analytics]
      config += compliance_config if options[:compliance]
      config += supermarket_config if options[:supermarket]
      config += automate_config if options[:automate]
      config += build_nodes_config if options[:build_nodes]
      config += runners_config if options[:runners]
      config += adhoc_config if options[:adhoc]
      config += chef_backend_config if options[:chef_backend]
      config += nodes_config if options[:nodes]
      if options[:filename]
        mode = options[:append] ? 'a' : 'w'
        IO.write(options[:filename], config, mode: mode)
      else
        puts config
      end
    end

    desc "status [SERVER_NAME_REGEX]", "Show status of servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def status(server_name_regex=nil)
      cluster = get_cluster(options[:config])
      if cluster.config['chef-server'][:topology] == "tier" && cluster.config['chef-server'][:fqdn]
        printf "Chef Server FQDN: %s\n\n", cluster.config['chef-server'][:fqdn]
      end
      if cluster.config['chef-backend'][:fqdn]
        printf "Chef Server FQDN: %s\n\n", cluster.config['chef-backend'][:fqdn]
      end
      if cluster.config['analytics'][:topology] == "tier" && cluster.config['analytics'][:fqdn]
        printf "Analytics FQDN: %s\n\n", cluster.config['analytics'][:fqdn]
      end
      servers = Array.new
      cluster.get_sorted_servers(server_name_regex).map { |s| servers << s.status }
      max_server_name_length = servers.max_by { |s| s['name'].length }['name'].length unless servers.empty?
      servers.each_with_index do |s, server_index|
        printf "%-#{max_server_name_length}s     %-15s %s\n", s['name'], s['state'].upcase, s['ip_addresses']
        server = cluster.get_server(s['name'])
        server.snapshot_list.each do |snapname, snaptime, snap_comment|
          printf "  |_ %s %s %s\n", snapname, snaptime, snap_comment
        end
        puts if server_index + 1 < servers.length
      end
    end

    desc "attach [SERVER_NAME_REGEX]", "Attach the terminal to a single server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def attach(server_name_regex)
      servers = get_cluster(options[:config]).get_sorted_servers(server_name_regex)
      if servers.length > 1
        puts "ERROR: The following servers matched '#{server_name_regex}'"
        servers.map { |s| puts "       #{s.name}" }
        puts "       Please specify a single server to attach to"
        exit 1
      elsif servers.empty?
        puts "ERROR: No servers matched '#{server_name_regex}'"
        puts "       Please specify a single server to attach to"
        exit 1
      end
      container = servers.first.container
      if !container.defined? || !container.running?
        puts "ERROR: Server '#{container.name}' is not running"
        exit 1
      end
      attach_opts = {
        wait: true,
        env_policy: LXC::LXC_ATTACH_CLEAR_ENV,
        extra_env_vars: ["LANG=en_US.UTF-8", "TERM=linux", "HOME=#{ENV['HOME']}"]
      }
      shell = ENV['SHELL']
      container.attach(attach_opts) { system(shell) }
    end

    desc "chef-repo", "Creates a chef-repo in the current directory using files from the cluster's backend /root/chef-repo"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :force, :aliases => "-f", :type => :boolean, :desc => "Overwrite any existing knife.rb or pivotal.rb files"
    option :pivotal, :aliases => "-p", :type => :boolean, :desc => "Also copy pivotal.rb and pivotal.pem"
    def chef_repo
      get_cluster(options[:config]).chef_repo(options[:force], options[:pivotal])
    end

    desc "print-automate-credentials", "Print Automate credentials"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def print_automate_credentials
      get_cluster(options[:config]).print_automate_credentials
    end

    desc "run-command [SERVER_NAME_REGEX] [COMMAND]", "Runs a command in each server"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def run_command(server_name_regex=nil, command)
      start_time = Time.now
      get_cluster(options[:config]).get_sorted_servers(server_name_regex).each { |s| s.run_command(command); puts }
      print_elapsed_time(Time.now - start_time)
    end

    desc "prepare-product-cache [SERVER_NAME_REGEX]", "Download required product packages to cache"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def prepare_product_cache(server_name_regex=nil)
      start_time = Time.now
      cluster = get_cluster(options[:config])
      servers = cluster.get_sorted_servers(server_name_regex)
      cluster.prep_product_cache(servers, true)
      print_elapsed_time(Time.now - start_time)
    end

    desc "up [SERVER_NAME_REGEX]", "Start servers - This is the default if no subcommand is given"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def up(server_name_regex=nil)
      start_time = Time.now
      get_cluster(options[:config]).up(server_name_regex)
      print_elapsed_time(Time.now - start_time)
    end

    desc "halt [SERVER_NAME_REGEX]", "Shutdown servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    def halt(server_name_regex=nil)
      start_time = Time.now
      get_cluster(options[:config]).halt(server_name_regex)
      print_elapsed_time(Time.now - start_time)
    end

    desc "snapshot [SERVER_NAME_REGEX]", "Manage a cluster's snapshots"
    option :comment, :aliases => "-c", :desc => "Add snapshot comment"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :destroy, :aliases => "-d", :desc => "Destroy snapshot - use ALL to destroy all snapshots"
    option :list, :aliases => "-l", :type => :boolean, :desc => "List snapshots"
    option :restore, :aliases => "-r", :desc => "Restore snapshots"
    def snapshot(server_name_regex=nil)
      start_time = Time.now
      servers = get_cluster(options[:config]).get_sorted_servers(server_name_regex)
      if options[:list]
        servers.each_with_index do |s, server_index|
          puts s.name
          s.snapshot_list.each do |snapname, snaptime, snap_comment|
            printf "  |_ %s %s %s\n", snapname, snaptime, snap_comment
          end
          puts if server_index + 1 < servers.length
        end
        return
      elsif options[:destroy]
        snapname = options[:destroy] == 'destroy' ? "LAST" : options[:destroy]
        servers.each { |s| s.snapshot_destroy(snapname); puts }
      elsif options[:restore]
        running_servers = Array.new
        servers.each do |s|
          running_servers << s.name if s.container.running?
        end
        unless running_servers.empty?
          puts "ERROR: Aborting snapshot restore because the following servers are running"
          puts running_servers
          exit 1
        end
        snapname = options[:restore] == 'restore' ? "LAST" : options[:restore]
        servers.each { |s| s.snapshot_restore(snapname); puts }
      else
        running_servers = Array.new
        servers.each do |s|
          running_servers << s.name if s.container.running?
        end
        unless running_servers.empty?
          puts "ERROR: Aborting snapshot because the following servers are running"
          puts running_servers
          exit 1
        end
        servers.each { |s| s.snapshot(options[:comment]); puts }
      end
      print_elapsed_time(Time.now - start_time)
    end

    desc "destroy [SERVER_NAME_REGEX]", "Destroy servers"
    option :config, :desc => "Specify a cluster's YAML config file. `./dev-lxc.yml` will be used by default"
    option :force, :aliases => "-f", :type => :boolean, :desc => "Destroy servers without confirmation"
    def destroy(server_name_regex=nil)
      servers = get_cluster(options[:config]).get_sorted_servers(server_name_regex)
      if servers.empty?
        puts "No matching server names were found"
        exit
      end
      unless options[:force]
        confirmation_string = String.new
        servers.reverse_each { |s| confirmation_string += "#{s.name}\n" }
        confirmation_string += "Are you sure you want to destroy these servers? (y/N)\n"
        return unless yes?(confirmation_string)
      end
      start_time = Time.now
      get_cluster(options[:config]).destroy(server_name_regex)
      print_elapsed_time(Time.now - start_time)
    end

  end
end
