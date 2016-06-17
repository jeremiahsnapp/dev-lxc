require "json"
require "dev-lxc/container"

module DevLXC
  class Server
    attr_reader :server

    def initialize(name, ipaddress, additional_fqdn, mounts, ssh_keys)
      @server = DevLXC::Container.new(name)
      @ipaddress = ipaddress
      @additional_fqdn = additional_fqdn
      @mounts = mounts
      @ssh_keys = ssh_keys
    end

    def realpath(rootfs_path)
      "#{@server.config_item('lxc.rootfs')}#{rootfs_path}" if @server.defined?
    end

    def run_command(command)
      if @server.running?
        puts "Running '#{command}' in '#{@server.name}'"
        @server.run_command(command)
      else
        puts "'#{@server.name}' is not running"
      end
    end

    def start
      hwaddr = @server.config_item("lxc.network.0.hwaddr")
      DevLXC.assign_ip_address(@ipaddress, @server.name, hwaddr)
      DevLXC.create_dns_record(@additional_fqdn, @server.name, @ipaddress) unless @additional_fqdn.nil?
      @server.sync_mounts(@mounts)
      @server.start
      @server.sync_ssh_keys(@ssh_keys)
    end

    def stop
      hwaddr = @server.config_item("lxc.network.0.hwaddr") if @server.defined?
      @server.stop
      deregister_from_dnsmasq(hwaddr)
    end

    def snapshot(comment=nil)
      unless @server.defined?
        puts "WARNING: Skipping snapshot of '#{@server.name}' because it does not exist"
        return
      end
      if @server.running?
        puts "WARNING: Skipping snapshot of '#{@server.name}' because it is running"
        return
      end
      puts "Creating snapshot of container '#{@server.name}'"
      snapname = @server.snapshot
      unless comment.nil?
        snapshot = @server.snapshot_list.select { |sn| sn.first == snapname }
        snapshot_comment_file = snapshot.flatten[1]
        IO.write(snapshot_comment_file, comment) unless snapshot_comment_file.nil?
      end
    end

    def snapshot_destroy(snapname=nil)
      unless @server.defined?
        puts "Skipping container '#{@server.name}' because it does not exist"
        return
      end
      if snapname == "ALL"
        if @server.snapshot_list.empty?
          puts "Container '#{@server.name}' does not have any snapshots"
        else
          @server.snapshot_list.each do |snapshot|
            puts "Destroying snapshot '#{snapshot.first}' of container '#{@server.name}'"
            @server.snapshot_destroy(snapshot.first)
          end
        end
      elsif snapname == "LAST"
        if @server.snapshot_list.empty?
          puts "Container '#{@server.name}' does not have any snapshots"
        else
          snapname = @server.snapshot_list.last.first
          puts "Destroying snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_destroy(snapname)
        end
      else
        snapshot = @server.snapshot_list.select { |sn| sn.first == snapname }
        if snapshot.flatten.empty?
          puts "Container '#{@server.name}' does not have a '#{snapname}' snapshot"
        else
          puts "Destroying snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_destroy(snapname)
        end
      end
    end

    def snapshot_list
      snapshots = Array.new
      return snapshots unless @server.defined?
      @server.snapshot_list.each do |snapshot|
        (snapname, snap_comment_file, snaptime) = snapshot
        snap_comment = IO.read(snap_comment_file).chomp if File.exist?(snap_comment_file)
        snapshots << [snapname, snaptime, snap_comment]
      end
      snapshots
    end

    def snapshot_restore(snapname=nil)
      unless @server.defined?
        puts "WARNING: Skipping container '#{@server.name}' because it does not exist"
        return
      end
      if @server.running?
        puts "WARNING: Skipping container '#{@server.name}' because it is running"
        return
      end
      if snapname == "LAST"
        if @server.snapshot_list.empty?
          puts "WARNING: Skipping container '#{@server.name}' because it does not have any snapshots"
        else
          snapname = @server.snapshot_list.last.first
          puts "Restoring snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_restore(snapname)
        end
      else
        snapshot = @server.snapshot_list.select { |sn| sn.first == snapname }
        if snapshot.flatten.empty?
          puts "WARNING: Skipping container '#{@server.name}' because it does not have a '#{snapname}' snapshot"
        else
          puts "Restoring snapshot '#{snapname}' of container '#{@server.name}'"
          @server.snapshot_restore(snapname)
        end
      end
    end

    def destroy
      if @server.defined?
        hwaddr = @server.config_item("lxc.network.0.hwaddr")
        @server.snapshot_list.each { |snapshot| @server.snapshot_destroy(snapshot.first) }
      end
      @server.destroy
      deregister_from_dnsmasq(hwaddr)
    end

    def deregister_from_dnsmasq(hwaddr)
      DevLXC.search_file_delete_line("/etc/lxc/addn-hosts.conf", /^#{@ipaddress}\s/)
      DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /,#{@ipaddress}$/)
      unless hwaddr.nil?
        DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /^#{hwaddr}/)
      end
      DevLXC.reload_dnsmasq
    end

  end
end
