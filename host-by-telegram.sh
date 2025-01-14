#!/usr/bin/env bash
## /etc/icinga2/scripts/host-by-telegram.sh / 20170330
## Last updated 20190820
## Last tests used 2.11.2-1.buster

# Copyright (C) 2018 Marianne M. Spiller <github@spiller.me>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

PROG="`basename $0`"
HOSTNAME="`hostname`"
TRANSPORT="curl"
unset DEBUG

if [ -z "`which $TRANSPORT`" ] ; then
  echo "$TRANSPORT not in \$PATH. Consider installing it."
  exit 1
fi

Usage() {
cat << EOF

host-by-mail notification script for Icinga 2 by spillerm <github@spiller.me>

The following are mandatory:
  -4 HOSTADDRESS (\$address$)
  -6 HOSTADDRESS6 (\$address6$)
  -d LONGDATETIME (\$icinga.long_date_time$)
  -l HOSTALIAS (\$host.name$)
  -n HOSTDISPLAYNAME (\$host.display_name$)
  -o HOSTOUTPUT (\$host.output$)
  -p TELEGRAM_BOT (\$telegram_bot$)
  -q TELEGRAM_CHATID (\$telegram_chatid$)
  -r TELEGRAM_BOTTOKEN (\$telegram_bottoken$)
  -s HOSTSTATE (\$host.state$)
  -t NOTIFICATIONTYPE (\$notification.type$)

And these are optional:
  -b NOTIFICATIONAUTHORNAME (\$notification.author$)
  -c NOTIFICATIONCOMMENT (\$notification.comment$)
  -i HAS_ICINGAWEB2 (\$icingaweb2url$, Default: unset)
  -v (\$notification_logtosyslog$, Default: false)
  -D DEBUG enable debug output - meant for CLI debug only

EOF

exit 1;
}

while getopts 4:6::b:c:d:hi:l:n:o:p:q:r:s:t:u:v:D opt
do
  case "$opt" in
    4) HOSTADDRESS=$OPTARG ;;
    6) HOSTADDRESS6=$OPTARG ;;
    b) NOTIFICATIONAUTHORNAME=$OPTARG ;;
    c) NOTIFICATIONCOMMENT=$OPTARG ;;
    d) LONGDATETIME=$OPTARG ;;
    h) Usage ;;
    i) HAS_ICINGAWEB2=$OPTARG ;;
    l) HOSTALIAS=$OPTARG ;;
    n) HOSTDISPLAYNAME=$OPTARG ;;
    o) HOSTOUTPUT=$OPTARG ;;
    p) TELEGRAM_BOT=$OPTARG ;;
    q) TELEGRAM_CHATID=$OPTARG ;;
    r) TELEGRAM_BOTTOKEN=$OPTARG ;;
    s) HOSTSTATE=$OPTARG ;;
    t) NOTIFICATIONTYPE=$OPTARG ;;
    v) VERBOSE=$OPTARG ;;
    D) DEBUG=1; echo -e "\n**********************************************\nWARNING: DEBUG MODE, DEACTIVATE ASAP\n**********************************************\n" ;;
   \?) echo "ERROR: Invalid option -$OPTARG" >&2
       Usage ;;
    :) echo "Missing option argument for -$OPTARG" >&2
       Usage ;;
    *) echo "Unimplemented option: -$OPTARG" >&2
       Usage ;;
  esac
done

## Build the message's subject
SUBJECT="[$NOTIFICATIONTYPE] $SERVICEDISPLAYNAME on $HOSTDISPLAYNAME is $SERVICESTATE!"

## Build the message itself
NOTIFICATION_MESSAGE=$(cat << EOF
$HOSTDISPLAYNAME ($HOSTALIAS) is $HOSTSTATE!
When?    $LONGDATETIME
Info?    $HOSTOUTPUT
Host?    $HOSTALIAS
IPv4?    $HOSTADDRESS
EOF
)

## Is this host IPv6 capable?
if [ -n "$HOSTADDRESS6" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
IPv6?    $HOSTADDRESS6"
fi
## Are there any comments? Put them into the message!
if [ -n "$NOTIFICATIONCOMMENT" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
Comment by $NOTIFICATIONAUTHORNAME:
  $NOTIFICATIONCOMMENT"
fi
## Are we using Icinga Web 2? Put the URL into the message!
if [ -n "$HAS_ICINGAWEB2" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
Get live status:
  $HAS_ICINGAWEB2/monitoring/host/show?host=$HOSTALIAS"
fi
## Build the message's subject
SUBJECT="[$NOTIFICATIONTYPE] Host $HOSTDISPLAYNAME is $HOSTSTATE!"

## debug output or not
if [ -z $DEBUG ];then
    CURLARGS="--silent --output /dev/null"
else
    CURLARGS=-v
    set -x
    echo -e "DEBUG MODE!"
fi

## And finally, send the message
## if needed to comply with 4096 characters limit, try to split around a newline near every 3000 characters to have a margin for possible encodings

EX=0
HTTP_CODES=()
STATUSES=()
send_message() {
  TXT="$1"
  HTTP_CODE=`/usr/bin/curl $CURLARGS \
      --data-urlencode "chat_id=${TELEGRAM_CHATID}" \
      --data-urlencode "text=${TXT}" \
      --data-urlencode "parse_mode=HTML" \
      --data-urlencode "disable_web_page_preview=true" \
      --write-out "%{http_code}" \
      "https://api.telegram.org/bot${TELEGRAM_BOTTOKEN}/sendMessage"`
  STATUS=$?
  if [ $EX -eq 0 ]; then
    [ "$STATUS" = 0 -a "$HTTP_CODE" = 200 ]
    EX=$?
  fi
  HTTP_CODE=("${HTTP_CODES[@]}" "$HTTP_CODE")
  STATUSES=("${STATUSES[@]}" "$STATUS")
}

readarray -t MESSAGE_LINES <<< "$NOTIFICATION_MESSAGE"
MESSAGE="${MESSAGE_LINES[0]}"
MESSAGE_LINES=("${MESSAGE_LINES[@]:1}")
for LINE in "${MESSAGE_LINES[@]}" ; do
  if [[ ${#MESSAGE}+${#LINE}+1 -gt 3000 ]]; then
    send_message "$MESSAGE"
    MESSAGE="$LINE"
  else
    MESSAGE="$MESSAGE"$'\n'"$LINE"
  fi
done
if [ -n "$MESSAGE" ] && [[ ! $MESSAGE =~ ^$'\n'*$ ]]; then
  send_message "$MESSAGE"
fi
set +x

## Are we verbose? Then put a message to syslog...
if [ "$VERBOSE" == "true" ] ; then
  logger "$PROG sent $SUBJECT => Telegram Channel $TELEGRAM_BOT (${#NOTIFICATION_MESSAGE} chars) code: ${HTTP_CODES[@]} status: ${STATUSES[@]}"
fi

# exit 0 if no errors from curl request, else exit non-zero
exit $EX
