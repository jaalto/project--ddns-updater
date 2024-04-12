#! /bin/sh
#
#   Copyright
#
#       Copyright (C) 2019-2024 Jari Aalto <jari.aalto@cante.net>
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
#       - Lint by https://www.shellcheck.net
#
#      Note: This program is designed to not expect to have GNU
#      utilities and their options. This means writing:
#
#           egrep ...  /dev/null 2>&1
#
#       Instead of:
#
#           grep --extended-regexp --quiet ...

AUTHOR="Jari Aalto <jari.aalto@cante.net>"
VERSION="2024.0412.1200"
LICENSE="GPL-2+"
HOMEPAGE="https://github.com/jaalto/project--ddns-updater"

PROGRAM=${0##*/}

# mktemp(1) would be an external program
TMPDIR=${TMPDIR:-/tmp}
[ -d "$TMPDIR" ] || TMPDIR=/tmp

TMPBASE=${TMPDIR:-/tmp}/${LOGNAME:-$USER}.$$.ddns-updater.tmp

if [ ! "$PATH" ]; then
    PATH="/usr/bin:/usr/local/bin"
fi

GREP="egrep"
CURL="curl"
WEBCALL=   # See Require()

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

VARDIR=$CONF

# -----------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------

LOGGER=    # Syslog support. Debian: "apt-get install bsdutils"

# Use prefix 00.* for files to appear first in ls(1) listing

# Can be set in program's configuration file <program>.conf

URL_WHATSMYIP=ifconfig.co
MSG_PREFIX="DDNS-UPDATER "
CURL_OPTIONS="--max-time 15"
WGET_OPTIONS="--timeout=15"

LOG_FILE_PREFIX="00.ddns-updater.ip"

# -----------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------

HELP="\
Synopsis: $PROGRAM [option]

OPTIONS
    -c, --config NAME
        Read configuration NAME (or path)

    -f, --force
        Force update even if IP is same.

    -g, --get-ip IP
        A URL to return current IP address.
        Default: $URL_WHATSMYIP

    -l, --list
        List status of configuration files and exit.

    -L, --log
        Display log file and exit.

    -p, --persistent-data-dir DIR
        Location where to save variable persistent data
        like current and uddated Ip addresses. See
        FILES. Default: $VARDIR

    -s, --status
        Show status and exit.

    -S, --syslog
        Send status to syslog. Only for root (in cron).

    -t, --test
        Run in test mode. No network update.

    -v, --verbose
        Display verbose messages.

    -V, --version
        Display version information and exit.

    -h, --help
        Display short help.

    Please note that stacking of short options is not supported.
    E.g. -v -f cannot be combined into -vf.

DESCRIPTION
    Updates IP address to free DDNS services:

        duckdns.org
        dns.he.net

DIRECTORIES
    CONFDIR Configuration directory searched is one of:

    \$HOME/.config/ddns-updater
    /etc/ddns-updater

FILES
    Read configuration files:

    $CONF/*.conf

    Written files:

    $FILE_IP
        Last update - ip address

    $FILE_LOG
        Last update - error log

    $FILE_TIMESTAMP
        Last update - YYYY-MM-DD HH:MM"

Help ()
{
    echo "$HELP" | sed "s,$HOME,~,g"
}

SetLogVariables ()
{
    FILE_IP="$VARDIR/$LOG_FILE_PREFIX.now"
    FILE_LOG="$VARDIR/$LOG_FILE_PREFIX.log"
    FILE_TIMESTAMP="$VARDIR/$LOG_FILE_PREFIX.updated"
}

Atexit ()
{
    rm -f "$TMPBASE"*   # Clean up temporary files
}

Version ()
{
    echo "$VERSION $LICENSE $AUTHOR $HOMEPAGE"
}

IsUSerRoot ()
{
    [ "$(id --user)" = "0" ]
}

Which ()
{
    # "command -v" is POSIX
    command -v "$1" > /dev/null 2>&1 || return 1
    return 0
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

DieEmpty ()
{
    [ "$1" ] && return 0

    shift
    Die "$*"
}

DieNoFile ()
{
    if [ ! -e "$1" ]; then
        Die "$PROGRAM ERROR: no such file: $1"
    fi
}

DieEmptyFile ()
{
    if [ ! -s "$1" ]; then
        Die "$PROGRAM ERROR: empty file: $1"
    fi
}

DieNoDir ()
{
    if [ ! -d "$1" ]; then
        Die "$PROGRAM ERROR: no such dir: $1"
    fi
}

DieOptionNotNumber ()
{
    case "$2" in
        [0-9]*)
            ;;
        *)
            Die "$PROGRAM ERROR: option $1 requires a number, got: $1"
            ;;
    esac
}

DieOptionMinus ()
{
    case "$2" in
        -*)
            Die "$PROGRAM ERROR: option $1 requires ARG, got $2"
            ;;
    esac
}

DieOptionEmpty ()
{
    if [ ! "$2" ]; then
        Die "$PROGRAM ERROR: option $1 requires ARG, got empty"
    fi
}

DieOption ()
{
    DieOptionMinus "$@"
    DieOptionEmpty "$@"
}

MakeEmptyFile ()
{
    : > "$1"   # The True operator. An echo would add a newline.
}

SyslogStatusWrite ()
{
    status=$1
    id=$2
    ip=$3
    msg=$4

    [ "$LOGGER" ] || return 1

    case "$status" in
        *good*)
            $LOGGER --priority local0.info \
                --tag "$id" "OK: $ip address updated$msg"
            ;;
        *nochange*)
            $LOGGER --priority local0.notice \
                --tag "$id" "OK: $ip address no change$msg"
            ;;
        *)
            $LOGGER --priority local0.err \
                --tag "$id" "ERROR: $ip address not updated$msg"
            ;;
    esac
}

SyslogStatusUpdate ()
{
    if [ "$SYSLOG" ]; then
        SyslogStatusWrite "$@"
    fi
}

SyslogMsg ()
{
    if [ "$SYSLOG" ]; then
        logger --priority local0.err --tag DDNS-MSG "$*"
    fi
}

Log ()
{
    Warn "$*"
    SyslogMsg "$*"
}

Date ()
{
    date "+%Y-%m-%d %H:%M"
}

ReadFileAsString ()
{
    # Remove newlines
    tr '\n' ' ' < "$1" | sed 's,[ \t]*$,,'
}

IpPrevious ()
{
    [ -f "$FILE_IP" ] || return 1

    cat "$FILE_IP" 2> /dev/null
}

ConvertHOME ()
{
    # Instead of long /mount/some/home/USER, use "~"
    echo "$1" | sed "s,$HOME,~,"
}

Webcall ()
{
    # ARGUMENTS: URL [LOGFILE]
    logfile=$2

    echo "Webcall() $*" >> "$FILE_LOG"

    # shell check SC2086: do not check unquoted $VAR

    if [ "$WEBCALL" = "curl" ]; then
        if [ "$logfile" ]; then
            # shellcheck disable=SC2086
            ${TEST:+echo} curl --silent --insecure --output "$logfile" $CURL_OPTIONS "$1" 2>> "$FILE_LOG"
        else
            # shellcheck disable=SC2086
            ${TEST:+echo} curl --silent --insecure $CURL_OPTIONS "$1" 2>> "$FILE_LOG"
        fi
    elif [ "$WEBCALL" = "wget" ]; then
        if [ "$logfile" ]; then
            # Filter out the status message
            # shellcheck disable=SC2086
            ${TEST:+echo} wget --no-verbose --output-document="$logfile" $WGET_OPTIONS "$1" 2>> "$FILE_LOG"
        else
            # shellcheck disable=SC2086
            ${TEST:+echo} wget --no-verbose --output-document=- $WGET_OPTIONS "$1" 2>> "$FILE_LOG"
        fi
    elif [ "$WEBCALL" = "lynx" ]; then
        if [ "$logfile" ]; then
            lynx --dump "$2" > "$logfile" 2>> "$FILE_LOG"
        else
            lynx --dump "$2" 2>> "$FILE_LOG"
        fi
    else
        Die "ERROR: No programs found in PATH: curl, wget or lynx"
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
    Webcall "$URL_WHATSMYIP" > "$tmpwhatsmyip"

    [ -s "$tmpwhatsmyip" ] || return 1

    WhatsmyipParse "$tmpwhatsmyip"
}

IpCurrent ()
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
    echo "${1%.conf}.log"
}

ServiceId ()
{
    # /path/service.conf => service
    id=${1##*/}
    id=${id%.conf}

    # Ignore to suggest [:lower:] accents and foreign alphabets
    # shellcheck disable=SC2018,SC2019
    echo "$id" | tr 'a-z' 'A-Z'
}

ServiceStatus ()
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

    [ "$VERBOSE" ] && cat "$log"

    # Noting to check here
    # shellcheck disable=SC1090
    . "$file"      # Source configuration file

    SetLogVariables # Update location of writable files

    # Make sure variables got defined

    if [ ! "$REGEXP_OK" ]; then
        Log "ERROR: Missing variable REGEXP_OK in $file"
        return 1
    fi

    if [ ! "$REGEXP_NOCHANGE" ]; then
       Log "ERROR: Missing variable REGEXP_NOCHANGE in $file"
       return 1
    fi

    if $GREP "$REGEXP_NOCHANGE" "$log" > /dev/null 2>&1 ; then
        # Disabled: do not add additional noise to syslog
        # SyslogStatusUpdate nochange DNS-HENET $ip
        return 0
    elif $GREP "$REGEXP_OK" "$log" > /dev/null 2>&1 ; then
        SyslogStatusUpdate good  "DDNS-$id" "$ip"
        return 0
    else
        SyslogStatusUpdate error "DDNS-$id" "$ip" "$(ReadFileAsString "$log")"
        return 1
    fi
)}

ServiceRunUpdate ()
{(
    # Run in a subshell which isolates program from setting
    # variables in config file.

    ip=$1
    file=$2
    log=$(ServiceLogFile "$file")
    id=$(ServiceId "$file")

    if [ ! -f "$file" ]; then  # No configuration file?
        return 0
    fi

    [ "$VERBOSE" ] && cat "$log"

    # Noting to check here
    # shellcheck disable=SC1090
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

            URL=$(echo "$URL" | sed "s,WHATSMYIP,$ip,")
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

ServiceRunConfig ()
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
        echo "$ip" > "$FILE_IP"
        Date > "$FILE_TIMESTAMP"
    fi

    ret=0

    for conffile in $list
    do
        id=$(ServiceId "$conffile")

        ServiceRunConfig "$ip" "$conffile"
        status=$?

        if [ $status -ne 0 ]; then
            ret=$status
            Verbose "update status FAILED"
        else
            Verbose "update status ok"
        fi
    done

    return $ret
}

# -----------------------------------------------------------------------
# FUNCTIONS: CONFIGURATION FILES
# -----------------------------------------------------------------------

ConfigFilePath ()
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

ConfigFileIsEnabled ()
{
    $GREP "^(ENABLED?=[\"\']?yes|ENABLED?=1$)" "$1" > /dev/null 2>&1
}

ConfigFileStatus ()
{
   if [ ! "$1" ]; then  # No user specific files to check
       set -- "$CONF"/*.conf
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

ConfiFileList ()
{
    list=

    for file in "$CONF"/*.conf
    do
        [ -f "$file" ] || continue
        ConfigFileIsEnabled "$file" || continue

        list="$list $file"
    done

    [ "$list" ] || return 1

    echo "$list"
}

# -----------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------

Require ()
{
    for tmp in curl wget lynx
    do
        if Which "$tmp"; then
            WEBCALL=$tmp
            return 0
        fi
    done

    Die "ERROR: Not any found in PATH: curl, wget or lynx"
}

Main ()
{
    Require
    SetLogVariables

    unset TEST
    unset conffiles
    unset showlog
    tmpmain="$TMPBASE.Main"

    # egrep is beging deprecated. Check.

    if ! Which egrep; then
        if grep --version 2> /dev/null | grep "GNU" > /dev/null; then
            GREP="grep --extended-regexp"
        else
            Verbose "WARN: egrep not in PATH, switching 'grep -E'" \
                    "(please install GNU grep if this does not work)"
        fi
    fi

    # Optional feature

    Which logger && LOGGER="logger"

    while :
    do
        case "$1" in
            -c | --config)
                DieOption "--config" "$2"
                file=$(ConfigFilePath "$2")
                DieEmpty "$file" "ERROR: No file found for --config $2"
                conffiles="$conffiles $file"
                shift 2
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
            -g | --get-ip)
                DieOption "--get-ip" "$2"
                URL_WHATSMYIP=$2
                shift 2
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
                VERBOSE="verbose"
                TEST="test"
                ;;
            -p | --persistent-data-dir)
                DieOption "--persistent-data-dir" "$2"
                VARDIR=$2
                shift 2
                ;;
            -v | --verbose)
                shift
                VERBOSE="verbose"
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
            --) shift
                break
                ;;
            -*) Warn "WARN: Unknown option: $1"
                shift
                ;;
            *)  break
                ;;
        esac
    done

    # -----------------------------------------------------------------------

    DieEmpty "$CONF" "ERROR: No configuration directory: $CONFHOME"
    DieNoDir "$CONF" "ERROR: No configuration directory: $CONF"

    if [ "$lsconf" ]; then
        ConfigFileStatus "$conffiles"
        return 0
    fi

    if [ ! "$conffiles" ]; then
        conffiles=$(ConfiFileList)
    fi

    DieEmpty "$conffiles" "ERROR: No live configuration files available"

    DieEmpty "$VARDIR" "ERROR: No VARDIR set or missing --persistent-data-dir DIR"
    DieNoDir "$VARDIR" "ERROR: No data directory: $VARDIR"

    # -----------------------------------------------------------------------

    MakeEmptyFile "$FILE_LOG"

    ip_prev=$(IpPrevious)

    IpCurrent > "$tmpmain"     # Might call exit. Can't use $()
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
            Verbose "Conf: $(ConvertHOME "$file")"
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

trap Atexit 0 1 2 3 15
Main "$@"

# End of file
