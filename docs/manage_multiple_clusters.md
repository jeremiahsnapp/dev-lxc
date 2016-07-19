### Maintain Uniqueness Across Multiple Clusters

The default cluster configs are already designed to be unique from each other but as you build
more clusters you have to maintain uniqueness across the YAML config files for the following items.

* Server names, `api_fqdn` and `analytics_fqdn`

    Server names should really be unique across all clusters.

    Even when cluster A is shutdown, if cluster B uses the same server names when it is created it
	will use the already existing servers from cluster A.

    `api_fqdn` and `analytics_fqdn` uniqueness only matters when clusters with the same `api_fqdn`
	and `analytics_fqdn` are running.

    If cluster B is started with the same `api_fqdn` or `analytics_fqdn` as an already running cluster A,
	then cluster B will overwrite cluster A's DNS resolution of `api_fqdn` or `analytics_fqdn`.

* IP Addresses

    IP addresses uniqueness only matters when clusters with the same IP's are running.

    If cluster B is started with the same IP's as an already running cluster A, then cluster B
	will overwrite cluster A's DHCP reservation of the IP's but dnsmasq will still refuse to
	assign the IP's to cluster B because they already in use by cluster A. dnsmasq then assigns
	random IP's from the DHCP pool to cluster B leaving it in an unexpected state.

    The `dev-lxc-platform` creates the IP range 10.0.3.150 - 254 for DHCP reserved IP's.

    Use unique IP's from that range when configuring clusters.
