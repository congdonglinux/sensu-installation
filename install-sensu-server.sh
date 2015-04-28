# !/bin/bash
 
if [ `whoami` != "root" ] ; then
    echo "WARNING: You must switch to root to execute this script."
    exit 255
fi

# Include general functions
source bash-common-functions.sh

# Identify the OS
identify_os

RABBITMQ_ADDR="$(ifconfig em1 | grep 'inet' | awk -F' ' '{print $2}' | awk -F':' '{print $2}')"
RABBITMQ_VHOST="/sensu"
RABBITMQ_USER="sensu"
RABBITMQ_PASSWORD="mypass"

generate_ssl_certificate() {
    ssl_certificate_dir="${1}"

    echo "Generating SSL certificate for RabbitMQ..."
    
    sensu_ssl_tool_url="${2}"
    sensu_ssl_tool_name="$(echo "${sensu_ssl_tool_url}" | awk -F "/" '{print $NF}')"
    sensu_ssl_tool_dir="$(echo "${sensu_ssl_tool_name}" | awk -F "." '{print $1}')"

    # Fetch Sensu ssl tool and generates ssl certificates with this tool
    cd /tmp
    if [ ! -f ${sensu_ssl_tool_name} ]; then
        wget "${sensu_ssl_tool_url}"
    fi
    # notify "${sensu_ssl_tool_url}"
    tar -xf "${sensu_ssl_tool_name}"
    cd "${sensu_ssl_tool_dir}"
    chmod u+x ssl_certs.sh
    ./ssl_certs.sh generate

    # The directory where ssl certificates(for both RabbitMQ & Sensu) exist
    ssl_dir="/tmp/""${sensu_ssl_tool_dir}"

    mkdir sensu_client_ssl

    # Save RabbitMQ configuration to ini file for Sensu clients
    echo "RABBITMQ_ADDR="${RABBITMQ_ADDR} >> sensu_client_ssl/rabbitmq.ini
    echo "RABBITMQ_VHOST="${RABBITMQ_VHOST} >> sensu_client_ssl/rabbitmq.ini
    echo "RABBITMQ_USER="${RABBITMQ_USER} >> sensu_client_ssl/rabbitmq.ini
    echo "RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD} >> sensu_client_ssl/rabbitmq.ini

    # Save SSL certificates for Sensu clients
    cp client/cert.pem client/key.pem sensu_client_ssl
    tar cz sensu_client_ssl -f sensu_client_ssl.tar.gz
    mv sensu_client_ssl.tar.gz "${ssl_certificate_dir}"

    # clearning temporary files
    rm -rf sensu_client_ssl

    # change back to working directory
    cd "${working_dir}"
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
            yum install -y erlang
            rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
            
            # Get current RabbitMQ Server 
            CURRENT_RABBITMQ_SERVER=`curl -s http://www.rabbitmq.com/releases/rabbitmq-server/current/ --list-only | egrep -o 'rabbitmq-server-([0-9]{1,}\.)+[0-9]{1,}\-[0-9].noarch.rpm' | head -1`
            rpm -Uvh http://www.rabbitmq.com/releases/rabbitmq-server/current/"$CURRENT_RABBITMQ_SERVER"
        ;;
    esac

    mkdir -p /etc/rabbitmq/ssl
    cp ${ssl_dir}/{sensu_ca/cacert.pem,server/cert.pem,server/key.pem} /etc/rabbitmq/ssl

    cp examples/rabbitmq.config.example /etc/rabbitmq/rabbitmq.config
    chmod a+r /etc/rabbitmq/rabbitmq.config

    # Start RabbitMQ server
    case $DIST in
        'DEBIAN')
            update-rc.d rabbitmq-server defaults
            /etc/init.d/rabbitmq-server start
        ;;
        'CENTOS')
            # Ensure RabbitMQ would not be blocked by firewall
#            firewall-cmd --permanent --add-port=5672/tcp
#            firewall-cmd --reload
#            setsebool -P nis_enabled 1

            chkconfig rabbitmq-server on
            # systemctl start rabbitmq-server.service
            service rabbitmq-server start
        ;;
    esac

    rabbitmqctl add_vhost "${RABBITMQ_VHOST}"
    rabbitmqctl add_user "${RABBITMQ_USER}" "${RABBITMQ_PASSWORD}"
    rabbitmqctl set_permissions -p "${RABBITMQ_VHOST}" "${RABBITMQ_USER}" ".*" ".*" ".*"
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
            yum install -y  redis
            chkconfig redis on
            # systemctl start redis.service
            service redis start
        ;;
    esac
}

install_sensu_server() {
    case $DIST in
        'DEBIAN')
            wget -q http://repos.sensuapp.org/apt/pubkey.gpg -O- | sudo apt-key add -
            echo "deb http://repos.sensuapp.org/apt sensu main" > /etc/apt/sources.list.d/sensu.list
            apt-get update
            apt-get install -y sensu
        ;;
        'CENTOS')
            cp examples/sensu.repo.example /etc/yum.repos.d/sensu.repo

            # Sensu only support Centos 5 and Centos 6
            if [ $CENTOS_VERSION == 7 ]; then
                CENTOS_VERSION=6
            fi

            sed -i "s/\$releasever/${CENTOS_VERSION}/g" /etc/yum.repos.d/sensu.repo
            sed -i "s/\$basearch/${KERNELARCH}/g" /etc/yum.repos.d/sensu.repo

            yum install -y  sensu
        ;;
    esac

    mkdir -p /etc/sensu/ssl
    cp ${ssl_dir}/{client/cert.pem,client/key.pem} /etc/sensu/ssl
    chmod a+r /etc/sensu/ssl/*

    # Create RabbitMQ configuration for Sensu
    cp examples/rabbitmq.json.example /etc/sensu/conf.d/rabbitmq.json
    sed -i "s/\"host\": \".*\"/\"host\": \"localhost\"/g" /etc/sensu/conf.d/rabbitmq.json
    sed -i "s/\"user\": \".*\"/\"user\": \"$RABBITMQ_USER\"/g" /etc/sensu/conf.d/rabbitmq.json
    sed -i "s/\"password\": \".*\"/\"password\": \"${RABBITMQ_PASSWORD}\"/g" /etc/sensu/conf.d/rabbitmq.json

    chmod a+r /etc/sensu/conf.d/rabbitmq.json

    # Create client configuration file
    cp examples/client.json.example /etc/sensu/conf.d/client.json

    # Create Redis configuration file
    cp examples/redis.json.example /etc/sensu/conf.d/redis.json

    # Create Sensu API configuration file
    cp examples/api.json.example /etc/sensu/conf.d/api.json

    chmod a+r /etc/sensu/conf.d/*
    
    # Enable Sensu services when server boot
    case $DIST in
        'DEBIAN')
            update-rc.d sensu-server defaults
            update-rc.d sensu-api defaults
            /etc/init.d/sensu-server start
            /etc/init.d/sensu-api start
        ;;
        'CENTOS')
            chkconfig sensu-server on
            chkconfig sensu-api on
            # systemctl start sensu-server.service
            # systemctl start sensu-api.service
            service sensu-server start
            service sensu-api start
        ;;
    esac
}

install_uchiwa() {
    case $DIST in
        'DEBIAN')
            apt-get install -y uchiwa
        ;;
        'CENTOS')
            yum install -y  uchiwa
        ;;
    esac

    # Create Uchiwa configuration file
    cp examples/uchiwa.json.example /etc/sensu/uchiwa.json
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
            # systemctl start uchiwa.service
            service uchiwa start
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
    cp examples/relay.json.example /etc/sensu/conf.d/relay.json
}

function display_usage() {
    local script_name="$(basename "${BASH_SOURCE[0]}")"

    echo -e "\033[1;33m"
    echo    "SYNOPSIS :"
    echo    "    ${script_name} [--dir <DIRECTORY_FOR_SSL_CERTIFICATES>] [--help]"
    echo -e "\033[1;35m"
    echo    "DESCRIPTION :"
    echo    "    --help    Help page"
    echo    "    --cert    [Optional] Directory which the SSL certificate tarball will be generated to while Sensu server installation. If this parameter was not provided , SSL certificates will be generated to HOME directory of current user" 
    echo    "    --tool    [Mandatory] Tool url used to generate ssl certificate which provided by Sensu project. Refer to Sensu official documentation for this parameter. For example, \"http://sensuapp.org/docs/0.17/files/sensu_ssl_tool.tar\""
    echo -e "\033[0m"

    exit ${1} 
}

function main() {
    working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    source "${working_dir}/util.sh" || exit 1
    source "${working_dir}/install-graphite.sh" || exit 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                display_usage 0

                ;;
            --cert)
                shift
                
                if [[ $# -gt 0 ]]; then
                    local ssl_certificate_dir="$(trim_string "${1}")"
                fi

                ;;

            --tool)
                shift
                
                if [[ $# -gt 0 ]]; then
                    local sensu_ssl_tool_url="$(trim_string "${1}")"
                fi

                ;;
                
            *)
                shift
                ;;
        esac
    done

    if [[ "$(is_empty_string ${ssl_certificate_dir})" = 'true' ]]; then
        ssl_certificate_dir="${HOME}"
        warn 'directory parameter not found! SSL certificates will be generated into HOME directory!'
    else 
        if [[ -e "${ssl_certificate_dir}" ]]; then
            warn "${ssl_certificate_dir}"' does not exist!'
            mkdir -p "${ssl_certificate_dir}"
        fi
    fi

    if [[ "$(is_empty_string "${sensu_ssl_tool_url}")" = 'true' ]]; then
        error 'tool url parameter not found!\n'
        display_usage 0
    fi

    if [[ "$(validate_url "${sensu_ssl_tool_url}")" = 'false' ]]; then
        error 'invalid url for Sensu ssl tool!'
        exit 1
    fi

    generate_ssl_certificate "${ssl_certificate_dir}" "${sensu_ssl_tool_url}"
    install_rabbitmq
#    install_redis
#    install_sensu_server
#    install_uchiwa
#    install_sensu_metrics_relay


#    resolve_dependency
#    install_graphite
#    configure_graphite
#    configure_carbon
}

main "$@"
