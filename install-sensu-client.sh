# !/bin/bash
 
if [ `whoami` != "root" ] ; then
    echo "WARNING: You must switch to root to execute this script."
    exit 255
fi

# Include general functions
source bash-common-functions.sh

# Identify the OS
identify_os

# Constants
SENSU_RABBITMQ_CONFIG="/etc/sensu/conf.d/rabbitmq.json"
SENSU_CLIENT_CONFIG="/etc/sensu/conf.d/client.json"
SENSU_SSL_DIR="/etc/sensu/ssl"

install_sensu_client() {
    notify "STEP 01: Installing Sensu Client ..."    

    CERTIFICATE_FILE="${1}"

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

            yum install -y sensu
        ;;
    esac
}

configure_sensu_client() {
    notify "STEP 02: Configuring Sensu Client ..."
    
    ssl_certificate="${1}"
    sensu_client_name="${2}"
    sensu_client_ip_addr=$(ifconfig eth0 | grep 'inet addr' | awk -F " " '{print $2}' | awk -F ":" '{print $2}')

    # Extract RabbitMQ SSL certificates into '/tmp'
    local cert_extract_dir="/tmp/sensu_ssl_cert/"
    mkdir -p "${cert_extract_dir}"
    tar xJf "${ssl_certificate}" -C "${cert_extract_dir}"

    mkdir -p "${SENSU_SSL_DIR}"
    cp "$(find ${cert_extract_dir} -name "key.pem")" "${SENSU_SSL_DIR}"
    cp "$(find ${cert_extract_dir} -name "cert.pem")" "${SENSU_SSL_DIR}"
    chmod a+r /etc/sensu/ssl/*

    local rabbitmq_ini="$(find ${cert_extract_dir} -name "rabbitmq.ini")"

    # Parse file for RabbitMQ information
    RABBITMQ_ADDR=$(awk -F "=" '/RABBITMQ_ADDR/ {print $2}' "${rabbitmq_ini}")
    RABBITMQ_VHOST=$(awk -F "=" '/RABBITMQ_VHOST/ {print $2}' "${rabbitmq_ini}")
    RABBITMQ_USER=$(awk -F "=" '/RABBITMQ_USER/ {print $2}' "${rabbitmq_ini}")
    RABBITMQ_PASSWORD=$(awk -F "=" '/RABBITMQ_PASSWORD/ {print $2}' "${rabbitmq_ini}")

    # Create RabbitMQ configuration for Sensu
    cp examples/rabbitmq.json.example "${SENSU_RABBITMQ_CONFIG}"
    sed -i "s/\"host\": \".*\"/\"host\": \"${RABBITMQ_ADDR}\"/g" "${SENSU_RABBITMQ_CONFIG}"
    sed -i "s/\"user\": \".*\"/\"user\": \"${RABBITMQ_USER}\"/g" "${SENSU_RABBITMQ_CONFIG}"
    sed -i "s/\"password\": \".*\"/\"password\": \"${RABBITMQ_PASSWORD}\"/g" "${SENSU_RABBITMQ_CONFIG}"

    chmod a+r "${SENSU_RABBITMQ_CONFIG}"

    # Create client configuration file
    cp examples/client.json.example "${SENSU_CLIENT_CONFIG}"

    sed -i "s/\"name\": \".*\"/\"name\": \"${sensu_client_name}\"/g" "${SENSU_CLIENT_CONFIG}"
    sed -i "s/\"address\": \".*\"/\"address\": \"${sensu_client_ip_addr}\"/g" "${SENSU_CLIENT_CONFIG}"

    chmod a+r /etc/sensu/conf.d/*
    
    # Enable Sensu services when server boot
    case $DIST in
        'DEBIAN')
            update-rc.d sensu-client defaults
            /etc/init.d/sensu-client start
        ;;
        'CENTOS')
            chkconfig sensu-client on
            systemctl start sensu-client.service
        ;;
    esac
}

function display_usage() {
    local script_name="$(basename "${BASH_SOURCE[0]}")"

    echo -e "\033[1;33m"
    echo    "SYNOPSIS :"
    echo    "    ${script_name} --name <CLIENT_NAME> --cert <SSL_CERTIFICATE> [--help]"
    echo -e "\033[1;35m"
    echo    "DESCRIPTION :"
    echo    "    --help    Help page"
    echo    "    --name    Name for Sensu client (should be unique)"
    echo    "    --cert    Path to SSL certificate file which generated while Sensu server installation process" 
    echo -e "\033[0m"

    exit ${1} 
}

function main() {
    current_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    source "${current_path}/util.sh" || exit 1

    local option_count=$#
    local ssl_path=""

    if [[ $# -eq 0 ]]; then
        display_usage 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                display_usage 0

                ;;
            --cert)
                shift
                
                if [[ $# -gt 0 ]]; then
                    local ssl_certificate="$(trim_string "${1}")"
                fi

                ;;

            --name)
                shift
                
                if [[ $# -gt 0 ]]; then
                    local sensu_client_name="$(trim_string "${1}")"
                fi

                ;;
                
            *)
                shift
                ;;
        esac
    done

    if [[ "$(is_empty_string ${ssl_certificate})" = 'true' || 
          "$(is_empty_string ${sensu_client_name})" = 'true' ]]; then
        if [[ ${option_count} -gt 0 ]]; then
            error "cert, or name parameter not found!"
            display_usage 1
        fi

        display_usage 0
    fi

    # ensure passed in file is a valid XZ compressed file
    if [[ ! -f ${ssl_certificate} ]]; then
        error "${ssl_certificate} is not exist!\n"
        exit 1
    else
        if [[ "$(file "${ssl_certificate}" | awk -F ":" '{print $2}')" != " XZ compressed data" ]]; then
            error "${ssl_certificate} is not a XZ compressed file!\n"
            exit 1
        fi
    fi

    install_sensu_client 
    configure_sensu_client "${ssl_certificate}" "${sensu_client_name}"
}

main "$@"
