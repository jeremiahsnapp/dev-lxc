
# reference: https://hub.docker.com/r/dinkel/openldap/
# docker run --name my-ldap -d -p 389:389 -e SLAPD_PASSWORD=mysecretpassword -e SLAPD_DOMAIN=ldap.example.org dinkel/openldap

# reference: https://docs.chef.io/server_ldap.html
ldap['base_dn'] = 'DC=ldap,DC=example,DC=org'
ldap['bind_dn'] = 'CN=admin,DC=ldap,DC=example,DC=org'
ldap['bind_password'] = 'mysecretpassword'
ldap['host'] = '10.0.3.1'
ldap['login_attribute'] = 'cn'
