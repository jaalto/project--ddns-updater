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
#       Simple install program. Default is to install under $HOME
#       Adjust variables before calling:
#
#           test=1 BINDIR=/usr/local/bin CONFDIR=/etc/ddns-updater <program>

BINDIR=${BINDIR:-$HOME/bin}

Run ()
{
    if [ "$test" ]; then
        echo "$*"
    else
        echo "# $*"
        "$@"
    fi
}

Run mkdir --parents $BINDIR
Run cp --verbose bin/ddns-updater.sh $BINDIR/ddns-updater
Run chmod 755 $BINDIR/ddns-updater

file=ddns-updater.conf
CONFDIR=${CONFDIR:-$HOME/.config/ddns-updater}

Run mkdir --parents $CONFDIR

if [ ! -f "$CONFDIR/$file" ]; then
    Run cp --verbose conf/*.conf examples/*.conf $CONFDIR/
fi

case "$BINDIR" in
    /usr/local/bin* | /usr/bin*)
        Run cp cron.d/ddns-updater /etc/cron.d/
        ;;
    *)
        echo "\
# DONE. Add a cron entry with: crontatab -e
# See an example in file: cron.d/ddns-updater"
        ;;
esac

# End of file
