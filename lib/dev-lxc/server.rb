require "json"
require "dev-lxc/container"

module DevLXC
  class Server
    attr_reader :container

    def initialize(name, ipaddress, additional_fqdn, mounts, ssh_keys)
      @container = DevLXC::Container.new(name)
      @ipaddress = ipaddress
      @additional_fqdn = additional_fqdn
      @mounts = mounts
      @ssh_keys = ssh_keys
    end

    def name
      @container.name
    end

    def status
      @container.status
    end

    def run_command(command, output_file=nil)
      if @container.running?
        puts "Running '#{command}' in '#{@container.name}'"
        puts "Saving output to #{output_file}" if output_file
        @container.run_command(command, output_file)
      else
        puts "'#{@container.name}' is not running"
      end
    end

    def install_package(package_path)
      @container.install_package(package_path)
    end

    def start
      return if @container.running?
      hwaddr = @container.config_item("lxc.network.0.hwaddr")
      release_lingering_dhcp_ip_addresses(hwaddr)
      assign_static_ip_address(hwaddr) if @ipaddress
      @container.sync_mounts(@mounts)
      @container.start
      @container.sync_ssh_keys(@ssh_keys)
      puts
    end

    def shutdown
      @container.shutdown if @container.running?
      remove_static_ip_address(@container.config_item("lxc.network.0.hwaddr")) if @container.defined?
    end

    def snapshot(comment=nil)
      unless @container.defined?
        puts "WARNING: Skipping snapshot of '#{@container.name}' because it does not exist"
        return
      end
      if @container.running?
        puts "WARNING: Skipping snapshot of '#{@container.name}' because it is running"
        return
      end
      puts "Creating snapshot of container '#{@container.name}'"
      snapname = @container.snapshot
      unless comment.nil?
        snapshot = @container.snapshot_list.select { |sn| sn.first == snapname }
        snapshot_comment_file = snapshot.flatten[1]
        IO.write(snapshot_comment_file, comment) unless snapshot_comment_file.nil?
      end
    end

    def snapshot_destroy(snapname=nil)
      unless @container.defined?
        puts "Skipping container '#{@container.name}' because it does not exist"
        return
      end
      if snapname == "ALL"
        if @container.snapshot_list.empty?
          puts "Container '#{@container.name}' does not have any snapshots"
        else
          @container.snapshot_list.each do |snapshot|
            puts "Destroying snapshot '#{snapshot.first}' of container '#{@container.name}'"
            @container.snapshot_destroy(snapshot.first)
          end
        end
      elsif snapname == "LAST"
        if @container.snapshot_list.empty?
          puts "Container '#{@container.name}' does not have any snapshots"
        else
          snapname = @container.snapshot_list.last.first
          puts "Destroying snapshot '#{snapname}' of container '#{@container.name}'"
          @container.snapshot_destroy(snapname)
        end
      else
        snapshot = @container.snapshot_list.select { |sn| sn.first == snapname }
        if snapshot.flatten.empty?
          puts "Container '#{@container.name}' does not have a '#{snapname}' snapshot"
        else
          puts "Destroying snapshot '#{snapname}' of container '#{@container.name}'"
          @container.snapshot_destroy(snapname)
        end
      end
    end

    def snapshot_list
      snapshots = Array.new
      return snapshots unless @container.defined?
      @container.snapshot_list.each do |snapshot|
        (snapname, snap_comment_file, snaptime) = snapshot
        snap_comment = IO.read(snap_comment_file).chomp if File.exist?(snap_comment_file)
        snapshots << [snapname, snaptime, snap_comment]
      end
      snapshots
    end

    def snapshot_restore(snapname=nil)
      unless @container.defined?
        puts "WARNING: Skipping container '#{@container.name}' because it does not exist"
        return
      end
      if @container.running?
        puts "WARNING: Skipping container '#{@container.name}' because it is running"
        return
      end
      if snapname == "LAST"
        if @container.snapshot_list.empty?
          puts "WARNING: Skipping container '#{@container.name}' because it does not have any snapshots"
        else
          snapname = @container.snapshot_list.last.first
          puts "Restoring snapshot '#{snapname}' of container '#{@container.name}'"
          @container.snapshot_restore(snapname)
        end
      else
        snapshot = @container.snapshot_list.select { |sn| sn.first == snapname }
        if snapshot.flatten.empty?
          puts "WARNING: Skipping container '#{@container.name}' because it does not have a '#{snapname}' snapshot"
        else
          puts "Restoring snapshot '#{snapname}' of container '#{@container.name}'"
          @container.snapshot_restore(snapname)
        end
      end
    end

    def destroy
      return unless @container.defined?
      @container.snapshot_list.each { |snapshot| @container.snapshot_destroy(snapshot.first) }
      hwaddr = @container.config_item("lxc.network.0.hwaddr")
      @container.destroy
      remove_static_ip_address(hwaddr)
    end

    def release_lingering_dhcp_ip_addresses(hwaddr)
      dhcp_leases = IO.readlines('/var/lib/misc/dnsmasq.lxcbr0.leases')
      leases_to_release = dhcp_leases.map do |dhcp_lease|
        if m = dhcp_lease.match(/ #{hwaddr} (\d+\.\d+\.\d+\.\d+) /)
          mac_addr = hwaddr
          ip_addr = m[1]
        elsif m = dhcp_lease.match(/ (\w\w:\w\w:\w\w:\w\w:\w\w:\w\w) #{@ipaddress} /)
          mac_addr = m[1]
          ip_addr = @ipaddress
        elsif m = dhcp_lease.match(/ (\w\w:\w\w:\w\w:\w\w:\w\w:\w\w) (\d+\.\d+\.\d+\.\d+) #{@container.name.sub(/\.lxc$/, '')} /)
          mac_addr = m[1]
          ip_addr = m[2]
        end
        if mac_addr && ip_addr
          { dhcp_lease: dhcp_lease, mac_addr: mac_addr, ip_addr: ip_addr }
        end
      end
      leases_to_release.compact!
      unless leases_to_release.empty?
        system("systemctl stop lxc-net.service")
        leases_to_release.each do |l|
          puts "Releasing lingering DHCP lease: #{l[:dhcp_lease]}"
          DevLXC.search_file_delete_line("/var/lib/misc/dnsmasq.lxcbr0.leases", /( #{l[:mac_addr]} #{l[:ip_addr]} )/)
        end
        system("systemctl start lxc-net.service")
      end
    end

    def assign_static_ip_address(hwaddr)
      puts "Assigning IP address #{@ipaddress} to '#{@container.name}' container's lxc.network.hwaddr #{hwaddr}"
      DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /(^#{hwaddr}|,#{@ipaddress}$)/)
      DevLXC.append_line_to_file("/etc/lxc/dhcp-hosts.conf", "#{hwaddr},#{@ipaddress}\n")
      DevLXC.reload_dnsmasq
    end

    def remove_static_ip_address(hwaddr=nil)
      if hwaddr
        DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /^#{hwaddr}/)
        DevLXC.reload_dnsmasq
      end
    end

  end
end
