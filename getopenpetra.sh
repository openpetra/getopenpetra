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
# This should work on CentOS 7 and Fedora 31,
# and Ubuntu 19.10 (Eoan Ermine), Ubuntu 18.04 (Bionic Beaver)
# and Debian 10 (Buster).
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
	if [ -f /etc/nginx/sites-enabled/default ]; then
		sed -i "s/listen\(.*\)80/listen\181/g" /etc/nginx/sites-enabled/default
	fi
	# modify fastcgi_params
	if [[ "`grep SCRIPT_FILENAME /etc/nginx/fastcgi_params`" == "" ]]
	then
		cat >> /etc/nginx/fastcgi_params <<FINISH
fastcgi_param  PATH_INFO          "";
fastcgi_param  SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
FINISH
	fi

	cat $SRC_PATH/setup/petra0300/linuxserver/nginx.conf \
		| sed -e "s/OPENPETRA_SERVERNAME/$OPENPETRA_SERVERNAME/g" \
		| sed -e "s#OPENPETRA_HOME#$OPENPETRA_HOME#g" \
		| sed -e "s#OPENPETRA_URL#$OPENPETRA_URL#g" \
		> $openpetra_conf_path

	systemctl start nginx
	systemctl enable nginx

}

generatepwd()
{
	dd bs=1024 count=1 if=/dev/urandom status=none | tr -dc 'a-zA-Z0-9#?_' | fold -w 32 | head -n 1
}

openpetra_conf()
{
	useradd --home $OPENPETRA_HOME $OPENPETRA_USER

	# install OpenPetra service file
	systemdpath="/usr/lib/systemd/system"
	if [ ! -d $systemdpath ]; then
		# Ubuntu Bionic
		systemdpath="/lib/systemd/system"
	fi
	cat $SRC_PATH/setup/petra0300/linuxserver/$OPENPETRA_RDBMSType/openpetra.service \
		| sed -e "s/OPENPETRA_USER/$OPENPETRA_USER/g" \
		| sed -e "s#OPENPETRA_SERVER_BIN#$OPENPETRA_SERVER_BIN#g" \
		> $systemdpath/openpetra.service

	systemctl enable openpetra
	systemctl start openpetra

	# copy web.config for easier debugging
	mkdir -p $SRC_PATH/delivery
	cp $SRC_PATH/setup/petra0300/linuxserver/web.config $SRC_PATH/delivery/web.config

	# create OpenPetra.build.config
	cat $SRC_PATH/setup/petra0300/linuxserver/$OPENPETRA_RDBMSType/OpenPetra.build.config \
		| sed -e "s/OPENPETRA_RDBMSType/$OPENPETRA_RDBMSType/g" \
		| sed -e "s/OPENPETRA_DBNAME/$OPENPETRA_DBNAME/g" \
		| sed -e "s/OPENPETRA_DBUSER/$OPENPETRA_DBUSER/g" \
		| sed -e "s/OPENPETRA_DBPWD/$OPENPETRA_DBPWD/g" \
		> $SRC_PATH/OpenPetra.build.config

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

	cp $SRC_PATH/setup/petra0300/linuxserver/common.config $OPENPETRA_HOME/etc/common.config

	# set symbolic links
	cd $OPENPETRA_HOME
	MY_SRC_PATH=$SRC_PATH
	MY_SRC_PATH_SERVER=$SRC_PATH
	if [ "$SRC_PATH" = "$OPENPETRA_HOME/openpetra" ]; then
		MY_SRC_PATH=openpetra
	fi
	ln -s $MY_SRC_PATH/setup/petra0300/linuxserver/openpetra-server.sh $OPENPETRA_SERVER_BIN
	chmod a+x $OPENPETRA_SERVER_BIN
	ln -s $MY_SRC_PATH/delivery $OPENPETRA_HOME/server
	ln -s $MY_SRC_PATH/XmlReports $OPENPETRA_HOME/reports
	ln -s $MY_SRC_PATH/csharp/ICT/Petra/Server/sql $OPENPETRA_HOME/sql
	ln -s $MY_SRC_PATH/demodata/formletters $OPENPETRA_HOME/formletters
	ln -s $MY_SRC_PATH/inc/template/email $OPENPETRA_HOME/emails
	ln -s $MY_SRC_PATH/js-client $OPENPETRA_HOME/client
	ln -s $MY_SRC_PATH_SERVER/delivery $SRC_PATH/delivery/api
	ln -s $MY_SRC_PATH_SERVER/csharp/ICT/Petra/Server/app/WebService/*.asmx $OPENPETRA_HOME/server
	ln -s $MY_SRC_PATH_SERVER/csharp/ICT/Petra/Server/app/WebService/*.aspx $OPENPETRA_HOME/server
	cd -
}

install_openpetra()
{
	trap 'echo -e "Aborted, error $? in command: $BASH_COMMAND"; trap ERR; exit 1' ERR
	install_type="$1"

	OPENPETRA_DBPWD=`generatepwd`

	if [ ! -z "$2" ]; then
		GITHUB_USER="$2"
	fi

	if [ ! -z "$3" ]; then
		OPENPETRA_BRANCH="$3"
	fi

	if [ ! -z "$4" ]; then
		OPENPETRA_RDBMSType="$4"
	fi

	if [[ "$OPENPETRA_RDBMSType" == "sqlite" ]]; then
		OPENPETRA_DBPWD=
	elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
		OPENPETRA_DBPORT=5432
	fi

	# Valid install type is required
	if [[ "$install_type" != "devenv" && "$install_type" != "test" && "$install_type" != "prod" ]]; then
		echo "You must specify the install type:"
		echo "  devenv: install a development environment for OpenPetra"
		echo "  test: install an environment to test OpenPetra"
		echo "  prod: install a production server with OpenPetra"
		return 9
	fi

	# We don't run with SELinux for the moment
	if [ -f /usr/sbin/sestatus ]; then
		if [[ "`sestatus | grep -E 'disabled|permissive'`" == "" ]]; then
			echo "SELinux is active, please set it to permissive"
			exit 1
		fi
	fi

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
			&& "$OS" != "Fedora"
			&& "$OS" != "Debian"
			&& "$OS" != "Ubuntu"
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
			if [[ "$VER" != "10" && "$VER" != "18.04"  && "$VER" != "19.10" ]]; then
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
			dnf -y install git sudo
			# for printing reports to pdf
			dnf -y install wkhtmltopdf
			# for cypress tests
			dnf -y install libXScrnSaver GConf2 Xvfb gtk3
			# for printing bar codes
			curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/code128.ttf
			# for the js client
			dnf -y install nodejs
			# for mono development
			dnf -y install nant mono-devel mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel
			dnf -y install nginx lsb libsodium
			if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
				dnf -y install mariadb-server
				# phpmyadmin
				dnf -y install phpMyAdmin php-fpm
				sed -i "s#user = apache#user = nginx#" /etc/php-fpm.d/www.conf
				sed -i "s#group = apache#group = nginx#" /etc/php-fpm.d/www.conf
				sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php-fpm.d/www.conf
				sed -i "s#;chdir = /var/www#chdir = /usr/share/phpMyAdmin#" /etc/php-fpm.d/www.conf
				chown nginx:nginx /var/lib/php/session
				systemctl enable php-fpm
				systemctl start php-fpm
			elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
				dnf -y install postgresql-server
			elif [[ "$OPENPETRA_RDBMSType" == "sqlite" ]]; then
				dnf -y install sqlite
			fi
		elif [[ "$OS" == "CentOS" ]]; then
			yum -y install epel-release yum-utils git sudo
			git config --global push.default simple
			# install Copr repository for Mono >= 5.10
			su -c 'curl https://copr.fedorainfracloud.org/coprs/tpokorra/mono-5.18/repo/epel-7/tpokorra-mono-5.18-epel-7.repo | tee /etc/yum.repos.d/tpokorra-mono5.repo'
			# for printing reports to pdf
			if [[ "`rpm -qa | grep wkhtmltox`" == "" ]]; then
				yum -y install https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox-0.12.5-1.centos7.x86_64.rpm
			fi
			# for cypress tests
			yum -y install libXScrnSaver GConf2 Xvfb gtk3
			# for printing bar codes
			curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/code128.ttf
			# for the js client
			curl --silent --location https://rpm.nodesource.com/setup_8.x  | bash -
			yum -y install nodejs
			# for mono development
			yum -y install nant mono-devel mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel
			# update the certificates for Mono
			curl https://curl.haxx.se/ca/cacert.pem > ~/cacert.pem && cert-sync ~/cacert.pem
			yum -y install nginx lsb libsodium
			if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
				yum -y install mariadb-server
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
			elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
				yum -y install postgresql-server
			elif [[ "$OPENPETRA_RDBMSType" == "sqlite" ]]; then
				yum -y install sqlite
			fi
		elif [[ "$OS" == "Debian" ]]; then
			apt-get -y install git sudo
			# for printing reports to pdf
			apt-get -y install wkhtmltopdf
			# for cypress tests
			apt-get -y install gconf2 xvfb libnss3 libxss1 libasound2 # libgtk3.0-cil libXScrnSaver
			# for printing bar codes
			curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/truetype/code128.ttf
			# for the js client
			apt-get -y install nodejs npm
			# for mono development
			if [[ "$VER" == "10" ]]; then
				# for nant
				echo 'deb [arch=amd64] https://lbs.solidcharity.com/repos/tpokorra/nant/debian/buster buster main' >> /etc/apt/sources.list
				apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0x4796B710919684AC
				apt-get update
			fi
			apt-get -y install nant mono-devel mono-xsp4 mono-fastcgi-server4 ca-certificates-mono xfonts-75dpi fonts-liberation libgdiplus
			# to avoid errors like: error CS0433: The imported type `System.CodeDom.Compiler.CompilerError' is defined multiple times
			if [ -f /usr/lib/mono/4.5-api/System.dll -a -f /usr/lib/mono/4.5/System.dll ]; then
				rm -f /usr/lib/mono/4.5-api/System.dll
			fi
			apt-get -y install nginx libsodium23
			if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
				apt-get -y install mariadb-server
				# phpmyadmin
				#apt-get -y install phpmyadmin php-fpm
				#sed -i "s#user = apache#user = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
				#sed -i "s#group = apache#group = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
				#sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php/7.2/fpm/pool.d/www.conf
				#sed -i "s#;chdir = /var/www#chdir = /usr/share/phpmyadmin#" /etc/php/7.2/fpm/pool.d/www.conf
				#chown nginx:nginx /var/lib/php/session
				#systemctl enable php-fpm
				#systemctl start php-fpm
			elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
				apt-get -y install postgresql-server
			elif [[ "$OPENPETRA_RDBMSType" == "sqlite" ]]; then
				apt-get -y install sqlite
			fi
		elif [[ "$OS" == "Ubuntu" ]]; then
			apt-get -y install git sudo
			# for printing reports to pdf
			if [[ "$VER" == "18.04" ]]; then
				# we need version 0.12.5, not 0.12.4 which is part of bionic.
				curl --silent --location https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb > wkhtmltox_0.12.5-1.bionic_amd64.deb
				apt-get -y install ./wkhtmltox_0.12.5-1.bionic_amd64.deb
				rm -Rf wkhtmltox_0.12.5-1.bionic_amd64.deb
			else
				apt-get -y install wkhtmltopdf
			fi
			# for cypress tests
			apt-get -y install gconf2 xvfb # libgtk3.0-cil libXScrnSaver
			# for printing bar codes
			curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/truetype/code128.ttf
			# for the js client
			apt-get -y install nodejs npm
			# for mono development
			if [[ "$VER" == "18.04" ]]; then
				apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
				echo "deb https://download.mono-project.com/repo/ubuntu stable-bionic main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
				apt-get update
			fi
			apt-get -y install nant mono-devel mono-xsp4 mono-fastcgi-server4 ca-certificates-mono xfonts-75dpi fonts-liberation libgdiplus
			# to avoid errors like: error CS0433: The imported type `System.CodeDom.Compiler.CompilerError' is defined multiple times
			if [ -f /usr/lib/mono/4.5-api/System.dll -a -f /usr/lib/mono/4.5/System.dll ]; then
				rm -f /usr/lib/mono/4.5-api/System.dll
			fi
			apt-get -y install nginx libsodium23 lsb
			if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
				apt-get -y install mariadb-server
				# phpmyadmin
				#apt-get -y install phpmyadmin php-fpm
				#sed -i "s#user = apache#user = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
				#sed -i "s#group = apache#group = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
				#sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php/7.2/fpm/pool.d/www.conf
				#sed -i "s#;chdir = /var/www#chdir = /usr/share/phpmyadmin#" /etc/php/7.2/fpm/pool.d/www.conf
				#chown nginx:nginx /var/lib/php/session
				#systemctl enable php-fpm
				#systemctl start php-fpm
			elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
				apt-get -y install postgresql-server
			elif [[ "$OPENPETRA_RDBMSType" == "sqlite" ]]; then
				apt-get -y install sqlite
			fi
		fi

		if [ ! -d $SRC_PATH ]
		then
			git clone --depth 50 https://github.com/$GITHUB_USER/openpetra.git -b $OPENPETRA_BRANCH $SRC_PATH
		fi
		cd $SRC_PATH

		# configure nginx
		nginx_conf /etc/nginx/conf.d/openpetra.conf
		# configure openpetra (mono process)
		openpetra_conf

		chown -R $OPENPETRA_USER:$OPENPETRA_USER $OPENPETRA_HOME

		# configure database
		su $OPENPETRA_USER -c "nant generateTools createSQLStatements" || exit -1
		OP_CUSTOMER=$OPENPETRA_USER $OPENPETRA_SERVER_BIN initdb || exit -1
		su $OPENPETRA_USER -c "nant recreateDatabase resetDatabase" || exit -1

		su $OPENPETRA_USER -c "nant generateSolution" || exit -1
		su $OPENPETRA_USER -c "nant install.net" || exit -1
		su $OPENPETRA_USER -c "nant install.js" || exit -1

		# for the cypress test environment
		su $OPENPETRA_USER -c "cd js-client && CI=1 npm install cypress --quiet" || exit -1

		# download and restore demo database
		demodbfile=$OPENPETRA_HOME/demoWith1ledger.yml.gz
		curl --silent --location https://github.com/openpetra/demo-databases/raw/master/demoWith1ledger.yml.gz > $demodbfile
		OP_CUSTOMER=$OPENPETRA_USER $OPENPETRA_SERVER_BIN loadYmlGz $demodbfile || exit -1

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
