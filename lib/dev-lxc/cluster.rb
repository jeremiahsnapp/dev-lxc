require "dev-lxc/server"
require "mixlib/install"
require "open-uri"

module DevLXC
  class Cluster
    attr_reader :config

    def initialize(cluster_config)
      FileUtils.mkdir_p('/var/dev-lxc') unless Dir.exist?('/var/dev-lxc')

      @config = Hash.new { |hash, key| hash[key] = {} }
      @server_configs = Hash.new

      %w(adhoc analytics automate build-nodes chef-backend chef-server compliance nodes supermarket).each do |server_type|
        if cluster_config[server_type]
          mounts = ["/var/dev-lxc var/dev-lxc"]
          if cluster_config[server_type]["mounts"]
            mounts.concat(cluster_config[server_type]["mounts"])
          elsif cluster_config["mounts"]
            mounts.concat(cluster_config["mounts"])
          end
          ssh_keys = cluster_config[server_type]["ssh-keys"]
          ssh_keys ||= cluster_config["ssh-keys"]
          base_container_name = cluster_config[server_type]["base_container"]
          base_container_name ||= cluster_config["base_container"]

          if cluster_config[server_type]["servers"]
            cluster_config[server_type]["servers"].each do |server_name, server_config|
              server_config ||= Hash.new
              products = server_config['products']
              products ||= Hash.new
              mounts = ["/var/dev-lxc var/dev-lxc"] + server_config["mounts"] if server_config["mounts"]
              ssh_keys = server_config["ssh-keys"] if server_config["ssh-keys"]
              base_container_name = server_config["base_container"] if server_config["base_container"]
              @server_configs[server_name] = {
                server_type: server_type,
                products: products,
                ipaddress: server_config['ipaddress'],
                additional_fqdn: nil,
                mounts: mounts,
                ssh_keys: ssh_keys,
                base_container_name: base_container_name
              }
              # gather configuration from only the first "automate", "compliance" or "supermarket" server
              break if %w(automate compliance supermarket).include?(server_type)
            end
          end

          case server_type
          when "analytics"
            @config[server_type][:topology] = cluster_config[server_type]["topology"]
            @config[server_type][:topology] ||= 'standalone'
            @config[server_type][:fqdn] = cluster_config[server_type]["analytics_fqdn"]
            @config[server_type][:frontends] = Array.new

            if cluster_config[server_type]["servers"]
              cluster_config[server_type]["servers"].each do |server_name, server_config|
                server_config ||= Hash.new
                additional_fqdn = nil
                case @config[server_type][:topology]
                when 'standalone'
                  @config[server_type][:bootstrap_backend] = server_name if server_config["role"].nil?
                  @config[server_type][:fqdn] ||= @config[server_type][:bootstrap_backend]
                when 'tier'
                  @config[server_type][:bootstrap_backend] = server_name if server_config["role"] == "backend" && server_config["bootstrap"] == true
                  if server_config["role"] == "frontend"
                    additional_fqdn = @config[server_type][:fqdn]
                    @config[server_type][:frontends] << server_name
                  end
                end
                @server_configs[server_name].merge!({
                  additional_fqdn: additional_fqdn
                })
              end
            end
          when "chef-backend"
            @config[server_type][:fqdn] = cluster_config[server_type]["api_fqdn"]
            @config[server_type][:users] = cluster_config[server_type]["users"]
            @config[server_type][:users] ||= Array.new
            @config[server_type][:orgs] = cluster_config[server_type]["orgs"]
            @config[server_type][:orgs] ||= Hash.new
            @config[server_type][:backends] = Array.new
            @config[server_type][:frontends] = Array.new

            servers = cluster_config[server_type]["servers"]
            if servers
              @config[server_type][:leader_backend] = servers.select { |s,sc| sc['role'] == 'backend' && sc['leader'] == true }.keys.first
              @config[server_type][:bootstrap_frontend] = servers.select { |s,sc| sc['role'] == 'frontend' && sc['bootstrap'] == true }.keys.first
              @config[server_type][:backends] << @config[server_type][:leader_backend]
              @config[server_type][:frontends] << @config[server_type][:bootstrap_frontend]
              servers.each do |server_name, server_config|
                server_config ||= Hash.new
                additional_fqdn = nil
                case server_config["role"]
                when "backend"
                  @config[server_type][:backends] << server_name unless server_name == @config[server_type][:leader_backend]
                when "frontend"
                  additional_fqdn = @config[server_type][:fqdn]
                  @config[server_type][:frontends] << server_name unless server_name == @config[server_type][:bootstrap_frontend]
                end
                @server_configs[server_name].merge!({
                  additional_fqdn: additional_fqdn,
                  chef_server_type: 'chef-server'
                })
              end
            end
          when "chef-server"
            @config[server_type][:topology] = cluster_config[server_type]["topology"]
            @config[server_type][:topology] ||= 'standalone'
            @config[server_type][:fqdn] = cluster_config[server_type]["api_fqdn"]
            @config[server_type][:users] = cluster_config[server_type]["users"]
            @config[server_type][:users] ||= Array.new
            @config[server_type][:orgs] = cluster_config[server_type]["orgs"]
            @config[server_type][:orgs] ||= Hash.new
            @config[server_type][:frontends] = Array.new

            if cluster_config[server_type]["servers"]
              cluster_config[server_type]["servers"].each do |server_name, server_config|
                server_config ||= Hash.new
                additional_fqdn = nil
                chef_server_type = 'private-chef' if @server_configs[server_name][:products].has_key?('private-chef')
                chef_server_type = 'chef-server' if @server_configs[server_name][:products].has_key?('chef-server')
                case @config[server_type][:topology]
                when 'standalone'
                  @config[server_type][:bootstrap_backend] = server_name if server_config["role"].nil?
                  @config[server_type][:fqdn] ||= @config[server_type][:bootstrap_backend]
                when 'tier'
                  @config[server_type][:bootstrap_backend] = server_name if server_config["role"] == "backend" && server_config["bootstrap"] == true
                  if server_config["role"] == "frontend"
                    additional_fqdn = @config[server_type][:fqdn]
                    @config[server_type][:frontends] << server_name
                  end
                end
                @server_configs[server_name].merge!({
                  additional_fqdn: additional_fqdn,
                  chef_server_type: chef_server_type
                })
              end
            end
          when "supermarket"
            unless cluster_config[server_type]["servers"].first.nil?
              (server_name, server_config) = cluster_config[server_type]["servers"].first
              @config[server_type][:fqdn] = server_name
            end
          when "automate"
            unless cluster_config[server_type]["servers"].first.nil?
              (server_name, server_config) = cluster_config[server_type]["servers"].first
              server_config ||= Hash.new
              @server_configs[server_name].merge!({
                license_path: server_config['license_path'],
                chef_org: server_config['chef_org'],
                enterprise_name: server_config['enterprise_name']
              })
            end
          when "nodes"
            chef_server_url = cluster_config[server_type]['chef_server_url']
            validation_client_name = cluster_config[server_type]['validation_client_name']
            validation_key = cluster_config[server_type]['validation_key']
            if cluster_config[server_type]["servers"]
              cluster_config[server_type]["servers"].each do |server_name, server_config|
                server_config ||= Hash.new
                chef_server_url = server_config['chef_server_url'] if server_config['chef_server_url']
                validation_client_name = server_config['validation_client_name'] if server_config['validation_client_name']
                validation_key = server_config['validation_key'] if server_config['validation_key']
                @server_configs[server_name].merge!({
                  chef_server_url: chef_server_url,
                  validation_client_name: validation_client_name,
                  validation_key: validation_key
                })
              end
            end
          end
        end
      end
      validate_cluster_config
    end

    def validate_cluster_config
      base_container_names = Array.new
      mounts = Array.new
      ssh_keys = Array.new
      hostnames = Array.new

      @config.map { |server_type, config| hostnames.push(config[:fqdn]) }

      @server_configs.each do |server_name, server_config|
        base_container_names.push(server_config[:base_container_name]).uniq! if server_config[:base_container_name]
        mounts.concat(server_config[:mounts]).uniq! if server_config[:mounts]
        ssh_keys.concat(server_config[:ssh_keys]).uniq! if server_config[:ssh_keys]
        hostnames.push(server_name)
        case server_config[:server_type]
        when "automate"
          if server_config[:license_path] && !File.exists?(server_config[:license_path])
            puts "ERROR: Automate license #{server_config[:license_path]} does not exist."
            exit 1
          end
        when "nodes"
          if server_config[:validation_key] && !File.exists?(server_config[:validation_key])
            puts "ERROR: Validation key #{server_config[:validation_key]} does not exist."
            exit 1
          end
        end
      end

      unless base_container_names.empty?
        base_container_names.each do |base_container_name|
          unless ::DevLXC::Container.new(base_container_name).defined?
            puts "ERROR: Base container #{base_container_name} does not exist."
            exit 1
          end
        end
      end
      unless hostnames.empty?
        hostnames.each do |hostname|
          unless hostname.end_with?(".lxc")
            puts "ERROR: Hostname #{hostname} does not end with '.lxc'."
            exit 1
          end
        end
      end
      unless mounts.empty?
        mounts.each do |mount|
          unless File.exists?(mount.split.first)
            puts "ERROR: Mount source #{mount.split.first} does not exist."
            exit 1
          end
        end
      end
      unless ssh_keys.empty?
        ssh_keys.each do |ssh_key|
          unless File.exists?(ssh_key)
            puts "ERROR: SSH key #{ssh_key} does not exist."
            exit 1
          end
        end
      end
    end

    def show_config(include_products=false)
      require 'pp'
      calculate_required_products(get_sorted_servers, true) if include_products
      puts "Cluster config:"
      pp @config
      puts
      puts "Server configs:"
      pp @server_configs
    end

    def get_server(server_name)
      ipaddress = @server_configs[server_name][:ipaddress]
      additional_fqdn = @server_configs[server_name][:additional_fqdn]
      mounts = @server_configs[server_name][:mounts]
      ssh_keys = @server_configs[server_name][:ssh_keys]
      Server.new(server_name, ipaddress, additional_fqdn, mounts, ssh_keys)
    end

    def get_sorted_servers(server_name_regex=nil)
      servers = Array.new

      # the order of this list of server_types matters
      # it determines the order in which actions are applied to each server_type
      %w(chef-backend chef-server analytics compliance supermarket automate build-nodes nodes adhoc).each do |server_type|
        unless @config[server_type].empty?
          case server_type
          when "chef-backend"
            @config[server_type][:backends].each do |backend_name|
              servers << get_server(backend_name)
            end
            @config[server_type][:frontends].each do |frontend_name|
              servers << get_server(frontend_name)
            end
          when "analytics", "chef-server"
            if @config[server_type][:bootstrap_backend]
              server_name = @config[server_type][:bootstrap_backend]
              servers << get_server(server_name)
            end
            @config[server_type][:frontends].each do |frontend_name|
              servers << get_server(frontend_name)
            end
          end
        end
        if %w(adhoc automate build-nodes compliance nodes supermarket).include?(server_type)
          server_configs = @server_configs.select { |server_name, server_config| server_config[:server_type] == server_type }
          server_configs.each_key { |server_name| servers << get_server(server_name) }
        end
      end
      servers.select { |s| s.name =~ /#{server_name_regex}/ }
    end

    def up(server_name_regex=nil)
      abort_up = false
      configured_servers = Array.new
      servers = get_sorted_servers(server_name_regex)
      servers.each do |server|
        next if server.container.defined?
        if (@config['chef-server'][:frontends] && @config['chef-server'][:frontends].include?(server.name)) || server.name == @config['analytics'][:bootstrap_backend]
          if @config['chef-server'][:bootstrap_backend].nil?
            puts "ERROR: '#{server.name}' requires a Chef Server bootstrap backend to be configured first."
            abort_up = true
          elsif !get_server(@config['chef-server'][:bootstrap_backend]).container.defined? && servers.select { |s| s.name == @config['chef-server'][:bootstrap_backend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['chef-server'][:bootstrap_backend]}' to be configured first."
            abort_up = true
          end
        end
        if @config['chef-server'][:bootstrap_backend] && @server_configs[server.name][:server_type] == 'supermarket'
          if !get_server(@config['chef-server'][:bootstrap_backend]).container.defined? && servers.select { |s| s.name == @config['chef-server'][:bootstrap_backend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['chef-server'][:bootstrap_backend]}' to be configured first."
            abort_up = true
          end
        end
        if @config['analytics'][:frontends] && @config['analytics'][:frontends].include?(server.name)
          if @config['analytics'][:bootstrap_backend].nil?
            puts "ERROR: '#{server.name}' requires an Analytics Server bootstrap backend to be configured first."
            abort_up = true
          elsif !get_server(@config['analytics'][:bootstrap_backend]).container.defined? && servers.select { |s| s.name == @config['analytics'][:bootstrap_backend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['analytics'][:bootstrap_backend]}' to be configured first."
            abort_up = true
          end
        end
        if @config['chef-backend'][:frontends] && @config['chef-backend'][:frontends].include?(server.name) && server.name != @config['chef-backend'][:bootstrap_frontend]
          if @config['chef-backend'][:bootstrap_frontend].nil?
            puts "ERROR: '#{server.name}' requires a Chef Server bootstrap frontend to be configured first."
            abort_up = true
          elsif !get_server(@config['chef-backend'][:bootstrap_frontend]).container.defined? && servers.select { |s| s.name == @config['chef-backend'][:bootstrap_frontend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['chef-backend'][:bootstrap_frontend]}' to be configured first."
            abort_up = true
          end
        end
        if server.name == @config['chef-backend'][:bootstrap_frontend]
          if (@config['chef-backend'][:backends].select { |s| get_server(s).container.running? }.length + servers.select { |s| @config['chef-backend'][:backends].include?(s.name) }.length) < 2
            puts "ERROR: '#{server.name}' requires at least two nodes in the backend cluster to be running first."
            abort_up = true
          end
        end
        if @config['chef-backend'][:backends] && @config['chef-backend'][:backends].include?(server.name) && server.name != @config['chef-backend'][:leader_backend]
          if !get_server(@config['chef-backend'][:leader_backend]).container.running? && servers.select { |s| s.name == @config['chef-backend'][:leader_backend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['chef-backend'][:leader_backend]}' to be running first."
            abort_up = true
          end
        end
        if @server_configs[server.name][:server_type] == 'nodes'
          if @server_configs[server.name][:chef_server_url] && @server_configs[server.name][:validation_client_name] && @server_configs[server.name][:validation_key].nil?
            if @config['chef-server'][:bootstrap_backend] && !get_server(@config['chef-server'][:bootstrap_backend]).container.defined? && servers.select { |s| s.name == @config['chef-server'][:bootstrap_backend] }.empty?
              puts "ERROR: '#{server.name}' requires '#{@config['chef-server'][:bootstrap_backend]}' to be configured first."
              abort_up = true
            elsif @config['chef-backend'][:bootstrap_frontend] && !get_server(@config['chef-backend'][:bootstrap_frontend]).container.defined? && servers.select { |s| s.name == @config['chef-backend'][:bootstrap_frontend] }.empty?
              puts "ERROR: '#{server.name}' requires '#{@config['chef-backend'][:bootstrap_frontend]}' to be configured first."
              abort_up = true
            end
          end
        end
        if @server_configs[server.name][:server_type] == 'automate'
          if @config['chef-server'][:bootstrap_backend].nil?
            puts "ERROR: '#{server.name}' requires a Chef Server bootstrap backend to be configured first."
            abort_up = true
          elsif !get_server(@config['chef-server'][:bootstrap_backend]).container.defined? && servers.select { |s| s.name == @config['chef-server'][:bootstrap_backend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['chef-server'][:bootstrap_backend]}' to be configured first."
            abort_up = true
          end
        end
        if @server_configs[server.name][:server_type] == 'build-nodes'
          if @config['chef-server'][:bootstrap_backend].nil?
            puts "ERROR: '#{server.name}' requires a Chef Server bootstrap backend to be configured first."
            abort_up = true
          elsif !get_server(@config['chef-server'][:bootstrap_backend]).container.running? && servers.select { |s| s.name == @config['chef-server'][:bootstrap_backend] }.empty?
            puts "ERROR: '#{server.name}' requires '#{@config['chef-server'][:bootstrap_backend]}' to be running first."
            abort_up = true
          end
          if @config['chef-server'][:topology] == 'tier'
            if @config[server_type][:frontends].empty?
              puts "ERROR: '#{server.name}' requires at least one Chef Server frontend to be configured first."
              abort_up = true
            elsif (@config['chef-server'][:frontends].select { |s| get_server(s).container.running? }.length + servers.select { |s| @config['chef-server'][:frontends].include?(s.name) }.length) < 1
              puts "ERROR: '#{server.name}' requires at least one Chef Server frontend to be running first."
              abort_up = true
            end
          end
          automate_server_name = @server_configs.select {|name, config| config[:server_type] == 'automate'}.keys.first
          if automate_server_name
            if !get_server(automate_server_name).container.running? && servers.select { |s| s.name == automate_server_name }.empty?
              puts "ERROR: '#{server.name}' requires '#{automate_server_name}' to be running first."
              abort_up = true
            end
          else
            puts "ERROR: '#{server.name}' requires an Automate Server to be configured first."
            abort_up = true
          end
        end
      end
      exit 1 if abort_up
      prep_product_cache(servers)
      servers.each do |server|
        clone_from_base_container(server) unless server.container.defined?
      end
      servers = get_sorted_servers(server_name_regex)
      servers.each do |server|
        if @server_configs[server.name][:server_type] == "build-nodes"
          next if @server_configs[server.name][:required_products]["chefdk"] && @server_configs[server.name][:required_products].length == 1
        end
        install_products(server) unless @server_configs[server.name][:required_products].empty?
      end
      servers.each do |server|
        if server.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: completed") }.empty?
          if server.name == @config["chef-backend"][:bootstrap_frontend]
            running_backends = Array.new
            @config["chef-backend"][:backends].reverse_each do |server_name|
              backend = get_server(server_name)
              if backend.container.defined? && backend.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: backend cluster configured but frontend not bootstrapped") }.empty?
                if backend.container.running?
                  running_backends << backend.name
                  backend.stop
                end
                backend.snapshot("dev-lxc build: backend cluster configured but frontend not bootstrapped")
                snapshot = backend.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: completed") }.first
                backend.snapshot_destroy(snapshot.first) if snapshot
              end
            end
            @config["chef-backend"][:backends].each do |server_name|
              if running_backends.include?(server_name)
                get_server(server_name).start
                configured_servers << server_name unless configured_servers.include?(server_name)
              end
            end
          end
          configure_products(server)
          configured_servers << server.name
        end
        server.start unless server.container.running?
      end
      configured_servers.reverse_each do |server_name|
        server = get_server(server_name)
        server.stop if server.container.running?
        server.snapshot("dev-lxc build: completed")
      end
      configured_servers.each do |server_name|
        server = get_server(server_name)
        server.start if server.container.defined?
      end
    end

    def clone_from_base_container(server)
      server_type = @server_configs[server.name][:server_type]
      base_container = DevLXC::Container.new(@server_configs[server.name][:base_container_name])
      puts "Cloning base container '#{base_container.name}' into container '#{server.name}'"
      base_container.clone(server.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
      server.container.load_config
      puts "Deleting SSH Server Host Keys"
      FileUtils.rm_f(Dir.glob("#{server.container.config_item('lxc.rootfs')}/etc/ssh/ssh_host*_key*"))
      puts "Adding lxc.hook.post-stop hook"
      server.container.set_config_item("lxc.hook.post-stop", "/usr/local/share/lxc/hooks/post-stop-dhcp-release")
      server.container.save_config
    end

    def get_product_download_info(server, product_name, product_options)
      server_type = @server_configs[server.name][:server_type]
      base_container = DevLXC::Container.new(@server_configs[server.name][:base_container_name])
      mixlib_install_platform_detection_path = "#{base_container.config_item('lxc.rootfs')}/mixlib-install-platform-detection"
      IO.write(mixlib_install_platform_detection_path, Mixlib::Install::Generator::Bourne.detect_platform_sh)
      platform_results = `chroot #{base_container.config_item('lxc.rootfs')} bash mixlib-install-platform-detection`
      File.unlink(mixlib_install_platform_detection_path)
      if platform_results.empty?
        puts "ERROR: Unable to detect the platform of container '#{base_container.name}'"
        exit 1
      end
      (platform, platform_version, architecture) = platform_results.split
      product_version = product_options['version'] if product_options
      product_version ||= 'latest'
      channel = product_options['channel'] if product_options
      channel ||= 'stable'
      channel = channel.to_sym
      options = {
        product_name: product_name,
        product_version: product_version,
        channel: channel,
        platform: platform,
        platform_version: platform_version,
        architecture: architecture
      }
      artifact = Mixlib::Install.new(options).artifact_info
      if artifact.class != Mixlib::Install::ArtifactInfo
        puts "ERROR: Unable to find download URL for the following product"
        puts JSON.pretty_generate(options)
        exit 1
      end
      [artifact.url, artifact.sha256]
    end

    def calculate_required_products(servers, force=false)
      all_required_products = Hash.new
      servers.each do |server|
        products = @server_configs[server.name][:products]
        @server_configs[server.name][:required_products] = Hash.new
        if !force && !server.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: products installed") }.empty?
          # Skipping product cache preparation for container because it has a 'products installed' snapshot
          next
        elsif !force && !server.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: completed") }.empty?
          # Skipping product cache preparation for container because it has a 'build: completed' snapshot
          next
        end
        products.each do |product_name, product_options|
          if product_options && product_options['package_source']
            package_source = product_options['package_source']
            all_required_products[package_source] = [product_name, nil]
            @server_configs[server.name][:required_products][product_name] = package_source
          else
            package_source, package_sha256 = get_product_download_info(server, product_name, product_options)
            all_required_products[package_source] = [product_name, package_sha256]
            product_cache_path = "/var/dev-lxc/cache/chef-products/#{product_name}/#{File.basename(package_source)}"
            @server_configs[server.name][:required_products][product_name] = product_cache_path
          end
        end
      end
      all_required_products
    end

    def prep_product_cache(servers, force=false)
      all_required_products = calculate_required_products(servers, force)
      all_required_products.each do |package_source, v|
        product_name, package_sha256 = v
        if package_source.start_with?('http')
          product_cache_path = "/var/dev-lxc/cache/chef-products/#{product_name}/#{File.basename(package_source)}"
          if !File.exist?(product_cache_path)
            FileUtils.mkdir_p(File.dirname(product_cache_path)) unless Dir.exist?(File.dirname(product_cache_path))
            puts "Downloading #{package_source} to #{product_cache_path}"
            open(package_source) { |url| File.open(product_cache_path, 'wb') { |f| f.write(url.read) } }
          end
          actual_sha256 = Digest::SHA256.file(product_cache_path).hexdigest
          if package_sha256 != actual_sha256
            puts "ERROR: Invalid SHA256 #{actual_sha256} for #{File.basename(product_cache_path)}."
            exit 1
          end
        elsif !File.exist?(package_source)
          puts "ERROR: Package source #{package_source} does not exist."
          exit 1
        end
      end
    end

    def install_products(server)
      if !server.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: products installed") }.empty?
        puts "Skipping product installation for container '#{server.name}' because it already has a 'products installed' snapshot"
        return
      elsif !server.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: completed") }.empty?
        puts "Skipping product installation for container '#{server.name}' because it already has a 'build: completed' snapshot"
        return
      end
      if server.container.running?
        server_was_running = true
      else
        server_was_running = false
        server.start
      end
      @server_configs[server.name][:required_products].each do |product_name, package_source|
        next if @server_configs[server.name][:server_type] == "build-nodes" && product_name == "chefdk"
        server.install_package(package_source)
      end
      server.stop
      server.snapshot("dev-lxc build: products installed")
      server.start if server_was_running
    end

    def configure_products(server)
      puts "Configuring container '#{server.name}'"
      server.start unless server.container.running?
      required_products = @server_configs[server.name][:required_products].keys if @server_configs[server.name][:required_products]
      required_products ||= Array.new
      server_type = @server_configs[server.name][:server_type]
      dot_chef_path = "/root/chef-repo/.chef"
      case server_type
      when 'adhoc'
        # Allow adhoc servers time to generate SSH Server Host Keys
        sleep 5
      when 'analytics'
        configure_analytics(server) if required_products.include?('analytics')
      when 'build-nodes'
        sleep 5     # give time for DNS resolution to be available
        configure_build_node(server)
      when 'chef-backend'
        configure_chef_backend(server) if required_products.include?('chef-backend')
        if required_products.include?('chef-server')
          configure_chef_frontend(server)
          if server.name == @config['chef-backend'][:bootstrap_frontend]
            create_users_orgs_knife_configs(server, dot_chef_path)
          end
        end
        configure_manage(server) if required_products.include?('manage')
      when 'chef-server'
        if required_products.include?('chef-server') || required_products.include?('private-chef')
          configure_chef_server(server)
          if server.name == @config['chef-server'][:bootstrap_backend]
            create_users_orgs_knife_configs(server, dot_chef_path)

            automate_server_name = @server_configs.select {|name, config| config[:server_type] == 'automate'}.keys.first
            if automate_server_name
              automate_user = "delivery"
              automate_chef_org = @server_configs[automate_server_name][:chef_org]
              create_user(server, automate_user, dot_chef_path)
              create_org(server, automate_chef_org, dot_chef_path)
              org_add_user(server, automate_chef_org, automate_user, true, dot_chef_path)
            end
          end
        end
        configure_reporting(server) if required_products.include?('reporting')
        configure_push_jobs_server(server) if required_products.include?('push-jobs-server')
        configure_manage(server) if required_products.include?('manage')
      when 'compliance'
        configure_compliance(server) if required_products.include?('compliance')
      when 'automate'
        configure_automate(server) if required_products.include?('delivery')
      when 'nodes'
        # Allow servers time to generate SSH Server Host Keys
        sleep 5
        configure_chef_client(server, dot_chef_path) if required_products.include?('chef') || required_products.include?('chefdk')
      when 'supermarket'
        configure_supermarket(server) if required_products.include?('supermarket')
      end
    end

    def configure_automate(server)
      license_path = @server_configs[server.name][:license_path]
      chef_org = @server_configs[server.name][:chef_org]
      enterprise_name = @server_configs[server.name][:enterprise_name]
      chef_server_url = @config['chef-server'][:fqdn]
      supermarket_fqdn = @config['supermarket'][:fqdn]

      FileUtils.cp(license_path, "#{server.container.config_item('lxc.rootfs')}/root/automate.license")

      chef_server = get_server(@config['chef-server'][:bootstrap_backend])
      automate_chef_user_key = "#{chef_server.container.config_item('lxc.rootfs')}/root/chef-repo/.chef/delivery.pem"
      FileUtils.cp(automate_chef_user_key, "#{server.container.config_item('lxc.rootfs')}/root/automate_chef_user_key.pem")

      setup_cmd = "setup"
      setup_cmd += " --license /root/automate.license"
      setup_cmd += " --fqdn #{server.name}"
      setup_cmd += " --key /root/automate_chef_user_key.pem"
      setup_cmd += " --server-url https://#{chef_server_url}/organizations/#{chef_org}"
      setup_cmd += " --supermarket-fqdn #{supermarket_fqdn}" if supermarket_fqdn
      setup_cmd += " --enterprise #{enterprise_name}"
      setup_cmd += " --no-build-node"
      setup_cmd += " --configure"
      run_ctl(server, "delivery", setup_cmd)
    end

    def print_automate_credentials
      automate_server_name = @server_configs.select {|name, config| config[:server_type] == 'automate'}.keys.first
      if automate_server_name
        automate_server = get_server(automate_server_name)
        automate_credentials_files = Dir.glob("#{automate_server.container.config_item('lxc.rootfs')}/etc/delivery/*-credentials")
        automate_credentials_files.each_with_index do |automate_credentials_file, index|
          puts IO.read(automate_credentials_file)
          puts if index + 1 < automate_credentials_files.length
        end
      else
        puts "WARNING: An Automate server is not defined."
        exit 1
      end
    end

    def configure_build_node(server)
      automate_server_name = @server_configs.select {|name, config| config[:server_type] == 'automate'}.keys.first
      if automate_server_name
        automate_server = get_server(automate_server_name)
        install_build_node_cmd = "install-build-node"
        install_build_node_cmd += " --fqdn #{server.name}"
        install_build_node_cmd += " --username dev-lxc"
        install_build_node_cmd += " --password dev-lxc"
        install_build_node_cmd += " --installer #{@server_configs[server.name][:required_products]["chefdk"]}"
        install_build_node_cmd += " --overwrite-registration"
        run_ctl(automate_server, "delivery", install_build_node_cmd)
      end
    end

    def configure_chef_client(server, dot_chef_path)
      puts "Configuring Chef Client in container '#{server.name}'"

      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/etc/chef")

      chef_server_url = @server_configs[server.name][:chef_server_url]
      validation_client_name = @server_configs[server.name][:validation_client_name]
      validation_key = @server_configs[server.name][:validation_key]
      if validation_key.nil?
        chef_server_name = @config['chef-server'][:bootstrap_backend]
        chef_server_name ||= @config['chef-backend'][:bootstrap_frontend]
        if chef_server_name
          chef_server = get_server(chef_server_name)
          if chef_server.container.defined?
            validator_pem_files = Dir.glob("#{chef_server.container.config_item('lxc.rootfs')}#{dot_chef_path}/*-validator.pem")
            FileUtils.cp(validator_pem_files, "#{server.container.config_item('lxc.rootfs')}/etc/chef/") unless validator_pem_files.empty?
          end
        end
      else
        FileUtils.cp(validation_key, "#{server.container.config_item('lxc.rootfs')}/etc/chef/") if File.exists?(validation_key)
      end

      client_rb = %Q(chef_server_url '#{chef_server_url}'
validation_client_name '#{validation_client_name}'
validation_key '/etc/chef/#{validation_client_name}.pem'
ssl_verify_mode :verify_none
)

      automate_server_name = @server_configs.select {|name, config| config[:server_type] == 'automate'}.keys.first
      if automate_server_name
        client_rb += %Q(
data_collector.server_url "https://#{automate_server_name}/data-collector/v0/"
data_collector.token "93a49a4f2482c64126f7b6015e6b0f30284287ee4054ff8807fb63d9cbd1c506"
)
      end

      IO.write("#{server.container.config_item('lxc.rootfs')}/etc/chef/client.rb", client_rb)
    end

    def configure_chef_backend(server)
      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/var/opt/chef-backend")
      FileUtils.touch("#{server.container.config_item('lxc.rootfs')}/var/opt/chef-backend/.license.accepted")
      if server.name == @config['chef-backend'][:leader_backend]
        puts "Creating /etc/chef-backend/chef-backend.rb"
        FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/etc/chef-backend")
        chef_backend_config = "publish_address '#{@server_configs[server.name][:ipaddress]}'\n"
        IO.write("#{server.container.config_item('lxc.rootfs')}/etc/chef-backend/chef-backend.rb", chef_backend_config)
        run_ctl(server, "chef-backend", "bootstrap --yes")
      else
        puts "Joining #{server.name} to the chef-backend cluster"
        leader_backend = get_server(@config['chef-backend'][:leader_backend])
        FileUtils.cp("#{leader_backend.container.config_item('lxc.rootfs')}/etc/chef-backend/chef-backend-secrets.json",
                     "#{server.container.config_item('lxc.rootfs')}/root/")
        run_ctl(server, "chef-backend", "join-cluster #{@server_configs[leader_backend.name][:ipaddress]} -p #{@server_configs[server.name][:ipaddress]} -s /root/chef-backend-secrets.json --yes")
      end
    end

    def configure_chef_frontend(server)
      puts "Creating /etc/opscode/chef-server.rb"
      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/etc/opscode")
      leader_backend = get_server(@config['chef-backend'][:leader_backend])
      run_ctl(leader_backend, "chef-backend", "gen-server-config #{server.name} --filename /tmp/#{server.name}.rb")
      FileUtils.cp("#{leader_backend.container.config_item('lxc.rootfs')}/tmp/#{server.name}.rb",
                   "#{server.container.config_item('lxc.rootfs')}/etc/opscode/chef-server.rb")
      unless server.name == @config['chef-backend'][:bootstrap_frontend]
        bootstrap_frontend = get_server(@config['chef-backend'][:bootstrap_frontend])
        puts "Copying /etc/opscode/private-chef-secrets.json from bootstrap frontend '#{bootstrap_frontend.name}'"
        FileUtils.cp("#{bootstrap_frontend.container.config_item('lxc.rootfs')}/etc/opscode/private-chef-secrets.json",
                     "#{server.container.config_item('lxc.rootfs')}/etc/opscode/")
        puts "Copying /etc/opscode/pivotal.pem from bootstrap frontend '#{bootstrap_frontend.name}'"
        FileUtils.cp("#{bootstrap_frontend.container.config_item('lxc.rootfs')}/etc/opscode/pivotal.pem",
                     "#{server.container.config_item('lxc.rootfs')}/etc/opscode/")
      end
      run_ctl(server, "chef-server", "reconfigure")
    end

    def configure_chef_server(server)
      if @config['chef-server'][:topology] == "standalone" || @config['chef-server'][:bootstrap_backend] == server.name
        case @server_configs[server.name][:chef_server_type]
        when 'private-chef'
          puts "Creating /etc/opscode/private-chef.rb"
          FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/etc/opscode")
          IO.write("#{server.container.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", chef_server_config)
        when 'chef-server'
          puts "Creating /etc/opscode/chef-server.rb"
          FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/etc/opscode")
          IO.write("#{server.container.config_item('lxc.rootfs')}/etc/opscode/chef-server.rb", chef_server_config)
        end
      elsif @config['chef-server'][:frontends].include?(server.name)
        puts "Copying /etc/opscode from bootstrap backend '#{@config['chef-server'][:bootstrap_backend]}'"
        FileUtils.cp_r("#{get_server(@config['chef-server'][:bootstrap_backend]).container.config_item('lxc.rootfs')}/etc/opscode",
                       "#{server.container.config_item('lxc.rootfs')}/etc", preserve: true)
      end
      run_ctl(server, @server_configs[server.name][:chef_server_type], "reconfigure")
    end

    def configure_reporting(server)
      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/var/opt/opscode-reporting")
      FileUtils.touch("#{server.container.config_item('lxc.rootfs')}/var/opt/opscode-reporting/.license.accepted")
      if @config['chef-server'][:frontends].include?(server.name)
        puts "Copying /etc/opscode-reporting from bootstrap backend '#{@config['chef-server'][:bootstrap_backend]}'"
        FileUtils.cp_r("#{get_server(@config['chef-server'][:bootstrap_backend]).container.config_item('lxc.rootfs')}/etc/opscode-reporting",
                       "#{server.container.config_item('lxc.rootfs')}/etc", preserve: true)
      end
      run_ctl(server, @server_configs[server.name][:chef_server_type], "reconfigure")
      run_ctl(server, "opscode-reporting", "reconfigure")
    end

    def configure_push_jobs_server(server)
      run_ctl(server, "opscode-push-jobs-server", "reconfigure")
      run_ctl(server, @server_configs[server.name][:chef_server_type], "reconfigure")
    end

    def configure_manage(server)
      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/var/opt/chef-manage")
      FileUtils.touch("#{server.container.config_item('lxc.rootfs')}/var/opt/chef-manage/.license.accepted")
      if @server_configs[server.name][:chef_server_type] == 'private-chef'
        puts "Disabling old opscode-webui in /etc/opscode/private-chef.rb"
        DevLXC.search_file_delete_line("#{server.container.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", /opscode_webui[.enable.]/)
        DevLXC.append_line_to_file("#{server.container.config_item('lxc.rootfs')}/etc/opscode/private-chef.rb", "\nopscode_webui['enable'] = false\n")
        run_ctl(server, @server_configs[server.name][:chef_server_type], "reconfigure")
      end
      run_ctl(server, "opscode-manage", "reconfigure")
    end

    def configure_analytics(server)
      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/var/opt/opscode-analytics")
      FileUtils.touch("#{server.container.config_item('lxc.rootfs')}/var/opt/opscode-analytics/.license.accepted")
      if @config['analytics'][:topology] == "standalone" || @config['analytics'][:bootstrap_backend] == server.name
        puts "Copying /etc/opscode-analytics from Chef Server bootstrap backend '#{@config['chef-server'][:bootstrap_backend]}'"
        FileUtils.cp_r("#{get_server(@config['chef-server'][:bootstrap_backend]).container.config_item('lxc.rootfs')}/etc/opscode-analytics",
                       "#{server.container.config_item('lxc.rootfs')}/etc", preserve: true)

        IO.write("#{server.container.config_item('lxc.rootfs')}/etc/opscode-analytics/opscode-analytics.rb", analytics_config)
      elsif @config['analytics'][:frontends].include?(server.name)
        puts "Copying /etc/opscode-analytics from Analytics bootstrap backend '#{@config['analytics'][:bootstrap_backend]}'"
        FileUtils.cp_r("#{get_server(@config['analytics'][:bootstrap_backend]).container.config_item('lxc.rootfs')}/etc/opscode-analytics",
                       "#{server.container.config_item('lxc.rootfs')}/etc", preserve: true)
      end
      run_ctl(server, "opscode-analytics", "reconfigure")
    end

    def configure_compliance(server)
      FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/var/opt/chef-compliance")
      FileUtils.touch("#{server.container.config_item('lxc.rootfs')}/var/opt/chef-compliance/.license.accepted")
      run_ctl(server, "chef-compliance", "reconfigure")
    end

    def configure_supermarket(server)
      if @config['chef-server'][:bootstrap_backend] && get_server(@config['chef-server'][:bootstrap_backend]).container.defined?
        chef_server_supermarket_config = JSON.parse(IO.read("#{get_server(@config['chef-server'][:bootstrap_backend]).container.config_item('lxc.rootfs')}/etc/opscode/oc-id-applications/supermarket.json"))
        supermarket_config = {
          'chef_server_url' => "https://#{@config['chef-server'][:fqdn]}/",
          'chef_oauth2_app_id' => chef_server_supermarket_config['uid'],
          'chef_oauth2_secret' => chef_server_supermarket_config['secret'],
          'chef_oauth2_verify_ssl' => false
        }
        FileUtils.mkdir_p("#{server.container.config_item('lxc.rootfs')}/etc/supermarket")
        IO.write("#{server.container.config_item('lxc.rootfs')}/etc/supermarket/supermarket.json", JSON.pretty_generate(supermarket_config))
      end
      run_ctl(server, "supermarket", "reconfigure")
    end

    def run_ctl(server, component, subcommand)
      server.run_command("#{component}-ctl #{subcommand}")
    end

    def create_users_orgs_knife_configs(server, dot_chef_path)
      server_type = @server_configs[server.name][:server_type]
      # give time for all services to come up completely
      sleep 10
      if @server_configs[server.name][:chef_server_type] == 'private-chef'
        # give more time for all services to come up completely
        sleep 50
        server.run_command("/opt/opscode/embedded/bin/gem install knife-opc --no-ri --no-rdoc -v 0.3.1")
      end
      chef_server_dot_chef_path = "#{server.container.config_item('lxc.rootfs')}#{dot_chef_path}"
      FileUtils.mkdir_p(chef_server_dot_chef_path)
      FileUtils.cp( "#{server.container.config_item('lxc.rootfs')}/etc/opscode/pivotal.pem", chef_server_dot_chef_path )
      create_pivotal_knife_config('127.0.0.1', chef_server_dot_chef_path)
      create_knife_config('127.0.0.1', chef_server_dot_chef_path)
      @config[server_type][:users].each do |username|
        create_user(server, username, dot_chef_path)
      end
      @config[server_type][:orgs].each do |orgname, org_users|
        create_org(server, orgname, dot_chef_path)
        if org_users
          if org_users['admins']
            org_users['admins'].each do |username|
              org_add_user(server, orgname, username, true, dot_chef_path)
            end
          end
          if org_users['non-admins']
            org_users['non-admins'].each do |username|
              org_add_user(server, orgname, username, false, dot_chef_path)
            end
          end
        end
      end
    end

    def create_pivotal_knife_config(fqdn, dot_chef_path)
      pivotal_rb = %Q(
current_dir = File.dirname(__FILE__)

chef_server_root "https://#{fqdn}"
chef_server_url "https://#{fqdn}"

node_name "pivotal"
client_key "\#{current_dir}/pivotal.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd

ssl_verify_mode :verify_none
)
      IO.write("#{dot_chef_path}/pivotal.rb", pivotal_rb)
    end

    def create_knife_config(fqdn, dot_chef_path)
      knife_rb = %Q(
username = "CHANGEME"
orgname = "CHANGEME"

if [username, orgname].include?("CHANGEME")
  puts "ERROR: Please set 'username' and 'orgname' to proper values in knife.rb"
  exit!
end

current_dir = File.dirname(__FILE__)

chef_server_url "https://#{fqdn}/organizations/\#{orgname}"

node_name username
client_key "\#{current_dir}/\#{username}.pem"

validation_client_name "\#{orgname}-validator"
validation_key "\#{current_dir}/\#{orgname}-validator.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd

ssl_verify_mode :verify_none
)
      IO.write("#{dot_chef_path}/knife.rb", knife_rb)
    end

    def create_user(server, username, dot_chef_path)
      create_user_string = "#{username} #{username} #{username} #{username}@noreply.com #{username} --filename #{dot_chef_path}/#{username}.pem"
      case @server_configs[server.name][:chef_server_type]
      when 'private-chef'
        server.run_command("/opt/opscode/embedded/bin/knife opc user create #{create_user_string} -c #{dot_chef_path}/pivotal.rb")
      when 'chef-server'
        run_ctl(server, "chef-server", "user-create #{create_user_string}")
      end
    end

    def create_org(server, orgname, dot_chef_path)
      create_org_string = "#{orgname} #{orgname} --filename #{dot_chef_path}/#{orgname}-validator.pem"
      case @server_configs[server.name][:chef_server_type]
      when 'private-chef'
        server.run_command("/opt/opscode/embedded/bin/knife opc org create #{create_org_string} -c #{dot_chef_path}/pivotal.rb")
      when 'chef-server'
        run_ctl(server, "chef-server", "org-create #{create_org_string}")
      end
    end

    def org_add_user(server, orgname, username, admin, dot_chef_path)
      org_add_user_string = "#{orgname} #{username}"
      org_add_user_string += " --admin" if admin
      case @server_configs[server.name][:chef_server_type]
      when 'private-chef'
        server.run_command("/opt/opscode/embedded/bin/knife opc org user add #{org_add_user_string} -c #{dot_chef_path}/pivotal.rb")
      when 'chef-server'
        run_ctl(server, "chef-server", "org-user-add #{org_add_user_string}")
      end
    end

    def chef_repo(force=false, pivotal=false)
      chef_server_dot_chef_path = "/root/chef-repo/.chef"
      dot_chef_path = "./chef-repo/.chef"

      if @config['chef-server'][:bootstrap_backend]
        chef_server = get_server(@config['chef-server'][:bootstrap_backend])
        chef_server_fqdn = @config['chef-server'][:fqdn]
      elsif @config['chef-backend'][:bootstrap_frontend]
        chef_server = get_server(@config['chef-backend'][:bootstrap_frontend])
        chef_server_fqdn = @config['chef-backend'][:fqdn]
      else
        puts "ERROR: A Chef Server is not defined in the cluster's config. Please define it first."
        exit 1
      end
      unless chef_server.container.defined?
        puts "ERROR: The '#{chef_server.name}' Chef Server does not exist."
        exit 1
      end

      puts "Creating chef-repo with pem files and knife.rb in the current directory"
      FileUtils.mkdir_p(dot_chef_path)

      pem_files = Dir.glob("#{chef_server.container.config_item('lxc.rootfs')}#{chef_server_dot_chef_path}/*.pem")
      pem_files.delete_if { |pem_file| pem_file.end_with?("/pivotal.pem") } unless pivotal
      FileUtils.cp(pem_files, dot_chef_path) unless pem_files.empty?

      if pivotal
        if File.exists?("#{dot_chef_path}/pivotal.rb") && ! force
          puts "Skipping pivotal.rb because it already exists in `#{dot_chef_path}`"
        else
          create_pivotal_knife_config(chef_server_fqdn, dot_chef_path)
        end
      end

      if File.exists?("./chef-repo/.chef/knife.rb") && ! force
        puts "Skipping knife.rb because it already exists in `#{dot_chef_path}`"
      else
        create_knife_config(chef_server_fqdn, dot_chef_path)
      end
    end

    def chef_server_config
      chef_server_config = %Q(api_fqdn "#{@config['chef-server'][:fqdn]}"\n)
      if @config['chef-server'][:topology] == 'tier'
        chef_server_config += %Q(
topology "#{@config['chef-server'][:topology]}"

server "#{@config['chef-server'][:bootstrap_backend]}",
  :ipaddress => "#{@server_configs[@config['chef-server'][:bootstrap_backend]][:ipaddress]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@config['chef-server'][:bootstrap_backend]}",
  :ipaddress => "#{@server_configs[@config['chef-server'][:bootstrap_backend]][:ipaddress]}"
)
        @config['chef-server'][:frontends].each do |frontend_name|
          chef_server_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@server_configs[frontend_name][:ipaddress]}",
  :role => "frontend"
)
        end
      end
      if @config['analytics'][:fqdn]
        chef_server_config += %Q(
oc_id['applications'] ||= {}
oc_id['applications']['analytics'] = {
  'redirect_uri' => 'https://#{@config['analytics'][:fqdn]}/'
}
rabbitmq['vip'] = '#{@config['chef-server'][:bootstrap_backend]}'
rabbitmq['node_ip_address'] = '0.0.0.0'
)
      end
      if @config['supermarket'][:fqdn]
        chef_server_config += %Q(
oc_id['applications'] ||= {}
oc_id['applications']['supermarket'] = {
  'redirect_uri' => 'https://#{@config['supermarket'][:fqdn]}/auth/chef_oauth2/callback'
}
)
      end
      automate_server_name = @server_configs.select {|name, config| config[:server_type] == 'automate'}.keys.first
      if automate_server_name
        chef_server_config += %Q(
data_collector['root_url'] = "https://#{automate_server_name}/data-collector/v0/"
data_collector['token'] = "93a49a4f2482c64126f7b6015e6b0f30284287ee4054ff8807fb63d9cbd1c506"
)
      end
      return chef_server_config
    end

    def analytics_config
      analytics_config = %Q(analytics_fqdn "#{@config['analytics'][:fqdn]}"
topology "#{@config['analytics'][:topology]}"
)
      if @config['analytics'][:topology] == 'tier'
        analytics_config += %Q(
server "#{@config['analytics'][:bootstrap_backend]}",
  :ipaddress => "#{@server_configs[@config['analytics'][:bootstrap_backend]][:ipaddress]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@config['analytics'][:bootstrap_backend]}",
  :ipaddress => "#{@server_configs[@config['analytics'][:bootstrap_backend]][:ipaddress]}"
)
        @config['analytics'][:frontends].each do |frontend_name|
          analytics_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@server_configs[frontend_name][:ipaddress]}",
  :role => "frontend"
)
        end
      end
      return analytics_config
    end

  end
end
