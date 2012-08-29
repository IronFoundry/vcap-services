SQL 2008 Setup:

* Ensure that sa user has known password. This goes into the 'mssql' section of mssql_node.yml
* Ensure that TCP/IP is enabled via SQL configuration manager.
* Either disable windows firewall or add an incoming rule allowing port 1433 connections.

Ensure that sqlite and curl DLLs are in Ruby bin directory

Do a 'gem install bundler'

Installing curb gem on Windows:
    gem install curb --version 0.7.18 --platform=x86-mingw32 -- -- --with-curl-lib=C:\proj\misc\curl-7.27.0-devel-mingw32\bin --with-curl-include=C:\proj\misc\curl-7.27.0-devel-mingw32\include

