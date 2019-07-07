..  comment: the source is maintained in ReST format.
    Emacs: http://docutils.sourceforge.net/tools/editors/emacs/rst.el
    Manual: http://docutils.sourceforge.net/docs/user/rst/quickref.html

DESCRIPTION
===========

Utility to update IP address[1] to service http://duckdns.org
You need account and domains from the service.

How does it work?
-----------------

Based on your domains and credentials, it periodically checks if IP address
has changed and sends an update request.

1. Create a user account

2. Add domain to your account

3. Copy the TOKEN from your account

4. Configure update interval in cronjob

  crontab -e
  */30 * * * * ddns-duckdns.sh

After these steps, the script is ready to use.

Call it once from command line to seed the initial IP. To check for
probelems, run it under the shell debugging option ``-x`` to see if there
are any probelms.

  sh -x /<path to>/ddns-duckdns.sh

REQUIREMENTS
============

1. Environment: any POSIX environment

2. POSIX ``/bin/sh`` and ``curl(1)`` client.

INSTALL
=======

See separate file INSTALL.

REFERENCES
==========

[1] https://www.duckdns.org/spec.jsp

COPYRIGHT AND LICENSE
=====================

Copyright (C) 2019 Jari Aalto <jari.aalto@cante.net>

This project is free; you can redistribute and/or modify it under
the terms of GNU General Public license either version 2 of the
License, or (at your option) any later version.

Project homepage (bugs and source) is at
https://github.com/jaalto/project--restricted-shell-rbash

.. End of file
