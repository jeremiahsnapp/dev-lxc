module DevLXC
  class Container < LXC::Container
    def status
      if self.defined?
        state = self.state
        ip_addresses = self.ip_addresses.join(" ") if self.state == :running
      else
        state = "not_created"
      end
      { 'name' => self.name, 'state' => state, 'ip_addresses' => ip_addresses }
    end

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
      60.times do
        ips = self.ip_addresses
        break unless ips.empty?
        sleep 1
      end
      if ips.empty?
        puts "ERROR: Container '#{self.name}' network is not available."
        exit 1
      end
    end

    def shutdown
      puts "Shutting down container '#{self.name}'"
      super
      wait(:stopped, 3)
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
        self.clear_config_item('lxc.mount.entry')
        self.set_config_item("lxc.mount.entry", preserved_mounts)
      end
      unless mounts.nil?
        mounts.each do |mount|
          if ! preserved_mounts.nil? && preserved_mounts.any? { |m| m.start_with?("#{mount} ") }
            puts "Skipping mount entry #{mount}, it already exists"
            next
          else
            puts "Adding mount entry #{mount}"
            self.set_config_item("lxc.mount.entry", "#{mount} none bind,optional,create=dir 0 0     ## dev-lxc ##")
          end
        end
      end
      self.save_config
    end

    def sync_ssh_keys(ssh_keys)
      dot_ssh_path = "/home/dev-lxc/.ssh"
      unless File.exist?("#{config_item('lxc.rootfs')}#{dot_ssh_path}/authorized_keys")
        run_command("sudo -u dev-lxc mkdir -p #{dot_ssh_path}")
        run_command("sudo -u dev-lxc chmod 700 #{dot_ssh_path}")
        run_command("sudo -u dev-lxc touch #{dot_ssh_path}/authorized_keys")
        run_command("sudo -u dev-lxc chmod 600 #{dot_ssh_path}/authorized_keys")
      end
      authorized_keys = IO.read("#{config_item('lxc.rootfs')}#{dot_ssh_path}/authorized_keys").split("\n")
      authorized_keys.delete_if { |m| m.end_with?("## dev-lxc ##") }
      unless ssh_keys.nil?
        ssh_keys.each do |ssh_key|
          puts "Adding SSH key #{ssh_key} to #{dot_ssh_path}/authorized_keys"
          authorized_keys << IO.read(ssh_key).chomp + "     ## dev-lxc ##"
        end
      end
      authorized_keys_content = String.new
      authorized_keys_content = authorized_keys.join("\n") + "\n" unless authorized_keys.empty?
      IO.write("#{config_item('lxc.rootfs')}#{dot_ssh_path}/authorized_keys", authorized_keys_content)
    end

    def run_command(command, output_file=nil)
      unless running?
        puts "ERROR: Container '#{self.name}' must be running first"
        exit 1
      end
      attach_opts = { wait: true, env_policy: LXC::LXC_ATTACH_CLEAR_ENV, extra_env_vars: ['HOME=/root'] }
      if output_file
        file = File.open(output_file, 'w+')
        attach_opts[:stdout] = file
      end
      begin
        attach(attach_opts) do
          LXC.run_command(command)
        end
      ensure
        file.close if file
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
        install_command = "dpkg -i --skip-same-version #{package_path}"
      when ".rpm"
        install_command = "rpm -Uvh #{package_path}"
      end
      run_command(install_command)
    end

  end
end
