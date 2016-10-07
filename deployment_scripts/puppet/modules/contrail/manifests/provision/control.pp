#    Copyright 2015 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

class contrail::provision::control {

  Exec {
    provider => 'shell',
    path     => '/usr/bin:/bin:/sbin',
  }

  define contrail::provision::prov_ext_bgp {
    exec { "prov_external_bgp_${name}":
      command => "python /opt/contrail/utils/provision_mx.py  \
--api_server_ip ${contrail::contrail_mgmt_vip} --api_server_port ${contrail::api_server_port} \
--oper add --router_name ${name} --router_ip ${name} --router_asn ${contrail::asnum} \
--admin_user '${contrail::neutron_user}' --admin_tenant_name '${contrail::service_tenant}' --admin_password '${contrail::service_token}' \
&& touch /opt/contrail/prov_external_bgp_${name}-DONE",
      creates => "/opt/contrail/prov_external_bgp_${name}-DONE",
    }
  }

  define contrail::provision::add_route_to_mx {
    if $contrail::gateway {
      file_line {"route_to_gw_${name}":
        ensure    => 'present',
        line      => "post-up ip route add ${name}/32 via ${contrail::gateway} dev ${contrail::interface}",
        path      => "/etc/network/interfaces.d/ifcfg-${contrail::interface}",
      }
      exec {"route_to_gw_${name}":
        command => "ip route add ${name}/32 via ${contrail::gateway} dev ${contrail::interface}",
        unless  => "ip route | grep ${name}"
      }
    }
  }

  if roles_include(['primary-contrail-control']) {
    contrail::provision::api_readiness::check{'/opt/contrail/prov_control_asn-DONE':} ->
    exec { 'prov_control_asn':
      command => "python /opt/contrail/utils/provision_control.py \
--api_server_ip ${contrail::contrail_mgmt_vip} --api_server_port ${contrail::api_server_port} \
--router_asn ${contrail::asnum} \
--admin_user '${contrail::neutron_user}' --admin_tenant_name '${contrail::service_tenant}' --admin_password '${contrail::service_token}' \
&& touch /opt/contrail/prov_control_asn-DONE",
      creates => '/opt/contrail/prov_control_asn-DONE',
      before  => Exec['prov_control_bgp'],
    }
  }

  contrail::provision::api_readiness::check{'/opt/contrail/prov_control_bgp-DONE':} ->
  exec { 'prov_control_bgp':
    command => "python /opt/contrail/utils/provision_control.py \
--api_server_ip ${contrail::contrail_mgmt_vip} --api_server_port ${contrail::api_server_port} \
--oper add --host_name ${::fqdn} --host_ip ${contrail::address} --router_asn ${contrail::asnum} \
--admin_user '${contrail::neutron_user}' --admin_tenant_name '${contrail::service_tenant}' --admin_password '${contrail::service_token}' \
&& touch /opt/contrail/prov_control_bgp-DONE",
    creates => '/opt/contrail/prov_control_bgp-DONE',
  }

  if roles_include('primary-contrail-control') {
    contrail::provision::prov_ext_bgp { $contrail::gateways:
      require  => Exec['prov_control_bgp'],
    }
  }

  contrail::provision::add_route_to_mx { $contrail::gateways:
      require  => Exec['prov_control_bgp'],
  }
}
