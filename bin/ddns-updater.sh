#! /bin/sh
#
#   Copyright
#
#       Copyright (C) 2019 Jari Aalto <jari.aalto@cante.net>
#
#   License
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#   Description
#
#       Dynamic DNS (DDNS) update client.
#
#       See --help. Configuration files must exist before use.

AUTHOR="Jari Aalto <jari.aalto@cante.net>"
VERSION="2019.0708.1306"
LICENSE="GPL-2+"

# See https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html

if [ "$XDG_CONFIG_HOME" ]; then
    CONFHOME=$XDG_CONFIG_HOME/ddns-updater
else
    CONFHOME=$HOME/.config/ddns-updater
fi

CONF=

for dir in $CONFHOME /etc/ddns-updater
do
    if [ -d "$dir" ]; then
        CONF=$dir
    fi
done

HELP="\
Synopsis: $0 [option]

DESCRIPTION
  Updates IP address to DDNS services: duckdns.org and
  dns.he.net

OPTIONS
  -f, --force    Force update even if IP is same.
  -s, --status   Show status and exit.
  -t, --test     Run in test mode. No network update.
  -v, --verbose  Display verbose messages.
  -V, --version  Display version information and exit.
  -h, --help     Display short help.

  Please note that stacking of short options is not supported. E.g.
  -v -f cannot be combined into -vf.

DIRECTORIES

  CONFDIR Configuration directories searched in order:

  \$HOME/.config/ddns-updater
  /etc/ddns-updater

FILES
  Configuration files:

  # For duckdns.org
  $CONF/duckdns.domains  Comma separated list of the subnames (not FQDN)
  $CONF/duckdns.token    The token of account (see your profile)

  # For dns.he.org
  $CONF/henet.domains    Comma separated list of the subnames
  $CONF/henet.pass       The account password

  Internal house keeping files:

  $CONF/00.ip             Current ip
  $CONF/00.updated        contains YYYY-MM-DD HH:MM of last update"

DUCKDNS_FILE_DOMAINS=$CONF/duckdns.domains
DUCKDNS_FILE_TOKEN=$CONF/duckdns.token
DUCKDNS_FILE_LOG=$CONF/duckdns.log
DUCKDNS_URI_VERBOSE="&verbose=true"

HENET_FILE_DOMAINS=$CONF/henet.domains
HENET_FILE_PASS=$CONF/henet.pass
HENET_FILE_LOG=$CONF/henet.log

# Use prefix 00.* to make data files to appear first in ls(1)
FILE_IP=$CONF/00.ip
FILE_TIMESTAMP=$CONF/00.updated

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

Help ()
{
    echo "$HELP" | sed "s,$HOME,~,g"
}

Webcall ()
{
    # ARGUMENTS: URL [LOGFILE]
    logfile=$2

    if which curl > /dev/null 2>&1 ; then
        if [ "$logfile" ]; then
            ${TEST:+echo} curl --silent --insecure --output "$logfile" "$1"
        else
            ${TEST:+echo} curl --silent --insecure "$1"
        fi
    elif which wget > /dev/null 2>&1 ; then
        if [ "$logfile" ]; then
            ${TEST:+echo} wget --quiet --output-document="$logfile" "$1"
        else
            ${TEST:+echo} wget --quiet "$1"
        fi
    elif which lynx > /dev/null 2>&1 ; then
        if [ "$logfile" ]; then
            lynx --dump "$2" > "$logfile"
        else
            lynx --dump "$2"
        fi
    else
        Die "ERROR: No programs to access web: curl, wget or lynx"
    fi
}

CurrentIP ()
{
    if [ "$TEST" ]; then
        echo "0.0.0.0"
    else
        Webcall ifconfig.co
    fi
}

IsHenet ()
{
    [ -f "$HENET_FILE_PASS" ]
}

HenetStatus ()
{
    [ -f "$HENET_FILE_LOG" ] || return 2

    if [ "$VERBOSE" ]; then
        cat $HENET_FILE_LOG
    fi

    grep "^OK" $HENET_FILE_LOG > /dev/null 2>&1
}

Henet ()
{
    :
}

IsDuckdns ()
{
    [ -f "$DUCKDNS_FILE_TOKEN" ]
}

DuckdnsStatus ()
{
    [ -f "$DUCKDNS_FILE_LOG" ] || return 2

    grep "^OK" $DUCKDNS_FILE_LOG > /dev/null 2>&1
}

Duckdns ()
{
    domains=$(sed -e 's/[ \t]*//' $DUCKDNS_FILE_DOMAINS)
    token=$(cat $DUCKDNS_FILE_TOKEN)

    if [ ! "$token" ] ; then
        Die "ERROR: No token id in: $DUCKDNS_FILE_TOKEN"
    fi

    if [ ! "$domains" ]; then
        Die "ERROR: No subdomains in: $DUCKDNS_FILE_DOMAINS"
    fi

    if grep "\." $DUCKDNS_FILE_DOMAINS ; then
        Die "ERROR: FQDN names not allowed, only subdomains" \
            "names in: $DUCKDNS_FILE_DOMAINS"
    fi

    url="https://www.duckdns.org/update?domains=$domains&token=$token&ip=$ip$DUCKDNS_URI_VERBOSE"

    Echo "Info: Updating Duckdns..."
    Webcall "$DUCKDNS_LOG" "$url"

    # Add missing last NEWLINE
    [ "$TEST" ] || echo >> $DUCKDNS_LOG

    if [ "$VERBOSE" ]; then
        # Delete empty lines
        sed '/^[ \t]*$/d' $DUCKDNS_FILE_LOG
    fi

    Echo "Info: Updating Duckdns...done"
}

Main ()
{
    unset TEST

    while :
    do
        case "$1" in
            -f | --force)
                shift
                FORCE=force
                ;;
            -s | --status)
                shift
                status=status
                ;;
            -t | --test | --dry-run)
                shift
                echo "** Running in test mode, no network calls"
                VERBOSE=verbose
                TEST=test
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
                Help
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

    if [ ! "$CONF" ] ; then
        Die "ERROR: No configuration directory: $CONFHOME"
    fi

    if [ ! -d "$CONF" ]; then
        Die "ERROR: No configuration directory: $CONF"
    fi

    ip_old=$(OldIP)
    ip=$(CurrentIP)

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

    if [ ! "$FORCE" ] && [ "$ip_old" = "$ip" ]; then
        Echo "Info: Nothing to update"
        return 0
    else
        echo $ip > $FILE_IP
        Date > $FILE_TIMESTAMP

        done=
        status=0

        IsDuckdns && { Duckdns $ip ; DuckdnsStatus; status=$? ; done=done ;}
        IsHenet   && { Henet $ip ; HenetStatus; status=$? ; done=done ; }

        if [ ! "$done" ]; then
            Die "WARN: No DDNS configuration files. See --help."
        fi

        return $status
    fi
}

Main "$@"

# End of file
