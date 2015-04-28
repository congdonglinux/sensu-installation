# !/bin/bash
 
# Constants
GRAPHITE_ROOT='/opt/graphite'
GRAPHITE_CONF_DIR='/opt/graphite/conf'
GRAPHITE_WEBAPP_CONF='/opt/graphite/webapp/graphite/local_settings.py'
GRAPHITE_VHOST_EXAMPLE='/opt/graphite/examples/example-graphite-vhost.conf'

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
            apt-get install -y expect
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
            yum install -y expect
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
    cp $GRAPHITE_VHOST_EXAMPLE $APACHE_CONF_DIR/graphite.conf
    chmod a+r $APACHE_CONF_DIR/graphite.conf

    # On CentOS, the SELinux would prevent httpd to access log file in
    # "/opt/graphite/storage/log", so, you should change the context of that 
    # directory. Or, you'll get some Perminssion denied error in "/var/log/httpd/error_log"
#    if [ $DIST == 'CENTOS' ]; then
#        semanage fcontext -a -t httpd_sys_rw_content_t /opt/graphite/storage
#        restorecon -v /opt/graphite/storage
#        semanage fcontext -a -t var_log_t /opt/graphite/storage/log
#        restorecon -v /opt/graphite/storage/log
#        semanage fcontext -a -t httpd_log_t /opt/graphite/storage/log/webapp
#        restorecon -v /opt/graphite/storage/log/webapp
#
#        setsebool -P httpd_unified 1
#    fi

    # Substitue Django root directory
    DJANGO_ROOT=`pip show django | grep 'Location' | sed 's/Location:\ //g'`
    echo $DJANGO_ROOT
    sed -i "s|\@DJANGO_ROOT\@|${DJANGO_ROOT}|g" $APACHE_CONF_DIR/graphite.conf

    # Add Directory to Graphite VHost
    sed -i "s/WSGISocketPrefix\ run\/wsgi/WSGISocketPrefix\ \/var\/run\/${APACHE_SERVICE}\/wsgi/" $APACHE_CONF_DIR/graphite.conf
    sed -i '/<Directory.*/,/<\/Directory>/{N;$!D}' $APACHE_CONF_DIR/graphite.conf
    sed -i "$ i <Directory /opt/graphite/conf/>\n\t\tRequire all granted\n\t</Directory>" $APACHE_CONF_DIR/graphite.conf
    sed -i "$ i <Directory /opt/graphite/webapp/>\n\t\tRequire all granted\n\t</Directory>" $APACHE_CONF_DIR/graphite.conf

    # Copy configuration templates
    cp $GRAPHITE_CONF_DIR/carbon.conf.example $GRAPHITE_CONF_DIR/carbon.conf
    cp $GRAPHITE_CONF_DIR/dashboard.conf.example $GRAPHITE_CONF_DIR/dashboard.conf
    cp $GRAPHITE_CONF_DIR/graphite.wsgi.example $GRAPHITE_CONF_DIR/graphite.wsgi
    cp $GRAPHITE_CONF_DIR/graphTemplates.conf.example $GRAPHITE_CONF_DIR/graphTemplates.conf
    cp $GRAPHITE_CONF_DIR/relay-rules.conf.example $GRAPHITE_CONF_DIR/relay-rules.conf
    cp $GRAPHITE_CONF_DIR/storage-aggregation.conf.example $GRAPHITE_CONF_DIR/storage-aggregation.conf
    cp $GRAPHITE_CONF_DIR/storage-schemas.conf.example $GRAPHITE_CONF_DIR/storage-schemas.conf

    # Copy configuration templates
    cp $GRAPHITE_WEBAPP_CONF".example" $GRAPHITE_WEBAPP_CONF

    # Tweak local_settings.py for Graphite webapp
    case $DIST in
        'DEBIAN')    
            TIMEZONE=`cat /etc/timezone`
        ;;
        'CENTOS')
            TIMEZONE=`readlink /etc/localtime | awk -F'/' '{print $5"/"$6}'`
        ;;
    esac

    sed -i 's/#SECRET_KEY/SECRET_KEY/g' $GRAPHITE_WEBAPP_CONF
    sed -i "s|#TIME_ZONE = .*|TIME_ZONE = \'${TIMEZONE}\'|g" $GRAPHITE_WEBAPP_CONF
    sed -i 's/#LOG_RENDERING_PERFORMANCE/LOG_RENDERING_PERFORMANCE/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#LOG_CACHE_PERFORMANCE/LOG_CACHE_PERFORMANCE/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#LOG_METRIC_ACCESS/LOG_METRIC_ACCESS/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#DEBUG/DEBUG/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#GRAPHITE_ROOT/GRAPHITE_ROOT/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#CONF_DIR/CONF_DIR/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#STORAGE_DIR/STORAGE_DIR/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#CONTENT_DIR/CONTENT_DIR/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#DASHBOARD_CONF/DASHBOARD_CONF/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#GRAPHTEMPLATES_CONF/GRAPHTEMPLATES_CONF/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#WHISPER_DIR/WHISPER_DIR/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#RRD_DIR/RRD_DIR/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#LOG_DIR/LOG_DIR/g' $GRAPHITE_WEBAPP_CONF
    sed -i 's/#INDEX_FILE/INDEX_FILE/g' $GRAPHITE_WEBAPP_CONF

    # Configure Whisper storage
    chmod u+x $GRAPHITE_ROOT/webapp/graphite/manage.py
    python /opt/graphite/webapp/graphite/manage.py syncdb --noinput
    python /opt/graphite/webapp/graphite/manage.py createsuperuser --username="root" --email="example@example.com" --noinput

    # Change password
    expect << EOF
        spawn python /opt/graphite/webapp/graphite/manage.py changepassword "root"
        expect "Password: "
        send -- "123456\r"
        expect "Password (again): "
        send -- "123456\r"
        expect eof
EOF

    chown -R $APACHE_USER:$APACHE_USER $GRAPHITE_ROOT/storage
    chmod -R a+w $GRAPHITE_ROOT/storage

    case $DIST in
        'DEBIAN')
            a2dissite 000-default
            a2ensite graphite.conf
            service apache2 restart
        ;;
        'CENTOS')
            # systemctl enable httpd
            # systemctl start httpd
            chkconfig httpd on
            service httpd start
        ;;
    esac
}

configure_carbon() {
    case $DIST in
        'DEBIAN')
            cp examples/carbon.sh.example /etc/init.d/carbon.sh
            chmod 755 /etc/init.d/carbon.sh
            update-rc.d carbon.sh defaults
            service carbon.sh start
        ;;
        'CENTOS')
           mkdir -p /usr/lib/systemd/scripts
           cp examples/carbon.sh.example /usr/lib/systemd/scripts/carbon.sh
           chmod 755 /usr/lib/systemd/scripts/carbon.sh
           cp examples/carbon.service.example /usr/lib/systemd/system/carbon.service
           # systemctl start carbon.service
           # systemctl enable carbon.service
           chkconfig --add carbon
           chkconfig carbon on
           service carbon start
        ;;
    esac
}
