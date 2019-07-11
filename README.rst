..  comment: the source is maintained in ReST format.
    Emacs: http://docutils.sourceforge.net/tools/editors/emacs/rst.el
    Manual: http://docutils.sourceforge.net/docs/user/rst/quickref.html

DESCRIPTION
===========

A generic dynamic DNS (DDNS) update client implemented in POSIX shell.

Any DDNS service provider providing HTTP or HTTPS update can be added.
Consult API documention of those services to add support. Program
includes few ready templates to start with:

- http://dns.he.net  [1] (host your own DOMAIN and update using DDNS)
- http://duckdns.org [2] (US, free third level domains)
- http://dsnss.de    [3] (EU, free third level domains)

See the examples/ directory.

How does it work?
-----------------

Based on your domains and credentials, it periodically checks if IP address
has changed and sends an update request.

1. Create a user account.

2. Add domain(s) to your account.

3. Copy the TOKEN or PASSWORD from your account depending on used DDNS service.

4. Configure update interval for a cron job.

After setting up configuration files, call program once from command
line to seed the initial IP. After that cron takes care of updates. ::

    /usr/local/bin/ddns-updater --verbose

REQUIREMENTS
============

1. POSIX environment and standard utilities (grep, awk...)

2. POSIX ``/bin/sh`` and some web client like ``curl(1)``, ``wget(1)`` etc.

INSTALL
=======

See details in separate INSTALL file.

REFERENCES
==========

- [1] Hurricane Electric https://dns.he.net/docs.html
- [2] https://www.duckdns.org/spec.jsp
- [3] https://ddnss.de/ua/help.php

COPYRIGHT AND LICENSE
=====================

Copyright (C) 2019 Jari Aalto <jari.aalto@cante.net>

This project is free; you can redistribute and/or modify it under
the terms of GNU General Public license either version 2 of the
License, or (at your option) any later version.

Project homepage (bugs and source) is at
https://github.com/jaalto/project--restricted-shell-rbash

.. End of file
