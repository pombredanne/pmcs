#!/bin/sh

# Variable declarations
PORT=""
FQDN=""
DOMAIN=""
CLASS=""
REPO=""
PLATFORM=""
KEYWORDS=""
RESULTREPO=""
SCAPSCANOVAL=""
SCAPSCANOVAL_NOID=""
SCAPSCANXCCDF=""
SCAPSCANXCCDF_NOPROFILE=""

CDIR=$(pwd);

TMPDIR=$(mktemp -d --suffix='pmcsa');

# Functions
die() {
  RC=$1; shift;
  echo "!! $*";
  exit ${RC};
}

copyResourceToLocal() {
  SRC="$1"
  DST="$2"
  RC=0;

  PROTO=$(echo ${SRC} | sed -e 's|\([^:]*\):.*|\1|g');
  if [ "${PROTO}" = "file" ];
  then
    LOCALSRC=$(echo ${SRC} | sed -e 's|^[^:]*://||g');
    cp ${LOCALSRC} ${DST};
    RC=$?;
  elif [ "${PROTO}" = "http" ] || [ "${PROTO}" = "https" ];
  then
    wget -q -O ${DST} ${SRC};
    RC=$?;
  fi

  return ${RC};
}

copyResourceToRemote() {
  SRC="$1";
  DST="$2";
  RC=0;

  PROTO=$(echo ${DST} | sed -e 's|\([^:]*\):.*|\1|g');
  if [ "${PROTO}" = "file" ];
  then
    REMOTEDST=$(echo ${DST} | sed -e 's|^[^:]*://||g');
    cp ${SRC} ${REMOTEDST};
    RC=$?;
  elif [ "${PROTO}" = "http" ] || [ "${PROTO}" = "https" ];
  then
    wget --post-file="${SRC}" "${DST}";
  fi;
}

setConfigurationVariables() {
  echo "Fetching configuration from central configuration repository.";

  REPO_URLS="
    ${REPO}/config/domains/${DOMAIN}.conf
    ${REPO}/config/classes/${CLASS}.conf
    ${REPO}/config/domains/${DOMAIN}/classes/${CLASS}.conf
    ${REPO}/config/hosts/${FQDN}.conf
  "

  for REPO_URL in ${REPO_URLS};
  do
    copyResourceToLocal ${REPO_URL} ${TMPDIR}/config;
    if [ $? -eq 0 ];
    then
      grep -q ^platform= ${TMPDIR}/config && PLATFORM=$(grep ^platform= ${TMPDIR}/config | cut -f 2 -d '=');
      grep -q ^resultrepo= ${TMPDIR}/config && RESULTREPO=$(grep ^resultrepo= ${TMPDIR}/config | cut -f 2 -d '=');
      grep -q ^scapscanneroval= ${TMPDIR}/config && SCAPSCANOVAL=$(grep ^scapscanneroval= ${TMPDIR}/config | cut -f 2 -d '=');
      grep -q ^scapscanneroval_noid= ${TMPDIR}/config && SCAPSCANOVAL_NOID=$(grep ^scapscanneroval_noid= ${TMPDIR}/config | cut -f 2 -d '=');
      grep -q ^scapscannerxccdf= ${TMPDIR}/config && SCAPSCANXCCDF=$(grep ^scapscannerxccdf= ${TMPDIR}/config | cut -f 2 -d '=');
      grep -q ^scapscannerxccdf_noprofile= ${TMPDIR}/config && SCAPSCANXCCDF_NOPROFILE=$(grep ^scapscannerxccdf_noprofile= ${TMPDIR}/config | cut -f 2 -d '=');
      grep -q ^keywords= ${TMPDIR}/config && KEYWORDS="${KEYWORDS},$(grep ^keywords= ${TMPDIR}/config | cut -f 2 -d '=')";
      rm ${TMPDIR}/config;
    fi
  done

  echo "PLATFORM                = ${PLATFORM}";
  echo "RESULTREPO              = ${RESULTREPO}";
  echo "KEYWORDS                = ${KEYWORDS}";
  echo "SCAPSCANOVAL            = ${SCAPSCANOVAL}";
  echo "SCAPSCANOVAL_NOID       = ${SCAPSCANOVAL_NOID}";
  echo "SCAPSCANXCCDF           = ${SCAPSCANXCCDF}";
  echo "SCAPSCANXCCDF_NOPROFILE = ${SCAPSCANXCCDF_NOPROFILE}";
  echo "";
}

getStreamList() {
  echo "Getting list of SCAP data streams to evaluate";

  REPO_URLS="
    ${REPO}/stream/hosts/${FQDN}/list.conf
    ${REPO}/stream/domains/${DOMAIN}/classes/${CLASS}/platforms/${PLATFORM}/list.conf
    ${REPO}/stream/domains/${DOMAIN}/classes/${CLASS}/list.conf
    ${REPO}/stream/classes/${CLASS}/platforms/${PLATFORM}/list.conf
    ${REPO}/stream/classes/${CLASS}/list.conf
    ${REPO}/stream/domains/${DOMAIN}/list.conf
  "

  for REPO_URL in ${REPO_URLS};
  do
    copyResourceToLocal ${REPO_URL} ${TMPDIR}/sublist;
    if [ $? -eq 0 ];
    then
      cat ${TMPDIR}/sublist >> ${TMPDIR}/list;
    fi
  done

  for KEYWORD in $(echo ${KEYWORDS} | sed -e 's:,: :g');
  do
    copyResourceToLocal ${REPO}/stream/keywords/${KEYWORD}/list.conf ${TMPDIR}/sublist;
    if [ $? -eq 0 ];
    then
      cat ${TMPDIR}/sublist >> ${TMPDIR}/list;
    fi
  done

  touch ${TMPDIR}/list;
  sort ${TMPDIR}/list | uniq > ${TMPDIR}/orderedlist;
  mv ${TMPDIR}/orderedlist ${TMPDIR}/list;
   
  echo "";
}

sendResults() {
  FILE=$1;
  REPOTYPE=$(echo ${RESULTREPO} | cut -f 1 -d ':' -s);
  POSTRES=$(echo ${RESULTREPO} | sed -e "s:@@TARGETNAME@@:${FQDN}:g" -e "s:@@FILENAME@@:${FILE}:g");

  echo "Sending ${FILE} to ${POSTRES}.";

  copyResourceToRemote ${FILE} ${POSTRES};
};

daemonize() {
  echo "Daemonizing pmcsa on port ${PORT}";
  echo "";

  RC=0;
  OUT="";
  URL="";
  REMHOST="";

  # HTTP header info
  TYPE=""
  URL=""
  VERS=""

  # pmcs variables to create stream info
  STREAMTYPE=""
  STREAMPATH=""
  STREAMID=""

  # expression matching
  USERSTRING="[a-zA-Z0-9_-/\.]*"
  URLSTRING="(type|path|id)"

  while [ ${RC} -eq 0 ]; 
  do
    OUT=$(echo "Om mnom mnom... " | nc -l -v -p ${PORT} 2>&1);
    RC=$?;
    URL=$(echo "${OUT}" | grep -E '^(HEAD|GET) ' | sed -e 's:^[^	 ]*[ 	]\([^ 	]*\).*:\1:g');
    REMHOST=$(echo "${OUT}" | grep '^connect to' | sed -e 's:.* from \(.*\)[ 	][0-9]*:\1:g');

    echo "Request from '${REMHOST}': ${URL}";
    echo "${URL}" | grep -qE "/Evaluate\?${URLSTRING}=${USERSTRING}\&${URLSTRING}=${USERSTRING}\&${URLSTRING}=${USERSTRING}";
    if [ $? -ne 0 ];
    then
      echo "  Request does not match required '/Evaluate' with parameters type, path and id";
      continue;
    fi

    STREAMTYPE=$(echo ${URL} | grep 'type=' | sed -e "s:.*type=\(${USERSTRING}\).*:\1:g");
    STREAMPATH=$(echo ${URL} | grep 'path=' | sed -e "s:.*path=\(${USERSTRING}\).*:\1:g");
    STREAMID=$(echo ${URL} | grep 'id=' | sed -e "s:.*id=\(${USERSTRING}\).*:\1:g");

    if [ -z "${STREAMTYPE}" ] || [ -z "${STREAMPATH}" ] || [ -z "${STREAMID}" ];
    then
      echo "  Request does not contain type, path AND id parameters";
      continue;
    fi

    echo "${STREAMTYPE}#${STREAMPATH}#${STREAMID}" > ${TMPDIR}/list;

    evaluateStreams;
  done
};

evaluateStreams() {
  for STREAM in $(cat ${TMPDIR}/list);
  do
    STREAMTYPE=$(echo ${STREAM} | cut -f 1 -d '#' -s);
    STREAMPATH=$(echo ${STREAM} | cut -f 2 -d '#' -s);
    STREAMID=$(echo ${STREAM} | cut -f 3 -d '#' -s);
    echo "-- Evaluating STREAM ${STREAMPATH} (type ${STREAMTYPE}, id ${STREAMID})";
    echo "";
    STREAMNAME=$(basename ${STREAMPATH});
    copyResourceToLocal ${REPO}/stream/${STREAMPATH} ${TMPDIR}/${STREAMNAME};
    if [ $? -eq 0 ];
    then
      if [ "${STREAMTYPE}" = "xccdf" ];
      then
        if [ -z "${STREAMID}" ];
	then
          CMD=$(echo "${SCAPSCANXCCDF_NOPROFILE}" | sed -e "s:@@STREAMNAME@@:${STREAMNAME}:g" -e "s:@@XCCDFRESULTNAME@@:${STREAMNAME%%.xml}-xccdf-results.xml:g" -e "s:@@OVALRESULTNAME@@:${STREAMNAME%%.xml}-oval-results.xml:g");
	else
          CMD=$(echo "${SCAPSCANXCCDF}" | sed -e "s:@@STREAMNAME@@:${STREAMNAME}:g" -e "s:@@XCCDFRESULTNAME@@:${STREAMNAME%%.xml}-xccdf-results.xml:g" -e "s:@@OVALRESULTNAME@@:${STREAMNAME%%.xml}-oval-results.xml:g" -e "s:@@STREAMID@@:${STREAMID}:g");
	fi
	echo "Running ${CMD}";
	cd ${TMPDIR};
	${CMD};
	sendResults ${STREAMNAME%%.xml}-xccdf-results.xml;
	# Hack because oscap does not allow providing filename for oval results
        OVALFILES=$(grep check-content-ref.*oval: ${STREAMNAME} | sed -e 's:.*href="\([^"]*\)".*:\1:g' | sort | uniq);
	for OVALFILE in ${OVALFILES};
	do
          sendResults ${OVALFILE}.result.xml;
	done
	# Now send oval results if they exist
        if [ -f ${STREAMNAME%%.xml}-oval-results.xml ];
	then
          sendResults ${STREAMNAME%%.xml}-oval-results.xml;
	fi
      elif [ "${STREAMTYPE}" = "oval" ];
      then
        if [ -z "${STREAMID}" ];
	then
          CMD=$(echo "${SCAPSCANOVAL_NOID}" | sed -e "s:@@STREAMNAME@@:${STREAMNAME}:g" -e "s:@@OVALRESULTNAME@@:${STREAMNAME%%.xml}-oval-results.xml:g");
	else
          CMD=$(echo "${SCAPSCANOVAL}" | sed -e "s:@@STREAMNAME@@:${STREAMNAME}:g" -e "s:@@OVALRESULTNAME@@:${STREAMNAME%%.xml}-oval-results.xml:g" -e "s:@@STREAMID@@:${STREAMID}:g");
	fi
	echo "Running ${CMD}";
	cd ${TMPDIR};
	${CMD};
	sendResults ${STREAMNAME%%.xml}-oval-results.xml;
      else
        echo "!! Type ${STREAMTYPE} is not known.";
      fi;
    else
      echo "!! Stream ${REPO}/stream/${STREAMPATH} could not be found";
    fi
    echo "";
  done
}

##
## Main 
##
if [ "$1" = "-d" ];
then
  [ $2 -gt 1 ] || die 2 "Parameter $2 is not a valid port number";
  PORT="${2}";
  REPO="${3}";
else
  REPO="${1}";
fi


# We are a shell script, so 'unix' seems obvious (for now)
CLASS="unix"
DOMAIN="$(dnsdomainname)"
[ -z "${DOMAIN}" ] && DOMAIN="localdomain"
FQDN="$(hostname).${DOMAIN}"

echo "Poor Man Central SCAP Agent v0.1";
echo "";

echo "Detected local variables from system.";
echo "REPO   = ${REPO}";
echo "FQDN   = ${FQDN}";
echo "DOMAIN = ${DOMAIN}";
echo "CLASS  = ${CLASS}";
echo "PORT   = ${PORT}";
echo "";

# Retrieve configuration variables from central configuration repository
setConfigurationVariables;

if [ -n "${PORT}" ];
then
  daemonize;
else
  getStreamList;
  evaluateStreams;
fi

cd ${CDIR};
rm -rf ${TMPDIR};
