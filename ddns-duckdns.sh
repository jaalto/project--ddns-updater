# /bin/sh
#
# crontab -e
# */30 * * * * ~/.duckdns/duckdns.sh >/dev/null 2>&1

CONF=$HOME/.duckdns
DOMAIN=$(cat $CONF/domain)
TOKEN=$(cat $CONF/token)
LOG=$CONF/log
IP_FILE=$CONF/ip

ip_old=$(cat $IP_FILE 2> /dev/null)
ip=$(curl --silent ifconfig.co)  # Get current IP
url="https://www.duckdns.org/update?domains=$DOMAIN&token=$TOKEN&ip=$ip"

if [ "$DOMAIN" ] &&
   [ "$TOKEN" ] &&
   [ ! "$ip_old" = "$ip" ]
then
    echo $ip > $IP_FILE
    curl --silent --insecure --output $LOG "$url"
fi
