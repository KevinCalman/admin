#!/bin/bash
# fscan.sh: shell script to run a Fortify SCA scan on an extracted pre-build image
# (c)2012 Codex Systems; Kevin Calman, kevinc@codexsys.com

# Activate debugging verbose output
[[ -n $DBUG ]] && set -vx
# JVM config for SCA execution
export SCA_VM_OPTS=${SCA_VM_OPTS:-'-Xms256M -Xmx2048M'}
# Provide default values for F360 interaction if not inherited from calling env
THIS=$0; VERS="$Revision$"; VERS=${VERS//[^0-9]/}
F360_URL=${F360_URL:-'https://fortify.dell.com/f360/'}
F360_USER=${F360_USER:-$USER}
F360_ID=${F360_ID:-'12536'}
F360_PROJ=${F360_PROJ:-'EMS'}
F360_VERS=${F360_VERS:-'EMSBE'}
# Default value for build dir as current directory if not $WORKSPACE passed from Hudson job
BUILD_ROOT="${WORKSPACE:-$PWD}"
# Define build tag from the Hudson build tag, or the F360 Project name, version and date, time stamp (goes into report)
BUILD_TAG=${BUILD_TAG:-"${F360_PROJ}-${F360_VERS}-$(date "+%Y%m%d.%H%M%S")"}
# Define a root for the scan file name from the F360 Project name and version (not a Hudson variable)
OUTFILE=${OUTFILE:-"${F360_PROJ}-${F360_VERS}"}

# Display the current relevant environment variables
printf "%s version %s:\tbuild %s\n" $THIS $VERS $BUILD_TAG
if [[ -n $DBUG ]]
then
	echo -e "\tEnvironment:"
	set | egrep '^(BUILD|F360|SCA)'
	echo -ne "\tF360_PW checksum: "; md5sum <<<${F360_PW}
fi

# Define CLASSPATH to be the default CLASSPATH plus all classes, libs, and jars extracted from Perforce for this build
BUILD_CP=$(find ${BUILD_ROOT} -type d -name classes -o -type d -name lib -o -type f -name '*.jar' | xargs echo | tr ' ' ':')
BUILD_CP=${CLASSPATH}${BUILD_CP:+:${BUILD_CP}}
# Define SCA Excludes as any directory of the form ".../src/test" or ".../*Test*"
BUILD_EXCLUDES=$( ( find . -type d | grep  src/test; find . -type d | grep Test ) | sed -e 's|\(Test[^/]*\).*$|\1|;s|\(src/test\).*|\1|' | sort -u | xargs -i echo "-exclude {} "; )

# Change directory to root of build
pushd ${BUILD_ROOT}

# Authenticate and obtain token from F360 server to facilitate further interactions
echo -e '\tAuthenticate (will prompt for input if F360_PW not set)'
${DBUG:+time} \
fortifyclient token \
-gettoken AnalysisDownloadToken \
-user ${F360_USER} \
${F360_PW:+-password ${F360_PW}} \
-url ${F360_URL} | tee f360-AnalysisDownloadToken.tmp
[[ $? -eq 0 ]] || exit $?
F360_TOKEN=$(sed -e 's/^.* //' f360-AnalysisDownloadToken.tmp)

# Get F360 Project Version ID from list of current projects on F360
echo -e "\tListProjects"
${DBUG:+time} \
fortifyclient listProjectVersions \
-url ${F360_URL} \
-authtoken ${F360_TOKEN} >f360-listProjectVersions.tmp
F360_ID=$(awk -F"\t" '$2=="'${F360_PROJ}'" && $5=="'${F360_VERS}'" {print $1}' f360-listProjectVersions.tmp)
[[ $? -eq 0 ]] || exit $?

# Clean the build tree (irrelevant if fresh extract)
echo -e "\tClean"
${DBUG:+time} \
sourceanalyzer \
-b ${F360_ID} \
-clean 
[[ $? -eq 0 ]] || exit $?

# Pull the current version of the FPR file from F360 server
echo -e "\tGet FPR"
${DBUG:+time} \
fortifyclient downloadFPR \
-file ${OUTFILE}-F360.fpr \
-projectID ${F360_ID} \
-url ${F360_URL} \
-authtoken ${F360_TOKEN}
[[ $? -eq 0 ]] || exit $?

# Build translates various source languages into SCA bytecode for analysis
echo -e "\tBuild"
${DBUG:+time} \
sourceanalyzer \
-b ${F360_ID} \
-build-label ${BUILD_TAG} \
-build-project ${F360_PROJ} \
-build-version ${F360_VERS} \
-source "1.6" \
-debug \
${BUILD_EXCLUDES} \
-cp "${BUILD_CP}" \
${BUILD_ROOT}
[[ $? -eq 0 ]] || exit $?

# Scan the project creates new FPR scan file, time execution unconditionally
echo -e "\tScan"
time \
sourceanalyzer \
-b ${F360_ID} \
-scan \
-format "fpr" \
-f ${OUTFILE}-scan.fpr
[[ $? -eq 0 ]] || exit $?

# Merge the server and local versions of the FPR files to carry over previous "suppressions"
echo -e "\tMerge"
${DBUG:+time} \
FPRUtility -merge \
-project "${OUTFILE}-F360.fpr" \
-source  "${OUTFILE}-scan.fpr" \
-f "${OUTFILE}-merged.fpr"
[[ $? -eq 0 ]] || exit $?

# Generate human-readable reports from the merged FPR file
echo -e "\tReports"
for F in pdf xml
do
	${DBUG:+time} \
	ReportGenerator \
	-format ${F} \
	-f "${OUTFILE}-merged.${F}" \
	-source  "${OUTFILE}-merged.fpr" \
	-user ${F360_USER}
	[[ $? -eq 0 ]] || exit $?
done

# TODO: upload the merged scan file to Fortify 360/SSC

# Discard authentication token from F360 server
echo -e '\tInvalidate'
fortifyclient invalidatetoken \
-invalidate ${F360_TOKEN} \
-user ${F360_USER} \
${F360_PW:+-password ${F360_PW}} \
-url ${F360_URL}
[[ $? -eq 0 ]] || exit $?

# Return to calling directory 
popd

#eof
