
# Chef Server doesn't work properly with elasticsearch 5.x but i'm keeping the following info here for reference anyway
# reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html
# docker run --name my-elasticsearch -d -p 9200:9200 -e "http.host=0.0.0.0" -e "transport.host=127.0.0.1" -e "xpack.security.enabled=false docker.elastic.co/elasticsearch/elasticsearch:5.2.2


# Chef Server works with elasticsearch 2.3 so use the following docker command to create an elasticsearch instance
# reference: https://hub.docker.com/r/library/elasticsearch/
# docker run --name my-elasticsearch -d -p 9200:9200 -e "http.host=0.0.0.0" -e "transport.host=127.0.0.1" elasticsearch:2.3


# reference: https://github.com/chef/chef-server/blob/master/PRIOR_RELEASE_NOTES.md#elasticsearch-search-indexing
# These settings ensure that we use remote elasticsearch
# instead of local solr for search.  This also
# set search_queue_mode to 'batch' to remove the indexing
# dependency on rabbitmq, which is not supported in this HA configuration.
opscode_solr4['external'] = true
opscode_solr4['external_url'] = 'http://10.0.3.1:9200'
opscode_erchef['search_provider'] = 'elasticsearch'
opscode_erchef['search_queue_mode'] = 'batch'

# RabbitMQ settings

# Disable rabbit backend. Note that this makes
# this incompatible with reporting and analytics unless you're bringing in
# an external rabbitmq.
rabbitmq['enable'] = false
rabbitmq['management_enabled'] = false
rabbitmq['queue_length_monitor_enabled'] = false

# Opscode Expander
#
# opscode-expander isn't used when the search_queue_mode is batch.  It
# also doesn't support the elasticsearch backend.
opscode_expander['enable'] = false

# Prevent startup failures due to missing rabbit host
dark_launch['actions'] = false
