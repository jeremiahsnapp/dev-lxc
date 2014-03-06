# Authors
# Seth Chisamore
# Seth Falcon
# Jeremiah Snapp

require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

class PiabHelper

  VALID_OMNIBUS_ROOTS = %w{
    /opt/opscode
    /opt/chef-server
  }

  def self.omnibus_root
    @@root_path ||= begin
      root_path = VALID_OMNIBUS_ROOTS.detect{|path| File.exists?(path) }
      raise "Could not locate one of #{VALID_OMNIBUS_ROOTS.join(', ')}" unless root_path
      root_path
    end
  end

  def self.omnibus_bin_path
    self.omnibus_root + "/embedded/bin"
  end

  def self.private_chef_ha?
    File.exists?("/etc/opscode/private-chef.rb") && File.read("/etc/opscode/private-chef.rb") =~ /topology\s+.*ha/
  end

  def self.private_chef?
    File.exists?("/opt/opscode/bin/private-chef-ctl")
  end

  def self.open_source_chef?
    File.exists?("/opt/chef-server/bin/chef-server-ctl")
  end

  def self.existing_config
    config_files = {
      "private_chef" => "/etc/opscode/chef-server-running.json",
      "chef_server" => "/etc/chef-server/chef-server-running.json"
    }
    config_files.each do |key, path|
      if ::File.exists?(path)
        return Chef::JSONCompat.from_json(IO.read(path))[key]
      end
    end
    raise "No existing config found"
  end

end
