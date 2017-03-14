
# reference: https://hub.docker.com/_/postgres/
# docker run --name my-postgres -d -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword postgres

# reference:
# https://docs.chef.io/server_components.html#external-postgresql
# https://github.com/chef/chef-server/blob/master/PRIOR_RELEASE_NOTES.md#chef-server-5
# Specify that postgresql is an external database, and provide the
# VIP of this cluster.  This prevents the chef-server instance
# from creating it's own local postgresql instance.
postgresql['external'] = true
postgresql['vip'] = '10.0.3.1'
postgresql['db_superuser'] = 'postgres'
postgresql['db_superuser_password'] = 'mysecretpassword'
