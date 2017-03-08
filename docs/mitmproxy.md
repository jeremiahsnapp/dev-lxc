### Use mitmproxy to view HTTP traffic

Run `mitmproxy` in a terminal on the host instance.

Uncomment the `https_proxy` line in the chef-repo's `.chef/knife.rb` or in a node's `/etc/chef/client.rb` so traffic from knife commands or chef-client runs will be proxied through mitmproxy making the HTTP requests visible in the mitmproxy console.

If you enabled local port forwarding for port 8080 in your workstation's SSH config file and configured your web browser to use `127.0.0.1:8080` for HTTP and HTTPS proxies as described in the [dev-lxc-platform README.md](https://github.com/jeremiahsnapp/dev-lxc-platform) then you should be able to see the HTTP requests appear in the mitmproxy console.
