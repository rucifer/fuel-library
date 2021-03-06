notice('MODULAR: controller.pp')

# Pulling hiera
$public_int                     = hiera('public_int', undef)
$public_vip                     = hiera('public_vip')
$management_vip                 = hiera('management_vip')
$internal_address               = hiera('internal_address')
$primary_controller             = hiera('primary_controller')
$storage_address                = hiera('storage_address')
$use_neutron                    = hiera('use_neutron')
$neutron_nsx_config             = hiera('nsx_plugin')
$cinder_nodes_array             = hiera('cinder_nodes', [])
$sahara_hash                    = hiera('sahara', {})
$murano_hash                    = hiera('murano', {})
$heat_hash                      = hiera('heat', {})
$mp_hash                        = hiera('mp')
$verbose                        = true
$debug                          = hiera('debug', true)
$use_monit                      = false
$mongo_hash                     = hiera('mongo', {})
$auto_assign_floating_ip        = hiera('auto_assign_floating_ip', false)
$nodes_hash                     = hiera('nodes', {})
$storage_hash                   = hiera('storage', {})
$vcenter_hash                   = hiera('vcenter', {})
$nova_hash                      = hiera('nova', {})
$mysql_hash                     = hiera('mysql', {})
$rabbit_hash                    = hiera('rabbit', {})
$glance_hash                    = hiera('glance', {})
$keystone_hash                  = hiera('keystone', {})
$swift_hash                     = hiera('swift', {})
$cinder_hash                    = hiera('cinder', {})
$ceilometer_hash                = hiera('ceilometer',{})
$access_hash                    = hiera('access', {})
$network_scheme                 = hiera('network_scheme', {})
$controllers                    = hiera('controllers')
$neutron_mellanox               = hiera('neutron_mellanox', false)
$syslog_hash                    = hiera('syslog', {})
$base_syslog_hash               = hiera('base_syslog', {})
$use_syslog                     = hiera('use_syslog', true)
$syslog_log_facility_glance     = hiera('syslog_log_facility_glance', 'LOG_LOCAL2')
$syslog_log_facility_cinder     = hiera('syslog_log_facility_cinder', 'LOG_LOCAL3')
$syslog_log_facility_neutron    = hiera('syslog_log_facility_neutron', 'LOG_LOCAL4')
$syslog_log_facility_nova       = hiera('syslog_log_facility_nova','LOG_LOCAL6')
$syslog_log_facility_keystone   = hiera('syslog_log_facility_keystone', 'LOG_LOCAL7')
$syslog_log_facility_murano     = hiera('syslog_log_facility_murano', 'LOG_LOCAL0')
$syslog_log_facility_heat       = hiera('syslog_log_facility_heat','LOG_LOCAL0')
$syslog_log_facility_sahara     = hiera('syslog_log_facility_sahara','LOG_LOCAL0')
$syslog_log_facility_ceilometer = hiera('syslog_log_facility_ceilometer','LOG_LOCAL0')
$syslog_log_facility_ceph       = hiera('syslog_log_facility_ceph','LOG_LOCAL0')

# TODO: openstack_version is confusing, there's such string var in hiera and hardcoded hash
$hiera_openstack_version = hiera('openstack_version')
$openstack_version = {
  'keystone'   => 'installed',
  'glance'     => 'installed',
  'horizon'    => 'installed',
  'nova'       => 'installed',
  'novncproxy' => 'installed',
  'cinder'     => 'installed',
}

$queue_provider='rabbitmq'
$custom_mysql_setup_class='galera'

# Do the stuff
if $neutron_mellanox {
  $mellanox_mode = $neutron_mellanox['plugin']
} else {
  $mellanox_mode = 'disabled'
}

if (!empty(filter_nodes(hiera('nodes'), 'role', 'ceph-osd')) or
  $storage_hash['volumes_ceph'] or
  $storage_hash['images_ceph'] or
  $storage_hash['objects_ceph']
) {
  $use_ceph = true
} else {
  $use_ceph = false
}


if $use_neutron {
  include l23network::l2
  $novanetwork_params        = {}
  $neutron_config            = hiera('quantum_settings')
  $network_provider          = 'neutron'
  $neutron_db_password       = $neutron_config['database']['passwd']
  $neutron_user_password     = $neutron_config['keystone']['admin_password']
  $neutron_metadata_proxy_secret = $neutron_config['metadata']['metadata_proxy_shared_secret']
  $base_mac                  = $neutron_config['L2']['base_mac']
  if $neutron_nsx_config['metadata']['enabled'] {
    $use_vmware_nsx     = true
  }
} else {
  $neutron_config     = {}
  $novanetwork_params = hiera('novanetwork_parameters')
  $network_size       = $novanetwork_params['network_size']
  $num_networks       = $novanetwork_params['num_networks']
  $vlan_start         = $novanetwork_params['vlan_start']
  $network_provider   = 'nova'
}
$network_manager = "nova.network.manager.${novanetwork_params['network_manager']}"

if !$ceilometer_hash {
  $ceilometer_hash = {
    enabled => false,
    db_password => 'ceilometer',
    user_password => 'ceilometer',
    metering_secret => 'ceilometer',
  }
  $ext_mongo = false
} else {
  # External mongo integration
  if $mongo_hash['enabled'] {
    $ext_mongo_hash = hiera('external_mongo')
    $ceilometer_db_user = $ext_mongo_hash['mongo_user']
    $ceilometer_db_password = $ext_mongo_hash['mongo_password']
    $ceilometer_db_name = $ext_mongo_hash['mongo_db_name']
    $ext_mongo = true
  } else {
    $ceilometer_db_user = 'ceilometer'
    $ceilometer_db_password = $ceilometer_hash['db_password']
    $ceilometer_db_name = 'ceilometer'
    $ext_mongo = false
    $ext_mongo_hash = {}
  }
}


if $primary_controller {
  if ($mellanox_mode == 'ethernet') {
    $test_vm_pkg = 'cirros-testvm-mellanox'
  } else {
    $test_vm_pkg = 'cirros-testvm'
  }
  package { 'cirros-testvm' :
    ensure => 'installed',
    name   => $test_vm_pkg,
  }
}


if $ext_mongo {
  $mongo_hosts = $ext_mongo_hash['hosts_ip']
  if $ext_mongo_hash['mongo_replset'] {
    $mongo_replicaset = $ext_mongo_hash['mongo_replset']
  } else {
    $mongo_replicaset = undef
  }
} elsif $ceilometer_hash['enabled'] {
  $mongo_hosts = mongo_hosts($nodes_hash)
  if size(mongo_hosts($nodes_hash, 'array', 'mongo')) > 1 {
    $mongo_replicaset = 'ceilometer'
  } else {
    $mongo_replicaset = undef
  }
}

if !$rabbit_hash['user'] {
  $rabbit_hash['user'] = 'nova'
}

if ! $use_neutron {
  $floating_ips_range = hiera('floating_network_range')
}
$floating_hash = {}

##CALCULATED PARAMETERS


##NO NEED TO CHANGE

$node = filter_nodes($nodes_hash, 'name', $::hostname)
if empty($node) {
  fail("Node $::hostname is not defined in the hash structure")
}

# get cidr netmasks for VIPs
$primary_controller_nodes = filter_nodes($nodes_hash,'role','primary-controller')

##REFACTORING NEEDED


##TODO: simply parse nodes array
$controller_internal_addresses = nodes_to_hash($controllers,'name','internal_address')
$controller_public_addresses = nodes_to_hash($controllers,'name','public_address')
$controller_storage_addresses = nodes_to_hash($controllers,'name','storage_address')
$controller_hostnames = keys($controller_internal_addresses)
$controller_nodes = ipsort(values($controller_internal_addresses))
$controller_node_public  = $public_vip
$controller_node_address = $management_vip
$roles = node_roles($nodes_hash, hiera('uid'))
$mountpoints = filter_hash($mp_hash,'point')

# AMQP client configuration
if $internal_address in $controller_nodes {
  # prefer local MQ broker if it exists on this node
  $amqp_nodes = concat(['127.0.0.1'], fqdn_rotate(delete($controller_nodes, $internal_address)))
} else {
  $amqp_nodes = fqdn_rotate($controller_nodes)
}

$amqp_port = '5673'
$amqp_hosts = inline_template("<%= @amqp_nodes.map {|x| x + ':' + @amqp_port}.join ',' %>")
$rabbit_ha_queues = true

# RabbitMQ server configuration
$rabbitmq_bind_ip_address = 'UNSET'              # bind RabbitMQ to 0.0.0.0
$rabbitmq_bind_port = $amqp_port
$rabbitmq_cluster_nodes = $controller_hostnames  # has to be hostnames

# SQLAlchemy backend configuration
$max_pool_size = min($::processorcount * 5 + 0, 30 + 0)
$max_overflow = min($::processorcount * 5 + 0, 60 + 0)
$max_retries = '-1'
$idle_timeout = '3600'

$cinder_iscsi_bind_addr = $storage_address

# Determine who should get the volume service

if (member($roles, 'cinder') and $storage_hash['volumes_lvm']) {
  $manage_volumes = 'iscsi'
} elsif (member($roles, 'cinder') and $storage_hash['volumes_vmdk']) {
  $manage_volumes = 'vmdk'
} elsif ($storage_hash['volumes_ceph']) {
  $manage_volumes = 'ceph'
} else {
  $manage_volumes = false
}

#Determine who should be the default backend

if ($storage_hash['images_ceph']) {
  $glance_backend = 'ceph'
  $glance_known_stores = [ 'glance.store.rbd.Store', 'glance.store.http.Store' ]
} elsif ($storage_hash['images_vcenter']) {
  $glance_backend = 'vmware'
  $glance_known_stores = [ 'glance.store.vmware_datastore.Store', 'glance.store.http.Store' ]
} else {
  $glance_backend = 'swift'
  $glance_known_stores = [ 'glance.store.swift.Store', 'glance.store.http.Store' ]
}

# Use Swift if it isn't replaced by vCenter, Ceph for BOTH images and objects
if !($storage_hash['images_ceph'] and $storage_hash['objects_ceph']) and !$storage_hash['images_vcenter'] {
  $use_swift = true
} else {
  $use_swift = false
}

if ($use_swift) {
  if !hiera('swift_partition', false) {
    $swift_partition = '/var/lib/glance/node'
  }
  $swift_proxies            = $controllers
  $swift_local_net_ip       = $storage_address
  $master_swift_proxy_nodes = filter_nodes($nodes_hash,'role','primary-controller')
  $master_swift_proxy_ip    = $master_swift_proxy_nodes[0]['storage_address']
  #$master_hostname         = $master_swift_proxy_nodes[0]['name']
  $swift_loopback = false
  if $primary_controller {
    $primary_proxy = true
  } else {
    $primary_proxy = false
  }
} elsif ($storage_hash['objects_ceph']) {
  $rgw_servers = $controllers
}


$network_config = {
  'vlan_start'     => $vlan_start,
}

# NOTE(bogdando) for controller nodes running Corosync with Pacemaker
#   we delegate all of the monitor functions to RA instead of monit.
if member($roles, 'controller') or member($roles, 'primary-controller') {
  $use_monit_real = false
} else {
  $use_monit_real = $use_monit
}

if $use_monit_real {
  # Configure service names for monit watchdogs and 'service' system path
  # FIXME(bogdando) replace service_path to systemd, once supported
  include nova::params
  include cinder::params
  include neutron::params
  include l23network::params
  $nova_compute_name   = $::nova::params::compute_service_name
  $nova_api_name       = $::nova::params::api_service_name
  $nova_network_name   = $::nova::params::network_service_name
  $cinder_volume_name  = $::cinder::params::volume_service
  $ovs_vswitchd_name   = $::l23network::params::ovs_service_name
  case $::osfamily {
    'RedHat' : {
       $service_path   = '/sbin/service'
    }
    'Debian' : {
      $service_path    = '/usr/sbin/service'
    }
    default  : {
      fail("Unsupported osfamily: ${osfamily} for os ${operatingsystem}")
    }
  }
}

#HARDCODED PARAMETERS

$multi_host = true
$mirror_type = 'external'
Exec { logoutput => true }

class compact_controller (
  $primary_controller,
) {

  class { 'openstack::controller_ha':
    controllers                    => $::controllers,
    controller_public_addresses    => $::controller_public_addresses,
    controller_internal_addresses  => $::controller_internal_addresses,
    internal_address               => $::internal_address,
    public_interface               => $::public_int,
    private_interface              => $::use_neutron ? { true=>false, default=>hiera('fixed_interface')},
    internal_virtual_ip            => $::management_vip,
    public_virtual_ip              => $::public_vip,
    primary_controller             => $::primary_controller,
    floating_range                 => $::use_neutron ? { true=>$floating_hash, default=>false},
    fixed_range                    => $::use_neutron ? { true=>false, default=>hiera('fixed_network_range')},
    multi_host                     => $::multi_host,
    network_manager                => $::network_manager,
    num_networks                   => $::num_networks,
    network_size                   => $::network_size,
    network_config                 => $::network_config,
    debug                          => $::debug,
    verbose                        => $::verbose,
    auto_assign_floating_ip        => $::auto_assign_floating_ip,
    mysql_root_password            => $::mysql_hash[root_password],
    admin_email                    => $::access_hash[email],
    admin_user                     => $::access_hash[user],
    admin_password                 => $::access_hash[password],
    keystone_db_password           => $::keystone_hash[db_password],
    keystone_admin_token           => $::keystone_hash[admin_token],
    keystone_admin_tenant          => $::access_hash[tenant],
    glance_db_password             => $::glance_hash[db_password],
    glance_user_password           => $::glance_hash[user_password],
    glance_image_cache_max_size    => $::glance_hash[image_cache_max_size],
    known_stores                   => $::glance_known_stores,
    glance_vcenter_host            => $::storage_hash['vc_host'],
    glance_vcenter_user            => $::storage_hash['vc_user'],
    glance_vcenter_password        => $::storage_hash['vc_password'],
    glance_vcenter_datacenter      => $::storage_hash['vc_datacenter'],
    glance_vcenter_datastore       => $::storage_hash['vc_datastore'],
    glance_vcenter_image_dir       => $::storage_hash['vc_image_dir'],
    nova_db_password               => $::nova_hash[db_password],
    nova_user_password             => $::nova_hash[user_password],
    queue_provider                 => $::queue_provider,
    amqp_hosts                     => $::amqp_hosts,
    amqp_user                      => $::rabbit_hash['user'],
    amqp_password                  => $::rabbit_hash['password'],
    rabbit_ha_queues               => $::rabbit_ha_queues,
    rabbitmq_bind_ip_address       => $::rabbitmq_bind_ip_address,
    rabbitmq_bind_port             => $::rabbitmq_bind_port,
    rabbitmq_cluster_nodes         => $::rabbitmq_cluster_nodes,
    memcached_servers              => $::controller_nodes,
    memcached_bind_address         => $::internal_address,
    export_resources               => false,
    glance_backend                 => $::glance_backend,
    swift_proxies                  => $::swift_proxies,
    rgw_servers                    => $::rgw_servers,

    network_provider               => $::network_provider,
    neutron_db_password            => $::neutron_db_password,
    neutron_user_password          => $::neutron_user_password,
    neutron_metadata_proxy_secret  => $::neutron_metadata_proxy_secret,
    neutron_ha_agents              => $::primary_controller ? {true => 'primary', default => 'slave'},
    base_mac                       => $::base_mac,

    cinder                         => true,
    cinder_user_password           => $::cinder_hash[user_password],
    cinder_iscsi_bind_addr         => $::cinder_iscsi_bind_addr,
    cinder_db_password             => $::cinder_hash[db_password],
    cinder_volume_group            => "cinder",
    manage_volumes                 => $::manage_volumes,
    ceilometer                     => $::ceilometer_hash[enabled],
    ceilometer_db_user             => $::ceilometer_db_user,
    ceilometer_db_password         => $::ceilometer_db_password,
    ceilometer_user_password       => $::ceilometer_hash[user_password],
    ceilometer_metering_secret     => $::ceilometer_hash[metering_secret],
    ceilometer_db_type             => 'mongodb',
    swift_rados_backend            => $::storage_hash['objects_ceph'],
    ceilometer_db_dbname           => $::ceilometer_db_name,
    ceilometer_db_host             => $::mongo_hosts,
    ceilometer_ext_mongo           => $::ext_mongo,
    mongo_replicaset               => $::mongo_replicaset,
    galera_nodes                   => $::controller_nodes,
    novnc_address                  => $::internal_address,
    sahara                         => $::sahara_hash[enabled],
    murano                         => $::murano_hash['enabled'],
    custom_mysql_setup_class       => $::custom_mysql_setup_class,
    mysql_skip_name_resolve        => true,
    use_syslog                     => $::use_syslog,
    syslog_log_facility_glance     => $::syslog_log_facility_glance,
    syslog_log_facility_cinder     => $::syslog_log_facility_cinder,
    syslog_log_facility_neutron    => $::syslog_log_facility_neutron,
    syslog_log_facility_nova       => $::syslog_log_facility_nova,
    syslog_log_facility_keystone   => $::syslog_log_facility_keystone,
    syslog_log_facility_ceilometer => $::syslog_log_facility_ceilometer,
    nova_rate_limits               => $::nova_rate_limits,
    cinder_rate_limits             => $::cinder_rate_limits,
    horizon_use_ssl                => hiera('horizon_use_ssl', false),
    use_unicast_corosync           => hiera('use_unicast_corosync', false),
    nameservers                    => $::dns_nameservers,
    max_retries                    => $::max_retries,
    max_pool_size                  => $::max_pool_size,
    max_overflow                   => $::max_overflow,
    idle_timeout                   => $::idle_timeout,
    nova_report_interval           => $::nova_report_interval,
    nova_service_down_time         => $::nova_service_down_time,
  }
}

if $use_vmware_nsx {
  class { 'plugin_neutronnsx':
    neutron_config     => $neutron_config,
    neutron_nsx_config => $neutron_nsx_config,
    roles              => $roles,
  }
}

#################################################################
# we need to evaluate ceph here, because ceph notifies/requires
# other services that are declared in openstack manifests
if $use_ceph {
  $primary_mons   = $controllers
  $primary_mon    = $controllers[0]['name']

  if ($use_neutron) {
    prepare_network_config($network_scheme)
    $ceph_cluster_network = get_network_role_property('storage', 'cidr')
    $ceph_public_network  = get_network_role_property('management', 'cidr')
  } else {
    $ceph_cluster_network = hiera('storage_network_range')
    $ceph_public_network = hiera('management_network_range')
  }

  class {'ceph':
    primary_mon              => $primary_mon,
    mon_hosts                => nodes_with_roles($nodes_hash, ['primary-controller',
                                                 'controller', 'ceph-mon'], 'name'),
    mon_ip_addresses         => nodes_with_roles($nodes_hash, ['primary-controller',
                                                 'controller', 'ceph-mon'], 'internal_address'),
    cluster_node_address     => $controller_node_public,
    osd_pool_default_size    => $storage_hash['osd_pool_size'],
    osd_pool_default_pg_num  => $storage_hash['pg_num'],
    osd_pool_default_pgp_num => $storage_hash['pg_num'],
    use_rgw                  => $storage_hash['objects_ceph'],
    glance_backend           => $glance_backend,
    rgw_pub_ip               => $public_vip,
    rgw_adm_ip               => $management_vip,
    rgw_int_ip               => $management_vip,
    cluster_network          => $ceph_cluster_network,
    public_network           => $ceph_public_network,
    use_syslog               => $use_syslog,
    syslog_log_level         => $syslog_log_level,
    syslog_log_facility      => $syslog_log_facility_ceph,
    rgw_keystone_admin_token => $keystone_hash['admin_token'],
    ephemeral_ceph           => $storage_hash['ephemeral_ceph']
  }
  Class['openstack::controller'] -> Class['ceph']
}
#################################################################
include osnailyfacter::test_controller

class { 'cluster::haproxy':
  haproxy_maxconn    => '16000',
  haproxy_bufsize    => '32768',
  primary_controller => $primary_controller
}

class { 'compact_controller':
  primary_controller => $primary_controller
}

if ($use_swift) {
  $swift_zone = $node[0]['swift_zone']

  # At least debian glance-common package chowns whole /var/lib/glance recursively
  # which breaks swift ownership of dirs inside $storage_mnt_base_dir (default: /var/lib/glance/node/)
  # so we just need to make sure package glance-common (dependency for glance-api) is already installed
  # before creating swift device directories

  Package[$glance::params::api_package_name] -> Anchor <| title=='swift-device-directories-start' |>

  class { 'openstack::swift::storage_node':
    storage_type          => $swift_loopback,
    loopback_size         => '5243780',
    storage_mnt_base_dir  => $swift_partition,
    storage_devices       => $mountpoints,
    swift_zone            => $swift_zone,
    swift_local_net_ip    => $storage_address,
    master_swift_proxy_ip => $master_swift_proxy_ip,
    sync_rings            => ! $primary_proxy,
    debug                 => $::debug,
    verbose               => $::verbose,
    log_facility          => 'LOG_SYSLOG',
  }
  if $primary_proxy {
    ring_devices {'all':
      storages => $controllers,
      require  => Class['swift'],
    }
  }

  if !$swift_hash['resize_value']
  {
    $swift_hash['resize_value'] = 2
  }

  $ring_part_power=calc_ring_part_power($controllers,$swift_hash['resize_value'])

  class { 'openstack::swift::proxy':
    swift_user_password     => $swift_hash[user_password],
    swift_proxies           => $controller_internal_addresses,
    ring_part_power         => $ring_part_power,
    primary_proxy           => $primary_proxy,
    controller_node_address => $management_vip,
    swift_local_net_ip      => $swift_local_net_ip,
    master_swift_proxy_ip   => $master_swift_proxy_ip,
    debug                   => $::debug,
    verbose                 => $::verbose,
    log_facility            => 'LOG_SYSLOG',
  }
  class { 'swift::keystone::auth':
    password         => $swift_hash[user_password],
    public_address   => $public_vip,
    internal_address => $management_vip,
    admin_address    => $management_vip,
  }
}
#TODO: PUT this configuration stanza into nova class
nova_config { 'DEFAULT/use_cow_images':                   value => hiera('use_cow_images')}

# TODO(bogdando) move exec checkers to puppet native types for haproxy backends
if $primary_controller {
  exec { 'wait-for-haproxy-keystone-backend':
    command   => "echo show stat | socat unix-connect:///var/lib/haproxy/stats stdio | grep '^keystone-1,' | egrep -v ',FRONTEND,|,BACKEND,' | grep -qv ',INI,' &&
                  echo show stat | socat unix-connect:///var/lib/haproxy/stats stdio | grep -q '^keystone-1,BACKEND,.*,UP,'",
    path      => ['/usr/bin', '/usr/sbin', '/sbin', '/bin'],
    try_sleep => 5,
    tries     => 60,
    require   => Package['socat'],
  }
  exec { 'wait-for-haproxy-keystone-admin-backend':
    command   => "echo show stat | socat unix-connect:///var/lib/haproxy/stats stdio | grep '^keystone-2,' | egrep -v ',FRONTEND,|,BACKEND,' | grep -qv ',INI,' &&
                  echo show stat | socat unix-connect:///var/lib/haproxy/stats stdio | grep -q '^keystone-2,BACKEND,.*,UP,'",
    path      => ['/usr/bin', '/usr/sbin', '/sbin', '/bin'],
    try_sleep => 5,
    tries     => 60,
    require   => Package['socat'],
  }

  Openstack::Ha::Haproxy_service <| |> -> Exec<| title=='wait-for-haproxy-keystone-admin-backend' |>
  Openstack::Ha::Haproxy_service <| |> -> Exec<| title=='wait-for-haproxy-keystone-backend' |>

  Class['keystone', 'openstack::ha::keystone'] -> Exec<| title=='wait-for-haproxy-keystone-backend' |>
  Class['keystone', 'openstack::ha::keystone'] -> Exec<| title=='wait-for-haproxy-keystone-admin-backend' |>

  exec { 'wait-for-haproxy-nova-backend':
    command   => "echo show stat | socat unix-connect:///var/lib/haproxy/stats stdio | grep '^nova-api-2,' | egrep -v ',FRONTEND,|,BACKEND,' | grep -qv ',INI,' &&
                  echo show stat | socat unix-connect:///var/lib/haproxy/stats stdio | grep -q '^nova-api-2,BACKEND,.*,UP,'",
    path      => ['/usr/bin', '/usr/sbin', '/sbin', '/bin'],
    try_sleep => 5,
    tries     => 60,
    require   => Package['socat'],
  }

  Openstack::Ha::Haproxy_service <| |> -> Exec<| title=='wait-for-haproxy-nova-backend' |>
  Class['nova::api', 'openstack::ha::nova', 'nova::keystone::auth'] -> Exec<| title=='wait-for-haproxy-nova-backend' |>

  exec {'create-m1.micro-flavor':
    command => "bash -c \"source /root/openrc; nova flavor-create --is-public true m1.micro auto 64 0 1\"",
    path    => '/sbin:/usr/sbin:/bin:/usr/bin',
    unless  => 'bash -c "source /root/openrc; nova flavor-list | grep -q m1.micro"',
    require => [Class['nova'],Class['openstack::auth_file']],
  }

  Exec<| title=='wait-for-haproxy-keystone-admin-backend' |> ->
  Exec<| title=='create-m1.micro-flavor' |>
  Exec<| title=='wait-for-haproxy-keystone-backend' |> ->
  Exec<| title=='create-m1.micro-flavor' |>
  Exec<| title=='wait-for-haproxy-nova-backend' |> ->
  Exec<| title=='create-m1.micro-flavor' |>
  Class['keystone::roles::admin'] ->
  Exec<| title=='create-m1.micro-flavor' |>

  if ! $use_neutron {
    nova_floating_range { $floating_ips_range:
      ensure          => 'present',
      pool            => 'nova',
      username        => $access_hash[user],
      api_key         => $access_hash[password],
      auth_method     => 'password',
      auth_url        => "http://${management_vip}:5000/v2.0/",
      authtenant_name => $access_hash[tenant],
      api_retries     => 10,
    }
    Exec<| title=='wait-for-haproxy-nova-backend' |> ->
    Nova_floating_range <| |>

    Exec<| title=='wait-for-haproxy-keystone-backend' |> ->
    Nova_floating_range <| |>

    Exec<| title=='wait-for-haproxy-keystone-admin-backend' |> ->
    Nova_floating_range <| |>
  }
}

#ADDONS START

if $sahara_hash['enabled'] {
  class { 'sahara' :
    sahara_api_host            => $public_vip,

    sahara_db_password         => $sahara_hash['db_password'],
    sahara_db_host             => $management_vip,

    sahara_keystone_host       => $management_vip,
    sahara_keystone_user       => 'sahara',
    sahara_keystone_password   => $sahara_hash['user_password'],
    sahara_keystone_tenant     => 'services',
    sahara_auth_uri            => "http://${management_vip}:5000/v2.0/",
    sahara_identity_uri        => "http://${management_vip}:35357/",
    use_neutron                => $use_neutron,
    syslog_log_facility_sahara => $syslog_log_facility_sahara,
    debug                      => $::debug,
    verbose                    => $::verbose,
    use_syslog                 => $use_syslog,
    enable_notifications       => $ceilometer_hash['enabled'],
    rpc_backend                => 'rabbit',
    amqp_password              => $rabbit_hash['password'],
    amqp_user                  => $rabbit_hash['user'],
    amqp_port                  => $rabbitmq_bind_port,
    amqp_hosts                 => $amqp_hosts,
    rabbit_ha_queues           => $rabbit_ha_queues,
    openstack_version          => $hiera_openstack_version,
    auto_assign_floating_ip    => $auto_assign_floating_ip,
  }
  $scheduler_default_filters = [ 'DifferentHostFilter' ]
} else {
  $scheduler_default_filters = []
}

class { '::nova::scheduler::filter':
  cpu_allocation_ratio       => '8.0',
  disk_allocation_ratio      => '1.0',
  ram_allocation_ratio       => '1.0',
  scheduler_host_subset_size => '30',
  scheduler_default_filters  => concat($scheduler_default_filters, [ 'RetryFilter', 'AvailabilityZoneFilter', 'RamFilter', 'CoreFilter', 'DiskFilter', 'ComputeFilter', 'ComputeCapabilitiesFilter', 'ImagePropertiesFilter', 'ServerGroupAntiAffinityFilter', 'ServerGroupAffinityFilter' ])
}

# From logasy filter.pp
nova_config {
  'DEFAULT/ram_weight_multiplier':        value => '1.0'
}

class { 'openstack::heat' :
  external_ip            => $controller_node_public,

  keystone_host     => $controller_node_address,
  keystone_user     => 'heat',
  keystone_password =>  $heat_hash['user_password'],
  keystone_tenant   => 'services',

  keystone_ec2_uri  => "http://${controller_node_address}:5000/v2.0",

  rpc_backend         => 'heat.openstack.common.rpc.impl_kombu',
  #FIXME(bogdando) we have to split amqp_hosts until all modules synced
  amqp_hosts          => split($amqp_hosts, ','),
  amqp_user           => $rabbit_hash['user'],
  amqp_password       => $rabbit_hash['password'],

  sql_connection      =>
    "mysql://heat:${heat_hash['db_password']}@${$controller_node_address}/heat?read_timeout=60",
  db_host             => $controller_node_address,
  db_password         => $heat_hash['db_password'],
  max_retries         => $max_retries,
  max_pool_size       => $max_pool_size,
  max_overflow        => $max_overflow,
  idle_timeout        => $idle_timeout,

  debug               => $::debug,
  verbose             => $::verbose,
  use_syslog          => $use_syslog,
  syslog_log_facility => $::syslog_log_facility_heat,

  auth_encryption_key => $heat_hash['auth_encryption_key'],

}
include heat_ha::engine


if $murano_hash['enabled'] {

  #NOTE(mattymo): Backward compatibility for Icehouse
  case $hiera_openstack_version {
    /201[1-3]\./: {
      fail("Unsupported OpenStack version: ${hiera_openstack_version}")
    }
    /2014\.1\./: {
      $murano_package_name              = 'murano-api'
    }
    default: {
      $murano_package_name              = 'murano'
    }
  }

  class { 'murano' :
    murano_package_name      => $murano_package_name,
    murano_api_host          => $management_vip,

    # Controller adresses (for endpoints)
    admin_address            => $controller_node_address,
    public_address           => $controller_node_public,
    internal_address         => $controller_node_address,

    # Murano uses two RabbitMQ - one from OpenStack and another one installed on each controller.
    #   The second instance is used for communication with agents.
    #   * murano_rabbit_host provides address for murano-engine which communicates with this
    #    'separate' rabbitmq directly (without oslo.messaging).
    #   * murano_rabbit_ha_hosts / murano_rabbit_ha_queues are required for murano-api which
    #     communicates with 'system' RabbitMQ and uses oslo.messaging.
    murano_rabbit_host       => $public_vip,
    murano_rabbit_ha_hosts   => $amqp_hosts,
    murano_rabbit_ha_queues  => $rabbit_ha_queues,
    murano_os_rabbit_userid  => $rabbit_hash['user'],
    murano_os_rabbit_passwd  => $rabbit_hash['password'],
    murano_own_rabbit_userid => 'murano',
    murano_own_rabbit_passwd => $heat_hash['rabbit_password'],


    murano_db_host           => $management_vip,
    murano_db_password       => $murano_hash['db_password'],

    murano_keystone_host     => $management_vip,
    murano_keystone_user     => 'murano',
    murano_keystone_password => $murano_hash['user_password'],
    murano_keystone_tenant   => 'services',

    use_neutron              => $use_neutron,

    use_syslog               => $use_syslog,
    debug                    => $::debug,
    verbose                  => $::verbose,
    syslog_log_facility      => $::syslog_log_facility_murano,

    primary_controller       => $primary_controller,
    neutron_settings         => $neutron_config,
  }

 Class['openstack::heat'] -> Class['murano']

}

# vCenter integration

if hiera('libvirt_type') == 'vcenter' {
  class { 'vmware' :
    vcenter_user            => $vcenter_hash['vc_user'],
    vcenter_password        => $vcenter_hash['vc_password'],
    vcenter_host_ip         => $vcenter_hash['host_ip'],
    vcenter_cluster         => $vcenter_hash['cluster'],
    vcenter_datastore_regex => $vcenter_hash['datastore_regex'],
    vlan_interface          => $vcenter_hash['vlan_interface'],
    use_quantum             => $use_neutron,
    ha_mode                 => true,
    vnc_address             => $controller_node_public,
    ceilometer              => $ceilometer_hash['enabled'],
    debug                   => $debug,
  }
}

if ($::mellanox_mode == 'ethernet') {
  $ml2_eswitch = $neutron_mellanox['ml2_eswitch']
  class { 'mellanox_openstack::controller':
    eswitch_vnic_type            => $ml2_eswitch['vnic_type'],
    eswitch_apply_profile_patch  => $ml2_eswitch['apply_profile_patch'],
  }
}

#ADDONS END

########################################################################

# TODO(bogdando) add monit zabbix services monitoring, if required
# NOTE(bogdando) for nodes with pacemaker, we should use OCF instead of monit

package { 'screen':
  ensure => present,
}

# Reduce swapiness on controllers, see LP#1413702
sysctl::value { 'vm.swappiness':
  value => "10"
}

# vim: set ts=2 sw=2 et :
