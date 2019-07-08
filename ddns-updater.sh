# /bin/sh
#
# crontab -e
# */30 * * * * ~/.duckdns/duckdns.sh >/dev/null 2>&1

AUTHOR="Jari Aalto <jari.aalto@cante.net>"
VERSION="2019.0708.0909"
LICENSE="GPL-2+"

CONF=$HOME/.duckdns
DOMFILE=$CONF/domains
DOMAINS=$(sed -e 's/[ \t]*//' $DOMFILE)
TOKEN=$(cat $CONF/token)
LOG=$CONF/log
FILE_IP=$CONF/ip
FILE_TIMESTAMP=$CONF/last-update
VERBOSE_URI="&verbose=true"

HELP="\
Synopsis: $0 [option]

DESCRIPTION
  Updates IP address to service duckdns.org

OPTIONS
  -f, --force    Force update even if IP is same.
  -s, --status   Show status and exit.
  -v, --verbose  Display verbose output.
  -V, --version  Display version information and exit.
  -h, --help     Display short help.

FILES
  These files must exist:

  $CONF/domains  Comma separated list of the subnames
  $CONF/token    The token of account (see your profile)"

Version ()
{
    echo "$VERSION $LICENSE $AUTHOR $HOMEPAGE"
}

Echo ()
{
    [ "$VERBOSE" ] && echo "$*"
}

Warn ()
{
    echo "$*" >&2
}

Die ()
{
    Warn "$*"
    exit 1
}

Date ()
{
    date "+%Y-%m-%d %H:%M"
}

OldIP ()
{
    cat $FILE_IP 2> /dev/null
}

CurrentIP ()
{
    curl --silent ifconfig.co
}

Status ()
{
    # Linus commands do not display anything by default but
    # return status code, like:
    #
    # <command> ; echo $?

    if [ "$VERBOSE" ]; then
        cat $LOG
    fi

    grep "^OK" $LOG > /dev/null 2>&1
}

Main ()
{
    while :
    do
        case "$1" in
            -f | --force)
                shift
                force=force
                ;;
            -s | --status)
                shift
                status=status
                ;;
            -v | --verbose)
                shift
                VERBOSE=verbose
                ;;
            -V | --version)
                shift
                Version
                return 0
                ;;
            -h | --help)
                shift
                echo "$HELP"
                return 0
                ;;
            -*) Warn "WARN: Unknown option: $1"
                shift
                ;;
            --) shift
                break
                ;;
            *)  break
                ;;
        esac
    done

    if [ ! -d "$CONF" ]; then
        Die "ERROR: No configuration directory: $CONF"
    fi

    if [ ! "$DOMAINS" ]; then
        Die "ERROR: No subdomains in: $DOMFILE"
    fi

    if grep "\." $DOMFILE ; then
        Die "ERROR: FQDN names not allowed, only subdomains names in: $DOMFILE"
    fi

    if [ ! "$TOKEN" ] ; then
        Die "ERROR: No token id in: $CONF/token"

    fi

    ip_old=$(OldIP)
    ip=$(CurrentIP)
    url="https://www.duckdns.org/update?domains=$DOMAINS&token=$TOKEN&ip=$ip$VERBOSE_URI"

    Echo "IP old: $ip_old"
    Echo "IP now: $ip"

    if [ "$status" ]; then
        date=$(cat $FILE_TIMESTAMP 2> /dev/null)
        str=" Upated: $date"

        if [ ! "$date" ]; then
            str=" Updated: UNKNOWN (timestamp not available until next update)"
        fi

        if [ "$ip_old" = "$ip" ]; then
            echo "OK IP: $ip (update not needed)$str"
        else
            if ["$ip_old" ]; then
                ip_old="was $ip_old"
            else
                ip_old="old ip UNKNOWN"
            fi

            echo "NOK IP: '$ip' (update needed, $old_ip).$str"
        fi

        return 0
    fi

    if [ ! "$force" ] && [ "$ip_old" = "$ip" ]; then
        Echo "Info: Nothing to update"
        return 0
    else
        echo $ip > $FILE_IP
        Date > $FILE_TIMESTAMP
        Echo "Info: Updating..."
        curl --silent --insecure --output $LOG "$url"
        Echo "Info: Updating...done"
        Status
    fi
}

Main "$@"

# End of file
