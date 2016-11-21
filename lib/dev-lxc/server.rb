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

    def run_command(command)
      if @container.running?
        puts "Running '#{command}' in '#{@container.name}'"
        @container.run_command(command)
      else
        puts "'#{@container.name}' is not running"
      end
    end

    def install_package(package_path)
      @container.install_package(package_path)
    end

    def start
      hwaddr = @container.config_item("lxc.network.0.hwaddr")
      DevLXC.assign_ip_address(@ipaddress, @container.name, hwaddr) if @ipaddress
      @container.sync_mounts(@mounts)
      @container.start
      @container.sync_ssh_keys(@ssh_keys)
    end

    def stop
      hwaddr = @container.config_item("lxc.network.0.hwaddr") if @container.defined?
      @container.stop
      deregister_from_dhcp(hwaddr)
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
      if @container.defined?
        hwaddr = @container.config_item("lxc.network.0.hwaddr")
        @container.snapshot_list.each { |snapshot| @container.snapshot_destroy(snapshot.first) }
      end
      @container.destroy
      deregister_from_dhcp(hwaddr)
    end

    def deregister_from_dhcp(hwaddr)
      if @ipaddress
        DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /,#{@ipaddress}$/)
      end
      unless hwaddr.nil?
        DevLXC.search_file_delete_line("/etc/lxc/dhcp-hosts.conf", /^#{hwaddr}/)
      end
      DevLXC.reload_dnsmasq
    end

  end
end
