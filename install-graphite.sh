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
GRAPHITE_ROOT='/opt/graphite'
GRAPHITE_CONFIG_DIR='/opt/graphite/conf'
GRAPHITE_WEBAPP_CONFIG='/opt/graphite/webapp/graphite/local_settings.py'
GRAPHITE_VHOST_EXAMPLE='/opt/graphite/examples/example-graphite-vhost.conf'
APACHE_AVAILABLE_SITES_DIR='/etc/apache2/sites-available/'

# Check dependencies
# wget https://raw.github.com/graphite-project/graphite-web/master/check-dependencies.py
# python check-dependencies.py

# Resolving Dependencies
resolve_dependency() {
    case $DIST in
        'DEBIAN')
            apt-get install -y python-pip 
            apt-get install -y apache2 apache2-dev libapache2-mod-wsgi libapache2-mod-python
            apt-get install -y python-dev libldap2-dev libsasl2-dev libssl-dev
            apt-get install -y librrd-dev
            apt-get install -y build-essential
            apt-get install -y python-cairo 
            apt-get install -y memcached
        ;;
        'CENTOS')
            yum install -y python-pip 
            yum install -y httpd httpd-devel mod_wsgi
            yum install -y python-devel

            # Manually install mod_python
            wget http://dist.modpython.org/dist/mod_python-3.5.0.tgz
            tar xzf mod_python-3.5.0.tgz
            cd mod_python-3.5.0
            ./configure
            make
            make install

            yum install -y openldap-devel cyrus-sasl-devel openssl-devel
            yum install -y cairo-devel
            yum install -y rrdtool-devel
            yum install -y gcc gcc-c++
        ;;
    esac

    pip install whisper 
    pip install django 
    pip install pytz 
    pip install pyparsing 
    pip install tagging 
    pip install simplejson 
    pip install zope.interface 
    pip install python-memcached 
    pip install python-ldap 
    pip install twisted 
    pip install txamqp 
    pip install rrdtool 
    pip install django-tagging mod_wsgi
}

# Installing Graphite
install_graphite() {
    pip install https://github.com/graphite-project/ceres/tarball/master
    pip install whisper
    pip install carbon
    pip install graphite-web
}

# Configuring Graphite
configure_graphite() {
    TIMEZONE=`cat /etc/timezone`
    echo $TIMEZONE

    cp $GRAPHITE_VHOST_EXAMPLE $APACHE_AVAILABLE_SITES_DIR/graphite.conf
    chmod a+r $APACHE_AVAILABLE_SITES_DIR/graphite.conf
    DJANGO_ROOT=`pip show django | grep 'Location' | sed 's/Location:\ //g'`
    echo $DJANGO_ROOT
    sed -i "s|\@DJANGO_ROOT\@|${DJANGO_ROOT}|g" $APACHE_AVAILABLE_SITES_DIR/graphite.conf

    # Add Directory to Graphite VHost
    sed -i "s/WSGISocketPrefix\ run\/wsgi/WSGISocketPrefix\ \/var\/run\/apache2\/wsgi/" $APACHE_AVAILABLE_SITES_DIR/graphite.conf
    sed -i '/<Directory.*/,/<\/Directory>/{N;$!D}' $APACHE_AVAILABLE_SITES_DIR/graphite.conf
    sed -i "$ i <Directory /opt/graphite/conf/>\n\t\tRequire all granted\n\t</Directory>" $APACHE_AVAILABLE_SITES_DIR/graphite.conf
    sed -i "$ i <Directory /opt/graphite/webapp/>\n\t\tRequire all granted\n\t</Directory>" $APACHE_AVAILABLE_SITES_DIR/graphite.conf

    cp $GRAPHITE_CONFIG_DIR/carbon.conf.example $GRAPHITE_CONFIG_DIR/carbon.conf
    cp $GRAPHITE_CONFIG_DIR/dashboard.conf.example $GRAPHITE_CONFIG_DIR/dashboard.conf
    cp $GRAPHITE_CONFIG_DIR/graphite.wsgi.example $GRAPHITE_CONFIG_DIR/graphite.wsgi
    cp $GRAPHITE_CONFIG_DIR/graphTemplates.conf.example $GRAPHITE_CONFIG_DIR/graphTemplates.conf
    cp $GRAPHITE_CONFIG_DIR/relay-rules.conf.example $GRAPHITE_CONFIG_DIR/relay-rules.conf
    cp $GRAPHITE_CONFIG_DIR/storage-aggregation.conf.example $GRAPHITE_CONFIG_DIR/storage-aggregation.conf
    cp $GRAPHITE_CONFIG_DIR/storage-schemas.conf.example $GRAPHITE_CONFIG_DIR/storage-schemas.conf

    cp $GRAPHITE_WEBAPP_CONFIG".example" $GRAPHITE_WEBAPP_CONFIG

    sed -i 's/#SECRET_KEY/SECRET_KEY/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i "s|#TIME_ZONE = .*|TIME_ZONE = \'${TIMEZONE}\'|g" $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#LOG_RENDERING_PERFORMANCE/LOG_RENDERING_PERFORMANCE/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#LOG_CACHE_PERFORMANCE/LOG_CACHE_PERFORMANCE/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#LOG_METRIC_ACCESS/LOG_METRIC_ACCESS/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#DEBUG/DEBUG/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#GRAPHITE_ROOT/GRAPHITE_ROOT/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#CONF_DIR/CONF_DIR/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#STORAGE_DIR/STORAGE_DIR/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#CONTENT_DIR/CONTENT_DIR/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#DASHBOARD_CONF/DASHBOARD_CONF/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#GRAPHTEMPLATES_CONF/GRAPHTEMPLATES_CONF/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#WHISPER_DIR/WHISPER_DIR/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#RRD_DIR/RRD_DIR/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#LOG_DIR/LOG_DIR/g' $GRAPHITE_WEBAPP_CONFIG
    sed -i 's/#INDEX_FILE/INDEX_FILE/g' $GRAPHITE_WEBAPP_CONFIG

    chown -R www-data:www-data $GRAPHITE_ROOT/storage

    # Configure Whisper storage
    chmod u+x $GRAPHITE_ROOT/webapp/graphite/manage.py
    python /opt/graphite/webapp/graphite/manage.py syncdb --noinput
    python /opt/graphite/webapp/graphite/manage.py createsuperuser --username="root" --email=""

    a2dissite 000-default
    a2ensite graphite.conf

    chmod -R a+w $GRAPHITE_ROOT/storage

    service apache2 restart
}

configure_carbon() {
    cp examples/carbon.sh.example /etc/init.d/carbon.sh
    chmod 755 /etc/init.d/carbon.sh
    update-rc.d carbon.sh defaults
}

resolve_dependency
# install_graphite
# configure_graphite
# configure_carbon
