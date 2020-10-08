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
#	$ curl https://get.openpetra.org | bash -s devenv
#	 or
#	$ wget -qO- https://get.openpetra.org | bash -s devenv
#
# The syntax is:
#
#	bash -s [devenv|test|demo|prod]
#
# available options:
#     --git_url=<http git url>
#            default is: --git_url=https://github.com/openpetra/openpetra.git
#     --branch=<branchname>
#            default is: --branch=test
#     --dbms=<dbms>
#            default is: --dbms=mysql
#            other options: postgresql
#     --url=<outside url>
#            default is: --url=http://localhost
#            for demo: --url=https://demo.openpetra.org
#     --emaildomain=<your email domain, used for noreply sender address>
#            default is: --emaildomain=myexample.org
#            for demo: --emaildomain=openpetra.org
#     --instance=<instance>
#            default is: --instance=op_dev for devenv, --instance=op_test for test
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
# This should work on CentOS 7 and 8, Fedora 31 and 32
# and Ubuntu 20.04 (Focal Fossa), Ubuntu 19.10 (Eoan Ermine), Ubuntu 18.04 (Bionic Beaver)
# and Debian 9 (Stretch), Debian 10 (Buster).
# Please open an issue if you notice any bugs.

[[ $- = *i* ]] && echo "Don't source this script!" && return 10

export OPENPETRA_DBNAME=openpetra
export OPENPETRA_DBUSER=openpetra
export OPENPETRA_DBPWD=TO_BE_SET
export OPENPETRA_RDBMSType=mysql
export OPENPETRA_DBHOST=127.0.0.1
export OPENPETRA_DBPORT=3306
export OPENPETRA_HTTP_PORT=80
export OPENPETRA_USER=openpetra
export OP_CUSTOMER=
export OPENPETRA_HOME=/home/$OPENPETRA_USER
export SRC_PATH=$OPENPETRA_HOME/openpetra
export OPENPETRA_SERVERNAME=localhost
export OPENPETRA_URL=http://localhost
export OPENPETRA_EMAILDOMAIN=myexample.org
export OPENPETRA_SERVER_BIN=/usr/bin/openpetra
export GIT_URL=https://github.com/openpetra/openpetra.git
export OPENPETRA_BRANCH=test

nginx_conf()
{
	nginx_conf_path="$1"
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

	if [[ "$install_type" == "devenv" ]]; then
		cp $NGINX_TEMPLATE_FILE $nginx_conf_path
	else
		# drop location phpMyAdmin
		# drop the redirect for phpMyAdmin
		awk '/location \/phpMyAdmin/ {exit} {print}' $NGINX_TEMPLATE_FILE \
			| grep -v phpMyAdmin \
			> $nginx_conf_path
		echo "}" >> $nginx_conf_path
	fi

	sed -i "s/OPENPETRA_SERVERNAME/$OPENPETRA_SERVERNAME/g" $nginx_conf_path
	sed -i "s#OPENPETRA_PORT#$OPENPETRA_HTTP_PORT#g" $nginx_conf_path
	sed -i "s#OPENPETRA_HOME#$OPENPETRA_HOME#g" $nginx_conf_path
	sed -i "s#OPENPETRA_URL#$OPENPETRA_URL#g" $nginx_conf_path

	systemctl start nginx
	systemctl enable nginx
}

generatepwd()
{
	dd bs=1024 count=1 if=/dev/urandom status=none | tr -dc 'a-zA-Z0-9#?_' | fold -w 32 | head -n 1
}

openpetra_conf()
{
	groupadd openpetra
	useradd --shell /bin/bash --home $OPENPETRA_HOME --create-home -g openpetra $OPENPETRA_USER

	if [[ "$install_type" == "test" ]]; then
		for d in openpetra-20*; do
			mv $d/* $OPENPETRA_HOME
			rm -Rf $d
			chmod a+r -R $OPENPETRA_HOME
			find $OPENPETRA_HOME -type d -print0 | xargs -0 chmod a+x
			rm -f $OPENPETRA_HOME/server/bin/Mono.Security.dll
			rm -f $OPENPETRA_HOME/server/bin/Mono.Data.Sqlite.dll
			rm -f $OPENPETRA_HOME/server/bin/sqlite3.dll
			rm -f $OPENPETRA_HOME/server/bin/libsodium.dll
			rm -f $OPENPETRA_HOME/server/bin/libsodium-64.dll

			if [ -f /usr/lib64/libsodium.so.18 ]; then
				ln -s /usr/lib64/libsodium.so.18 $OPENPETRA_HOME/server/bin/libsodium.so
			elif [ -f /usr/lib/x86_64-linux-gnu/libsodium.so.18 ]; then
				ln -s /usr/lib/x86_64-linux-gnu/libsodium.so.18 $OPENPETRA_HOME/server/bin/libsodium.so
			elif [ -f /usr/lib64/libsodium.so.23 ]; then
				ln -s /usr/lib64/libsodium.so.23 $OPENPETRA_HOME/server/bin/libsodium.so
			elif [ -f /usr/lib/x86_64-linux-gnu/libsodium.so.23 ]; then
				ln -s /usr/lib/x86_64-linux-gnu/libsodium.so.23 $OPENPETRA_HOME/server/bin/libsodium.so
			else
				echo "Error: cannot find libsodium!"
				exit -1
			fi
		done
	fi

	# install OpenPetra service file
	systemdpath="/usr/lib/systemd/system"
	if [ ! -d $systemdpath ]; then
		# Ubuntu Bionic, and Debian Stretch
		systemdpath="/lib/systemd/system"
	fi
	cat $OPENPETRA_SERVICE_FILE \
		| sed -e "s/OPENPETRA_USER/$OPENPETRA_USER/g" \
		| sed -e "s#OPENPETRA_SERVER_BIN#$OPENPETRA_SERVER_BIN#g" \
		> $systemdpath/openpetra.service

	mkdir -p $OPENPETRA_HOME/etc
	cp $TEMPLATES_PATH/common.config $OPENPETRA_HOME/etc/common.config

	if [[ "$install_type" == "devenv" ]]; then
		mkdir /tmp/bootstrap
		cd /tmp/bootstrap
		curl --silent --location https://github.com/twbs/bootstrap/releases/download/v4.0.0/bootstrap-4.0.0-dist.zip > bootstrap-4.0.0-dist.zip
		unzip bootstrap-4.0.0-dist.zip
		mkdir -p $OPENPETRA_HOME/bootstrap-4.0
		mv js/bootstrap.bundle.min.js $OPENPETRA_HOME/bootstrap-4.0
		mv css/bootstrap.min.css $OPENPETRA_HOME/bootstrap-4.0
		cd -
		rm -Rf /tmp/bootstrap
	fi

	systemctl enable openpetra
	systemctl start openpetra
}

openpetra_conf_devenv()
{
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

	mkdir -p $OPENPETRA_HOME/log
	mkdir -p $OPENPETRA_HOME/etc
	mkdir -p $OPENPETRA_HOME/tmp
	mkdir -p $OPENPETRA_HOME/backup

	# copy config files (server, serveradmin.config) to etc, with adjustments
	cat $TEMPLATES_PATH/PetraServerConsole.config \
		| sed -e "s/OPENPETRA_PORT/$OPENPETRA_HTTP_PORT/" \
		| sed -e "s/OPENPETRA_RDBMSType/$OPENPETRA_RDBMSType/" \
		| sed -e "s/OPENPETRA_DBHOST/$OPENPETRA_DBHOST/" \
		| sed -e "s/OPENPETRA_DBUSER/$OPENPETRA_DBUSER/" \
		| sed -e "s/OPENPETRA_DBNAME/$OPENPETRA_DBNAME/" \
		| sed -e "s/OPENPETRA_DBPORT/$OPENPETRA_DBPORT/" \
		| sed -e "s~OPENPETRA_DBPWD~$OPENPETRA_DBPWD~" \
		| sed -e "s~OPENPETRA_URL~$OPENPETRA_URL~" \
		| sed -e "s~OPENPETRA_EMAILDOMAIN~$OPENPETRA_EMAILDOMAIN~" \
		| sed -e "s~SMTP_HOST~mail.example.org~" \
		| sed -e "s~SMTP_PORT~25~" \
		| sed -e "s~SMTP_USERNAME~SMTP_USER_NAME~" \
		| sed -e "s~SMTP_ENABLESSL~true~" \
		| sed -e "s~SMTP_AUTHTYPE~config~" \
		| sed -e "s/USERNAME/$OPENPETRA_USER/" \
		| sed -e "s#OPENPETRAPATH#$OPENPETRA_HOME#" \
		| sed -e "s#AUTHTOKENINITIALISATION##" \
		| sed -e "s#LICENSECHECK_URL##" \
		> $OPENPETRA_HOME/etc/PetraServerConsole.config

	cat $TEMPLATES_PATH/PetraServerAdminConsole.config \
		| sed -e "s/USERNAME/$OPENPETRA_USER/" \
		| sed -e "s#/openpetraOPENPETRA_PORT/#:$OPENPETRA_HTTP_PORT/#" \
		> $OPENPETRA_HOME/etc/PetraServerAdminConsole.config

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
	ln -s $MY_SRC_PATH/delivery/db $OPENPETRA_HOME/db
	ln -s $MY_SRC_PATH/XmlReports $OPENPETRA_HOME/reports
	ln -s $MY_SRC_PATH/csharp/ICT/Petra/Server/sql $OPENPETRA_HOME/sql
	ln -s $MY_SRC_PATH/demodata/formletters $OPENPETRA_HOME/formletters
	ln -s $MY_SRC_PATH/inc/template/email $OPENPETRA_HOME/emails
	ln -s $MY_SRC_PATH/js-client $OPENPETRA_HOME/client
	ln -s $MY_SRC_PATH_SERVER/delivery $SRC_PATH/delivery/api
	ln -s $MY_SRC_PATH_SERVER/csharp/ICT/Petra/Server/app/WebService/*.asmx $OPENPETRA_HOME/server
	ln -s $MY_SRC_PATH_SERVER/csharp/ICT/Petra/Server/app/WebService/*.aspx $OPENPETRA_HOME/server
	ln -s $MY_SRC_PATH_SERVER/setup/petra0300/linuxserver $OPENPETRA_HOME/templates
	cd -
	cd $SRC_PATH/js-client && ln -s ../setup/petra0300/releasenotes/ && cd -
	mkdir -p $OPENPETRA_HOME/openpetra/delivery/bin
	cd $OPENPETRA_HOME/server/bin && ln -s ../../db/version.txt && cd -
}

install_fedora()
{
	packagesToInstall="sudo"
	if [[ "$install_type" == "devenv" ]]; then
		# need unzip for devenv, nant buildRelease for bootstrap-4.0.0-dist.zip
		# need git for devenv
		packagesToInstall=$packagesToInstall" git unzip"
	fi
	dnf -y install $packagesToInstall || exit -1
	# for printing reports to pdf
	dnf -y install wkhtmltopdf || exit -1
	if [[ "$install_type" == "devenv" ]]; then
		# for cypress tests
		dnf -y install libXScrnSaver GConf2 Xvfb gtk3 || exit -1
	fi
	# for printing bar codes
	curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/code128.ttf
	if [[ "$install_type" == "devenv" ]]; then
		# for building the js client
		dnf -y install nodejs || exit -1
		# for mono development
		dnf -y install nant mono-devel mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel || exit -1
	else
		# for mono runtime
		dnf -y install mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel || exit -1
	fi
	dnf -y install nginx lsb libsodium || exit -1
	if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
		dnf -y install mariadb-server || exit -1
		if [[ "$install_type" == "devenv" ]]; then
			# phpmyadmin
			dnf -y install phpMyAdmin php-fpm || exit -1
			sed -i "s#user = apache#user = nginx#" /etc/php-fpm.d/www.conf
			sed -i "s#group = apache#group = nginx#" /etc/php-fpm.d/www.conf
			sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php-fpm.d/www.conf
			sed -i "s#;chdir = /var/www#chdir = /usr/share/phpMyAdmin#" /etc/php-fpm.d/www.conf
			chown nginx:nginx /var/lib/php/session
			systemctl enable php-fpm
			systemctl start php-fpm
		fi
	elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
		dnf -y install postgresql-server || exit -1
	fi
}

install_centos()
{
	packagesToInstall="epel-release yum-utils sudo"
	if [[ "$install_type" == "devenv" ]]; then
		# need unzip for devenv, nant buildRelease for bootstrap-4.0.0-dist.zip
		# need git for devenv
		packagesToInstall=$packagesToInstall" git unzip"
	fi
	yum -y install $packagesToInstall || exit -1
	# for printing reports to pdf
	if [[ "`rpm -qa | grep wkhtmltox`" == "" ]]; then
		url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox-0.12.5-1.centos$VER.x86_64.rpm"
		yum -y install $url || exit -1
	fi
	if [[ "$install_type" == "devenv" ]]; then
		# for cypress tests
		yum -y install libXScrnSaver GConf2 Xvfb gtk3 || exit -1
	fi
	# for printing bar codes
	curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/code128.ttf
	if [[ "$install_type" == "devenv" ]]; then
		# for building the js client
		curl --silent --location https://rpm.nodesource.com/setup_10.x  | bash -
		yum -y install nodejs || exit -1
		# for mono development
		yum -y install nant mono-devel mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel || exit -1
	else
		# for mono runtime
		yum -y install mono-mvc mono-wcf mono-data mono-winfx xsp liberation-mono-fonts libgdiplus-devel || exit -1
	fi
	# update the certificates for Mono
	curl https://curl.haxx.se/ca/cacert.pem > ~/cacert.pem && cert-sync ~/cacert.pem
	yum -y install nginx lsb libsodium || exit -1
	if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
		yum -y install mariadb-server || exit -1
		if [[ "$install_type" == "devenv" ]]; then
			# phpmyadmin
			if [[ "`rpm -qa | grep remi-release-$VER`" = "" ]]; then
				yum -y install http://rpms.remirepo.net/enterprise/remi-release-$VER.rpm || exit -1
			fi
			yum-config-manager --enable remi
			yum-config-manager --enable remi-php74 || dnf -y module enable php:remi-7.4
			yum -y install phpMyAdmin php-fpm || exit -1
			sed -i "s#user = apache#user = nginx#" /etc/php-fpm.d/www.conf
			sed -i "s#group = apache#group = nginx#" /etc/php-fpm.d/www.conf
			sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php-fpm.d/www.conf
			sed -i "s#;chdir = /var/www#chdir = /usr/share/phpMyAdmin#" /etc/php-fpm.d/www.conf
			chown nginx:nginx /var/lib/php/session
			systemctl enable php-fpm
			systemctl start php-fpm
		fi
	elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
		yum -y install postgresql-server || exit -1
	fi
}

install_debian()
{
	packagesToInstall="sudo"
	if [[ "$install_type" == "devenv" ]]; then
		# need unzip for devenv, nant buildRelease for bootstrap-4.0.0-dist.zip
		# need git for devenv
		packagesToInstall=$packagesToInstall" git unzip"
	fi
	if [[ "$install_type" == "test" || "$install_type" == "demo" ]]; then
		packagesToInstall=$packagesToInstall" cron"
	fi
	apt-get -y install $packagesToInstall || exit -1
	# for printing reports to pdf
	if [[ "$VER" == "9" ]]; then
		# we need version 0.12.5, not 0.12.3 which is part of stretch.
		url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.stretch_amd64.deb"
		curl --silent --location $url > wkhtmltox_0.12.5-1.stretch_amd64.deb || exit -1
		apt-get -y install ./wkhtmltox_0.12.5-1.stretch_amd64.deb || exit -1
		rm -Rf wkhtmltox_0.12.5-1.stretch_amd64.deb
	else
		apt-get -y install wkhtmltopdf || exit -1
	fi
	if [[ "$install_type" == "devenv" ]]; then
		# for cypress tests
		apt-get -y install libgtk2.0-0 libgtk-3-0 libnotify-dev libgconf-2-4 libnss3 libxss1 libasound2 libxtst6 xauth xvfb gconf2 libgdk-pixbuf2.0-0
	fi
	# for printing bar codes
	curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/truetype/code128.ttf
	if [[ "$install_type" == "devenv" ]]; then

		if [[ "$VER" == "9" ]]; then
			curl --silent --location https://deb.nodesource.com/setup_10.x  | bash -
		fi

		# for building the js client
		apt-get -y install nodejs npm || exit -1
		# for mono development
		if [[ "$VER" == "9" ]]; then
			# for nant
			echo 'deb [arch=amd64] https://lbs.solidcharity.com/repos/tpokorra/nant/debian/stretch stretch main' >> /etc/apt/sources.list
			apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0x4796B710919684AC
			apt-get update
		fi
		if [[ "$VER" == "10" ]]; then
			# for nant
			echo 'deb [arch=amd64] https://lbs.solidcharity.com/repos/tpokorra/nant/debian/buster buster main' >> /etc/apt/sources.list
			apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0x4796B710919684AC
			apt-get update
		fi
	fi
	# For Debian Stretch, get Mono packages compiled by SolidCharity.com, because Debian Stretch only has Mono 4.6
	# the packages from Xamarin/Microsoft will be recompiled, that takes too much time during CI
	if [[ "$VER" == "9" ]]; then
		apt-get -y install apt-transport-https dirmngr gnupg ca-certificates
		apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0x4796B710919684AC
		echo 'deb [arch=amd64] https://lbs.solidcharity.com/repos/tpokorra/mono/debian/stretch stretch main' | sudo tee /etc/apt/sources.list.d/mono-tpokorra.list
		apt-get update
	fi
	if [[ "$install_type" == "devenv" ]]; then
		apt-get -y install nant mono-devel mono-xsp4 mono-fastcgi-server4 ca-certificates-mono xfonts-75dpi fonts-liberation libgdiplus || exit -1
	else
		apt-get -y install mono-xsp4 mono-fastcgi-server4 ca-certificates-mono xfonts-75dpi fonts-liberation libgdiplus || exit -1
	fi
	# to avoid errors like: error CS0433: The imported type `System.CodeDom.Compiler.CompilerError' is defined multiple times
	if [ -f /usr/lib/mono/4.5-api/System.dll -a -f /usr/lib/mono/4.5/System.dll ]; then
		rm -f /usr/lib/mono/4.5-api/System.dll
	fi
	apt-get -y install nginx || exit -1
	if [[ "$VER" == "9" ]]; then
		apt-get -y install libsodium18 || exit -1
	else
		apt-get -y install libsodium23 || exit -1
	fi
	if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
		apt-get -y install mariadb-server || exit -1
		if [[ "$install_type" == "devenv" ]]; then
			echo "TODO: phpmyadmin"
			# phpmyadmin
			#apt-get -y install phpmyadmin php-fpm
			#sed -i "s#user = apache#user = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
			#sed -i "s#group = apache#group = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
			#sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php/7.2/fpm/pool.d/www.conf
			#sed -i "s#;chdir = /var/www#chdir = /usr/share/phpmyadmin#" /etc/php/7.2/fpm/pool.d/www.conf
			#chown nginx:nginx /var/lib/php/session
			#systemctl enable php-fpm
			#systemctl start php-fpm
		fi
	elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
		apt-get -y install postgresql-server || exit -1
	fi
}

install_ubuntu()
{
	packagesToInstall="sudo"
	if [[ "$install_type" == "devenv" ]]; then
		# need unzip for devenv, nant buildRelease for bootstrap-4.0.0-dist.zip
		# need git for devenv
		packagesToInstall=$packagesToInstall" git unzip"
	fi
	if [[ "$install_type" == "test" || "$install_type" == "demo" ]]; then
		packagesToInstall=$packagesToInstall" cron"
	fi

	if [[ ! -z $APPVEYOR_MONO ]]; then
		# On AppVeyor, disable security updates 
		# because that would require to run apt-get update to get latest nginx and mysql packages.
		# but that would lead for mono 6.8 to be downloaded, and that takes quite some time to install (mscorlib is compiled etc).
		sed -i  "/security/s/^/#/" /etc/apt/sources.list

		# move mono repo to separate list, so that we can do an apt-get update without getting latest version of Mono
		cat /etc/apt/sources.list | grep mono > /etc/apt/sources.list.d/mono.list
		sed -i  "/mono/s/^/#/" /etc/apt/sources.list
		apt-get update -o Dir::Etc::sourcelist="sources.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
	fi

	apt-get -y install $packagesToInstall || exit -1
	# for printing reports to pdf
	if [[ "$VER" == "18.04" ]]; then
		# we need version 0.12.5, not 0.12.4 which is part of bionic.
		url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb"
		curl --silent --location $url > wkhtmltox_0.12.5-1.bionic_amd64.deb || exit -1
		apt-get -y install ./wkhtmltox_0.12.5-1.bionic_amd64.deb || exit -1
		rm -Rf wkhtmltox_0.12.5-1.bionic_amd64.deb
	else
		apt-get -y install wkhtmltopdf || exit -1
	fi
	if [[ "$install_type" == "devenv" ]]; then
		# for cypress tests
		apt-get -y install libgtk2.0-0 libgtk-3-0 libnotify-dev libgconf-2-4 libnss3 libxss1 libasound2 libxtst6 xauth xvfb gconf2 libgdk-pixbuf2.0-0  || exit -1
	fi
	# for printing bar codes
	curl --silent --location https://github.com/Holger-Will/code-128-font/raw/master/fonts/code128.ttf > /usr/share/fonts/truetype/code128.ttf
	# Ubuntu Bionic has Mono 4.6, therefore we use our own compiled Mono.
	# Mono compiled by Xamarin takes too much time to install during CI...
	if [[ "$VER" == "18.04" ]]; then
		# if we are not on appveyor with already mono >= 5 installed...
		if [[ "$APPVEYOR_MONO" == "" ]]; then
			apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0x4796B710919684AC
			echo 'deb [arch=amd64] https://lbs.solidcharity.com/repos/tpokorra/mono/ubuntu/bionic bionic main' | sudo tee /etc/apt/sources.list.d/mono-tpokorra.list
			apt-get update
		fi
	fi
	if [[ "$install_type" == "devenv" ]]; then
		# for building the js client
		if [[ "$APPVEYOR_NODE" == "" ]]; then
			apt-get -y install nodejs npm || exit -1
		fi
		apt-get -y install nant mono-devel mono-xsp4 mono-fastcgi-server4 ca-certificates-mono xfonts-75dpi fonts-liberation libgdiplus || exit -1
	else
		apt-get -y install mono-xsp4 mono-fastcgi-server4 ca-certificates-mono xfonts-75dpi fonts-liberation libgdiplus || exit -1
	fi
	# to avoid errors like: error CS0433: The imported type `System.CodeDom.Compiler.CompilerError' is defined multiple times
	if [ -f /usr/lib/mono/4.5-api/System.dll -a -f /usr/lib/mono/4.5/System.dll ]; then
		rm -f /usr/lib/mono/4.5-api/System.dll
	fi
	apt-get -y install libsodium23 lsb || exit -1
	apt-get -y install nginx || exit -1

	if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
		if [[ "$APPVEYOR_MYSQL" == "" ]]; then
			apt-get -y install mariadb-server || exit -1
		fi
		if [[ "$install_type" == "devenv" ]]; then
			echo "TODO: phpmyadmin"
			# phpmyadmin
			#apt-get -y install phpmyadmin php-fpm
			#sed -i "s#user = apache#user = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
			#sed -i "s#group = apache#group = nginx#" /etc/php/7.2/fpm/pool.d/www.conf
			#sed -i "s#listen = 127.0.0.1:9000#listen = 127.0.0.1:8080#" /etc/php/7.2/fpm/pool.d/www.conf
			#sed -i "s#;chdir = /var/www#chdir = /usr/share/phpmyadmin#" /etc/php/7.2/fpm/pool.d/www.conf
			#chown nginx:nginx /var/lib/php/session
			#systemctl enable php-fpm
			#systemctl start php-fpm
		fi
	elif [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
		apt-get -y install postgresql-server || exit -1
	fi
}

install_openpetra()
{
	trap 'echo -e "Aborted, error $? in command: $BASH_COMMAND"; trap ERR; exit 1' ERR
	install_type="$1"

	export OPENPETRA_DBPWD="`generatepwd`"

	while [ $# -gt 0 ]; do
		case "$1" in
			--git_url=*)
				export GIT_URL="${1#*=}"
				;;
			--branch=*)
				export OPENPETRA_BRANCH="${1#*=}"
				;;
			--dbms=*)
				export OPENPETRA_RDBMSType="${1#*=}"
				;;
			--url=*)
				export OPENPETRA_URL="${1#*=}"
				;;
			--emaildomain=*)
				export OPENPETRA_EMAILDOMAIN="${1#*=}"
				;;
			--instance=*)
				export OP_CUSTOMER="${1#*=}"
				;;
		esac
		shift
	done

	if [[ "$OPENPETRA_RDBMSType" == "postgresql" ]]; then
		OPENPETRA_DBPORT=5432
		OPENPETRA_DBHOST=localhost
	fi

	# Valid install type is required
	if [[ "$install_type" != "devenv" && "$install_type" != "test" && "$install_type" != "prod" && "$install_type" != "demo" && "$install_type" != "old" ]]; then
		echo "You must specify the install type:"
		echo "  devenv: install a development environment for OpenPetra"
		echo "  test: install an environment to test OpenPetra"
		echo "  demo: install a demo server with OpenPetra (only supported on CentOS)"
		echo "  prod: install a production server with OpenPetra"
		return 9
	fi

	# just for documentation
	#if [[ "$install_type" == "reset" ]]; then
	#	systemctl stop openpetra && userdel openpetra && userdel op_test && rm -Rf /home/*
	#fi

	# We don't run with SELinux for the moment
	if [ -f /usr/sbin/sestatus ]; then
		if [[ "`sestatus | grep -E 'disabled|permissive'`" == "" ]]; then
			echo "SELinux is active, please set it to permissive"
			exit 1
		fi
	fi

	# you need to run as root
	if [[ "`whoami`" != "root" ]]; then
		echo "You need to run this script as root, or with sudo"
		exit 1
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
			if [[ "$VER" != "7" && "$VER" != "8" && "$VER" != "31" && "$VER" != "32" ]]; then
				echo "Aborted, Your distro version is not supported: " $OS $VER
				return 6
			fi
		fi

		if [[ "$OS_FAMILY" == "Debian" ]]; then
			if [[ "$VER" != "9" && "$VER" != "10" && "$VER" != "18.04"  && "$VER" != "19.10" && "$VER" != "20.04" ]]; then
				echo "Aborted, Your distro version is not supported: " $OS $VER
				return 6
			fi
		fi
	else
		echo "Aborted, Your distro could not be recognised."
		return 6
	fi

	if [[ "$OS" == "Fedora" ]]; then
		install_fedora
	elif [[ "$OS" == "CentOS" ]]; then
		install_centos
	elif [[ "$OS" == "Debian" ]]; then
		install_debian
	elif [[ "$OS" == "Ubuntu" ]]; then
		install_ubuntu
	fi

	if [[ "$OPENPETRA_RDBMSType" == "mysql" ]]; then
		if [ -z $MYSQL_ROOT_PWD ]; then
			export MYSQL_ROOT_PWD="`generatepwd`"
			echo "generated mysql root password: $MYSQL_ROOT_PWD"
			systemctl start mariadb
			systemctl enable mariadb
			mysqladmin -u root password "$MYSQL_ROOT_PWD" || exit 1
		fi
	fi

	#####################################
	# Setup the development environment #
	#####################################
	if [[ "$install_type" == "devenv" ]]; then
		if [ -z $OP_CUSTOMER ]; then
			export OP_CUSTOMER=op_dev
		fi
		export OPENPETRA_USER=$OP_CUSTOMER
		export OPENPETRA_DBNAME=$OP_CUSTOMER
		export OPENPETRA_DBUSER=$OP_CUSTOMER
		export OPENPETRA_SERVERNAME=$OPENPETRA_USER.localhost
		export OPENPETRA_HOME=/home/$OPENPETRA_USER
		export SRC_PATH=$OPENPETRA_HOME/openpetra
		export OPENPETRA_SERVER_BIN=$OPENPETRA_HOME/openpetra-server.sh
		export OPENPETRA_SERVICE_FILE=$SRC_PATH/setup/petra0300/linuxserver/$OPENPETRA_RDBMSType/openpetra.service
		export NGINX_TEMPLATE_FILE=$SRC_PATH/setup/petra0300/linuxserver/nginx.conf
		export TEMPLATES_PATH=$SRC_PATH/setup/petra0300/linuxserver

		if [ ! -z "$APPVEYOR" ]; then
			if [ -d /home/appveyor/projects/openpetra ]; then
				mkdir -p $SRC_PATH
				cp -R /home/appveyor/projects/openpetra/* $SRC_PATH
			fi
		fi

		if [ ! -d $SRC_PATH ]
		then
			git clone --depth 50 $GIT_URL -b $OPENPETRA_BRANCH $SRC_PATH
			#if you want a full repository clone:
			#git config remote.origin.fetch +refs/heads/*:refs/remotes/origin/*
			#git fetch --unshallow
		fi
		cd $SRC_PATH

		# configure openpetra (mono process)
		openpetra_conf
		openpetra_conf_devenv

		# configure nginx
		nginx_conf /etc/nginx/conf.d/$OP_CUSTOMER.conf

		chown -R $OPENPETRA_USER:openpetra $OPENPETRA_HOME

		# configure database
		su $OPENPETRA_USER -c "nant generateTools createSQLStatements" || exit -1
		OP_CUSTOMER=$OPENPETRA_USER MYSQL_ROOT_PWD="$MYSQL_ROOT_PWD" $OPENPETRA_SERVER_BIN initdb || exit -1
		su $OPENPETRA_USER -c "nant recreateDatabase resetDatabase" || exit -1

		su $OPENPETRA_USER -c "nant generateSolution" || exit -1
		su $OPENPETRA_USER -c "nant install.net -D:with-restart=false" || exit -1
		if [[ -z $APPVEYOR_MONO ]]; then
			su $OPENPETRA_USER -c "nant install.js" || exit -1
		fi

		# for fixing issues on CentOS, pushing to upstream branches
		git config --global push.default simple
		su $OPENPETRA_USER -c "git config --global push.default simple"

		# for the cypress test environment
		if [[ -z $APPVEYOR_MONO ]]; then
			su $OPENPETRA_USER -c "cd js-client && CI=1 npm install cypress@4.3.0 --save --save-exact --quiet" || exit -1
		fi

		# download and restore demo database
		demodbfile=$OPENPETRA_HOME/demoWith1ledger.yml.gz
		curl --silent --location https://github.com/openpetra/demo-databases/raw/master/demoWith1ledger.yml.gz > $demodbfile
		OP_CUSTOMER=$OPENPETRA_USER $OPENPETRA_SERVER_BIN loadYmlGz $demodbfile || exit -1

		systemctl restart openpetra
		systemctl restart nginx

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

	##############################
	# Setup the test environment #
	##############################
	if [[ "$install_type" == "test" ]]; then
		if [ -z $OP_CUSTOMER ]; then
			export OP_CUSTOMER=op_test
		fi
		export OPENPETRA_DBNAME=$OP_CUSTOMER
		export OPENPETRA_DBUSER=$OP_CUSTOMER
		export OPENPETRA_USER=openpetra
		export OPENPETRA_SERVERNAME=$OP_CUSTOMER.localhost
		export OPENPETRA_HOME=/home/$OPENPETRA_USER
		export SRC_PATH=/home/$OPENPETRA_USER
		export OPENPETRA_SERVER_BIN=$OPENPETRA_HOME/openpetra-server.sh
		export TEMPLATES_PATH=$SRC_PATH/templates
		export OPENPETRA_SERVICE_FILE=$TEMPLATES_PATH/openpetra.service
		export NGINX_TEMPLATE_FILE=$TEMPLATES_PATH/nginx.conf

		# get the binary tarball
		if [ ! -f openpetra-latest-bin.tar.gz ]; then
			curl --silent --location https://get.openpetra.org/openpetra-latest-bin.tar.gz > openpetra-latest-bin.tar.gz
		fi

		rm -Rf openpetra-2*
		tar xzf openpetra-latest-bin.tar.gz

		# configure openpetra (mono process)
		openpetra_conf

		# configure nginx
		nginx_conf /etc/nginx/conf.d/$OP_CUSTOMER.conf

		chown -R $OPENPETRA_USER:openpetra $OPENPETRA_HOME

		userName=$OPENPETRA_USER $OPENPETRA_SERVER_BIN init || exit -1
		$OPENPETRA_SERVER_BIN initdb || exit -1

		systemctl restart openpetra
		systemctl restart nginx

		# setup backup of all openpetra databases each night
		crontab -l | { cat; echo "45 0 * * * $OPENPETRA_SERVER_BIN backupall"; } | crontab -

		echo "Go and check your instance at $OPENPETRA_URL"
		echo "login with user SYSADMIN and password CHANGEME."
	fi

	##############################
	# Setup the demo environment #
	##############################
	if [[ "$install_type" == "demo" ]]; then

		if [[ "$OS" != "CentOS" ]]; then
			echo "Aborted, Your distro is not supported for demo installation: " $OS
			return 6
		fi

		if [ -z $OP_CUSTOMER ]; then
			export OP_CUSTOMER=op_demo
		fi
		export OPENPETRA_DBNAME=$OP_CUSTOMER
		export OPENPETRA_DBUSER=$OP_CUSTOMER
		export OPENPETRA_USER=openpetra
		export OPENPETRA_SERVERNAME=$OP_CUSTOMER.localhost
		export OPENPETRA_HOME=/home/$OPENPETRA_USER
		export SRC_PATH=/home/$OPENPETRA_USER
		export OPENPETRA_SERVER_BIN=$OPENPETRA_HOME/openpetra-server.sh
		export TEMPLATES_PATH=$SRC_PATH/templates
		export NGINX_TEMPLATE_FILE=$TEMPLATES_PATH/nginx.conf

		# setup the repository for the openpetranow-mysql-test rpm file
		# see https://lbs.solidcharity.com/package/solidcharity/openpetra/openpetranow-mysql-test
		cd /etc/yum.repos.d
		repourl=https://lbs.solidcharity.com/repos/solidcharity/openpetra/centos/7/lbs-solidcharity-openpetra.repo
		repofile=`basename $repourl`
		if [ ! -f $repofile ]
		then
		  curl -L $repourl -o $repofile
		fi
		sed -i "s/^enabled.*/enabled = 0/g" $repofile
		cd -

		yum -y install --enablerepo="lbs-solidcharity-openpetra" openpetranow-mysql-test || exit -1

		# configure nginx
		nginx_conf /etc/nginx/conf.d/$OP_CUSTOMER.conf

		userName=$OPENPETRA_USER $OPENPETRA_SERVER_BIN init || exit -1
		$OPENPETRA_SERVER_BIN initdb || exit -1

		# download and restore demo database
		demodbfile=$OPENPETRA_HOME/demoWith1ledger.yml.gz
		curl --silent --location https://github.com/openpetra/demo-databases/raw/master/demoWith1ledger.yml.gz > $demodbfile
		$OPENPETRA_SERVER_BIN loadYmlGz $demodbfile || exit -1

		chmod a+w /home/$OP_CUSTOMER/log/Server.log

		# setup restore of demo database each night
		crontab -l | { cat; echo "55 0 * * * OP_CUSTOMER=$OP_CUSTOMER $OPENPETRA_SERVER_BIN loadYmlGz $demodbfile"; } | crontab -

		systemctl restart openpetra
		systemctl restart nginx

		echo "Go and check your instance at $OPENPETRA_URL"
		echo "login with user DEMO and password demo, or user SYSADMIN and password CHANGEME."
	fi

	##############################
	# Setup the previous version #
	##############################
	if [[ "$install_type" == "old" ]]; then

		if [[ "$OS" != "CentOS" ]]; then
			echo "Aborted, Your distro is not supported for old installation: " $OS
			return 6
		fi

		if [ -z $OP_CUSTOMER ]; then
			export OP_CUSTOMER=op_test
		fi
		export OPENPETRA_DBNAME=$OP_CUSTOMER
		export OPENPETRA_DBUSER=$OP_CUSTOMER
		export OPENPETRA_USER=openpetra
		export OPENPETRA_SERVERNAME=$OP_CUSTOMER.localhost
		export OPENPETRA_HOME=/home/$OPENPETRA_USER
		export SRC_PATH=/home/$OPENPETRA_USER
		export OPENPETRA_SERVER_BIN=$OPENPETRA_HOME/openpetra-server.sh
		export TEMPLATES_PATH=$SRC_PATH/templates
		export NGINX_TEMPLATE_FILE=$TEMPLATES_PATH/nginx.conf
		export OLDVERSION="2020.04.0-3"
		export TagDemoDB="UsedForNUnitTests-202004"

		# setup the repository for the openpetranow-mysql-test rpm file
		# see https://lbs.solidcharity.com/package/solidcharity/openpetra/openpetranow-mysql-test
		cd /etc/yum.repos.d
		repourl=https://lbs.solidcharity.com/repos/solidcharity/openpetra/centos/7/lbs-solidcharity-openpetra.repo
		repofile=`basename $repourl`
		if [ ! -f $repofile ]
		then
		  curl -L $repourl -o $repofile
		fi
		sed -i "s/^enabled.*/enabled = 0/g" $repofile
		cd -

		yum -y install --enablerepo="lbs-solidcharity-openpetra" openpetranow-mysql-test-$OLDVERSION.x86_64 || exit -1

		# configure nginx
		nginx_conf /etc/nginx/conf.d/$OP_CUSTOMER.conf

		userName=$OPENPETRA_USER $OPENPETRA_SERVER_BIN init || exit -1
		$OPENPETRA_SERVER_BIN initdb || exit -1

		# download and restore demo database
		demodbfile=$OPENPETRA_HOME/demoWith1ledger.yml.gz
		curl --silent --location https://github.com/openpetra/demo-databases/raw/$TagDemoDB/demoWith1ledger.yml.gz > $demodbfile
		$OPENPETRA_SERVER_BIN loadYmlGz $demodbfile || exit -1

		chmod a+w /home/$OP_CUSTOMER/log/Server.log

		systemctl restart openpetra
		systemctl restart nginx

		echo "Go and check your instance at $OPENPETRA_URL"
		echo "login with user DEMO and password demo, or user SYSADMIN and password CHANGEME."
	fi
}


install_openpetra "$@"
