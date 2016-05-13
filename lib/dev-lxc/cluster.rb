require "dev-lxc/server"
require "mixlib/install"
require "open-uri"

module DevLXC
  class Cluster
    attr_reader :config

    def initialize(cluster_config)
      FileUtils.mkdir_p('/var/dev-lxc') unless Dir.exist?('/var/dev-lxc')
      validate_cluster_config(cluster_config)

      @config = Hash.new { |hash, key| hash[key] = {} }
      @server_configs = Hash.new

      %w(adhoc analytics chef-server compliance supermarket).each do |server_type|
        if cluster_config[server_type]
          @config[server_type][:mounts] = cluster_config[server_type]["mounts"]
          @config[server_type][:mounts] ||= cluster_config["mounts"]
          @config[server_type][:mounts] ||= Array.new
          @config[server_type][:mounts] << "/var/dev-lxc var/dev-lxc"
          @config[server_type][:ssh_keys] = cluster_config[server_type]["ssh-keys"]
          @config[server_type][:ssh_keys] ||= cluster_config["ssh-keys"]
          @config[server_type][:base_container_name] = cluster_config[server_type]["base_container"]
          @config[server_type][:base_container_name] ||= cluster_config["base_container"]

          case server_type
          when "adhoc"
            if cluster_config[server_type]["servers"]
              cluster_config[server_type]["servers"].each do |server_name, server_config|
                products = server_config['products']
                products ||= Hash.new
                @server_configs[server_name] = {
                  server_type: server_type,
                  products: products,
                  ipaddress: server_config['ipaddress'],
                  additional_fqdn: nil,
                  mounts: @config[server_type][:mounts],
                  ssh_keys: @config[server_type][:ssh_keys]
                }
              end
            end
          when "analytics"
            @config[server_type][:topology] = cluster_config[server_type]["topology"]
            @config[server_type][:topology] ||= 'standalone'
            @config[server_type][:fqdn] = cluster_config[server_type]["analytics_fqdn"]
            @config[server_type][:frontends] = Array.new

            if cluster_config[server_type]["servers"]
              cluster_config[server_type]["servers"].each do |server_name, server_config|
                additional_fqdn = nil
                products = server_config['products']
                products ||= Hash.new
                @server_configs[server_name] = server_config
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
                @server_configs[server_name] = {
                  server_type: server_type,
                  products: products,
                  ipaddress: server_config['ipaddress'],
                  additional_fqdn: additional_fqdn,
                  mounts: @config[server_type][:mounts],
                  ssh_keys: @config[server_type][:ssh_keys]
                }
              end
            end
          when "chef-server"
            @config[server_type][:topology] = cluster_config[server_type]["topology"]
            @config[server_type][:topology] ||= 'standalone'
            @config[server_type][:fqdn] = cluster_config[server_type]["api_fqdn"]
            @config[server_type][:frontends] = Array.new

            if cluster_config[server_type]["servers"]
              cluster_config[server_type]["servers"].each do |server_name, server_config|
                additional_fqdn = nil
                products = server_config['products']
                products ||= Hash.new
                chef_server_type = 'private-chef' if products.has_key?('private-chef')
                chef_server_type = 'chef-server' if products.has_key?('chef-server')
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
                @server_configs[server_name] = {
                  server_type: server_type,
                  products: products,
                  ipaddress: server_config['ipaddress'],
                  additional_fqdn: additional_fqdn,
                  mounts: @config[server_type][:mounts],
                  ssh_keys: @config[server_type][:ssh_keys],
                  chef_server_type: chef_server_type
                }
              end
            end
          when "compliance", "supermarket"
            unless cluster_config[server_type]["servers"].first.nil?
              (server_name, server_config) = cluster_config[server_type]["servers"].first
              @config[server_type][:fqdn] = server_name
              products = server_config['products']
              products ||= Hash.new
              @server_configs[server_name] = {
                server_type: server_type,
                products: products,
                ipaddress: server_config['ipaddress'],
                additional_fqdn: nil,
                mounts: @config[server_type][:mounts],
                ssh_keys: @config[server_type][:ssh_keys]
              }
            end
          end
        end
      end
    end

    def validate_cluster_config(cluster_config)
      hostnames = Array.new
      mounts = Array.new
      base_container_names = Array.new
      ssh_keys = Array.new

      base_container_names << cluster_config['base_container'] unless cluster_config['base_container'].nil?
      mounts.concat(cluster_config['mounts']) unless cluster_config['mounts'].nil?
      ssh_keys.concat(cluster_config['ssh-keys']) unless cluster_config['ssh-keys'].nil?

      %w(adhoc analytics chef-server compliance supermarket).each do |server_type|
        unless cluster_config[server_type].nil?
          base_container_names << cluster_config[server_type]['base_container'] unless cluster_config[server_type]['base_container'].nil?
          hostnames << cluster_config[server_type]['api_fqdn'] unless cluster_config[server_type]['api_fqdn'].nil?
          hostnames << cluster_config[server_type]['analytics_fqdn'] unless cluster_config[server_type]['analytics_fqdn'].nil?
          hostnames.concat(cluster_config[server_type]['servers'].keys) unless cluster_config[server_type]['servers'].nil?
          mounts.concat(cluster_config[server_type]['mounts']) unless cluster_config[server_type]['mounts'].nil?
          ssh_keys.concat(cluster_config[server_type]['ssh-keys']) unless cluster_config[server_type]['ssh-keys'].nil?
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
      %w(chef-server analytics compliance supermarket adhoc).each do |server_type|
        unless @config[server_type].empty?
          case server_type
          when "analytics", "chef-server"
            if @config[server_type][:bootstrap_backend]
              server_name = @config[server_type][:bootstrap_backend]
              servers << get_server(server_name)
            end
            @config[server_type][:frontends].each do |frontend_name|
              servers << get_server(frontend_name)
            end
          when "adhoc", "compliance", "supermarket"
            server_configs = @server_configs.select { |server_name, server_config| server_config[:server_type] == server_type }
            server_configs.each_key { |server_name| servers << get_server(server_name) }
          end
        end
      end
      servers.select { |s| s.name =~ /#{server_name_regex}/ }
    end

    def get_product_url(server, product_name, product_options)
      server_type = @server_configs[server.name][:server_type]
      base_container = DevLXC::Container.new(@config[server_type][:base_container_name])
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
      artifact.url
    end

    def prep_product_cache(servers)
      all_required_products = Hash.new
      servers.each do |server|
        products = @server_configs[server.name][:products]
        @server_configs[server.name][:required_products] = Hash.new
        if !server.snapshot_list.select { |sn| sn[2].start_with?("dev-lxc build: products installed") }.empty?
          puts "Skipping product cache preparation for container '#{server.name}' because it has a 'products installed' snapshot"
          next
        end
        products.each do |product_name, product_options|
          if product_options && product_options['package_source']
            package_source = product_options['package_source']
            all_required_products[package_source] = product_name
            @server_configs[server.name][:required_products][product_name] = package_source
          else
            package_source = get_product_url(server, product_name, product_options)
            all_required_products[package_source] = product_name
            product_cache_path = "/var/dev-lxc/cache/chef-products/#{product_name}/#{File.basename(package_source)}"
            @server_configs[server.name][:required_products][product_name] = product_cache_path
          end
        end
      end
      all_required_products.each do |package_source, product_name|
        if package_source.start_with?('http')
          product_cache_path = "/var/dev-lxc/cache/chef-products/#{product_name}/#{File.basename(package_source)}"
          if !File.exist?(product_cache_path)
            FileUtils.mkdir_p(File.dirname(product_cache_path)) unless Dir.exist?(File.dirname(product_cache_path))
            puts "Downloading #{package_source} to #{product_cache_path}"
            open(package_source) { |url| File.open(product_cache_path, 'wb') { |f| f.write(url.read) } }
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
      end
      if server.container.running?
        server_was_running = true
      else
        server_was_running = false
        server.start
      end
      @server_configs[server.name][:required_products].each do |product_name, package_source|
        server.install_package(package_source)
      end
      server.stop
      server.snapshot("dev-lxc build: products installed")
      server.start if server_was_running
    end

    def chef_repo(force=false, pivotal=false)
      if @config['chef-server'][:bootstrap_backend].nil?
        puts "ERROR: A bootstrap backend Chef Server is not defined in the cluster's config. Please define it first."
        exit 1
      end
      chef_server = get_server(@config['chef-server'][:bootstrap_backend])
      if ! chef_server.container.defined?
        puts "ERROR: The '#{chef_server.name}' Chef Server does not exist."
        exit 1
      end

      puts "Creating chef-repo with pem files and knife.rb in the current directory"
      FileUtils.mkdir_p("./chef-repo/.chef")

      pem_files = Dir.glob("#{chef_server.container.config_item('lxc.rootfs')}/root/chef-repo/.chef/*.pem")
      if pem_files.empty?
        puts "The pem files can not be copied because they do not exist in '#{chef_server.name}' Chef Server's `/root/chef-repo/.chef` directory"
      else
        pem_files.delete_if { |pem_file| pem_file.end_with?("/pivotal.pem") } unless pivotal
        FileUtils.cp( pem_files, "./chef-repo/.chef" )
      end

      chef_server_root = "https://#{@config['chef-server'][:fqdn]}"
      chef_server_url = "https://#{@config['chef-server'][:fqdn]}/organizations/demo"
      validator_name = "demo-validator"

      if pivotal
        if File.exists?("./chef-repo/.chef/pivotal.rb") && ! force
          puts "Skipping pivotal.rb because it already exists in `./chef-repo/.chef`"
        else
          pivotal_rb_path = "#{chef_server.container.config_item('lxc.rootfs')}/root/chef-repo/.chef/pivotal.rb"
          if File.exists?(pivotal_rb_path)
            pivotal_rb = IO.read(pivotal_rb_path)
            pivotal_rb.sub!(/^chef_server_root .*/, "chef_server_root \"#{chef_server_root}\"")
            pivotal_rb.sub!(/^chef_server_url .*/, "chef_server_url \"#{chef_server_root}\"")
            IO.write("./chef-repo/.chef/pivotal.rb", pivotal_rb)
          else
            puts "The pivotal.rb file can not be copied because it does not exist in '#{chef_server.name}' Chef Server's `/root/chef-repo/.chef` directory"
          end
        end
      end

      if File.exists?("./chef-repo/.chef/knife.rb") && ! force
        puts "Skipping knife.rb because it already exists in `./chef-repo/.chef`"
      else
        knife_rb_path = "#{chef_server.container.config_item('lxc.rootfs')}/root/chef-repo/.chef/knife.rb"
        if File.exists?(knife_rb_path)
          knife_rb = IO.read(knife_rb_path)
          knife_rb.sub!(/^chef_server_url .*/, "chef_server_url \"#{chef_server_url}\"")
          IO.write("./chef-repo/.chef/knife.rb", knife_rb)
        else
          puts "The knife.rb file can not be copied because it does not exist in '#{chef_server.name}' Chef Server's `/root/chef-repo/.chef` directory"
        end
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
