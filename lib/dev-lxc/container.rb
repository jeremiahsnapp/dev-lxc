module DevLXC
  class Container < LXC::Container
    def start
      unless self.defined?
        puts "ERROR: Container '#{self.name}' does not exist."
        exit 1
      end
      puts "Starting container '#{self.name}'"
      super
      wait(:running, 3)
      puts "Waiting for '#{self.name}' container's network"
      ips = nil
      30.times do
        ips = self.ip_addresses
        break unless ips.empty?
        sleep 1
      end
      if ips.empty?
        puts "ERROR: Container '#{self.name}' network is not available."
        exit 1
      end
    end

    def stop
      puts "Stopping container '#{self.name}'"
      super
      wait("STOPPED", 3)
    end

    def destroy
      stop if running?
      puts "Destroying container '#{self.name}'"
      super if self.defined?
    end

    def sync_mounts(mounts)
      existing_mounts = self.config_item("lxc.mount.entry")
      unless existing_mounts.nil?
        preserved_mounts = existing_mounts.delete_if { |m| m.end_with?("## dev-lxc ##") }
        self.clear_config_item('lxc.mount.entries')
        self.set_config_item("lxc.mount.entry", preserved_mounts)
      end
      mounts.each do |mount|
        unless File.exists?(mount.split.first)
          puts "ERROR: Mount source #{mount.split.first} does not exist."
          exit 1
        end
        if ! preserved_mounts.nil? && preserved_mounts.any? { |m| m.start_with?("#{mount} ") }
          puts "Skipping mount entry #{mount}, it already exists"
          next
        else
          puts "Adding mount entry #{mount}"
          self.set_config_item("lxc.mount.entry", "#{mount} none bind,optional,create=dir 0 0     ## dev-lxc ##")
        end
      end
      self.save_config
    end

    def run_command(command)
      unless running?
        puts "ERROR: Container '#{self.name}' must be running first"
        exit 1
      end
      attach_opts = { wait: true, env_policy: LXC::LXC_ATTACH_CLEAR_ENV, extra_env_vars: ['HOME=/root'] }
      attach(attach_opts) do
        LXC.run_command(command)
      end
    end

    def install_package(package_path)
      unless run_command("test -e #{package_path}") == 0
        puts "ERROR: File #{package_path} does not exist in container '#{self.name}'"
        exit 1
      end
      puts "Installing #{package_path} in container '#{self.name}'"
      case File.extname(package_path)
      when ".deb"
        install_command = "dpkg -D10 -i #{package_path}"
      when ".rpm"
        install_command = "rpm -Uvh #{package_path}"
      end
      run_command(install_command)
    end

    def install_chef_client(version=nil)
      unless self.defined?
        puts "ERROR: Container '#{self.name}' does not exist."
        exit 1
      end
      unless running?
        puts "ERROR: Container '#{self.name}' is not running"
        exit 1
      end
      if self.ip_addresses.empty?
        puts "ERROR: Container '#{self.name}' network is not available."
        exit 1
      end

      require 'tempfile'

      installed_version = nil
      file = Tempfile.new('installed_chef_client_version')
      begin
        attach_opts = { wait: true, env_policy: LXC::LXC_ATTACH_CLEAR_ENV, extra_env_vars: ['HOME=/root'], stdout: file }
        attach(attach_opts) do
          puts `chef-client -v`
        end
        file.rewind
        installed_version = Regexp.last_match[1] if file.read.match(/chef:\s*(\d+\.\d+\.\d+)/i)
      ensure
        file.close
        file.unlink
      end
      if installed_version.nil? || ( ! version.nil? && ! installed_version.start_with?(version) )
        require "net/https"
        require "uri"

        uri = URI.parse("https://www.chef.io/chef/install.sh")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri.request_uri)

        response = http.request(request)

        file = Tempfile.new('install_sh', "#{config_item('lxc.rootfs')}/tmp")
        file.write(response.body)
        begin
          version = 'latest' if version.nil?
          install_command = "bash /tmp/#{File.basename(file.path)} -v #{version}"
          run_command(install_command)
        ensure
          file.close
          file.unlink
        end
      else
        puts "Chef #{installed_version} is already installed."
      end
    end

    def configure_chef_client(chef_server_url, validation_client_name, validation_key)
      unless self.defined?
        puts "ERROR: Container '#{self.name}' does not exist."
        exit 1
      end

      puts "Configuring Chef Client in container '#{self.name}' for Chef Server '#{chef_server_url}'"

      FileUtils.mkdir_p("#{config_item('lxc.rootfs')}/etc/chef")

      client_rb = %Q(chef_server_url '#{chef_server_url}'
validation_client_name '#{validation_client_name}'
ssl_verify_mode :verify_none
)
      IO.write("#{config_item('lxc.rootfs')}/etc/chef/client.rb", client_rb)

      begin
        FileUtils.cp(validation_key, "#{config_item('lxc.rootfs')}/etc/chef/validation.pem")
      rescue Errno::ENOENT
        puts "ERROR: The validation key '#{validation_key}' does not exist."
      end
    end

    def bootstrap_container(base_container_name=nil, version=nil, run_list=nil, chef_server_url, validation_client_name, validation_key)
      puts "Bootstrapping container '#{self.name}' for Chef Server '#{chef_server_url}'"
      if base_container_name
        if self.defined?
          puts "WARN: Skipping cloning. Container '#{self.name}' already exists"
        else
          puts "Cloning base container '#{base_container_name}' into container '#{self.name}'"
          base_container = DevLXC::Container.new(base_container_name)
          unless base_container.defined?
            puts "ERROR: Base container '#{base_container_name} does not exist"
            exit 1
          end
          base_container.clone(self.name, {:flags => LXC::LXC_CLONE_SNAPSHOT})
          self.load_config
        end
      end
      self.start unless self.running?
      self.install_chef_client(version)
      self.configure_chef_client(chef_server_url, validation_client_name, validation_key)

      chef_client_command = "chef-client"
      chef_client_command += " -r #{run_list}" if run_list
      self.run_command(chef_client_command)
    end

  end
end
