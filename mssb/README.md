
Installing curb on Windows:
    gem install curb --version 0.7.18 --platform=x86-mingw32 -- -- --with-curl-lib=C:\proj\misc\curl-7.27.0-devel-mingw32\bin --with-curl-include=C:\proj\misc\curl-7.27.0-devel-mingw32\include

Getting a token for ServiceBusDefaultNamespace namespace via curl:

    C:\>curl -k -d "grant_type=authorization_code&client_id=mssb&client_secret=PASSWORD&scope=https%3a%2f%2fSERVER%3a4446%2fServiceBusDefaultNamespace%2f" https://SERVER:4446/ServiceBusDefaultNamespace/$STS/OAuth/

Creating a new namespace:

    New-SBNamespace -Name FooBar -ManageUsers mssb_test

Removing namespace:

    Remove-SBNamespace -Name FooBar

Adding user / password to local machine:

    net user mssb_test 3Nf62Jlf4VT2 /add /expires:never
    wmic path Win32_UserAccount where Name='mssb_test' set PasswordExpires=false

Deleting:

    net user mssb_test /delete

Service Bus Server setup:

* Remove password complexity requirement.
