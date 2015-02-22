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
10.0.0.21 	network	
10.0.0.31	compute
EOF


sed  -e "/^#net.ipv4.ip_forward/s/#//" -i /etc/sysctl.conf
sed -e 's|#net.ipv4.conf.all.rp_filter=1|net.ipv4.conf.all.rp_filter=0|' -i /etc/sysctl.conf
sed -e 's|#net.ipv4.conf.default.rp_filter=1|net.ipv4.conf.default.rp_filter=0|' -i /etc/sysctl.conf

sysctl -p
apt-get install -y neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent


sed -e '/^\[DEFAULT\]/ a\rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = secret' -i /etc/neutron/neutron.conf

sed  -e '/^\[DEFAULT\]/ a\auth_strategy = keystone' -i /etc/neutron/neutron.conf
sed -e 's|%SERVICE_TENANT_NAME%|service|' -i /etc/neutron/neutron.conf
sed -e 's|%SERVICE_USER%|neutron|' -i  /etc/neutron/neutron.conf
sed -e 's|%SERVICE_PASSWORD%|secret|' -i /etc/neutron/neutron.conf
sed -e '/^\[keystone_authtoken\]/ a\auth_uri = http://controller:5000/v2.0\nidentity_uri = http://controller:35357' -i /etc/neutron/neutron.conf
sed -e '/^auth_host/s/^/#/' -i /etc/neutron/neutron.conf
sed -e '/^auth_port/s/^/#/' -i /etc/neutron/neutron.conf
sed -e '/^auth_protocol/s/^/#/' -i /etc/neutron/neutron.conf



sed  -e '/^\[DEFAULT\]/ a\allow_overlapping_ips = True' -i /etc/neutron/neutron.conf
sed  -e '/^\[DEFAULT\]/ a\service_plugins = ml2' -i /etc/neutron/neutron.conf
sed  -e '/^\[DEFAULT\]/ a\core_plugin = ml2' -i /etc/neutron/neutron.conf


#####
# Configure modular Layer2 Plugin

sed  -e '/^\[ml2\]/ a\tenant_network_types = gre' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2\]/ a\mechanism_drivers = openvswitch' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2\]/ a\type_drivers = flat,gre' -i /etc/neutron/plugins/ml2/ml2_conf.ini

sed  -e '/^\[ml2_type_flat\]/ a\flat_networks = external' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[ml2_type_gre\]/ a\tunnel_id_ranges = 1:1000' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\enable_ipset = True' -i /etc/neutron/plugins/ml2/ml2_conf.ini
sed  -e '/^\[securitygroup\]/ a\enable_security = True' -i /etc/neutron/plugins/ml2/ml2_conf.ini


cat >> /etc/neutron//plugins/ml2/ml2_conf.ini << EOF

[ovs]
local_ip = IDONTKNOW
enable_tunneling = True
bridge_mappings = external:br-ex

[agent]
tunnel_types = gre
EOF


####
# Configure modular Layer2 Plugin

sed  -e '/^\[DEFAULT\]/ a\router_delete_namespaces = TRUE' -i /etc/neutron/l3_agent.ini
sed  -e '/^\[DEFAULT\]/ a\external_network_bridge = br-ex' -i /etc/neutron/l3_agent.ini
sed  -e '/^\[DEFAULT\]/ a\use_namespaces = TRUE' -i /etc/neutron/l3_agent.ini
sed  -e '/^\[DEFAULT\]/ a\interface_driver = neutron.agent.linux.interface.OVSInterfaceDrifer' -i /etc/neutron/l3_agent.ini

#####
# Configure DHCP Plugin

sed  -e '/^\[DEFAULT\]/ a\dhcp_delete_namespaces = True' -i /etc/neutron/dhcp_agent.ini
sed  -e '/^\[DEFAULT\]/ a\use_namespaces  = True' -i /etc/neutron/dhcp_agent.ini
sed  -e '/^\[DEFAULT\]/ a\dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq' -i /etc/neutron/dhcp_agent.ini
sed  -e '/^\[DEFAULT\]/ a\interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver' -i /etc/neutron/dhcp_agent.ini


#####
# Configure metadata agent

sed -e 's|%SERVICE_TENANT_NAME%|service|' -i /etc/neutron/metadata_agent.ini
sed -e 's|%SERVICE_USER%|neutron|' -i  /etc/neutron/metadata_agent.ini
sed -e 's|%SERVICE_PASSWORD%|secret|' -i /etc/neutron/metadata_agent.ini
sed -e 's|http://localhost:5000|http://controller:5000|' -i /etc/neutron/metadata_agent.ini
sed  -e '/^\[DEFAULT\]/ a\nova_metadata_ip  = controller' -i /etc/neutron/metadata_agent.ini
sed  -e '/^\[DEFAULT\]/ a\metadata_proxy_shared_secret  = secret' -i /etc/neutron/metadata_agent.ini
