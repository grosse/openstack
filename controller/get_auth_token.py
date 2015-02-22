from os import environ as env
import novaclient.client as nova_client
import keystoneclient.v2_0.client as keystone_client
import glanceclient.v2.client as glance_client
import time
USERNAME = env["OS_USERNAME"]
PASSWORD = env["OS_PASSWORD"]
TENANT_NAME = env["OS_TENANT_NAME"]
AUTH_URL = env["OS_AUTH_URL"]
keystone = keystone_client.Client(auth_url=env['OS_AUTH_URL'],
                           username=env['OS_USERNAME'],
                           password=env['OS_PASSWORD'],
                           tenant_name=env['OS_TENANT_NAME'],
                           )

print TENANT_NAME
glance_endpoint = keystone.service_catalog.url_for(service_type="image")

print glance_client.Client(glance_endpoint, token = keystone.auth_token)
nova =  nova_client.Client(2, USERNAME, PASSWORD, TENANT_NAME, AUTH_URL) 

cirros_flavor = nova.flavors.find(name="m1.tiny")
cirros_image = nova.images.find(name="cirros-0.3.3-x86_64")

print nova.servers.list()
for server in nova.servers.list():
	print "delete " + repr(server)
	server.delete()
try:
	nova.servers.find(name="eric")
except:
	pass	
	print "EXCEPT"
	instance = nova.servers.create(name="eric", image=cirros_image, flavor=cirros_flavor, keyname="my_key")
print nova.images.list()
print nova.servers.list()
print instance.status
time.sleep(3)
print instance.status

