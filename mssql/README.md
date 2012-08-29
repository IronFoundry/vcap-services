SQL 2008 Setup:

* Ensure that sa user has known password. This goes into the 'mssql' section of mssql_node.yml
* Ensure that TCP/IP is enabled via SQL configuration manager.
* Either disable windows firewall or add an incoming rule allowing port 1433 connections.

Git must be in system PATH. Installer here: http://code.google.com/p/msysgit/downloads/list?q=full+installer+official+git

Install latest Ruby and DevKit (1.9.3 as of this writing). Download from: http://rubyinstaller.org/downloads/

Assuming `C:\Ruby193` for Ruby and `C:\RubyDevKit` for Dev Kit

Add `C:\Ruby193\bin` to the front of the system `PATH`.

Setup Dev Kit:

    C:\>cd C:\RubyDevKit
    C:\RubyDevKit>ruby dk.rb init
    C:\RubyDevKit>ruby dk.rb review
    C:\RubyDevKit>ruby dk.rb install

Ensure that sqlite and curl DLLs are in `C:\Ruby193\bin` directory. Download from: https://github.com/IronFoundry/vcap-services/downloads

You will probably want a .gemrc in your user directory:

    C:\Users\USERNAME>type .gemrc
    install: --no-rdoc --no-ri
    update:  --no-rdoc --no-ri

Do a 'gem install bundler'

    C:\>gem install bundler

Installing curb gem on Windows:

    C:\>gem install curb --version 0.7.18 --platform=x86-mingw32 -- -- --with-curl-lib=C:\PATH\TO\curl-7.27.0-devel-mingw32\bin --with-curl-include=C:\PATH\TO\curl-7.27.0-devel-mingw32\include

Clone out vcap-services from Iron Foundry:

    C:\>mkdir IronFoundry
    C:\>cd IronFoundry
    C:\IronFoundry>git clone git://github.com/IronFoundry/vcap-services.git

You only need `mssql` and `mssb` (for MS service bus):

    C:\>cd \IronFoundry\vcap-services
    C:\IronFoundry\vcap-services>move mssql ..
    C:\IronFoundry\vcap-services>move mssb ..
    C:\IronFoundry\vcap-services>cd ..
    C:\IronFoundry>rd /s /q vcap-services

Install required gems:

    C:\>cd \IronFoundry\mssql
    C:\IronFoundry\mssql>bundle install

Create some dirs:

    C:\>cd \IronFoundry\mssql
    C:\IronFoundry\mssql>mkdir run
    C:\IronFoundry\mssql>mkdir log
    C:\IronFoundry\mssql>mkdir db
    C:\IronFoundry\mssql>cd ..\mssb
    C:\IronFoundry\mssb>mkdir run
    C:\IronFoundry\mssb>mkdir log
    C:\IronFoundry\mssb>mkdir db

Edit configuration in `C:\IronFoundry\mssql\config\*.yml` to match your environment. You may want to change logging to 'debug' and comment out 'file' for now so logging goes to the console.

Try it out in two separate cmd windows:
    
    C:\>cd \IronFoundry\mssql\bin
    C:\IronFoundry\mssql\bin>ruby mssql_gateway
    C:\>cd \IronFoundry\mssql\bin
    C:\IronFoundry\mssql\bin>ruby mssql_node

If all looks good and `vmc create-service mssql` works, install as windows services:

    C:\>sc create mssql_gateway_svc binPath= "C:\Ruby193\bin\rubyw.exe -C C:\IronFoundry\mssql\bin mssql_gateway_svc.rb" start= delayed-auto
    C:\>sc create mssql_node_svc binPath= "C:\Ruby193\bin\rubyw.exe -C C:\IronFoundry\mssql\bin mssql_node_svc.rb" start= delayed-auto

Re-edit configuration `*.yml` files - uncomment 'file' and change level to 'error'.

Start 'em up:

    C:\>sc start mssql_gateway_svc
    C:\>sc start mssql_node_svc

