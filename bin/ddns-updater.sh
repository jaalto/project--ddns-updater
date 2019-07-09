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
VERSION="2019.0709.0430"
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
  -S, --syslog   Send status to syslog.
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

  $CONF/duckdns.conf
  DUCKDNS_DOMAINS=host,host...
  DUCKDNS_TOKEN=yourtoken

  $CONF/henet.conf
  HENET_DOMAIN=host.exmaple.com
  HENET_PASS=password

  Program configuration file (read in this order):

  /etc/defaults/ddns-updater.conf
  $HOME/.ddns-updater

  Internal files:

  $CONF/00.ip            Current ip
  $CONF/00.updated       contains YYYY-MM-DD HH:MM of last update"

DUCKDNS_FILE_CONF=$CONF/duckdns.conf
DUCKDNS_FILE_LOG=$CONF/duckdns.log
DUCKDNS_URI_VERBOSE="&verbose=true"

HENET_FILE_CONF=$CONF/henet.conf
HENET_FILE_LOG=$CONF/henet.log

# Use prefix 00.* to make data files to appear first in ls(1)
FILE_IP=$CONF/00.ip
FILE_TIMESTAMP=$CONF/00.updated

# Can be set in program configuration file

URL_WHATSMYIP=ifconfig.co
MSG_PREFIX="[DDNS-UPDATER] "
CURL_OPTS="--max-time 10"
WGET_OPTS="--timeout=10"

Version ()
{
    echo "$VERSION $LICENSE $AUTHOR $HOMEPAGE"
}

Verbose ()
{
    [ "$VERBOSE" ] && echo "$MSG_PREFIX$*"
}

Msg ()
{
    echo "$MSG_PREFIX$*"
}

Warn ()
{
    Msg "$*" >&2
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

SyslogWrite ()
{
   status=$1
   id=$2
   ip=$3
   msg=$4

    case "$status" in
      *good*)
        logger -p local0.info   -t $id "OK: $ip address updated$msg" ;;
      *nochange*)
        logger -p local0.notice -t $id "OK: $ip address no change$msg" ;;
      *)
        logger -p local0.err    -t $id "ERROR: $ip address not updated$msg" ;;
    esac
}

Syslog ()
{
    if [ "$SYSLOG" ]; then
        SyslogWrite "$@"
    fi
}

IpPrevious ()
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
            ${TEST:+echo} curl --silent --insecure --output "$logfile" $CURL_OPTS "$1"
        else
            ${TEST:+echo} curl --silent --insecure $CURL_OPTS "$1"
        fi
    elif which wget > /dev/null 2>&1 ; then
        if [ "$logfile" ]; then
            ${TEST:+echo} wget --quiet --output-document="$logfile" $WGET_OPTS "$1"
        else
            ${TEST:+echo} wget --quiet $WGET_OPTS "$1"
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

IpCurrent ()
{
    if [ "$TEST" ]; then
        echo "0.0.0.0"
    else
        Webcall $URL_WHATSMYIP
    fi
}

IsHenet ()
{
    [ -f "$HENET_FILE_CONF" ] || return 1
    . $HENET_FILE_CONF
}

HenetStatus ()
{
    [ -f "$HENET_FILE_LOG" ] || return 2

    if [ "$VERBOSE" ]; then
        cat $HENET_FILE_LOG
    fi

    # on success, either:
    #   good 192.168.0.1
    #   nochg 192.168.0.1

    [ "$VERBOSE" ] && cat $HENET_FILE_LOG

    str=$(cat $HENET_FILE_LOG | tr '\n' ' ' | sed 's,[ \ŧ]*$,,')

    case "$str" in
        *good*)
            Syslog nochange DNS-HENET $ip
            return 0
            ;;
        *nochg*) Syslog good DNS-HENET $ip
             return 0
             ;;
        *)  Syslog error DNS-HENET $ip "$str"
            return 1
    esac
}

Henet ()
{
    ip=$1

    domain=$(sed -e 's/[ \t]*//' $HENET_FILE_DOMAIN)
    pass=$(cat $HENET_FILE_PASS)

    if [ ! "$pass" ] ; then
        Die "ERROR: no password in: $HENET_FILE_PASS"
    fi

    if [ ! "$domain" ]; then
        Die "ERROR: No FQDN in: $HENET_FILE_DOMAIN"
    fi

    # https://dns.he.net/docs.html
    # http://[your domain name]:[your password]@dyn.dns.he.net/nic/update?hostname=[your domain name]
    # username is also the hostname
    #
    # https://dyn.dns.he.net/nic/update?hostname=$HOST&password=$PASS&myip=$IP"

    url="https://$domain:$pass@dyn.dns.he.net/nic/update?hostname=$domain&myip=$ip"

    Verbose "Info: Updating Henet..."
    CURL_OPTS="--max-time=10 --ipv4" Webcall "$HENET_FILE_LOG" "$url"
    Verbose "Info: Updating Henet...done"
}

IsDuckdns ()
{
    [ -f "$DUCKDNS_FILE_CONF" ] || return 1
    . $DUCKDNS_FILE_CONF
}

DuckdnsStatus ()
{
    ip=$1

    [ -f "$DUCKDNS_FILE_LOG" ] || return 2

    [ "$VERBOSE" ] && cat $DUCKDNS_FILE_LOG

    str=$(cat $DUCKDNS_FILE_LOG | tr '\n' ' ' | sed 's,[ \ŧ]*$,,')

    case "$str" in
        *NOCHANGE*)
            Syslog nochange DNS-DUCK $ip
            return 0
            ;;
        OK*) Syslog good DNS-DUCK $ip
             return 0
             ;;
        *)  Syslog error DNS-DUCK $ip "$str"
            return 1
    esac
}

Duckdns ()
{
    ip=$1
    domains=$DUCKDNS_DOMAINS
    token=$DUCKDNS_TOKEN

    if [ ! "$token" ] ; then
        Die "ERROR: No DUCKDNS_TOKEN in $DUCKDNS_FILE_CONF"
    fi

    if [ ! "$domains" ]; then
        Die "ERROR: No DUCKDNS_DOMAINS in $DUCKDNS_FILE_CONF"
    fi

    url="https://www.duckdns.org/update?domains=$domains&token=$token&ip=$ip$DUCKDNS_URI_VERBOSE"

    Verbose "Info: Updating Duckdns..."
    Webcall "$DUCKDNS_FILE_LOG" "$url"

    # Add missing last NEWLINE
    [ "$TEST" ] || echo >> $DUCKDNS_FILE_LOG

    if [ "$VERBOSE" ]; then
        # Delete empty lines
        sed '/^[ \t]*$/d' $DUCKDNS_FILE_LOG
    fi

    Verbose "Info: Updating Duckdns...done"
}

ReadConfiguration ()
{
    [ -f /etc/defaults/ddns-updater.conf ] &&
        . /etc/defaults/ddns-updater.conf

    [ -f $HOME/.ddns-updater ] &&
        . $HOME/.ddns-updater
}

Main ()
{
    unset TEST

    ReadConfiguration

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
            -S | --syslog)
                shift
                SYSLOG=syslog
                ;;
            -t | --test | --dry-run)
                shift
                Msg "** Running in test mode, no network calls"
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

    ip_prev=$(IpPrevious)
    ip=$(IpCurrent)

    Verbose "IP old: $ip_prev"
    Verbose "IP now: $ip"

    if [ ! "$ip" ] || [ "$ip" = "0.0.0.0" ] ; then
        Warn "WARN: current IP address not available"
    fi

    if [ "$status" ]; then
        date=$(cat $FILE_TIMESTAMP 2> /dev/null)
        str=" Last-updated: $date"

        if [ ! "$date" ]; then
            str=" Last-updated: UNKNOWN (timestamp not available)"
        fi

        if [ "$ip_prev" = "$ip" ]; then
            Msg "OK IP: $ip (update not needed)$str"
        else
            if [ "$ip_prev" ]; then
                ip_prev="was $ip_prev"
            else
                ip_prev="previous IP UNKNOWN"
            fi

            Msg "NOK IP: $ip (update needed, $ip_prev).$str"
        fi

        return 0
    fi

    if [ ! "$FORCE" ] && [ "$ip_prev" = "$ip" ]; then
        Verbose "Info: Nothing to update"
        return 0
    else

        if [ ! "$ip" ] && [ ! "$TEST" ]; then
            Die "WARN: Cannot update. Current IP address not available"
        fi

        [ "$TEST" ] || echo $ip > $FILE_IP
        [ "$TEST" ] || Date > $FILE_TIMESTAMP

        done=
        status=0

        IsDuckdns && { Duckdns $ip ; DuckdnsStatus $ip; status=$? ; done=done ;}
        IsHenet   && { Henet $ip ; HenetStatus $ip; status=$? ; done=done ; }

        if [ ! "$done" ]; then
            Die "WARN: No DDNS configuration files. See --help."
        fi

        return $status
    fi
}

Main "$@"

# End of file
