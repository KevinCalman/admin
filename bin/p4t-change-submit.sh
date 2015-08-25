#!/bin/sh
## p4t-change-submit.sh: a Perforce trigger used at changelist submit time.
## (C)2012 Codex Systems by Kevin Calman, kevinc@codexsys.com
##  
## Utilize this script by installing it in a path accessable by the 
## Perforce server process (p4d), and adding a line to the Perforce
## triggers table similar to the following:
## 	Triggers:
## 		p4t-change-submit change-submit //depot/main/... "p4t-change-submit.sh -c %change% -u %user% -jr -q"
## 	or
## 		p4t-change-submit change-submit //depot/main/... "C:\cygwin\bin\bash -c 'admin/bin/p4t-change-submit.sh -c %change% -u %user% -jr -q'"
## This script may be called interactively:
## 	p4t-change-submit.sh -c <changelist#> [-u <userid> -k 'regex'] {-j|-r|-s}... [-p <p4port>] [-d] [-h] [-q] [-t] [-v]... [-V] 
## where:
## 	-c <changelist#> specifies the Perforce changelist number to examine
## 	[-j] tests the changelist comment for contains at least one JIRA ID
## 	[-r] tests the changelist comment for 'Reviewed by ...'
## 	[-s] tests the changelist Status to be 'pending'
## 	[-p <p4port>] specifies the P4PORT value
## 	[-k 'regex' specifies the "Key", a regex to match for unconditional acceptance, where
## 		test is only checked when other tests fail, and
## 		changelist comment matches regex provided, defaults to '^m1-release-plugin:', and
## 		changelist submitted from privileged user, defaults to 'build'.
## 	-u <userid>] specifies the Perforce User submitting the change
## 	[-d] specifies to turn on script Debugging (also envvar DBUG nonnull)
## 	[-h] specifies to show this Help text and quit
## 	[-q] specifies Quiet, no text message to stdout on success
## 	[-t] specifies Testing, always return non-0 exit status even if good
## 	[-v]... increases the Verbosity level, 0=none, 1=assignments, 2=loops
## 	[-V] displays the executed path and Version
## Note: Trigger type "change-submit" executes a changelist
## 	trigger after changelist creation, but before file transfer.
## 	Trigger may not access file contents.

# Initialization
[[ -n $DBUG ]] && set -vx
declare THIS=$0 VERS="$Revision$"; VERS=${VERS//[^0-9]/}
declare -i VERB=0 RC=0
declare privusr=build
export PATH=/usr/local/bin:/usr/bin${PATH:+:$PATH}

# Internal functions
# Display the help text from this file and exit with non-error exit status
function Help ()
{
	echo $THIS version $VERS
	sed -ne '/^##[[:space:]]/s///p' $THIS
}

# Exit the script with a given exit status and optional string to display
function Die ()
{
	local -i err=$1
	local msg=$2
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

# Display an assertion according to VERBosity level (0=none, 1=assignments, 2=loops)
function Squawk ()
{
	set +vx		# Disable debugging in assertions
	local -i rc=0 vlv=$1
	local msg=$2
	if [[ $vlv -le $VERB ]]; then
		echo "$THIS: $msg"
	fi
	[[ -n $DBUG ]] && set -vx 	# Reenable debugging
}

# Get parms
while getopts c:p:u:k:jrsdhqtvV OPTION; do
	Squawk 2 "OPTION=$OPTION"
	Squawk 2 "OPTIND=$OPTIND"
	Squawk 2 "OPTARG=$OPTARG"
	case $OPTION in
		(c) 	change=$OPTARG;	Squawk 1 "change=$change" ;;
		(p) 	port=$OPTARG;	Squawk 1 "port=$port" ;;
		(u) 	parmusr=$OPTARG;Squawk 1 "parmusr=$parmusr" ;;
		(k) 	key=$OPTARG;	Squawk 1 "key=$key"
				TESTKEY=true;	Squawk 1 "TESTKEY=$TESTKEY" ;;
		(j)		TESTJIRA=true;	Squawk 1 "TESTJIRA=$TESTJIRA" ;;
		(r)		TESTREVW=true;	Squawk 1 "TESTREVW=$TESTREVW" ;;
		(s)		TESTSTAT=true;	Squawk 1 "TESTSTAT=$TESTSTAT" ;;
		(t) 	TESTONLY=true;	Squawk 1 "TESTONLY=$TESTONLY" ;;
		(q)		QUIET=true;		Squawk 1 "QUIET=$QUIET" ;;
		(d) 	DBUG=true; set -vx; Squawk 0 "Debugging on" ;;
		(h) 	Help && Die 0 "Help text requested." ;;
		(v) 	VERB+=1; Squawk 1 "VERB=$VERB" ;;
		(V)		Squawk 0 "version $VERS" ;;
		(*) 	Help && Die 1 "Invalid option" ;;
	esac
done

# 	Entry conditions
# Assert self-reference, since it was defined before the assertion function "Squawk"
Squawk 1 "THIS=$THIS"
# Assert present working directory
Squawk 1 "PWD=$PWD"
# Assert current environment PATH 
Squawk 1 "PATH=$PATH"
# Assert locations of prerequisites
Squawk 1 "awk is $(which awk)"
Squawk 1 "grep is $(which grep)"
Squawk 1 "sed is $(which sed)"
Squawk 1 "sort is $(which sort)"

# Check for sufficient parameters
[[ -n $change ]] || Die 2 "No Perforce change list ID specified."
[[ -n $TESTJIRA || -n $TESTREVW || -n $TESTSTAT ]] || Die 3 "No tests requested, specify at least one of {-j|-r|-s}."
[[ -z $TESTKEY || -n $parmusr ]] || Die 4 "Key test (-k) requires specified userid (-u)."

# Pass specified, inherited, or default port specification to p4 binary via envvar
export P4PORT=${port:-${P4PORT:-'localhost:1666'}}
Squawk 1 "P4PORT=$P4PORT"

# Check that the current user is logged into p4
P4USER=$(p4 -ztag info | awk '/^\.\.\. userName/{print $3}')
p4 login -s >/dev/null 2>&1 || Die 5 "Perforce user account \"$P4USER\" is not logged into Perforce."

# Define the list of acceptable JIRA project names, 
# separated by '|' to be used as an extended regex.
JIRAPROJ="AFDEV AUTODEV BBDEV BS DEA DEVLAB DEVOPS EMSCLIENT EMSDEV EMSUI ERM IPMDEV OEDEV OPS OSDEV PERFTOOLS PLAY PROV PUP WMDEV ZOD"
JIRAPROJ=${JIRAPROJ// /|}
Squawk 1 "JIRAPROJ=$JIRAPROJ"

# Capture the changelist comment, converting embedded newlines to tabs.
COMMENT=$( \
	p4 -ztag change -o $change | \
	awk '/^\.\.\. Description/{C=substr($0,17); next}; \
		!/^\.\.\. /{C=C "\t" $0}; \
		/^\.\.\. Type /{print C}' \
)
Squawk 1 "COMMENT=$COMMENT"

# Capture the number of opened files
OPENED=$(p4 opened -ac $change //depot/... 2>/dev/null | wc -l)
Squawk 1 "OPENED=$OPENED"
MESSAGE="Change list $change on $OPENED file(s)"

# 	Apply tests. Conditions are all in the affirmative (true to pass)
## Interpreting failure exit codes:
# Test for JIRA ID assignment
if [[ -n $TESTJIRA ]]; then
	# Capture the JIRA IDs from the comment
	JIRAIDS=$(sed -e 's/[: ,]\{1,\}/\n/g' <<<$COMMENT | eval grep -E \'$JIRAPROJ-[0-9]\{1,8\}\' | sort -run -t- -k2 | awk '{O=O " " $0}; END {print substr(O,2)}')
	Squawk 1 "JIRAIDS=$JIRAIDS"
	if [[ -n $JIRAIDS ]]; then
		MESSAGE+=" is associated to JIRA(s) \"$JIRAIDS\""
		Squawk 1 "Pass TESTJIRA (-j) with RC=$RC"
	else
		MESSAGE+=" has no associated JIRAs"
## 	failure of JIRA ID test (-j) sets 1's (1st) bit
		RC+=1
		Squawk 1 "Fail TESTJIRA (-j) with RC=$RC"
	fi
else
	Squawk 1 "TESTJIRA not applied RC=$RC"
fi

# Test for reviewer assignment
if [[ -n $TESTREVW ]]; then
	# Capture the reviewer name
	REVIEWER=$(sed -ne '/reviewed by/Is/^.*reviewed by[ \t]*\([-a-z0-9_.]\{2,32\}\).*$/\1/Ip' <<<$COMMENT)
	Squawk 1 "REVIEWER=$REVIEWER"
	if [[ -n $REVIEWER ]]; then
		MESSAGE+=", is reviewed by \"$REVIEWER\""
		Squawk 1 "Pass TESTREVW (-r) with RC=$RC"
	else
		MESSAGE+=", has no associated reviewer"
## 	failure of reviewer test (-r) sets 2's (2nd) bit
		RC+=2
		Squawk 1 "Fail TESTREVW (-r) with RC=$RC"
	fi
else
	Squawk 1 "TESTREVW not applied RC=$RC"
fi

# Test for changelist in pending status
if [[ -n $TESTSTAT ]]; then
	# Capture the changelist status
	STATUS=$(p4 -ztag change -o $change | awk '/^\.\.\. Status/{print $3}')
	if [[ $STATUS == 'pending' ]]; then
		MESSAGE+=", and is in status 'pending'"
		Squawk 1 "Pass TESTSTAT (-s) with RC=$RC"
	else
		MESSAGE+=", and is in status \"$STATUS\""
## 	failure of changelist status test (-s) sets 4's (3rd) bit
		RC+=4
		Squawk 1 "Fail TESTSTAT (-s) with RC=$RC"
	fi
else
	Squawk 1 "TESTSTAT not applied RC=$RC"
fi

# Test for key match
if [[ -n $TESTKEY && $RC -gt 0 ]]; then
	if [[ $parmusr =~ $privusr ]]; then
		MESSAGE+=", but submitting user ($parmusr) is privileged"
		Squawk 1 "Pass TESTKEY user ($parmusr) is privileged"
		if [[ $COMMENT =~ $key ]]; then
			RC=0 	# privileged override overwrites previous RC to pass tests
			MESSAGE+=" and comment matches key so pass regardless of previous errors."
			Squawk 1 "Pass TESTKEY comment ($key) matches RC=$RC"
		else	# comment not match key
## 	failure of changelist key test (-k) sets 8's (4th) bit
			RC+=8
			MESSAGE+=" and comment not match key so retain previous errors."
			Squawk 1 "Fail TESTKEY comment ($key) not match RC=$RC"
		fi
	else 	# submitting user not privileged
## 	unprivileged user in key test (-k) sets 16's (5th) bit
		RC+=16
		MESSAGE+=", but submitting user ($parmusr) is not privileged so retain previous errors."
		Squawk 1 "Fail TESTKEY unprivileged submitting user ($parmuser) RC=$RC"
	fi
else
	MESSAGE+="." # no key test so finalize the output message
	Squawk 1 "TESTKEY not applied RC=$RC"
fi

# Final determination
## Trigger success returns exit status 0, a textual error message if not '-q', and transaction continues.
## Trigger failure returns exit status >0, a textual error message, and the transaction does not continue.
if [[ RC -eq 0 ]]; then
	[[ -n $QUIET ]] || echo "PASS:	$MESSAGE ($RC)"
else
	echo "FAIL:	$MESSAGE ($RC)"
fi
[[ -n $TESTONLY ]] && exit 99 || exit $RC

#eof
