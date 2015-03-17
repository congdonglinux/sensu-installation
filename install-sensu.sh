# !/bin/bash
 
if [ `whoami` != "root" ] ; then
    echo "WARNING: You must switch to root to execute this script."
    exit 255
fi

# Include general functions
source bash-common-functions.sh

# Identify the OS
identify_os

generate_ssl_certificate() {
    echo "Generating SSL certificate for RabbitMQ..."
    wget http://sensuapp.org/docs/0.16/tools/ssl_certs.tar
    tar -xvf ssl_certs.tar
    cd ssl_certs
    chmod u+x ssl_certs.sh
    ./ssl_certs.sh generate
    cd ..
}

install_rabbitmq() {
    case $DIST in
        'DEBIAN')
            apt-get -y install erlang-nox &> /dev/null
            wget http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
            apt-key add rabbitmq-signing-key-public.asc
            echo "deb http://www.rabbitmq.com/debian/ testing main" > /etc/apt/sources.list.d/rabbitmq.list
            apt-get update
            apt-get install rabbitmq-server
        ;;
        'CENTOS')
            if [ $CENTOS_VERSION == 6 ]; then
                rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
            elif [ $CENTOS_VERSION == 7 ]; then
                rpm -Uvh http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
            else
                sleep 1
            fi

            yum install -y erlang
            rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
            
            # Get current RabbitMQ Server 
            CURRENT_RABBITMQ_SERVER=`curl -s http://www.rabbitmq.com/releases/rabbitmq-server/current/ --list-only | egrep -o 'rabbitmq-server-([0-9]{1,}\.)+[0-9]{1,}\-[0-9].noarch.rpm' | head -1`
            rpm -Uvh http://www.rabbitmq.com/releases/rabbitmq-server/current/"$CURRENT_RABBITMQ_SERVER"
        ;;
    esac

    mkdir -p /etc/rabbitmq/ssl
    cp ssl_certs/{sensu_ca/cacert.pem,server/cert.pem,server/key.pem} /etc/rabbitmq/ssl

    cp rabbitmq.config.example /etc/rabbitmq/rabbitmq.config
    chmod a+r /etc/rabbitmq/rabbitmq.config

    # Start RabbitMQ server
    case $DIST in
        'DEBIAN')
            update-rc.d rabbitmq-server defaults
            /etc/init.d/rabbitmq-server start
        ;;
        'CENTOS')
            # Ensure RabbitMQ would not be blocked by firewall
            firewall-cmd --permanent --add-port=5672/tcp
            firewall-cmd --reload
            setsebool -P nis_enabled 1

            chkconfig rabbitmq-server on
            systemctl start rabbitmq-server.service
        ;;
    esac

    # Create credentials
    RABBITMQ_VHOST="/sensu"
    rabbitmqctl add_vhost $RABBITMQ_VHOST
          
    # echo -n "Enter a new RabbitMQ username: "
    # read RABBITMQ_USER
    RABBITMQ_USER="sensu"

    # echo -n "Enter a password: "
    # read RABBITMQ_PASSWORD
    RABBITMQ_PASSWORD="mypass"

    rabbitmqctl add_user $RABBITMQ_USER $RABBITMQ_PASSWORD
    rabbitmqctl set_permissions -p $RABBITMQ_VHOST $RABBITMQ_USER ".*" ".*" ".*"
    rabbitmq-plugins enable rabbitmq_management
}

install_redis() {
    case $DIST in
        'DEBIAN')
            apt-get install -y redis-server
            apt-get install -y sysv-rc-conf
            sysv-rc-conf redis on
            /etc/init.d/redis-server start
        ;;
        
        'CENTOS')
            yum install -y redis
            chkconfig redis on
            systemctl start redis.service
        ;;
    esac
}

install_sensu() {
    case $DIST in
        'DEBIAN')
            wget -q http://repos.sensuapp.org/apt/pubkey.gpg -O- | sudo apt-key add -
            echo "deb http://repos.sensuapp.org/apt sensu main" > /etc/apt/sources.list.d/sensu.list
            apt-get update
            apt-get install -y sensu
        ;;
        'CENTOS')
            cp sensu.repo.example /etc/yum.repos.d/sensu.repo

            # Sensu only support Centos 5 and Centos 6
            if [ $CENTOS_VERSION == 7 ]; then
                CENTOS_VERSION=6
            fi

            sed -i "s/\$releasever/${CENTOS_VERSION}/g" /etc/yum.repos.d/sensu.repo
            sed -i "s/\$basearch/${KERNELARCH}/g" /etc/yum.repos.d/sensu.repo
        ;;
    esac

    mkdir -p /etc/sensu/ssl
    cp ssl_certs/{client/cert.pem,client/key.pem} /etc/sensu/ssl
    chmod a+r /etc/sensu/ssl/*

    # Create RabbitMQ configuration for Sensu
    cp rabbitmq.json.example /etc/sensu/conf.d/rabbitmq.json
    sed -i 's/\"host\": \".*\"/\"host\": \"localhost\"/g' /etc/sensu/conf.d/rabbitmq.json
    sed -i 's/\"user\": \".*\"/\"user\": \"'$RABBITMQ_USER\"/g /etc/sensu/conf.d/rabbitmq.json
    sed -i 's/\"password\": \".*\"/\"password\": \"'$RABBITMQ_PASSWORD\"/g /etc/sensu/conf.d/rabbitmq.json

    chmod a+r /etc/sensu/conf.d/rabbitmq.json

    # Create client configuration file
    # TODO: tweak client configuration content
    cp client.json.example /etc/sensu/conf.d/client.json

    # Create Redis configuration file
    cp redis.json.example /etc/sensu/conf.d/redis.json

    # Create Sensu API configuration file
    cp api.json.example /etc/sensu/conf.d/api.json

    chmod a+r /etc/sensu/conf.d/*
    
    # Enable Sensu services when server boot
    case $DIST in
        'DEBIAN')
            update-rc.d sensu-server defaults
            update-rc.d sensu-api defaults
            # Start Sensu services
            /etc/init.d/sensu-server start
            /etc/init.d/sensu-api start
        ;;
        'CENTOS')
            chkconfig sensu-server on
            chkconfig sensu-api on
            systemctl start sensu-server.service
            systemctl start sensu-api.service
        ;;
    esac
}

install_uchiwa() {
    case $DIST in
        'DEBIAN')
            apt-get install -y uchiwa
        ;;
        'CENTOS')
            yum install -y uchiwa
        ;;
    esac

    # Create Uchiwa configuration file
    cp uchiwa.json.example /etc/sensu/uchiwa.json
    chmod a+r /etc/sensu/uchiwa.json

    # Enable Uchiwa service when server boot
    case $DIST in
        'DEBIAN')
            update-rc.d uchiwa defaults
            # Start Uchiwa service
            /etc/init.d/uchiwa start
        ;;
        'CENTOS')
            chkconfig uchiwa on
            systemctl start uchiwa.service
        ;;
    esac
}

install_sensu_metrics_relay() {
    case $DIST in
        'DEBIAN')
            apt-get install -y git
        ;;
        'CENTOS')
        ;;
    esac

    git clone git://github.com/opower/sensu-metrics-relay.git /usr/src/sensu-metrics-relay
    cp -R /usr/src/sensu-metrics-relay/lib/sensu/extensions/* /etc/sensu/extensions
    cp relay.json.example /etc/sensu/conf.d/relay.json
}

generate_ssl_certificate
install_rabbitmq
install_redis
install_sensu
install_uchiwa
install_sensu_metrics_relay
