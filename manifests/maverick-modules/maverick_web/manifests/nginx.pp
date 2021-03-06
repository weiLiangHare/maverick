# @summary
#   Maverick_web::Nginx class
#   This class installs and manages the Nginx webserver.
#
# @example Declaring the class
#   This class is included from maverick_web class and should not be included from elsewhere
#
# @param active
#   If true, start nginx service and enable at boot time.
# @param port
#   Unencrypted webserver port to listen on.  Default for web browsers is port 80.
# @param ssl_port
#   Encrypted webserver port to listen on.  Default for web browsers is port 443.
# @param server_hostname
#   Server FQDN to use to create default vhost.
# @param downloads
#   If true, activate a downloads web content.  This is useful to present large downloads to users.
# @param downloads_dir
#   Filesystem path to use to serve downloads.
# @param downloads_location
#   Web path for downloads.
# @param www_root
#   Filesystem root to serve legacy web content.
#   
class maverick_web::nginx (
    Boolean $active = true,
    Integer $port = 80,
    Integer $ssl_port = 443,
    String $server_hostname = $maverick_web::server_fqdn,
    Boolean $downloads = false,
    String $downloads_dir = "/var/www/html/maverick/downloads",
    String $downloads_location = "/maverick/downloads",
    String $www_root = '/srv/maverick/software/maverick-fcs/public',
) {
    if $active == true {
        $service_ensure = running
        $service_enable = true
    } else {
        $service_ensure = stopped
        $service_enable = false
    }

    # Nginx doesn't have repo for ARM, so don't try to use it
    if $::architecture =~ "arm" {
        $manage_repo = false
    } else {
        if $::operatingsystem == "Ubuntu" and versioncmp($::operatingsystemmajrelease, "18") < 0 {
            $manage_repo = true
        } else {
            $manage_repo = false
        }
    }

    # Workaround for ubilinux
    if $::lsbdistid == "ubilinux" and $::lsbdistcodename == "dolcetto" {
        $_release = "stretch"
    } else {
        $_release = $::lsbdistcodename
    }
    
    # Make sure apache system services are stopped
    service { "apache2":
        ensure      => stopped,
        enable      => false,
    } ->
    file { "/etc/systemd/system/maverick-nginx.service":
        owner       => "root",
        group       => "root",
        mode        => "644",
        source      => "puppet:///modules/maverick_web/maverick-nginx.service",
        notify      => Exec["maverick-systemctl-daemon-reload"],
    } ->
    class { 'nginx':
        confd_purge     => true,
        server_purge    => true,
        manage_repo     => $manage_repo,
        repo_release    => $_release,
        service_manage  => false,
        service_name    => "maverick-nginx",
    } ->
    # Make sure nginx system service is stopped
    service { "nginx":
        ensure          => stopped,
        enable          => false,
    } ->
    service { "maverick-nginx":
        ensure          => $service_ensure,
        enable          => $service_enable,
    }

    # apache2-utils used for htpasswd, even by nginx
    ensure_packages(["apache2-utils"])
    
    nginx::resource::server { $server_hostname:
        listen_port => $port,
        ssl         => true,
        ssl_port    => $ssl_port,
        ssl_cert    => "/srv/maverick/data/web/ssl/${server_hostname}-webssl.crt",
        ssl_key     => "/srv/maverick/data/web/ssl/${server_hostname}-webssl.key",
        www_root    => $www_root,
        require     => [ Class["maverick_web::fcs"], ],
        notify      => Service["maverick-nginx"],
    }
    
    nginx::resource::location { "mavca":
        ensure          => present,
        ssl             => true,
        location        => "/security/mavCA.crt",
        location_alias  => "/srv/maverick/data/security/ssl/ca/mavCA.pem",
        index_files     => [],
        server          => $server_hostname,
        require         => [ Class["maverick_web::fcs"], Service["nginx"] ],
        notify          => Service["maverick-nginx"],
    }

    # Add a location for downloads, turned off by default
    if $downloads {
        nginx::resource::location { "maverick-downloads":
            location        => $downloads_location,
            ensure          => present,
            ssl             => true,
            location_alias  => $downloads_dir,
            index_files     => [],
            server          => $server_hostname,
            require         => [ Class["maverick_web::fcs"], Class["nginx"], Service["nginx"] ],
        }
    }
    
    # Add a location to stub stats - used by collectd to collect nginx metrics
    $local_config = {
        'access_log' => 'off',
        'allow'      => '127.0.0.1',
        'deny'       => 'all'
    }
    nginx::resource::location { "status":
        ensure              => present,
        location            => "/nginx_status",
        stub_status         => true,
        location_cfg_append => $local_config,
        server              => $server_hostname,
        notify              => Service["maverick-nginx"],
        require             => [ Service["nginx"] ],
    }
    
    if defined(Class["maverick_analysis::collect"]) {
        class { 'collectd::plugin::nginx':
          url      => 'http://localhost/nginx_status?auto',
        }
    }

    # status.d entry
    file { "/srv/maverick/software/maverick/bin/status.d/120.web/101.nginx.status":
        owner   => "mav",
        content => "nginx,Webserver\n",
    }
}
