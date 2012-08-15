
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
