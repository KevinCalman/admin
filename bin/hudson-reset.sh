#!/bin/bash
# hudson-reset.sh: restart the Hudson service in a safe manner, 
# suitable for calling from a cron job for automation.
# (C)2013 Codex Systems by Kevin Calman, kevinc@codexsys.com
#
# Usage: Create a "password file" in ~hudson/.ssh called "username@domain.pwf"
#	that contains the user's password in cleartext, chmod 400 *.pwf
# Place this file in ~hudson and modify HUDSON_* envvars appropriately.
# Add the following lines to the hudson user's crontab:
#	# Daily safe reset of the Hudson service
# 	00 06 * * *	/var/lib/hudson/hudson-reset.sh >/var/log/hudson/hudson-reset.log 2>&1

# Initialization
[[ -n $DBUG ]] && set -vx
declare THIS=$(readlink -f ${BASH_SOURCE[0]})
declare JAVA_ENV=/etc/profile.d/jdk.sh
export HUDSON_URL=http://localhost:8080/
export HUDSON_CLI_HOME=~hudson/war/WEB-INF
export HUDSON_CLI=$HUDSON_CLI_HOME/hudson-cli.jar
export HUDSON_USR=build
export HUDSON_PWF=~hudson/.ssh/${HUDSON_USR}\@dgslab.pwf
export PATH=$PATH:$HUDSON_CLI_HOME
export CLASSPATH=${CLASSPATH:+${CLASSPATH}:}$HUDSON_CLI_HOME

function Die ()
{
	local -i err=$1
	local msg=$2
	exec >&2
	if [[ -z $err ]]
	then
		echo "$THIS: unspecified error occurred."
		err=-1
	elif [[ -z $msg ]]
	then
		echo "$THIS: error $err occurred."
	else
		echo "$THIS: $msg ($err)"
	fi
	exit $err
}

# Prerequisites
echo "${THIS}@$(date +'%Y/%m/%d-%H:%M:%S'):"
if [[ -n $JAVA_HOME ]] ; then 
	echo "Java is defined in environment as \"$JAVA_HOME\"."
elif [[ -r $JAVA_ENV ]] ; then
	if source $JAVA_ENV; then
		echo "Java was defined in environment by \"$JAVA_ENV\" as \"$JAVA_HOME\"."
	else
		Die 1 "Could not load Java in environment from \"$JAVA_ENV\"."
	fi
else
	Die 4 "Could not read Java environment setter \"$JAVA_ENV\"."
fi
[[ -r $HUDSON_CLI ]] || Die 2 "Hudson CLI jar \"$HUDSON_CLI\" unreadable."
[[ -r $HUDSON_PWF ]] || Die 3 "Hudson password file \"$HUDSON_PWF\" unreadable."

# Ensure login
if java -jar $HUDSON_CLI login --username build --password-file $HUDSON_PWF; then 
	echo "Logged in to \"$HUDSON_URL\" as user $HUDSON_USR."
else
	Die 4 "Could not Login to \"$HUDSON_URL\" as user $HUDSON_USR."
fi

# Issue restart command
if java -jar $HUDSON_CLI safe-restart; then 
	Die 0 "Issued 'safe-restart' to \"$HUDSON_URL\"."
else
	Die 5 "Could not issue 'safe-restart' to \"$HUDSON_URL\"."
fi

#eof
