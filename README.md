OpenPetra Installer Script
==========================

* Homepage: https://www.openpetra.org
* Issues:   https://github.com/openpetra/getopenpetra/issues
* Requires: bash, curl, sudo (if not root), tar

This script installs OpenPetra on your Linux system.

Please only run this script on a clean system, since it might destroy
other applications already running on this server.

You have various options, to install a development environment, or to 
install a test environment, or to install a production environment.

	$ curl https://get.openpetra.org | bash -s devenv
	 or
	$ wget -qO- https://get.openpetra.org | bash -s devenv

The syntax is:

	bash -s [devenv|test|prod]

available options:

     --git_url=<http git url>
            default is: --git_url=https://github.com/openpetra/openpetra.git
     --branch=<branchname>
            default is: --branch=test
     --dbms=<dbms>
            default is: --dbms=mysql
            other options: postgresql
     --url=<outside url>
            default is: --url=http://localhost
            for demo: --url=https://demo.openpetra.org
     --emaildomain=<your email domain, used for noreply sender address>
            default is: --emaildomain=myexample.org
            for demo: --emaildomain=openpetra.org
     --instance=<instance>
            default is: --instance=op_dev for devenv, --instance=op_test for test

If you purchased a commercial license, you must set your account
ID and API key in environment variables:

	$ export OPENPETRA_ACCOUNT_ID=...
	$ export OPENPETRA_API_KEY=...

Then you can request a commercially-licensed download:

	$ curl https://get.openpetra.org | bash -s prod

This should work on CentOS Stream 9, Fedora 41, Ubuntu 24.04 (Noble Numbat), and Debian 12 (Bookworm).

Please open an issue if you notice any bugs.
