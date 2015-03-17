# !/bin/bash
DATETIME=$(date +"%Y%m%d%H%M%S")
KERNELARCH=$(uname -p)

# Identify Linux Distribution type
identify_os() {
    if [ -f /etc/debian_version ] ; then
        DIST='DEBIAN'
    elif [ -f /etc/centos-release ] ; then
        DIST='CENTOS'
        CENTOS_VERSION=`awk '{print $4}' /etc/centos-release | sed 's/\..*//g'`
    else
        echo "This script is only intended to run on Ubuntu or CentOS"
        exit 1
    fi

    #Prepare settings for installation
    case $DIST in
        'DEBIAN')
            SCRIPT_VIRTUALENVWRAPPER="/usr/local/bin/virtualenvwrapper.sh"
	    APACHE_CONF_DIR="/etc/apache2/sites-enabled/"
	    APACHE_USER="www-data"
	    APACHE_SERVICE='apache2'
	    WSGI_ADDITIONAL=""
	    WSGIApplicationGroup=""
    	;;
	'CENTOS')
             SCRIPT_VIRTUALENVWRAPPER="/usr/bin/virtualenvwrapper.sh"
             APACHE_CONF_DIR="/etc/httpd/conf.d/"
             APACHE_USER="apache"
             APACHE_SERVICE='httpd'
             #WSGI_ADDITIONAL="WSGISocketPrefix run/wsgi"
             WSGI_ADDITIONAL="WSGISocketPrefix /var/run/wsgi"
             WSGIApplicationGroup="WSGIApplicationGroup %{GLOBAL}"
        ;;
     esac
}
