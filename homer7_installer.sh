#!/bin/bash
#
# --------------------------------------------------------------------------------
# HOMER/SipCapture automated installation script for Debian/CentOs/OpenSUSE (BETA)
# --------------------------------------------------------------------------------
# This script is only intended as a quickstart to test and get familiar with HOMER.
# It is not suitable for high-traffic nodes, complex capture scenarios, clusters.
# The HOW-TO should be ALWAYS followed for a fully controlled, manual installation!
# --------------------------------------------------------------------------------
#
#  Copyright notice:
#
#  (c) 2011-2016 Lorenzo Mangani <lorenzo.mangani@gmail.com>
#  (c) 2011-2016 Alexandr Dubovikov <alexandr.dubovikov@gmail.com>
#
#  All rights reserved
#
#  This script is part of the HOMER project (http://sipcapture.org)
#  The HOMER project is free software; you can redistribute it and/or 
#  modify it under the terms of the GNU Affero General Public License as 
#  published by the Free Software Foundation; either version 3 of 
#  the License, or (at your option) any later version.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#

#####################################################################
#                                                                   #
#  WARNING: THIS SCRIPT IS NOW UPDATED TO SUPPORT HOMER 5.x         #
#           PLEASE USE WITH CAUTION AND HELP US BY REPORTING BUGS!  #
#                                                                   #
#####################################################################

[[ "$TRACE" ]] && { set -x; set -o functrace; }

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

logfile="/tmp/$(basename $0).$$.log"
exec > >(tee -ia $logfile)
exec 2> >(tee -ia $logfile >&2)

trap 'exit 1' TERM
my_pid=$$


# HOMER Options, defaults
DB_USER="homer"
DB_PASS="v3tevjaqf9krwxd"
DB_HOST="localhost"
LISTEN_PORT="9060"

GO_VERSION="1.12.4"
OS=`uname -s`
HOME_DIR=$HOME
GO_HOME=$HOME_DIR/go
GO_ROOT=/usr/local/go
ARCH=`uname -m`




#### NO CHANGES BELOW THIS LINE! 

DB_ADMIN_USER="root"
DB_ADMIN_PASS=""
DB_ADMIN_TEMP_PASS=""

VERSION=7.0
SETUP_ENTRYPOINT=""
OS=""
DISTRO=""
DISTRO_VERSION=""
WEB_ROOT=""
KAMAILIO_VERSION="5"

######################################################################
#
# Start of function definitions
#
######################################################################
is_root_user() {
  # Function to check that the effective user id of the user running
  # the script is indeed that of the root user (0)

  if [[ $EUID != 0 ]]; then
    return 1
  fi
  return 0
}


install_golang() {
	echo
	# Check if there's any older version of GO installed on the machine.
	if [ -d /usr/local/go ]; then
		echo "...... [ Found an older version of GO ]"
		printf "Would you like to remove it? [y/N]: "
		read ans
		case "$ans" in
			"y"|"yes"|"Y"|"Yes"|"YES") rm -rf /usr/local/go;;
			*) echo "...... [ Exiting ]"; exit 0;;
		esac
	fi
	# If the operating system is 64-bit Linux
	if [ "$OS" == "Linux" ] && [ "$ARCH" == "x86_64" ]; then
		PACKAGE=go$GO_VERSION.linux-amd64.tar.gz
		pushd /tmp > /dev/null
		echo
		wget --no-check-certificate https://storage.googleapis.com/golang/$PACKAGE
		if [ $? -ne 0 ]; then
			echo "Failed to Download the package! Exiting."
			exit 1
		fi
		tar -C /usr/local -xzf $PACKAGE
		rm -rf $PACKAGE
		popd > /dev/null
		setup
		exit 0
	fi
	setup
}

setup() {
	# Create GOHOME and the required directories
	if [ ! -d $GO_HOME ]; then
		mkdir $GO_HOME
		mkdir -p $GO_HOME/{src,pkg,bin}
	else
		mkdir -p $GO_HOME/{src,pkg,bin}
	fi
	if [ "$OS" == "Linux" ] && [ "$ARCH" == "x86_64" ]; then
		grep -q -F 'export GOPATH=$HOME/go' $HOME/.bashrc || echo 'export GOPATH=$HOME/go' >> $HOME/.bashrc
		grep -q -F 'export GOROOT=/usr/local/go' $HOME/.bashrc || echo 'export GOROOT=/usr/local/go' >> $HOME/.bashrc
		grep -q -F 'export PATH=$PATH:$GOROOT/bin' $HOME/.bashrc || echo 'export PATH=$PATH:$GOROOT/bin' >> $HOME/.bashrc
		grep -q -F 'export PATH=$PATH:$GOPATH/bin' $HOME/.bashrc || echo 'export PATH=$PATH:$GOPATH/bin' >> $HOME/.bashrc
	fi
	
	#PATH="$PATH:/usr/local/go/bin"
}


have_commands() {
	# Function to check if we can find the command(s) passed to us
	# in the systems PATH

	local cmd_list="$1"
	local -a not_found=() 

	for cmd in $cmd_list; do
		command -v $cmd >/dev/null 2>&1 || not_found+=("$cmd")
	done

	if [[ ${#not_found[@]} == 0 ]]; then
		# All commands found
		return 0
	else
		# Something not found
		return 1
	fi
}

locate_cmd() {
	# Function to return the full path to the cammnd passed to us
	# Make sure it exists on the system first or else this exits
	# the script execution

	local cmd="$1"
	local valid_cmd=""

	# valid_cmd=$(hash -t $cmd 2>/dev/null)
	valid_cmd=$(command -v $cmd 2>/dev/null)
  if [[ ! -z "$valid_cmd" ]]; then
    echo "$valid_cmd"
  else
    echo "HALT: Please install package for command '$cmd'"
    /bin/kill -s TERM $my_pid
  fi
  return 0
}

is_supported_os() {
  # Function to see if the OS is a supported type, the 1st 
  # parameter passed should be the OS type to check. The bash 
  # shell has a built in variable "OSTYPE" which should be 
  # sufficient for a start

  local os_type=$1

  case "$os_type" in
    linux* ) OS="Linux"
             minimal_command_list="lsb_release wget curl dirmngr git"
             if ! have_commands "$minimal_command_list"; then
               echo "ERROR: You need the following minimal set of commands installed:"
               echo ""
               echo "       $minimal_command_list"
               echo ""
               exit 1
             fi
             detect_linux_distribution # Supported OS, Check if supported distro.
             return ;;  
    *      ) return 1 ;;               # Unsupported OS
  esac
}

detect_linux_distribution() {
  # Function to see if a specific linux distribution is supported by this script
  # If it is supported then the global variable SETUP_ENTRYPOINT is set to the 
  # function to be executed for the system setup

  local cmd_lsb_release=$(locate_cmd "lsb_release")
  local distro_name=$($cmd_lsb_release -si)
  local distro_version=$($cmd_lsb_release -sr)
  DISTRO="$distro_name"
  DISTRO_VERSION="$distro_version"

  case "$distro_name" in
    Debian ) case "$distro_version" in
               9* ) SETUP_ENTRYPOINT="setup_debian_9"
                    return 0 ;; # Suported Distribution
               *  ) return 1 ;; # Unsupported Distribution
             esac
             ;;
    CentOS ) case "$distro_version" in
               7* ) SETUP_ENTRYPOINT="setup_centos_7"
                    return 0 ;; # Suported Distribution
               *  ) return 1 ;; # Unsupported Distribution
             esac
             ;;
    *      ) return 1 ;; # Unsupported Distribution
 esac
}

check_status() {
  # Function to check and do something with the return code of some command

  local return_code="$1"

  if [[ $return_code != 0 ]]; then
    echo "HALT: Return code of command was '$return_code', aborting."
    echo "Please check the log above and correct the issue."
    exit 1
  fi
}

repo_clone_or_update() {
  # Function to clone a repository or update if it already exists locally
  local base_dir=$1
  local dest_dir=$2
  local git_repo=$3
  local git_branch=${4:-"origin/master"}
  local cmd_git=$(locate_cmd "git")

  if [ -d "$base_dir" ]; then
    cd "$base_dir"
    if [ -d "$dest_dir" ]; then
      cd $dest_dir
      # $cmd_git pull
      $cmd_git fetch --all
      $cmd_git reset --hard "$git_branch"
      check_status "$?"
    else
      $cmd_git clone --depth 1 "$git_repo" "$dest_dir"
      check_status "$?"
    fi
    return 0
  else
    return 1
  fi
}


create_heplify_service() {
  local sys_systemd_base='/lib/systemd/system'
  local usr_systemd_base='/etc/systemd/system'
  local sys_heplify_svc='heplify.service'
  local sys_postgresql_svc=''

  local cmd_systemctl=$(locate_cmd "systemctl")
  local cmd_cat=$(locate_cmd "cat")
  local cmd_mkdir=$(locate_cmd "mkdir")

  if [ -d $sys_systemd_base ]; then
    if [ -f $sys_systemd_base/postgresql.service ]; then
      sys_postgresql_svc=postgresql.service
    fi

    if [ ! -f $sys_systemd_base/$sys_heplify_svc ]; then
      $cmd_cat << __EOFL__ > $sys_systemd_base/$sys_heplify_svc
[Unit]
Description=HEP Server & Switch in Go
After=network.target

[Service]
WorkingDirectory=/opt/heplify-server
ExecStart=/opt/heplify-server/heplify-server
ExecStop=/bin/kill \${MAINPID}
Restart=on-failure
RestartSec=10s
Type=simple

[Install]
WantedBy=multi-user.target
__EOFL__
      check_status "$?"
    fi
    if [ ! -d $usr_systemd_base/${sys_heplify_svc}.d ]; then
      $cmd_mkdir -m 0755 -p $usr_systemd_base/${sys_heplify_svc}.d
      check_status "$?"
    fi
    if [ ! -f $usr_systemd_base/${sys_heplify_svc}.d/require_postgresql.conf ] && \
       [ ! -z "$sys_postgresql_svc" ]; then
      $cmd_cat << __EOFL__ > $usr_systemd_base/${sys_heplify_svc}.d/require_postgresql.conf
[Unit]
After= $sys_postgresql_svc
__EOFL__
      check_status "$?"
    fi
    $cmd_systemctl daemon-reload
    check_status "$?"
    $cmd_systemctl enable $sys_heplify_svc 
    check_status "$?"
    $cmd_systemctl start $sys_heplify_svc 
    check_status "$?"
  fi
}


create_homer_app_service() {
  local sys_systemd_base='/lib/systemd/system'
  local usr_systemd_base='/etc/systemd/system'
  local sys_homerapp_svc='homerapp.service'
  local sys_postgresql_svc=''

  local cmd_systemctl=$(locate_cmd "systemctl")
  local cmd_node=$(locate_cmd "node")
  local cmd_cat=$(locate_cmd "cat")
  local cmd_mkdir=$(locate_cmd "mkdir")

  if [ -d $sys_systemd_base ]; then
    if [ -f $sys_systemd_base/postgresql.service ]; then
      sys_postgresql_svc=postgresql.service
    fi

    if [ ! -f $sys_systemd_base/$sys_homerapp_svc ]; then
      $cmd_cat << __EOFL__ > $sys_systemd_base/$sys_homerapp_svc
[Unit]
Description=Homer App Server
ConditionPathExists=/opt/homer-app/

[Service]
WorkingDirectory=/opt/homer-app/
ExecStart=$cmd_node bootstrap.js
User=root
Group=root
# Required on some systems
#WorkingDirectory=/opt/nodeserver
Restart=always
# Restart service after 10 seconds if node service crashes
RestartSec=10
# Output to syslog
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=homer-app
#User=<alternate user>
#Group=<alternate group>
#Environment=NODE_ENV=production PORT=1337

[Install]
WantedBy=multi-user.target
__EOFL__
      check_status "$?"
    fi
    if [ ! -d $usr_systemd_base/${sys_homerapp_svc}.d ]; then
      $cmd_mkdir -m 0755 -p $usr_systemd_base/${sys_homerapp_svc}.d
      check_status "$?"
    fi
    if [ ! -f $usr_systemd_base/${sys_heplify_svc}.d/require_postgresql.conf ] && \
       [ ! -z "$sys_postgresql_svc" ]; then
      $cmd_cat << __EOFL__ > $usr_systemd_base/${sys_homerapp_svc}.d/require_postgresql.conf
[Unit]
After= $sys_postgresql_svc
__EOFL__
      check_status "$?"
    fi
    $cmd_systemctl daemon-reload
    check_status "$?"
    $cmd_systemctl enable $sys_homerapp_svc
    check_status "$?"
    $cmd_systemctl start $sys_homerapp_svc
    check_status "$?"
  fi
}


banner_start() {
  # This is the banner displayed at the start of script execution

  clear;
  echo "**************************************************************"
  echo "                                                              "
  echo "      ,;;;;;,       HOMER SIP CAPTURE (http://sipcapture.org) "
  echo "     ;;;;;;;;;.     Single-Node Auto-Installer (beta $VERSION)"
  echo "   ;;;;;;;;;;;;;                                              "
  echo "  ;;;;  ;;;  ;;;;   <--------------- INVITE ---------------   "
  echo "  ;;;;  ;;;  ;;;;    --------------- 200 OK --------------->  "
  echo "  ;;;;  ...  ;;;;                                             "
  echo "  ;;;;       ;;;;   WARNING: This installer is intended for   "
  echo "  ;;;;  ;;;  ;;;;   dedicated/vanilla OS setups without any   "
  echo "  ,;;;  ;;;  ;;;;   customization and with default settings   "
  echo "   ;;;;;;;;;;;;;                                              "
  echo "    :;;;;;;;;;;     THIS SCRIPT IS PROVIDED AS-IS, USE AT     "
  echo "     ^;;;;;;;^      YOUR *OWN* RISK, REVIEW LICENSE & DOCS    "
  echo "                                                              "
  echo "**************************************************************"
  echo;
}

banner_end() {
  # This is the banner displayed at the end of script execution

  local cmd_ip=$(locate_cmd "ip")
  local cmd_head=$(locate_cmd "head")
  local cmd_awk=$(locate_cmd "awk")

  local my_primary_ip=$($cmd_ip route get 8.8.8.8 | $cmd_head -1 | $cmd_awk '{ print $NF }')

  echo "*************************************************************"
  echo "      ,;;;;,                                                 "
  echo "     ;;;;;;;;.     Congratulations! HOMER has been installed!"
  echo "   ;;;;;;;;;;;;                                              "
  echo "  ;;;;  ;;  ;;;;   <--------------- INVITE ---------------   "
  echo "  ;;;;  ;;  ;;;;    --------------- 200 OK --------------->  "
  echo "  ;;;;  ..  ;;;;                                             "
  echo "  ;;;;      ;;;;   Your system should be now ready to rock!"
  echo "  ;;;;  ;;  ;;;;   Please verify/complete the configuration  "
  echo "  ,;;;  ;;  ;;;;   files generated by the installer below.   "
  echo "   ;;;;;;;;;;;;                                              "
  echo "    :;;;;;;;;;     THIS SCRIPT IS PROVIDED AS-IS, USE AT     "
  echo "     ;;;;;;;;      YOUR *OWN* RISK, REVIEW LICENSE & DOCS    "
  echo "                                                             "
  echo "*************************************************************"
  echo
  echo "     * Verify configuration for HOMER-API:"
  echo "         '$WEB_ROOT/api/configuration.php'"
  echo "         '$WEB_ROOT/api/preferences.php'"
  echo
  echo "     * Start/stop Homer SIP Capture:"
  echo "         'systemtcl start|stop heplify'"
  echo
  echo "     * Access HOMER UI:"
  echo "         http://$my_primary_ip"
  echo "         [default: admin/sipcapture]"
  echo
  echo "     * Send HEP/EEP Encapsulated Packets:"
  echo "         hep://$my_primary_ip:$LISTEN_PORT"
  echo
  echo "**************************************************************"
  echo
  echo " IMPORTANT: Do not forget to send Homer node some traffic! ;) "
  echo " For our capture agents, visit http://github.com/sipcapture "
  echo " For more help and information visit: http://sipcapture.org "
  echo
  echo "**************************************************************"
  echo " Installer Log saved to: $logfile "
  echo
}

start_app() {
  # This is the main app

  banner_start

  if ! is_root_user; then
    echo "ERROR: You must be the root user. Exiting..." 2>&1
    echo  2>&1
    exit 1
  fi

  if ! is_supported_os "$OSTYPE"; then
    echo "ERROR:"
    echo "Sorry, this Installer does not support your OS yet!"
    echo "Please follow instructions in the HOW-TO for manual installation & setup"
    echo "available at http://sipcapture.org"
    echo
    exit 1
  else
    unalias cp 2>/dev/null
    $SETUP_ENTRYPOINT
    banner_end
  fi
  exit 0
}

install_npm(){
	local cmd_curl=$(locate_cmd "curl")
  	local cmd_apt_key=$(locate_cmd "apt-key")
	$cmd_apt_key -sL https://deb.nodesource.com/setup_10.x | bash -
	$cmd_apt_key install -y nodejs
}

create_postgres_user_database(){
	su -c "psql  -c \"create user $DB_USER with password '$DB_PASS'\"" postgres
	su -c "psql  -c \"create database homer_config\"" postgres
	su -c "psql  -c \"create database homer_data\"" postgres
	su -c "psql  -c \"GRANT ALL PRIVILEGES ON DATABASE \"homer_config\" to $DB_USER;\"" postgres
	su -c "psql  -c \"GRANT ALL PRIVILEGES ON DATABASE \"homer_data\" to $DB_USER;\"" postgres
}


install_heplify_server(){
  local cmd_go=$(locate_cmd "go")
  local cmd_cp=$(locate_cmd "cp")
  local cmd_sed=$(locate_cmd "sed")
  local cmd_cd=$(locate_cmd "cd")
  local src_base_dir="/opt/"
  local src_heplify_dir="heplify-server"
  repo_clone_or_update "$src_base_dir" "$src_heplify_dir" "https://github.com/sipcapture/heplify-server"

  $cmd_cd "$src_base_dir/$src_heplify_dir/"
  $cmd_cp -f "$src_base_dir/$src_heplify_dir/example/homer7_config/heplify-server.toml" "./"
  $cmd_sed -i -e "s/DBUser          = \"postgres\"/DBUser          = \"$DB_USER\"/g" heplify-server.toml
  $cmd_sed -i -e "s/DBPass          = \"\"/DBPass          = \"$DB_PASS\"/g" heplify-server.toml
  $cmd_go build "cmd/heplify-server/heplify-server.go"
  create_heplify_service
}


install_homer_app(){
	local cmd_npm=$(locate_cmd "npm")
	local src_base_dir="/opt/"
	local src_homer_app_dir="homer-app"
	repo_clone_or_update "$src_base_dir" "$src_homer_app_dir" "https://github.com/sipcapture/homer-app"
	cd "$src_base_dir/$src_homer_app_dir"
	sed -i -e "s/homer_user/$DB_USER/g" "$src_base_dir/$src_homer_app_dir/server/config.js"
	sed -i -e "s/homer_password/$DB_PASS/g" "$src_base_dir/$src_homer_app_dir/server/config.js"
	$cmd_npm install && $cmd_npm install -g knex eslint eslint-plugin-html eslint-plugin-json eslint-config-google
	local cmd_knex=$(locate_cmd "knex")
	$cmd_knext migrate:latest
	$cmd_knext migrate:latest
	$cmd_npm run build
	create_homer_app_service
}


setup_centos_7() {
  # This is the main entrypoint for setup of sipcapture/homer on a CentOS 7
  # system

  local base_pkg_list="wget curl mlocate"
  local src_base_dir="/usr/src"

  local cmd_yum=$(locate_cmd "yum")
  local cmd_wget=$(locate_cmd "wget")
  local cmd_service=$(locate_cmd "systemctl")
  
  $cmd_yum install -y $base_pkg_list

  $cmd_curl -sL https://rpm.nodesource.com/setup_10.x | bash -

  $cmd_yum -q -y install "https://download.postgresql.org/pub/repos/yum/11/redhat/rhel-7-x86_64/pgdg-centos11-11-2.noarch.rpm"
  $cmd_yum install -y postgresql10-server postgresql10
  #lets find the file to initialize the service
  updatedb
  local cmd_locatepostgre="$(locate postgresql-11-setup)"
  $cmd_locatepostgre initdb
  $cmd_service start postgresql-10
  $cmd_service enable postgresql-10
  create_postgres_user_database
  install_golang
  install_heplify_server
  install_homer_app
}



setup_debian_9() {

  local base_pkg_list="software-properties-common make cmake gcc g++"
        local -a repo_keys=(
        'postgres|ACCC4CF8'
        )

  local src_base_dir="/usr/src"
  local cmd_apt_get=$(locate_cmd "apt-get")
  local cmd_apt_key=$(locate_cmd "apt-key")
  local cmd_service=$(locate_cmd "systemctl")
  local cmd_curl=$(locate_cmd "curl")
  local cmd_rm=$(locate_cmd "rm")
  local cmd_ln=$(locate_cmd "ln")

  $cmd_apt_get install -y $base_pkg_list

  $cmd_curl -sL https://deb.nodesource.com/setup_10.x | bash -
  $cmd_apt_get install -y nodejs


  echo "deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" > /etc/apt/sources.list.d/postgresql.list

  local original_ifs=$IFS
  IFS=$'|'
  for key_info in "${repo_keys[@]}"; do
          read -r repo key <<< "$key_info"
          $cmd_apt_key adv --recv-keys --keyserver hkp://ha.pool.sks-keyservers.net:80 $key
          #echo $killer
  done
  IFS=$original_ifs

  $cmd_apt_get update -qq
  
  $cmd_apt_get install -y postgresql-10 $base_pkg_list

  $cmd_service start postgresql

  create_postgres_user_database
  install_golang
  install_heplify_server
  install_homer_app
}

######################################################################
#
# End of function definitions
#
######################################################################

######################################################################
#
# Start of main script
#
######################################################################

[[ "$0" == "$BASH_SOURCE" ]] && start_app
