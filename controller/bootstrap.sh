#!/usr/bin/env bash

apt-get -y install ntp
echo "10.0.0.11  controller" >> /etc/hosts
apt-get install -y ubuntu-cloud-keyring
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
  "trusty-updates/juno main" > /etc/apt/sources.list.d/cloudarchive-juno.list 
apt-get update -y  && apt-get -y dist-upgrade
#apt-get install -y mariadb-server python-mysqldb
apt-get install -y rabbitmq-server

rabbitmqctl change_password guest secret


debconf-set-selections <<< 'mysql-server mysql-server/root_password password secret'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password secret'
apt-get -y install mysql-server


mysql -u root -psecret <<EOF
CREATE DATABASE neutron;



GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' \
  IDENTIFIED BY 'secret';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' \
  IDENTIFIED BY 'secret';
EOF



cat >> /etc/hosts <<EOF
10.0.0.11	controller
10.0.0.21	network
10.0.0.31       compute	
EOF

sed -e "s|bind-address.*|bind-address		=	controller|" -i /etc/mysql/my.cnf


service mysql restart
apt-get -y install ntp 
rabbitmqctl change_password guest secret


################
#  Install and Set up keystone identity service
 
apt-get -y install sqlite3 keystone python-keystoneclient

keystone-manage db_sync

sed '/^\[DEFAULT\]/ a\admin_token = secret' -i /etc/keystone/keystone.conf
sed '/^\[token\]/ a\provider = keystone.token.providers.uuid.Provider\ndriver = keystone.token.persistence.backends.sql.Token' -i /etc/keystone/keystone.conf

export OS_SERVICE_TOKEN=secret
export OS_SERVICE_ENDPOINT=http://controller:35357/v2.0
service keystone restart

####  Make sure keystone is up

sleep 20

keystone tenant-create --name admin --description "Admin Tenant"
keystone user-create --name admin  --pass secret --email "e@csc.com"
keystone role-create --name admin
keystone user-role-add --user admin --tenant admin --role admin
keystone tenant-create --name demo --description "Demo Tenant"
keystone user-create --name demo --tenant demo --pass secret  --email "d@csc.com"
keystone tenant-create --name service --description "Service Tenant"

keystone service-create --name keystone --type identity --description "Openstaick identity"

keystone endpoint-create --service-id $(keystone service-list | awk '/ identity / {print $2} ') --publicurl http://controller:5000/v2.0 --internalurl http://controller:5000/v2.0 --adminurl http://controller:35357/v2.0 --region regionOne


cat > /root/admin-openrc.sh <<EOF 
export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=secret
export OS_TENANT_NAME=admin
#export OS_SERVICE_TOKEN=secret
#export OS_SERVICE_ENDPOINT=http://controller:35357/v2.0
export OS_AUTH_URL=http://controller:35357/v2.0
EOF

cat > /root/demo-openrc.sh <<EOF

export OS_TENANT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=secret
export OS_AUTH_URL=http://controller:5000/v2.0
EOF

source /root/admin-openrc.sh


####################
### Install and setup up glance image service
####

keystone user-create --name glance --pass secret 

keystone user-role-add --user glance --tenant service --role admin

keystone service-create --name glance --type image --description "Openstack Image Service"


keystone endpoint-create --service-id $(keystone service-list | awk '/ image / {print $2} ') --publicurl http://controller:9292 --internalurl http://controller:9292 --adminurl http://controller:9292/v2.0 --region regionOne

apt-get install -y glance python-glanceclient

	sed -e '/^\[glance_store\]/ a\default_store = file' -i /etc/glance/glance-api.conf
for conf  in glance-api.conf glance-registry.conf
do
	sed -e 's|%SERVICE_TENANT_NAME%|service|' -i /etc/glance/$conf
	sed -e 's|%SERVICE_USER%|glance|' -i /etc/glance/$conf
	sed -e 's|%SERVICE_PASSWORD%|secret|' -i /etc/glance/$conf
	sed -e 's|identity_uri = http.*|identity_uri = http://controller:35357|' -i /etc/glance/$conf
	sed -e '/^\[keystone_authtoken\]/ a\auth_uri = http://controller:5000/v2.0' -i /etc/glance/$conf
	sed -e '/^\[paste_deploy\]/ a\flavor = keystone' -i /etc/glance/$conf
	sed -e '/^\[database\]/ a\connection = sqlite:////var/lib/glance/glance.sqlite' -i /etc/glance/$conf
	sed -e '/^\[DEFAULT\]/ a\notification = noop' -i /etc/glance/$conf
done	
#sed -e '/^\[glance_store\]/ a\default_store = file\nfilesystem_store_datadir = /var/lib/glance/images/' -i /etc/glance/glance-api.conf


su -s /bin/sh -c "glance-manage db_sync" glance
service glance-registry restart
service glance-api restart
sleep 5


#################################
##  Install the controller Node portion of Nova

 source /root/admin-openrc.sh
keystone user-create --name nova --pass secret
keystone user-role-add --user nova --tenant service --role admin
keystone service-create --name nova --type compute --description "Openstack Compute"
keystone endpoint-create --service-id $(keystone service-list | awk '/ compute / {print $2}') --publicurl http://controller:8774/v2/%\(tenant_id\)s --internalurl http://controller:8774/v2/%\(tenant_id\)s --adminurl http://controller:8774/v2/%\(tenant_id\)s  --region regionOne
apt-get install -y nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient

sed -e '/^\[DEFAULT\]/ a\rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = secret' -i /etc/nova/nova.conf

sed  -e '/^\[DEFAULT\]/ a\auth_strategy = keystone' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\my_ip = 10.0.0.11' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\vncsserver_listen = 10.0.0.11' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\vncsserver_proxyclient_address = 10.0.0.11' -i /etc/nova/nova.conf

cat >> /etc/nova/nova.conf <<EOF

[keystone_authtoken]

admin_password = secret
admin_tenant_name = service
admin_user = nova
auth_uri = http://controller:5000/v2.0
identity_uri = http://controller:35357

[glance]

host = controller
EOF


nova-manage db sync
service nova-api restart
service nova-cert restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart
#
# Make sure everything is restarted

sleep 40

#################################
#
#  Install Neutron


source /root/admin-openrc.sh
keystone user-create --name neutron --pass secret
keystone user-role-add --user neutron --tenant service --role admin
keystone service-create --name neutron --type network --description "OpenStack Networking"
keystone endpoint-create --service-id $(keystone service-list | awk '/ network / {print $2}') --publicurl http://controller:9696/ --adminurl http://controller:9696/ --internalurl http://controller:9696/ --region regionOne

#################
# Neutron
apt-get install -y  neutron-server neutron-plugin-ml2 python-neutronclient
sed -e "s|^connection =.*|connection = mysql://neutron:secret@controller/neutron|" -i /etc/neutron/neutron.conf
sed -e '/^\[DEFAULT\]/ a\rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = secret' -i /etc/neutron/neutron.conf
sed  -e '/^\[DEFAULT\]/ a\auth_strategy = keystone' -i /etc/neutron/neutron.conf
sed -e 's|%SERVICE_TENANT_NAME%|service|' -i /etc/neutron/neutron.conf
sed -e 's|%SERVICE_USER%|neutron|' -i  /etc/neutron/neutron.conf 
sed -e 's|%SERVICE_PASSWORD%|secret|' -i /etc/neutron/neutron.conf
sed -e '/^\[keystone_authtoken\]/ a\auth_uri = http://controller:5000/v2.0\nidentity_uri = http://controller:35357' -i /etc/neutron/neutron.conf
sed -e '/^auth_host/s/^/#/' -i /etc/neutron/neutron.conf
sed -e '/^auth_port/s/^/#/' -i /etc/neutron/neutron.conf
sed -e '/^auth_protocol/s/^/#/' -i /etc/neutron/neutron.conf

### ML2 router, overlapping IPS enableenable
source /root/admin-openrc.sh
SERVICE_TENANT_ID=$(keystone tenant-get service | awk -F\| ' / id / { print $3 }' | tr -d '[[:space:]]')
sed  -e '/^\[DEFAULT\]/ a\core_plugin = ml2\nservice_plugins = router\nallow_overlapping_ips = True' -i /etc/neutron/neutron.conf
sed  -e '/^\[DEFAULT\]/ a\notify_nova_on_port_status_changes = True\nnotify_nova_on_port_data_changes = True\nnova_url = http://controller:8774/v2\nnova_admin_auth_url = http://controller:35357/v2.0\nnova_region_name = regionOne\nnova_admin_username = nova\nnova_admin_tenant_id = '$SERVICE_TENANT_ID'\nnova_admin_password = secret' -i /etc/neutron/neutron.conf


sed  -e '/^\[DEFAULT\]/ a\firewall_driver = nova.virt.firewall.NoopFirewallDriver'  -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\linuxnet_interface_driver  = nova.network.linux_net.LinuxOVSInterfaceDriver'  -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\security_group_api = neutron'  -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\network_api_class = nova.network.neutronv2.api.API'  -i /etc/nova/nova.conf



#####
# Configure modular Layer2 Plugin

sed  -e '/^\[ml2\]/ a\tenant_network_types = gre' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2\]/ a\mechanism_drivers = openvswitch' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2\]/ a\type_drivers = flat,gre' -i /etc/neutron/plugins/ml2/ml2_conf.ini

sed  -e '/^\[ml2_type_flat\]/ a\flat_networks = external' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2_type_gre\]/ a\tunnel_id_ranges = 1:1000' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\enable_ipset = True' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\enable_security_group = True' -i /etc/neutron/plugins/ml2/ml2_conf.ini

cat >> /etc/nova/nova.conf <<EOF
[neutron]
url = http://controller:9696
auth_strategy = keystone
admin_auth_url = http://controller:35357/v2.0
admin_tenant_name = service
admin_username = neutron
admin_password = secret 
service_metadata_proxy = True
metadata_proxy_shared_secret = secret 
EOF




su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade juno" neutron

service nova-api start
service nova-scheduler restart
service nova-conductor restart
service neutron-server restart

sleep 20

neutron ext-list
