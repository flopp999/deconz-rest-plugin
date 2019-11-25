#!/bin/bash

UPDATE_VERSION_HB="0.4.50"
UPDATE_VERSION_HB_HUE="0.11.42"
UPDATE_VERSION_HB_LIB="4.4.7"
UPDATE_VERSION_NPM="6.9.0"
UPDATE_VERSION_NODE="12.13.0"
# use install name to install the specific node version via apt. Retrieve it via: apt-cache policy nodejs
# UPDATE_VERSION_NODE_INSTALL_NAME="10.16.3-1nodesource1"
# when increasing major version of node adjust downoload link
NODE_DOWNLOAD_LINK="https://deb.nodesource.com/setup_12.x"

TIMEOUT=0
LOG_LEVEL=3
ZLLDB=""
SQL_RESULT=
OWN_PID=$$
MAINUSER=$(getent passwd 1000 | cut -d: -f1)
DECONZ_CONF_DIR="/home/$MAINUSER/.local/share"
LOG_DIR=""
DECONZ_PORT=

PROXY_ADDRESS=""
PROXY_PORT=""
AUTO_UPDATE=false #auto update active status

LOG_EMERG=
LOG_ALERT=
LOG_CRIT=
LOG_ERROR=
LOG_WARN=
LOG_NOTICE=
LOG_INFO=
LOG_DEBUG=
LOG_SQL=

[[ $LOG_LEVEL -ge 0 ]] && LOG_EMERG="<0>"
[[ $LOG_LEVEL -ge 1 ]] && LOG_ALERT="<1>"
[[ $LOG_LEVEL -ge 2 ]] && LOG_CRIT="<2>"
[[ $LOG_LEVEL -ge 3 ]] && LOG_ERROR="<3>"
[[ $LOG_LEVEL -ge 4 ]] && LOG_WARN="<4>"
[[ $LOG_LEVEL -ge 5 ]] && LOG_NOTICE="<5>"
[[ $LOG_LEVEL -ge 6 ]] && LOG_INFO="<6>"
[[ $LOG_LEVEL -ge 7 ]] && LOG_DEBUG="<7>"
[[ $LOG_LEVEL -ge 8 ]] && LOG_SQL="<8>"

# $1 = key $2 = value
function putHomebridgeUpdated {
	curl --noproxy '*' -s -o /dev/null -d "{\"$1\":\"$2\"}" -X PUT http://127.0.0.1:${DECONZ_PORT}/api/$OWN_PID/config/homebridge/updated
}

# $1 = queryString
function sqliteSelect() {
    if [[ -z "$ZLLDB" ]] || [[ ! -f "$ZLLDB" ]]; then
        [[ $LOG_DEBUG ]] && echo "${LOG_DEBUG}database not found"
        ZLLDB=""
        return
    fi
    [[ $LOG_SQL ]] && echo "SQLITE3 $1"

    SQL_RESULT=$(sqlite3 $ZLLDB "$1")
    if [ $? -ne 0 ]; then
    	SQL_RESULT=
	fi
    [[ $LOG_SQL ]] && echo "$SQL_RESULT"
}

function init {
    # is sqlite3 installed?
	sqlite3 --version &> /dev/null
	if [ $? -ne 0 ]; then
		return
	fi

	# look for latest config in specific order
	drs=("data/dresden-elektronik/deCONZ/zll.db" "dresden-elektronik/deCONZ/zll.db" "deCONZ/zll.db")
	for i in "${drs[@]}"; do
		if [ -f "${DECONZ_CONF_DIR}/$i" ]; then
			ZLLDB="${DECONZ_CONF_DIR}/$i"
			LOG_DIR="${ZLLDB:0:-7}/homebridge-install-logfiles"
			break
		fi
	done

	if [ ! -f "$ZLLDB" ]; then
		# might have been deleted
		ZLLDB=""
	fi

	if [[ -z "$ZLLDB" ]]; then
		return
	fi

	# get deCONZ REST-API port
	sqliteSelect "select value from config2 where key=\"port\""
	local value="$SQL_RESULT"

	if [[ -n "$value" ]]; then
		DECONZ_PORT=$value
	fi

	# init logging
	if [ ! -d "$LOG_DIR" ]; then
		mkdir "$LOG_DIR"
	fi

	echo "Logging started $(date +%Y-%m-%dT%H:%M:%S)" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	echo "-----------------------------------" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	echo "UPDATE_VERSION_HB = $UPDATE_VERSION_HB" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	echo "UPDATE_VERSION_HB_HUE = $UPDATE_VERSION_HB_HUE" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	echo "UPDATE_VERSION_HB_LIB = $UPDATE_VERSION_HB_LIB" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	echo "UPDATE_VERSION_NPM = $UPDATE_VERSION_NPM" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	echo "UPDATE_VERSION_NODE = $UPDATE_VERSION_NODE" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
}

function installHomebridge {

	## get database config
	params=( [0]="proxyaddress" [1]="proxyport" [2]="homebridgeupdate" )
	values=()

	for i in {0..2}; do
		param=${params[$i]}

		sqliteSelect "select value from config2 where key=\"${param}\""
		value="$SQL_RESULT"

		# basic check for non empty
		if [[ ! -z "$value" ]]; then
			values[$i]=$(echo $value | cut -d'|' -f2)
		fi
	done

	PROXY_ADDRESS="${values[0]}"
	PROXY_PORT="${values[1]}"
	AUTO_UPDATE="${values[2]}"

	## check installed components
	hb_installed=false
	hb_hue_installed=false
	node_installed=false
	npm_installed=false
	node_ver=""
	hb_hue_version=""

	which homebridge >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	if [ $? -eq 0 ]; then
		hb_installed=true
		echo "homebridge installed version $(homebridge --version)" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		# look for homebridge-hue installation
		hb_hue_version=$(npm list -g homebridge-hue | grep homebridge-hue | cut -d@ -f2 | xargs)
		if [ -n "$hb_hue_version" ]; then
			# homebridge-hue installation found
			hb_hue_installed=true
			echo "found existing homebridge-hue installation $hb_hue_version" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			putHomebridgeUpdated "homebridgeversion" "$hb_hue_version"
		else
			echo "homebridge-hue not installed" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		fi
	else
		echo "homebridge not installed" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	fi

	which nodejs >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	if [ $? -eq 0 ]; then
		node_installed=true
		node_ver=$(node --version | cut -dv -f2) # strip the v
		[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} nodejs installed version $node_ver"
		echo "nodejs installed version $node_ver" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	else
		echo "nodejs not installed" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	fi

	if [[ $hb_installed = false || $hb_hue_installed = false || $node_installed = false ]]; then
		[[ $LOG_INFO ]] && echo "${LOG_INFO}check inet connectivity"
		echo "check inet connectivity" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

		putHomebridgeUpdated "homebridge" "installing"

		curl --head --connect-timeout 20 -k https://www.phoscon.de &> /dev/null
		if [ $? -ne 0 ]; then
			if [[ ! -z "$PROXY_ADDRESS" && ! -z "$PROXY_PORT" && "$PROXY_ADDRESS" != "none" ]]; then
				export http_proxy="http://${PROXY_ADDRESS}:${PROXY_PORT}"
				export https_proxy="http://${PROXY_ADDRESS}:${PROXY_PORT}"
				[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG}set proxy: ${PROXY_ADDRESS}:${PROXY_PORT}"
				echo "set proxy: ${PROXY_ADDRESS}:${PROXY_PORT}" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			else
				[[ $LOG_WARN ]] && echo "${LOG_WARN}no internet connection. Abort homebridge installation."
				echo "no internet connection. Abort homebridge installation." >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				putHomebridgeUpdated "homebridge" "install-error"
				return
			fi
		fi

		# check correct timezone
		sysTimezone = $(timedatectl | grep zone | cut -d':' -f2 | cut -d '(' -f1 | xargs)
		[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} System TZ: $sysTimezone"
		echo "System TZ: $sysTimezone" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		dbTimezone = $(sqliteSelect "select value from config2 where key=\"timezone\"")
		[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} TZ from db: $dbTimezone"
		echo "TZ from db: $dbTimezone" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

		if [[ "$sysTimezone" != "$dbTimezone" ]]; then
			[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} Setting sys timezone to db timezone"
			echo "Setting sys timezone to db timezone" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			timedatectl set-timezone "$dbTimezone"
		fi

		# install nodejs if not installed
		if [[ $node_installed = false ]]; then
		# example for getting it worked on rpi1 and 0
		# if armv6
			#wget node 8.12.0
			#cp -R to /usr/local
			#PATH=usr/local/bin/
			#link nodejs to node
		# else
			curl -sL "$NODE_DOWNLOAD_LINK" | bash -
			if [ $? -eq 0 ]; then
				apt-get install -y nodejs | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				if [ $? -ne 0 ]; then
					[[ $LOG_WARN ]] && echo "${LOG_WARN}could not install nodejs"
					echo "could not install nodejs" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
					putHomebridgeUpdated "homebridge" "install-error"
					return
				fi
			else
				[[ $LOG_WARN ]] && echo "${LOG_WARN}could not download node setup."
				echo "could not download node setup." >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				putHomebridgeUpdated "homebridge" "install-error"
				return
			fi
		# fi
		else
			echo "compare installed node version $node_ver to update version $UPDATE_VERSION_NODE" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		    dpkg --compare-versions "$node_ver" lt "$UPDATE_VERSION_NODE"
			if [ $? -eq 0 ]; then
			    curl -sL "$NODE_DOWNLOAD_LINK" | bash -
				if [ $? -eq 0 ]; then
					apt-get install -y nodejs | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
					if [ $? -ne 0 ]; then
						[[ $LOG_WARN ]] && echo "${LOG_WARN}could not install nodejs"
							echo "could not install nodejs" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
							putHomebridgeUpdated "homebridge" "install-error"
						return
					fi
				else
					[[ $LOG_WARN ]] && echo "${LOG_WARN}could not download node setup."
					echo "could not download node setup." >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
					putHomebridgeUpdated "homebridge" "install-error"
					return
				fi
		    fi
		fi

		# install homebridge if not installed
		if [[ $hb_installed = false ]]; then
			npm -g install npm@"$UPDATE_VERSION_NPM" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			if [ $? -eq 0 ]; then
				npm -g install homebridge@"$UPDATE_VERSION_HB" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				if [ $? -ne 0 ]; then
					[[ $LOG_WARN ]] && echo "${LOG_WARN}could not install homebridge"
					echo "could not install homebridge" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
					putHomebridgeUpdated "homebridge" "install-error"
					return
				fi
			else
				[[ $LOG_WARN ]] && echo "${LOG_WARN}could not update npm"
				echo "could not update npm" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				putHomebridgeUpdated "homebridge" "install-error"
				return
			fi
		fi

		# install homebridge-hue if not installed
		if [[ $hb_hue_installed = false ]]; then
			npm -g install homebridge-lib@"$UPDATE_VERSION_HB_LIB" homebridge-hue@"$UPDATE_VERSION_HB_HUE" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			if [ $? -ne 0 ]; then
				[[ $LOG_WARN ]] && echo "${LOG_WARN}could not install homebridge hue"
				echo "could not install homebridge hue" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				putHomebridgeUpdated "homebridge" "install-error"
				return
			else
				putHomebridgeUpdated "homebridgeversion" "$UPDATE_VERSION_HB_HUE"
			fi
		fi
	fi

	# fix missing homebridge-lib
	if [[ -n $(npm list -g homebridge-lib | grep empty) ]]; then
		npm -g install homebridge-lib@"$UPDATE_VERSION_HB_LIB" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	fi

	putHomebridgeUpdated "homebridgeupdateversion" "$UPDATE_VERSION_HB_HUE"
}

function checkUpdate {

	# delete old Log files
	if [ $(ls -1 "${LOG_DIR}" | wc -l) -gt 3 ]; then
		oldest=$(ls "${LOG_DIR}" -t | tail -n1)
		rm -f "${LOG_DIR}/$oldest"
    fi

	if [[ $AUTO_UPDATE = false ]] || [ -z $AUTO_UPDATE ]; then
		echo "check for updates is deactivated" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		return
	fi

	[[ $LOG_INFO ]] && echo "${LOG_INFO}check for homebridge updates"
	echo "check for homebridge updates" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	hb_version=""
	hb_hue_version=""
	node_version=""
	npm_version=""

	curl --head --connect-timeout 20 -k https://www.npmjs.com/ &> /dev/null
	if [ $? -ne 0 ]; then
		if [[ ! -z "$PROXY_ADDRESS" && ! -z "$PROXY_PORT" && "$PROXY_ADDRESS" != "none" ]]; then
			export http_proxy="http://${PROXY_ADDRESS}:${PROXY_PORT}"
			export https_proxy="http://${PROXY_ADDRESS}:${PROXY_PORT}"
			[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG}set proxy: ${PROXY_ADDRESS}:${PROXY_PORT}"
			echo "set proxy: ${PROXY_ADDRESS}:${PROXY_PORT}" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		else
			[[ $LOG_WARN ]] && echo "${LOG_WARN}no internet connection. Abort update check."
			echo "no internet connection. Abort update check." >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			return
		fi
	fi

	# check correct timezone
	sysTimezone = $(timedatectl | grep zone | cut -d':' -f2 | cut -d '(' -f1 | xargs)
	[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} System TZ: $sysTimezone"
	echo "System TZ: $sysTimezone" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
	dbTimezone = $(sqliteSelect "select value from config2 where key=\"timezone\"")
	[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} TZ from db: $dbTimezone"
	echo "TZ from db: $dbTimezone" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

	if [[ "$sysTimezone" != "$dbTimezone" ]]; then
		[[ $LOG_DEBUG ]] && echo "${LOG_DEBUG} Setting sys timezone to db timezone"
		echo "${LOG_DEBUG} Setting sys timezone to db timezone" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		timedatectl set-timezone "$dbTimezone"
	fi

	hb_version=$(npm list -g homebridge | grep homebridge | cut -d@ -f2 | xargs)
	hb_hue_version=$(npm list -g homebridge-hue | grep homebridge-hue | cut -d@ -f2 | xargs)
	putHomebridgeUpdated "homebridgeversion" "$hb_hue_version"
	npm_version=$(npm --version)
	node_version=$(node --version | cut -dv -f2) # strip the v

	# check if installed versions are smaller than update veresions

	# update node
	dpkg --compare-versions "$node_version" lt "$UPDATE_VERSION_NODE"
	if [ $? -eq 0 ]; then
		[[ $LOG_INFO ]] && echo "${LOG_INFO}installed node version: $node_version - latest supported: $UPDATE_VERSION_NODE"
		echo "installed node version: $node_version - latest supported: $UPDATE_VERSION_NODE" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		[[ $LOG_INFO ]] && echo "${LOG_INFO}update nodejs"
		echo "update nodejs" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

		curl -sL "$NODE_DOWNLOAD_LINK" | bash -
		if [ $? -eq 0 ]; then
			apt-get install -y nodejs | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			if [ $? -ne 0 ]; then
				[[ $LOG_WARN ]] && echo "${LOG_WARN}could not update nodejs"
				echo "could not update nodejs" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
				return
			fi
		else
			[[ $LOG_WARN ]] && echo "${LOG_WARN}could not download node setup."
			echo "could not download node setup." >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			return
		fi
	fi

	# update npm
	dpkg --compare-versions "$npm_version" lt "$UPDATE_VERSION_NPM"
	if [ $? -eq 0 ]; then
		[[ $LOG_INFO ]] && echo "${LOG_INFO}installed npm version: $npm_version - latest: $UPDATE_VERSION_NPM"
		echo "installed npm version: $npm_version - latest: $UPDATE_VERSION_NPM" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		[[ $LOG_INFO ]] && echo "${LOG_INFO}update npm"
		echo "update npm" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

		npm -g install npm@"$UPDATE_VERSION_NPM" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		if [ $? -ne 0 ]; then
			[[ $LOG_WARN ]] && echo "${LOG_WARN}could not update npm"
			echo "could not update npm" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			return
		fi
	fi

	# update homebridge
	dpkg --compare-versions "$hb_version" lt "$UPDATE_VERSION_HB"
	if [ $? -eq 0 ]; then
		[[ $LOG_INFO ]] && echo "${LOG_INFO}installed homebridge version: $hb_version - latest: $UPDATE_VERSION_HB"
		echo "installed homebridge version: $hb_version - latest: $UPDATE_VERSION_HB" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		[[ $LOG_INFO ]] && echo "${LOG_INFO}update homebridge"
		echo "update homebridge" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

		npm -g install homebridge@"$UPDATE_VERSION_HB" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		if [ $? -ne 0 ]; then
			[[ $LOG_WARN ]] && echo "${LOG_WARN}could not update homebridge"
			echo "could not update homebridge" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
			return
		fi

	fi

	# update homebridge hue
	dpkg --compare-versions "$hb_hue_version" lt "$UPDATE_VERSION_HB_HUE"
	if [ $? -eq 0 ]; then
		[[ $LOG_INFO ]] && echo "${LOG_INFO}installed homebridge-hue version: $hb_hue_version - latest: $UPDATE_VERSION_HB_HUE"
		echo "installed homebridge-hue version: $hb_hue_version - latest: $UPDATE_VERSION_HB_HUE" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		[[ $LOG_INFO ]] && echo "${LOG_INFO}update homebridge-hue"
		echo "update homebridge-hue" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"

		npm -g install homebridge-lib@"$UPDATE_VERSION_HB_LIB" homebridge-hue@"$UPDATE_VERSION_HB_HUE" | tee -a "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		if [ $? -ne 0 ]; then
			[[ $LOG_WARN ]] && echo "${LOG_WARN}could not update homebridge hue"
			echo "could not update homebridge hue" >> "$LOG_DIR/LOG_HOMEBRIDGE_INSTALL_$(date +%Y-%m-%d)"
		else
			putHomebridgeUpdated "homebridge" "updated"
			putHomebridgeUpdated "homebridgeversion" "$UPDATE_VERSION_HB_HUE"
		fi
	fi
}

# break loop on SIGUSR1
trap 'TIMEOUT=0' SIGUSR1

COUNTER=5

while [ 1 ]
do
	if [[ -z "$ZLLDB" ]] || [[ ! -f "$ZLLDB" ]] || [[ -z "$DECONZ_PORT" ]]; then
		init
	fi

	while [[ $TIMEOUT -gt 0 ]]
	do
		sleep 1
		TIMEOUT=$((TIMEOUT - 1))
	done

	TIMEOUT=600 # 10 minutes

	[[ -z "$ZLLDB" ]] && continue
	[[ ! -f "$ZLLDB" ]] && continue
	[[ -z "$DECONZ_PORT" ]] && continue

    installHomebridge

    COUNTER=$((COUNTER + 1))
	if [ $COUNTER -ge 6 ]; then
		# check for updates every hour
		COUNTER=0
		checkUpdate
	fi
done
