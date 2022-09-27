﻿
[CmdletBinding()]
param(    
    [Parameter(Mandatory=$False, HelpMessage='Tenant ID (This is a GUID which represents the "Directory ID" of the AzureAD tenant into which you want to create the apps')]
    [string] $tenantId,
    [Parameter(Mandatory=$False, HelpMessage='Azure environment to use while running the script. Default = Global')]
    [string] $azureEnvironmentName
)

if ($null -eq (Get-Module -ListAvailable -Name "Microsoft.Graph.Groups")) {
    Install-Module "Microsoft.Graph.Groups" -Scope CurrentUser 
}

Import-Module Microsoft.Graph.Groups

<#.Description
   This function first checks and then deletes an existing Azure AD Security Group, if required
#>  
Function RemoveSecurityGroup([string] $name, [switch] $promptBeforeDelete)
{

    # check if Group exists
    $group = Get-MgGroup -Filter "DisplayName eq '$name'"
    
    if( $group -ne $null)
    {
        if ($promptBeforeDelete) 
        {
            $confirmation = Read-Host "Proceed to delete an existing group named '$name' in the tenant ?(Y/N)"

            if($confirmation -eq 'y')
            {
               Remove-MgGroup -GroupId $group.Id
               Write-Host "Security group '$name' successfully deleted"
            }
        }
        else
        {
            Write-Host "No Security group by name '$name' exists in the tenant, no deletion needed."
        }     
    }
    
    return $group.Id    
}

Function Cleanup
{
    if (!$azureEnvironmentName)
    {
        $azureEnvironmentName = "Global"
    }

    <#
    .Description
    This function removes the Azure AD applications for the sample. These applications were created by the Configure.ps1 script
    #>

    # $tenantId is the Active Directory Tenant. This is a GUID which represents the "Directory ID" of the AzureAD tenant 
    # into which you want to create the apps. Look it up in the Azure portal in the "Properties" of the Azure AD. 

    # Connect to the Microsoft Graph API
    Write-Host "Connecting to Microsoft Graph"
    if ($tenantId -eq "") 
    {
        Connect-MgGraph -Scopes "Application.ReadWrite.All" -Environment $azureEnvironmentName
        $tenantId = (Get-MgContext).TenantId
    }
    else 
    {
        Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All" -Environment $azureEnvironmentName
    }
    
    # Removes the applications
    Write-Host "Cleaning-up applications from tenant '$tenantId'"

    Write-Host "Removing 'client' (msal-angular-app) if needed"
    try
    {
        Get-MgApplication -Filter "DisplayName eq 'msal-angular-app'" | ForEach-Object {Remove-MgApplication -ApplicationId $_.Id }
    }
    catch
    {
        $message = $_
        Write-Warning $Error[0]
        Write-Host "Unable to remove the application 'msal-angular-app'. Error is $message. Try deleting manually." -ForegroundColor White -BackgroundColor Red
    }

    Write-Host "Making sure there are no more (msal-angular-app) applications found, will remove if needed..."
    $apps = Get-MgApplication -Filter "DisplayName eq 'msal-angular-app'" | Format-List Id, DisplayName, AppId, SignInAudience, PublisherDomain
    
    if ($apps)
    {
        Remove-MgApplication -ApplicationId $apps.Id
    }

    foreach ($app in $apps) 
    {
        Remove-MgApplication -ApplicationId $app.Id
        Write-Host "Removed msal-angular-app.."
    }

    # also remove service principals of this app
    try
    {
        Get-MgServicePrincipal -filter "DisplayName eq 'msal-angular-app'" | ForEach-Object {Remove-MgServicePrincipal -ServicePrincipalId $_.Id -Confirm:$false}
    }
    catch
    {
        $message = $_
        Write-Warning $Error[0]
        Write-Host "Unable to remove ServicePrincipal 'msal-angular-app'. Error is $message. Try deleting manually from Enterprise applications." -ForegroundColor White -BackgroundColor Red
    }

    # remove security groups, if relevant to the sample
    RemoveSecurityGroup -name 'GroupAdmin' -promptBeforeDelete 'Y'
    RemoveSecurityGroup -name 'GroupMember' -promptBeforeDelete 'Y'
}

if ($null -eq (Get-Module -ListAvailable -Name "Microsoft.Graph.Applications")) { 
    Install-Module "Microsoft.Graph.Applications" -Scope CurrentUser                                            
} 
Import-Module Microsoft.Graph.Applications
$ErrorActionPreference = "Stop"


try
{
    Cleanup -tenantId $tenantId -environment $azureEnvironmentName
}
catch
{
    $_.Exception.ToString() | out-host
    $message = $_
    Write-Warning $Error[0]    
    Write-Host "Unable to register apps. Error is $message." -ForegroundColor White -BackgroundColor Red
}

Write-Host "Disconnecting from tenant"
Disconnect-MgGraph
