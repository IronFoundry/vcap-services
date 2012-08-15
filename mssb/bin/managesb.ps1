PARAM (
  [Parameter(Mandatory=$false)][switch]$Create = $false,
  [Parameter(Mandatory=$false)][switch]$Delete = $false,
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$false)][string]$ManageUser
)

if (($Create -eq $false) -and ($Delete -eq $false))
{
    Throw 'Must provide either -Create or -Delete to script!'
}
else
{
    if (($Create -eq $true) -and ([string]::IsNullOrEmpty($ManageUser)))
    {
        Throw '-Create requires -ManageUser!'
    }

    $installpath = (get-itemproperty "HKLM:\Software\Microsoft\Windows Azure Service Bus\1.0" INSTALLDIR).INSTALLDIR
    $installpath = $installpath.TrimEnd('\')

    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Common.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Admin.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Data.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Tracing.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.ServiceBus.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.ServiceBus.Commands.Common.dll") | Out-Null

    $env:Path = $env:Path + ";$installpath"
    Import-Module $installpath\Microsoft.ServiceBus.Commands.dll

    if ($Create -eq $true)
    {
        New-SBNamespace -Name $Name -ManageUsers $ManageUser
    }
    else
    {
        Remove-SBNamespace -Name $Name
    }
}
