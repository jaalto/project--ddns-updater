#! /bin/sh
#
#   Copyright
#
#       Copyright (C) 2019-2021 Jari Aalto <jari.aalto@cante.net>
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
#
#   Style Guide
#
#       - Indentation: 4 spaces.
#       - Global variables are capitalized.
#       - The "local" keyword is not used for variables.
#         It is not defined in POSIX /bin/sh although almost
#         all linux shells have added the support. Some routers
#         still may have older shells.
#
#      Note, that program cannot expect to have GNU utilities and
#      their options. This means using:
#
#           egrep ...  /dev/null 2>&1
#
#       Instead of calls like:
#
#           grep --extended-regexp --quiet ...

AUTHOR="Jari Aalto <jari.aalto@cante.net>"
VERSION="2021.0129.1739"
LICENSE="GPL-2+"
HOMEPAGE="https://github.com/jaalto/project--ddns-updater"

PROGRAM=ddns-updater

# mktemp(1) would be an external program
TMPDIR=${TMPDIR:-/tmp}
TMPBASE=$TMPDIR/$PROGRAM.$$

if [ ! "$PATH" ]; then
    PATH="/usr/bin:/usr/local/bin"
fi

# -----------------------------------------------------------------------
# CONFIGURATION DIRECRECTORIES
# -----------------------------------------------------------------------

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

CONF_PRORRAM="\
/etc/defaults/ddns-updater.conf \
$HOME/.ddns-updater"

# -----------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------

HELP="\
Synopsis: $0 [option]

DESCRIPTION
  Updates IP address to DDNS services: duckdns.org and
  dns.he.net

OPTIONS
  -c, --config NAME  Read configuration NAME (or path)
  -f, --force        Force update even if IP is same.
  -l, --list         List status of configuration files and exit.
  -L, --log          Display log file and exit.
  -s, --status       Show status and exit.
  -S, --syslog       Send status to syslog. Only for root (in cron).
  -t, --test         Run in test mode. No network update.
  -v, --verbose      Display verbose messages.
  -V, --version      Display version information and exit.
  -h, --help         Display short help.

  Please note that stacking of short options is not supported. E.g.
  -v -f cannot be combined into -vf.

DIRECTORIES

  CONFDIR Configuration directory searched is one of:

  \$HOME/.config/ddns-updater
  /etc/ddns-updater

FILES
  Configuration files:

  $CONF/*.conf

  Program's configuration file (read in this order):

  /etc/defaults/ddns-updater.conf
  $HOME/.ddns-updater

  Internal files:

  $CONF/00.ip            Last update - ip address
  $CONF/00.log           Last update - error log
  $CONF/00.updated       Last update - YYYY-MM-DD HH:MM"

# -----------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------

LOGGER=    # Syslog support. In debian this is in package bsdutils

if [ -x /usr/bin/logger ]; then
    LOGGER=logger
else
    tmp=$(which logger 2> /dev/null)
    [ "$tmp" ] && LOGGER=$tmp
fi

# Use prefix 00.* for files to appear first in ls(1) listing

FILE_IP="$CONF/00.ip"
FILE_LOG="$CONF/00.log"
FILE_TIMESTAMP="$CONF/00.updated"

# Can be set in program's configuration file <program>.conf

URL_WHATSMYIP=ifconfig.co
MSG_PREFIX="DDNS-UPDATER "
CURL_OPTIONS="--max-time 15"
WGET_OPTIONS="--timeout=15"

# -----------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------

Atexit ()
{
    rm -f "$TMPBASE"*   # Clean up temporary files
}

Version()
{
    echo "$VERSION $LICENSE $AUTHOR $HOMEPAGE"
}

Verbose()
{
    [ "$VERBOSE" ] && echo "$MSG_PREFIX$*"
}

Msg()
{
    echo "$MSG_PREFIX$*"
}

Warn()
{
    Msg "$*" >&2
}

Which ()
{
    # retruns status code only
    which "$1" > /dev/null 2>&1
}

EmptyFile ()
{
    : > "$1"   # The True operator. An echo would add a newline.
}

SyslogStatusWrite()
{
    status=$1
    id=$2
    ip=$3
    msg=$4

    [ "$LOGGER" ] || return 1

    case "$status" in
      *good*)
        $LOGGER -p local0.info   -t $id "OK: $ip address updated$msg" ;;
      *nochange*)
        $LOGGER -p local0.notice -t $id "OK: $ip address no change$msg" ;;
      *)
        $LOGGER -p local0.err    -t $id "ERROR: $ip address not updated$msg" ;;
    esac
}

SyslogStatusUpdate()
{
    if [ "$SYSLOG" ]; then
        SyslogStatusWrite "$@"
    fi
}

SyslogMsg()
{
    if [ "$SYSLOG" ]; then
        logger -p local0.err    -t DDNS-MSG "$*"
    fi
}

Log()
{
    Warn "$*"
    SyslogMsg "$*"
}

Die()
{
    Warn "$*"
    exit 1
}

Date()
{
    date "+%Y-%m-%d %H:%M"
}

ReadFileAsString()
{
    # Remove newlines
    cat "$1" | tr '\n' ' ' | sed 's,[ \ŧ]*$,,'
}

IpPrevious()
{
    [ -f "$FILE_IP" ] || return 1

    cat "$FILE_IP" 2> /dev/null
}

Help()
{
    echo "$HELP" | sed "s,$HOME,~,g"
}

ConvertHOME()
{
    # Instead of long /mount/some/home/USER, use "~"
    echo $1 | sed "s,$HOME,~,"
}

Webcall()
{
    # ARGUMENTS: URL [LOGFILE]
    logfile=$2

    echo "Webcall() $*" >> "$FILE_LOG"

    if Which curl ; then
        if [ "$logfile" ]; then
            ${TEST:+echo} curl --silent --insecure --output "$logfile" $CURL_OPTIONS "$1" 2>> "$FILE_LOG"
        else
            ${TEST:+echo} curl --silent --insecure $CURL_OPTIONS "$1" 2>> "$FILE_LOG"
        fi
    elif Which wget ; then
        if [ "$logfile" ]; then
            # Filter out the status message
            ${TEST:+echo} wget --no-verbose --output-document="$logfile" $WGET_OPTIONS "$1" 2>> "$FILE_LOG"
        else
            ${TEST:+echo} wget --no-verbose --output-document=- $WGET_OPTIONS "$1" 2>> "$FILE_LOG"
        fi
    elif Which lynx ; then
        if [ "$logfile" ]; then
            lynx --dump "$2" > "$logfile" 2>> "$FILE_LOG"
        else
            lynx --dump "$2" 2>> "$FILE_LOG"
        fi
    else
        Die "ERROR: Not any programs found in PATH: curl, wget or lynx"
    fi
}

WhatsmyipParse ()
{
    # <p><code class="ip">81.4.110.124</code></p>
    awk '
    /code class=.*ip/ {
	 sub("</code>.*","")
	 sub("^.*>","")
	 print
	 exit
     }
     /^[ \t]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
	 print $1
	 exit
     }
     ' "$@"
}

Whatsmyip ()
{
    tmpwhatsmyip="$TMPBASE.whatsmyip"

    # Can't use pipe. Might call Die()
    Webcall $URL_WHATSMYIP > "$tmpwhatsmyip"

    [ -s "$tmpwhatsmyip" ] || return 1

    WhatsmyipParse "$tmpwhatsmyip"
}

IpCurrent()
{
    if [ "$TEST" ]; then
        echo "0.0.0.0"
    else
        Whatsmyip
    fi
}

# -----------------------------------------------------------------------
# FUNCTIONS: SERVICE PROVIDER
# -----------------------------------------------------------------------

ServiceLogFile ()
{
    echo ${1%.conf}.log
}

ServiceId ()
{
    # /path/service.conf => service
    id=${1##*/}
    id=${id%.conf}
    echo "$id" | tr 'a-z' 'A-Z'
}

ServiceStatus()
{(  # Run in a subshell.
    # Isolate program from variables introduced by "sourcing"

    ip=$1
    file=$2
    log=$(ServiceLogFile "$file")
    id=$(ServiceId "$file")

    if [ ! -f "$file" ]; then   # No configuration file?
        return 0
    fi

    if [ ! -f "$log" ]; then   # configuration file but no update yet
        return 0
    fi

    [ "$VERBOSE" ] && cat $log

    . "$file"       # Source configuration file

    # Make sure variables got defined

    if [ ! "$REGEXP_OK" ]; then
        Log "ERROR: Missing variable REGEXP_OK in $file"
        return 1
    fi

    if [ ! "$REGEXP_NOCHANGE" ]; then
       Log "ERROR: Missing variable REGEXP_NOCHANGE in $file"
       return 1
    fi

    if egrep "$REGEXP_NOCHANGE" "$log" > /dev/null 2>&1 ; then
        # Disabled: do not add additional noise to syslog
        # SyslogStatusUpdate nochange DNS-HENET $ip
        return 0
    elif egrep "$REGEXP_OK" "$log" > /dev/null 2>&1 ; then
        SyslogStatusUpdate good  DDNS-$id $ip
        return 0
    else
        SyslogStatusUpdate error DDNS-$id $ip "$(ReadFileAsString $log)"
        return 1
    fi
)}

ServiceRunUpdate()
{(  # Run in a subshell.
    # Isolate program from variables introduced by "sourcing"

    ip=$1
    file=$2
    log=$(ServiceLogFile "$file")
    id=$(ServiceId "$file")

    if [ ! -f "$file" ]; then  # No configuration file?
        return 0
    fi

    [ "$VERBOSE" ] && cat $log

    . "$file"       # Source the configuration file

    # Make sure variables got defined

    if [ ! "$URL" ]; then
        Log "ERROR: Missing variable URL in $file"
    fi

    case "$URL" in
        *WHATSMYIP*)
            if [ ! "$ip" ]; then
                Log "ERROR: Current ip address not available from $URL_WHATSMYIP. Skipped $file"
                return 1
            fi

            URL=$(echo $URL | sed "s,WHATSMYIP,$ip,")
            ;;
    esac

    case "$URL" in
        *[$]*)
            Log "ERROR: Possibly unresolved variables in $URL at $file"
            return 1
            ;;
    esac

    Verbose "Info: Updating $id"

    Webcall "$URL" "$log"

    Verbose "Info: Updating $id...done"
)}

ServiceRunConfig()
{
    ip=$1
    file=$2

    ServiceRunUpdate "$ip" "$file"
    ServiceStatus "$ip" "$file"
}

ServiceRunConfigList ()
{
    ip="$1"
    list="$2"

    if [ ! "$TEST" ]; then
        echo $ip > $FILE_IP
        Date > $FILE_TIMESTAMP
    fi

    ret=0

    for conffile in $list
    do
        id=$(ServiceId "$conffile")

        ServiceRunConfig "$ip" "$conffile"
        status=$?

        if [ $status -ne 0 ]; then
            ret=$?
            Verbose "update status FAILED"
        else
            Verbose
            Verbose "update status ok"
        fi
    done

    return $ret
}

# -----------------------------------------------------------------------
# FUNCTIONS: CONFIGURATION FILES
# -----------------------------------------------------------------------

ConfigFilePath()
{
    file=$1

    case "$file" in
        */*) ;;  # Nothing, user supplied file
        *)
            case "$file" in
                *.conf)
                   ;;
                *) file="$file.conf"
                   ;;
            esac

            file=$CONF/$file
            ;;
    esac

    if [ ! -f "$file" ]; then
        Log "WARN: No config file $file"
        return 1
    fi

    echo "$file"
}

ConfigFileIsEnabled()
{
    egrep "^(ENABLED?=[\"\']?yes|ENABLED?=1$)" "$1" > /dev/null 2>&1
}

ConfigFileStatus()
{
   if [ ! "$1" ]; then  # No user specific files to check
       set -- $CONF/*.conf
   fi

    for file in "$@"
    do
        [ -f "$file" ] || continue

        if ConfigFileIsEnabled "$file"; then
            str="enabled  "
        else
            str="disabled "
        fi

        file=$(ConvertHOME "$file")
        Msg "$str$file"
    done
}

ConfiFileList()
{
    list=

    for file in $CONF/*.conf
    do
        [ -f "$file" ] || continue
        ConfigFileIsEnabled "$file" || continue

        list="$list $file"
    done

    [ "$list" ] || return 1

    echo $list
}

# -----------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------

Require ()
{
    for tmp in curl wget lynx
    do
        Which $tmp && return 0
    done

    Die "ERROR: Not any found in PATH: curl, wget or lynx in PATH"

    unset tmp
}

Main()
{
    unset TEST
    conffiles=
    tmpmain="$TMPBASE.Main"
    showlog=

    while :
    do
        case "$1" in
            -c | --conf | --config)
                shift
                [ "$1" ] || Die "ERROR: Missing arg for --conf"
                file=$(ConfigFilePath "$1")
                [ "$file" ] || Die "ERROR: No config file found for $1"
                shift
                conffiles="$conffiles $file"
                ;;
            -l | --list)
                shift
                lsconf=lsconf
                ;;
            -L | --log)
                shift
                showlog=showlog
                ;;
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
                if [ "$LOGGER" ]; then
                    SYSLOG=syslog
                else
                    Warn "ERROR: logger(1) not found in PATH. Syslog not available."
                fi
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

    # -----------------------------------------------------------------------

    if [ ! "$CONF" ] ; then
        Die "ERROR: No configuration directory: $CONFHOME"
    fi

    if [ ! -d "$CONF" ]; then
        Die "ERROR: No configuration directory: $CONF"
    fi

    if [ "$lsconf" ]; then
        ConfigFileStatus "$conffiles"
        return 0
    fi

    if [ ! "$conffiles" ]; then
        conffiles=$(ConfiFileList)
    fi

    if [ ! "$conffiles" ]; then
        Die "ERROR: No live configuration files available"
    fi

    # -----------------------------------------------------------------------

    EmptyFile "$FILE_LOG"

    ip_prev=$(IpPrevious)

    IpCurrent > "$tmpmain"     # Might call exit. Can't subshell $()
    ip=$(cat "$tmpmain")

    Verbose "IP old: $ip_prev"
    Verbose "IP now: $ip"

    if [ ! "$ip" ] || [ "$ip" = "0.0.0.0" ] ; then
        Verbose "WARN: current IP address not available"
    fi

    # -----------------------------------------------------------------------

    if [ "$status" ]; then
        for file in $conffiles
        do
            Verbose "Conf: $(ConvertHOME $file)"
        done

        date=$(cat "$FILE_TIMESTAMP" 2> /dev/null)
        str=" Last-updated: $date"

        if [ ! "$date" ]; then
            str=" Last-updated: UNKNOWN (timestamp not available)"
        fi

        if [ "$ip_prev" = "$ip" ]; then
            Msg "status: OK IP: $ip nochange$str"
        else
            if [ "$ip_prev" ]; then
                ip_prev="was $ip_prev"
            else
                ip_prev="previous IP UNKNOWN"
            fi

            Msg "status: NOK IP: $ip (update needed, $ip_prev).$str"
        fi

        return 0
    fi

    if [ "$showlog" ]; then
        if [ -f "$FILE_LOG" ]; then
            ls -l "$FILE_LOG"
            cat "$FILE_LOG"
        else
            Echo "No log file $FILE_LOG"
        fi
        return 0
    fi

    # -----------------------------------------------------------------------

    [ "$ip" ] || return 1

    if [ ! "$FORCE" ] && [ "$ip_prev" = "$ip" ]; then
        Verbose "Info: IP nochange. Not updated."
        return 0
    else
        ServiceRunConfigList "$ip" "$conffiles"
    fi
}

trap Atexit 0 1 2 3 5 15 19
Require
Main "$@"

# End of file
