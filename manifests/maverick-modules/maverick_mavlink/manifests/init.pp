class maverick_mavlink (
    $cmavnode_install = true,
    $cmavnode_source = "https://github.com/MonashUAS/cmavnode.git",
    $mavlinkrouter_install = true,
    $mavlinkrouter_source = "https://github.com/01org/mavlink-router.git",
    $mavproxy_install = true,
    $dronekit_install = true,
    $dronekit_la_install = true,
    $dronekit_la_source = "https://github.com/dronekit/dronekit-la.git",
) {
    
    $buildparallel = ceiling((0 + $::processorcount) / 2) # Restrict build parallelization to roughly processors/2 (to restrict memory usage during compilation)
    
    ### cmavnode
    # Install cmavnode from gitsource
    if $cmavnode_install {
        ensure_packages(["libboost-all-dev", "cmake", "libconfig++-dev", "libreadline-dev"])
        oncevcsrepo { "git-cmavnode":
            gitsource   => $cmavnode_source,
            dest        => "/srv/maverick/var/build/cmavnode",
            submodules  => true,
        } ->
        # Create build directory
        file { "/srv/maverick/var/build/cmavnode/build":
            ensure      => directory,
            owner       => "mav",
            group       => "mav",
            mode        => 755,
        }
        exec { "cmavnode-prepbuild":
            user        => "mav",
            timeout     => 0,
            command     => "/usr/bin/cmake -DCMAKE_INSTALL_PREFIX=/srv/maverick/software/cmavnode -DCMAKE_INSTALL_RPATH=/srv/maverick/software/cmavnode/lib ..",
            cwd         => "/srv/maverick/var/build/cmavnode/build",
            creates     => "/srv/maverick/var/build/cmavnode/build/Makefile",
            require     => [ File["/srv/maverick/var/build/cmavnode/build"], Package["libreadline-dev"] ], # ensure we have all the dependencies satisfied
        } ->
        exec { "cmavnode-build":
            user        => "mav",
            timeout     => 0,
            command     => "/usr/bin/make -j${buildparallel} >/srv/maverick/var/log/build/cmavnode.build.out 2>&1",
            cwd         => "/srv/maverick/var/build/cmavnode/build",
            creates     => "/srv/maverick/var/build/cmavnode/build/cmavnode",
            require     => Exec["cmavnode-prepbuild"],
        } ->
        exec { "cmavnode-install":
            user        => "mav",
            timeout     => 0,
            command     => "/usr/bin/make install >/srv/maverick/var/log/build/cmavnode.install.out 2>&1",
            cwd         => "/srv/maverick/var/build/cmavnode/build",
            creates     => "/srv/maverick/software/cmavnode/bin/cmavnode",
        }
        file { "/etc/systemd/system/maverick-cmavnode@.service":
            source      => "puppet:///modules/maverick_mavlink/maverick-cmavnode@.service",
            owner       => "root",
            group       => "root",
            mode        => 644,
            notify      => Exec["maverick-systemctl-daemon-reload"],
        }
        file { "/srv/maverick/software/maverick/bin/cmavnode.sh":
            ensure      => link,
            target      => "/srv/maverick/software/maverick/manifests/maverick-modules/maverick_mavlink/files/cmavnode.sh",
        }
    }

    ### mavlinkrouter
    # Install mavlinkrouter from gitsource
    if $mavlinkrouter_install {
        oncevcsrepo { "git-mavlinkrouter":
            gitsource   => $mavlinkrouter_source,
            dest        => "/srv/maverick/var/build/mavlinkrouter",
            submodules  => true,
        } ->
        exec { "mavlinkrouter-build":
            user        => "mav",
            timeout     => 0,
            command     => "/srv/maverick/var/build/mavlinkrouter/autogen.sh && /srv/maverick/var/build/mavlinkrouter/configure CFLAGS='-g -O2' --prefix=/srv/maverick/software/mavlinkrouter && /usr/bin/make -j${buildparallel} && make install >/srv/maverick/var/log/build/mavlinkrouter.build.out 2>&1",
            cwd         => "/srv/maverick/var/build/mavlinkrouter",
            creates     => "/srv/maverick/software/mavlinkrouter/bin/mavlinkrouterd",
        }
        file { "/etc/systemd/system/maverick-mavlinkrouter@.service":
            source      => "puppet:///modules/maverick_mavlink/maverick-mavlinkrouter@.service",
            owner       => "root",
            group       => "root",
            mode        => 644,
            notify      => Exec["maverick-systemctl-daemon-reload"],
        }
        file { "/srv/maverick/software/maverick/bin/mavlinkrouter.sh":
            ensure      => link,
            target      => "/srv/maverick/software/maverick/manifests/maverick-modules/maverick_mavlink/files/mavlinkrouter.sh",
        }
    }
    
    
    ### Mavproxy
    # Install mavproxy globally (not in virtualenv) from pip
    if $mavproxy_install {
        python::pip { 'pip-mavproxy-global':
            pkgname     => 'mavproxy',
            ensure      => present,
            timeout     => 0,
        }
        file { "/etc/systemd/system/maverick-mavproxy@.service":
            source      => "puppet:///modules/maverick_mavlink/maverick-mavproxy@.service",
            owner       => "root",
            group       => "root",
            mode        => 644,
            notify      => Exec["maverick-systemctl-daemon-reload"],
        }
        file { "/srv/maverick/software/maverick/bin/mavproxy.sh":
            ensure      => link,
            target      => "/srv/maverick/software/maverick/manifests/maverick-modules/maverick_mavlink/files/mavproxy.sh",
        }
    }

    
    # Install dronekit globall (not in virtualenv) from pip
    if $dronekit_install {
        python::pip { 'pip-dronekit-global':
            pkgname     => 'dronekit',
            ensure      => present,
            timeout     => 0,
        }
    }

    # Install dronekit-la (log analyzer)
    if $dronekit_la_install {
        oncevcsrepo { "git-dronekit-la":
            gitsource   => $dronekit_la_source,
            dest        => "/srv/maverick/var/build/dronekit-la",
            submodules  => true,
            owner        => mav,
            group       => mav,
        } ->
        # Compile dronekit-la
        exec { "compile-dronekit-la":
            command     => "/usr/bin/make -j${::processorcount} dronekit-la dataflash_logger >/srv/maverick/var/log/build/dronekit-la.build.log 2>&1",
            creates     => "/srv/maverick/var/build/dronekit-la/dronekit-la",
            user        => "mav",
            cwd         => "/srv/maverick/var/build/dronekit-la",
            timeout     => 0,
        } ->
        file { "/srv/maverick/software/dronekit-la":
            ensure      => directory,
            owner       => "mav",
            group       => "mav",
        } ->
        exec { "install-dronekit-la":
            command     => "/bin/cp dronekit-la dataflash_logger README.mdd /srv/maverick/software/dronekit-la; chmod a+rx /srv/maverick/software/dronekit-la/* >/srv/maverick/var/log/build/dronekit-la.install.log 2>&1",
            creates     => "/srv/maverick/software/dronekit-la/dronekit-la",
            user        => "mav",
            cwd         => "/srv/maverick/var/build/dronekit-la",
            timeout     => 0,
        } ->
        file { "/srv/maverick/data/config/dataflash_logger.conf":
            owner       => "mav",
            group       => "mav",
            mode        => "644",
            content     => template("maverick_fc/dataflash_logger.conf.erb")
        }
    }
    

}