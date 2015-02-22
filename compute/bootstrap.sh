#!/usr/bin/env bash

apt-get -y install ntp
apt-get install -y ubuntu-cloud-keyring
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
  "trusty-updates/juno main" > /etc/apt/sources.list.d/cloudarchive-juno.list 
apt-get update -y  && apt-get -y dist-upgrade
apt-get install -y rabbitmq-server

rabbitmqctl change_password guest secret

cat >> /etc/hosts <<EOF
10.0.0.11	controller
10.0.0.31	compute
EOF


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

apt-get install -y nova-compute sysfsutils


sed -e '/^\[DEFAULT\]/ a\rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = secret' -i /etc/nova/nova.conf

sed  -e '/^\[DEFAULT\]/ a\auth_strategy = keystone' -i /etc/nova/nova.conf
sed -e 's|%SERVICE_TENANT_NAME%|service|' -i /etc/nova/nova.conf
sed -e 's|%SERVICE_USER%|nova|' -i  /etc/nova/nova.conf
sed -e 's|%SERVICE_PASSWORD%|secret|' -i /etc/nova/nova.conf
sed -e '/^\[keystone_authtoken\]/ a\auth_uri = http://controller:5000/v2.0\nidentity_uri = http://controller:35357' -i /etc/nova/nova.conf
sed -e '/^auth_host/s/^/#/' -i /etc/nova/nova.conf
sed -e '/^auth_port/s/^/#/' -i /etc/nova/nova.conf
sed -e '/^auth_protocol/s/^/#/' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\my_ip = 10.0.0.31' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\vncsserver_listen = 0.0.0.0' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\vncsserver_proxyclient_address = 10.0.0.31' -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\novncproxy_base_url = http://controller:6080/vnc_auto.html' -i /etc/nova/nova.conf

cat >> /etc/nova/nova.conf <<EOF
[glance]

host = controller
EOF

sed -e 's|virt_type.*=.*|virt_type = qemu|' -i /etc/nova/nova-compute.conf


########################


sed -e 's|#net.ipv4.conf.all.rp_filter=1|net.ipv4.conf.all.rp_filter=0|' -i /etc/sysctl.conf

sed -e 's|#net.ipv4.conf.default.rp_filter=1|net.ipv4.conf.default.rp_filter=0|' -i /etc/sysctl.conf

sysctl -p

apt-get install -y neutron-plugin-ml2 neutron-plugin-openvswitch-agent


sed -e '/^\[DEFAULT\]/ a\rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = secret' -i /etc/neutron/neutron.conf

sed  -e '/^\[DEFAULT\]/ a\auth_strategy = keystone' -i /etc/neutron/neutron.conf
sed -e 's|%SERVICE_TENANT_NAME%|service|' -i /etc/neutron/neutron.conf
sed -e 's|%SERVICE_USER%|neutron|' -i  /etc/neutron/neutron.conf
sed -e 's|%SERVICE_PASSWORD%|secret|' -i /etc/neutron/neutron.conf
sed -e '/^\[keystone_authtoken\]/ a\auth_uri = http://controller:5000/v2.0\nidentity_uri = http://controller:35357' -i /etc/neutron/neutron.conf
sed -e '/^auth_host/s/^/#/' -i /etc/neutron/neutron.conf
sed -e '/^auth_port/s/^/#/' -i /etc/neutron/neutron.conf
sed -e '/^auth_protocol/s/^/#/' -i /etc/neutron/neutron.conf

sed  -e '/^\[DEFAULT\]/ a\core_plugin = ml2' -i /etc/neutron/neutron.conf
sed  -e '/^\[DEFAULT\]/ a\service_plugins = router' -i /etc/neutron/neutron.conf
sed  -e '/^\[DEFAULT\]/ a\allow_overlapping_ips = True' -i /etc/neutron/neutron.conf


sed  -e '/^\[ml2\]/ a\tenant_network_types = gre' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2\]/ a\mechanism_drivers = openvswitch' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2\]/ a\type_drivers = flat,gre' -i /etc/neutron/plugins/ml2/ml2_conf.ini

sed  -e '/^\[ml2_type_gre\]/ a\tunnel_id_ranges = 1:1000' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\enable_ipset = True' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\enable_security_group = True' -i /etc/neutron/plugins/ml2/ml2_conf.ini

cat >> /etc/neutron//plugins/ml2/ml2_conf.ini << EOF

[ovs]
local_ip = IDONTKNOW 
enable_tunneling = True

[agent]
tunnel_types = gre
EOF

service openswitch restart
sleep 5

sed  -e '/^\[DEFAULT\]/ a\firewall_driver = nova.virt.firewall.NoopFirewallDriver'  -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\linuxnet_interface_driver  = nova.network.linux_net.LinuxOVSInterfaceDriver'  -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\security_group_api = neutron'  -i /etc/nova/nova.conf
sed  -e '/^\[DEFAULT\]/ a\network_api_class = nova.network.neutronv2.api.API'  -i /etc/nova/nova.conf

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

service nova-compute restart

source /root/admin-openrc.sh

nova service-list
