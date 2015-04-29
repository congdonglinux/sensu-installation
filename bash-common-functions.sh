# !/bin/bash
DATETIME=$(date +"%Y%m%d%H%M%S")
KERNELARCH=$(uname -p)

configure_centos_epel_repo() {
    if [ $CENTOS_VERSION == 6 ]; then
        rpm -iUvh http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
    elif [ $CENTOS_VERSION == 7 ]; then
        rpm -iUvh http://download.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
    else
        sleep 1
    fi
}


# Identify Linux Distribution type
identify_os() {
    if [ -f /etc/debian_version ] ; then
        DIST='DEBIAN'
    elif [ -f /etc/centos-release ] ; then
        DIST='CENTOS'
        # CENTOS_VERSION=`awk '{print $4}' /etc/centos-release | sed 's/\..*//g'`
        CENTOS_VERSION=`grep -o -E '[0-9\.]*' /etc/centos-release | sed 's/\..*//g'`
        configure_centos_epel_repo
    else
        echo "This script is only intended to run on Ubuntu or CentOS"
        exit 1
    fi

    #Prepare settings for installation
    case $DIST in
        'DEBIAN')
	    APACHE_CONF_DIR="/etc/apache2/sites-available"
	    APACHE_USER="www-data"
	    APACHE_SERVICE='apache2'
	    WSGI_ADDITIONAL=""
	    WSGIApplicationGroup=""
    	;;
	'CENTOS')
             APACHE_CONF_DIR="/etc/httpd/conf.d"
             APACHE_USER="apache"
             APACHE_SERVICE='httpd'
             #WSGI_ADDITIONAL="WSGISocketPrefix run/wsgi"
             WSGI_ADDITIONAL="WSGISocketPrefix /var/run/wsgi"
             WSGIApplicationGroup="WSGIApplicationGroup %{GLOBAL}"
        ;;
     esac
}
