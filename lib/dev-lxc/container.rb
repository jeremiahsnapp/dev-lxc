module DevLXC
  class Container < LXC::Container
    def start
      raise "Container #{self.name} does not exist." unless self.defined?
      puts "Starting container #{self.name}"
      super
      wait(:running, 3)
      puts "Waiting for #{self.name} container's network"
      ips = nil
      30.times do
        ips = self.ip_addresses
        break unless ips.empty?
        sleep 1
      end
      raise "Container #{self.name} network is not available." if ips.empty?
    end

    def stop
      puts "Stopping container #{self.name}"
      super
      wait("STOPPED", 3)
    end

    def destroy
      return unless self.defined?
      stop if running?
      puts "Destroying container #{self.name}"
      super
    end

    def run_command(command)
      raise "Container #{self.name} must be running first" unless running?
      attach({:wait => true, :stdin => STDIN, :stdout => STDOUT, :stderr => STDERR}) do
        LXC.run_command(command)
      end
    end

    def install_package(package_path)
      puts "Installing #{package_path} in container #{self.name}"
      case File.extname(package_path)
      when ".deb"
        install_command = "dpkg -D10 -i #{package_path}"
      when ".rpm"
        install_command = "rpm -Uvh #{package_path}"
      end
      run_command(install_command)
    end
  end
end
