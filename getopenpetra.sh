#!/usr/bin/env bash
#
#                  OpenPetra Installer Script
#
#   Homepage: https://www.openpetra.org
#   Issues:   https://github.com/openpetra/getopenpetra/issues
#   Requires: bash, curl, sudo (if not root), tar
#
# This script installs OpenPetra on your Linux system.
# You have various options, to install a development environment, or to 
# install a test environment, or to install a production environment.
#
#	$ curl https://getopenpetra.com | bash -s devenv
#	 or
#	$ wget -qO- https://getopenpetra.com | bash -s devenv
#
# The syntax is:
#
#	bash -s [devenv|test|prod]
#
# If you purchased a commercial license, you must set your account
# ID and API key in environment variables:
#
#	$ export OPENPETRA_ACCOUNT_ID=...
#	$ export OPENPETRA_API_KEY=...
#
# Then you can request a commercially-licensed download:
#
#	$ curl https://getopenpetra.com | bash -s prod
#
# This should work on CentOS 7.
# We plan to support soon: Fedora 31 and Debian 10 (Buster) and Ubuntu 18.04 (Bionic Beaver).
# Please open an issue if you notice any bugs.

[[ $- = *i* ]] && echo "Don't source this script!" && return 10

OPENPETRA_DBNAME=openpetra
OPENPETRA_DBUSER=openpetra
OPENPETRA_DBPWD=TO_BE_SET
OPENPETRA_RDBMSType=mysql
OPENPETRA_DBHOST=localhost
OPENPETRA_DBPORT=3306
OPENPETRA_PORT=7000
OPENPETRA_USER=openpetra
OPENPETRA_HOME=/home/$OPENPETRA_USER
SRC_PATH=$OPENPETRA_HOME/openpetra
OPENPETRA_SERVERNAME=localhost
OPENPETRA_URL=http://localhost
OPENPETRA_SERVER_BIN=/usr/bin/openpetra
GITHUB_USER=openpetra
OPENPETRA_BRANCH=dev # TODO: switch to test by default???

nginx_conf()
{
	openpetra_conf_path="$1"
	# let the default nginx server run on another port
	sed -i "s/listen\(.*\)80/listen\181/g" /etc/nginx/nginx.conf
	# modify fastcgi_params
	if [[ "`grep SCRIPT_FILENAME /etc/nginx/fastcgi_params`" == "" ]]
	then
		cat >> /etc/nginx/fastcgi_params <<FINISH
fastcgi_param  PATH_INFO          "";
fastcgi_param  SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
FINISH
	fi
	cat > $openpetra_conf_path <<FINISH
server {
    listen 80;
    server_name $OPENPETRA_SERVERNAME;

    root ${OPENPETRA_HOME}/client;

    location / {
         rewrite ^/Selfservice.*$ /;
         rewrite ^/Settings.*$ /;
         rewrite ^/Partner.*$ /;
         rewrite ^/Finance.*$ /;
         rewrite ^/CrossLedger.*$ /;
         rewrite ^/System.*$ /;
         rewrite ^/.git/.*$ / redirect;
         rewrite ^/etc/.*$ / redirect;
         rewrite ^/phpmyadmin.*$ /phpMyAdmin redirect;
    }

    location /api {
         index index.html index.htm default.aspx Default.aspx;
         fastcgi_index Default.aspx;
         fastcgi_pass 127.0.0.1:6700;
         include /etc/nginx/fastcgi_params;
         sub_filter_types text/html text/css text/xml;
         sub_filter 'http://$OPENPETRA_SERVERNAME/api' '$OPENPETRA_URL/api';
    }

    location /phpMyAdmin {
         root /usr/share/;
         index index.php index.html index.htm;
         location ~ ^/phpMyAdmin/(.+\.php)$ {
                   root /usr/share/;
                   fastcgi_pass 127.0.0.1:8080;
                   fastcgi_index index.php;
                   include /etc/nginx/fastcgi_params;
                   fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
         }
    }
}
FINISH
	systemctl start nginx
	systemctl enable nginx

}

generatepwd()
{
	dd bs=1024 count=1 if=/dev/urandom status=none | tr -dc 'a-zA-Z0-9#?_' | fold -w 32 | head -n 1
}

mariadb_conf()
{
	OPENPETRA_DBPWD=`generatepwd`
	systemctl start mariadb
	systemctl enable mariadb
	mkdir -p $OPENPETRA_HOME/tmp
	echo "DROP DATABASE IF EXISTS \`$OPENPETRA_DBNAME\`;" > $OPENPETRA_HOME/tmp/createdb-MySQL.sql
	echo "CREATE DATABASE IF NOT EXISTS \`$OPENPETRA_DBNAME\`;" >> $OPENPETRA_HOME/tmp/createdb-MySQL.sql
	echo "USE \`$OPENPETRA_DBNAME\`;" >> $OPENPETRA_HOME/tmp/createdb-MySQL.sql
	echo "GRANT ALL ON \`$OPENPETRA_DBNAME\`.* TO \`$OPENPETRA_DBUSER\`@localhost IDENTIFIED BY '$OPENPETRA_DBPWD'" >> $OPENPETRA_HOME/tmp/createdb-MySQL.sql
	mysql -u root < $OPENPETRA_HOME/tmp/createdb-MySQL.sql
	rm -f $OPENPETRA_HOME/tmp/createdb-MySQL.sql
}

openpetra_conf()
{
	useradd --home $OPENPETRA_HOME $OPENPETRA_USER

	# install OpenPetra service file
	cat > /usr/lib/systemd/system/openpetra.service <<FINISH
[Unit]
Description=OpenPetra Server
After=mariadb.service
Wants=mariadb.service

[Service]
User=$OPENPETRA_USER
ExecStart=$OPENPETRA_SERVER_BIN start
ExecStop=$OPENPETRA_SERVER_BIN stop
RestartSec=5

[Install]
WantedBy=multi-user.target
FINISH

	systemctl enable openpetra
	systemctl start openpetra

	# copy web.config for easier debugging
	mkdir -p $SRC_PATH/delivery
	cat > $SRC_PATH/delivery/web.config <<FINISH
<configuration>
    <system.web>
        <customErrors mode="Off"/>
    </system.web>
</configuration>
FINISH

	# create OpenPetra.build.config
	cat > $SRC_PATH/OpenPetra.build.config <<FINISH
<?xml version="1.0"?>
<project name="OpenPetra-userconfig">
    <property name="DBMS.Type" value="mysql"/>
    <property name="DBMS.DBName" value="$OPENPETRA_DBNAME"/>
    <property name="DBMS.UserName" value="$OPENPETRA_DBUSER"/>
    <property name="DBMS.Password" value="$OPENPETRA_DBPWD"/>
    <property name="Server.DebugLevel" value="0"/>
</project>
FINISH

	mkdir -p $OPENPETRA_HOME/etc
	mkdir -p $OPENPETRA_HOME/log
	# copy config files (server, serveradmin.config) to etc, with adjustments
	cat $SRC_PATH/setup/petra0300/linuxserver/PetraServerConsole.config \
		| sed -e "s/OPENPETRA_PORT/$OPENPETRA_PORT/" \
		| sed -e "s/OPENPETRA_RDBMSType/$OPENPETRA_RDBMSType/" \
		| sed -e "s/OPENPETRA_DBHOST/$OPENPETRA_DBHOST/" \
		| sed -e "s/OPENPETRA_DBUSER/$OPENPETRA_DBUSER/" \
		| sed -e "s/OPENPETRA_DBNAME/$OPENPETRA_DBNAME/" \
		| sed -e "s/OPENPETRA_DBPORT/$OPENPETRA_DBPORT/" \
		| sed -e "s~PG_OPENPETRA_DBPWD~$OPENPETRA_DBPWD~" \
		| sed -e "s~OPENPETRA_URL~$OPENPETRA_URL~" \
		| sed -e "s~OPENPETRA_EMAILDOMAIN~$OPENPETRA_EMAILDOMAIN~" \
		| sed -e "s/USERNAME/$OPENPETRA_USER/" \
		| sed -e "s#/usr/local/openpetra/bin#$OPENPETRA_HOME/server/bin#" \
		| sed -e "s#/usr/local/openpetra#$OPENPETRA_HOME#" \
		> $OPENPETRA_HOME/etc/PetraServerConsole.config

	cat $SRC_PATH/setup/petra0300/linuxserver/PetraServerAdminConsole.config \
		| sed -e "s/USERNAME/$userName/" \
		| sed -e "s#/openpetraOPENPETRA_PORT/#:$OPENPETRA_HTTP_PORT/#" \
		> $OPENPETRA_HOME/etc/PetraServerAdminConsole.config
	cat >> $OPENPETRA_HOME/etc/common.config <<FINISH
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <system.web>
    <sessionState
      mode="InProc"
      timeout="30" /> <!-- timeout in minutes -->
    <customErrors mode="Off"/>
    <compilation tempDirectory="/var/tmp" debug="true" strict="false" explicit="true"/>
  </system.web>
</configuration>
FINISH

	# set symbolic links
	cd $OPENPETRA_HOME
	MY_SRC_PATH=$SRC_PATH
	if [ "$SRC_PATH" = "$OPENPETRA_HOME/openpetra" ]; then
		MY_SRC_PATH=openpetra
	fi
	ln -s $MY_SRC_PATH/setup/petra0300/linuxserver/mysql/centos/openpetra-server.sh $OPENPETRA_SERVER_BIN
	chmod a+x $OPENPETRA_SERVER_BIN
	ln -s $MY_SRC_PATH/delivery $OPENPETRA_HOME/server
	ln -s $MY_SRC_PATH/XmlReports $OPENPETRA_HOME/reports
	ln -s $MY_SRC_PATH/csharp/ICT/Petra/Server/sql $OPENPETRA_HOME/sql
	ln -s $MY_SRC_PATH/demodata/formletters $OPENPETRA_HOME/formletters
	ln -s $MY_SRC_PATH/inc/template/email $OPENPETRA_HOME/emails
	ln -s $MY_SRC_PATH/js-client $OPENPETRA_HOME/client
	ln -s $MY_SRC_PATH/delivery $SRC_PATH/delivery/api
	ln -s $MY_SRC_PATH/csharp/ICT/Petra/Server/app/WebService/*.asmx $OPENPETRA_HOME/server
	ln -s $MY_SRC_PATH/csharp/ICT/Petra/Server/app/WebService/*.aspx $OPENPETRA_HOME/server
	cd -
}

install_openpetra()
{
	trap 'echo -e "Aborted, error $? in command: $BASH_COMMAND"; trap ERR; exit 1' ERR
	install_type="$1"

	if [ ! -z "$2" ]; then
		GITHUB_USER="$2"
	fi

	if [ ! -z "$3" ]; then
		OPENPETRA_BRANCH="$3"
	fi

	# Valid install type is required
	if [[ "$install_type" != "devenv" && "$install_type" != "test" && "$install_type" != "prod" ]]; then
		echo "You must specify the install type:"
		echo "  devenv: install a development environment for OpenPetra"
		echo "  test: install an environment to test OpenPetra"
		echo "  prod: install a production server with OpenPetra"
		return 9
	fi

	sudo_cmd="sudo"

	#########################
	# Which OS and version? #
	#########################

	unameu="$(tr '[:lower:]' '[:upper:]' <<<$(uname))"
	if [[ $unameu == *LINUX* ]]; then
		install_os="linux"
	else
		echo "Aborted, unsupported or unknown os: $uname"
		return 6
	fi

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		OS=$NAME
		VER=$VERSION_ID

		if [[ "$OS" == "CentOS Linux" ]]; then OS="CentOS"; OS_FAMILY="Fedora"; fi
		if [[ "$OS" == "Red Hat Enterprise Linux Server" ]]; then OS="CentOS"; OS_FAMILY="Fedora"; fi
		if [[ "$OS" == "Fedora" ]]; then OS="Fedora"; OS_FAMILY="Fedora"; fi
		if [[ "$OS" == "Debian GNU/Linux" ]]; then OS="Debian"; OS_FAMILY="Debian"; fi
		if [[ "$OS" == "Ubuntu" ]]; then OS="Ubuntu"; OS_FAMILY="Debian"; fi

		if [[ "$OS" != "CentOS" 
			#&& "$OS" != "Fedora"
			#&& "$OS" != "Debian"
			#&& "$OS" != "Ubuntu"
			]]; then
			echo "Aborted, Your distro is not supported: " $OS
			return 6
		fi

		if [[ "$OS_FAMILY" == "Fedora" ]]; then
			if [[ "$VER" != "7" && "$VER" != "31" ]]; then
				echo "Aborted, Your distro version is not supported: " $OS $VER
				return 6
			fi
		fi

		if [[ "$OS_FAMILY" == "Debian" ]]; then
			if [[ "$VER" != "10" && "$VER" != "18.04" ]]; then
				echo "Aborted, Your distro version is not supported: " $OS $VER
				return 6
			fi
		fi
	else
		echo "Aborted, Your distro could not be recognised."
		return 6
	fi

	#####################################
	# Setup the development environment #
	#####################################
	if [[ "$install_type" == "devenv" ]]; then
		OPENPETRA_DBNAME=op_dev
		OPENPETRA_DBUSER=op_dev
		OPENPETRA_USER=op_dev
		OPENPETRA_SERVERNAME=$OPENPETRA_USER.localhost
		OPENPETRA_HOME=/home/$OPENPETRA_USER
		SRC_PATH=$OPENPETRA_HOME/openpetra
		OPENPETRA_SERVER_BIN=$OPENPETRA_HOME/openpetra-server.sh

		if [[ "$OS" == "Fedora" ]]; then
			dnf -y install git nant mono-devel
		elif [[ "$OS" == "CentOS" ]]; then
			yum -y install epel-release yum-utils git
			git config --global push.default simple
			# install Copr repository for Mono >= 5.10
			su -c 'curl https://copr.fedorainfracloud.org/coprs/tpokorra/mono-5.18/repo/epel-7/tpokorra-mono-5.18-epel-7.repo | tee /etc/yum.repos.d/tpokorra-mono5.repo'
			# for printing reports to pdf
			if [[ "`rpm -qa | grep wkhtmltox`" = "" ]]; then
				yum -y install https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox-0.12.5-1.centos7.x86_64.rpm
			fi
			# for cypress tests
			yum -y install libXScrnSaver GConf2 Xvfb
			# for printing bar codes
			curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/code128.ttf
			# for the js client
			curl --silent --location https://rpm.nodesource.com/setup_8.x  | bash -
			yum -y install nodejs
			npm set progress=false
			npm install -g browserify
			npm install -g uglify-es
			#npm install cypress # somehow this will be downloaded again later, when calling npm install in the js-client path
			# for mono development
			yum -y install nant mono-devel mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel
			yum -y install mariadb-server nginx lsb libsodium
			# phpmyadmin
			if [[ "`rpm -qa | grep remi-release-7`" = "" ]]; then
				yum -y install http://rpms.remirepo.net/enterprise/remi-release-7.rpm
			fi
			yum-config-manager --enable remi-php71
			yum-config-manager --enable remi
			yum -y install phpMyAdmin php-fpm
			sed -i "s#user = apache#user = nginx#" /etc/php-fpm.d/www.conf
			sed -i "s#group = apache#group = nginx#" /etc/php-fpm.d/www.conf
			sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php-fpm.d/www.conf
			sed -i "s#;chdir = /var/www#chdir = /usr/share/phpMyAdmin#" /etc/php-fpm.d/www.conf
			chown nginx:nginx /var/lib/php/session
			systemctl enable php-fpm
			systemctl start php-fpm
		elif [[ "$OS_FAMILY" == "Debian" ]]; then
			apt-get -y install git nant
		fi

		if [ ! -d $SRC_PATH ]
		then
			git clone --depth 50 https://github.com/$GITHUB_USER/openpetra.git -b $OPENPETRA_BRANCH $SRC_PATH
		fi
		cd $SRC_PATH

		# configure nginx
		nginx_conf /etc/nginx/conf.d/openpetra.conf
		# configure mariadb
		mariadb_conf
		# configure openpetra (mono process)
		openpetra_conf

		# TODO: run as user op_dev???

		nant generateTools recreateDatabase resetDatabase || exit -1
		nant generateSolution || exit -1

		# download and restore demo database
		demodbfile=$OPENPETRA_HOME/demoWith1ledger.yml.gz
		curl --silent --location https://github.com/openpetra/demo-databases/raw/master/demoWith1ledger.yml.gz > $demodbfile
		OP_CUSTOMER=$OPENPETRA_USER $OPENPETRA_SERVER_BIN loadYmlGz $demodbfile || exit -1

		# TODO drop non-linux dlls from bin
		rm -f delivery/bin/Mono.Data.Sqlite.dll
		rm -f delivery/bin/Mono.Security.dll
		rm -f delivery/bin/sqlite3.dll
		rm -f delivery/bin/libsodium.dll
		rm -f delivery/bin/libsodium-64.dll
		if [ ! -f delivery/bin/libsodium.so ]; then
			if [ -f /usr/lib64/libsodium.so.23 ]; then
				# CentOS 7
				ln -s /usr/lib64/libsodium.so.23 delivery/bin/libsodium.so
			fi
		fi

		cd js-client
		npm set progress=false
		# set CI=1 to avoid too much output from installing cypress. see https://github.com/cypress-io/cypress/issues/1243#issuecomment-365560861
		( CI=1 npm install --quiet ) || exit -1
		# TODO replace with nant install.js
		npm run build || exit -1
		cd ..

		# Still needed? nant install
		systemctl restart openpetra

		chown -R $OPENPETRA_USER:$OPENPETRA_USER $OPENPETRA_HOME

		# display information to the developer
		echo "Go and check your instance at $OPENPETRA_URL"
		echo "login with user DEMO and password demo, or user SYSADMIN and password CHANGEME."
		echo "See also the API at $OPENPETRA_URL/api/"
		echo "You find phpMyAdmin running at $OPENPETRA_URL/phpmyadmin"
		echo "Start developing in $SRC_PATH as user $OPENPETRA_USER, and use the following commands:"
		echo "    nant generateGlue"
		echo "    nant generateProjectFiles"
		echo "    nant quickCompile -D:onlyonce=yes"
		echo "    nant compileProject -D:name=Ict.Common"
	fi

}


install_openpetra "$@"
