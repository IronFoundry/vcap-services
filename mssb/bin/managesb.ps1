PARAM (
  [Parameter(Mandatory=$false)][switch]$Create = $false,
  [Parameter(Mandatory=$false)][switch]$Delete = $false,
  [Parameter(Mandatory=$false)][switch]$Check = $false,
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$false)][string]$ManageUser
)

if (($Create -eq $false) -and ($Delete -eq $false) -and ($Check -eq $false))
{
    Throw 'Must provide -Create, -Delete or -Check to script!'
}
else
{
    if (($Create -eq $true) -and ([string]::IsNullOrEmpty($ManageUser)))
    {
        Throw '-Create requires -ManageUser!'
    }

    $installpath = (get-itemproperty "HKLM:\Software\Microsoft\Windows Azure Service Bus\1.0" INSTALLDIR).INSTALLDIR
    $installpath = $installpath.TrimEnd('\')

#Load all Assemblies which are required for Microsoft.ServiceBus.Commands.dll

    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Common.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Admin.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Data.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.Cloud.ServiceBus.Tracing.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.ServiceBus.dll") | Out-Null
    [System.Reflection.Assembly]::LoadFrom("$installpath\Microsoft.ServiceBus.Commands.Common.dll") | Out-Null

    $env:Path = $env:Path + ";$installpath"
    Import-Module $installpath\Microsoft.ServiceBus.Commands.dll
# Update-FormatData -PrependPath $installpath\Microsoft.ServiceBus.Commands.Format.ps1xml

    if ($Create -eq $true)
    {
        try
        {
            New-SBNamespace -Name $Name -ManageUsers $ManageUser
        }
        catch
        {
            exit 1
        }
    }
    elseif ($Delete -eq $true)
    {
        try
        {
            Remove-SBNamespace -Name $Name
        }
        catch
        {
            exit 1
        }
    }
    else
    {
        try
        {
            Get-SBNamespace -Name $Name
        }
        catch
        {
            exit 1
        }
    }
}
