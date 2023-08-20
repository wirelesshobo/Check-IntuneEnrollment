<#
  .SYNOPSIS
  Confirm that devices on premise are Hybrid Azure AD Joined and enrolled in Intune.
  .DESCRIPTION
  This script obtains a list of Active Directory devices, Azure Active Directory devices, and Intune enrolled devices.
  It then compares the lists to output a CSV showing current status of the device.
  .EXAMPLE
  Check-IntuneEnrollment.ps1 -SearchBase "CN=Computers,DC=testdomain,DC=local"
  
  
  .NOTES
  Version:        1.2
  Author:         Scott Stancil
  Creation Date:  August 19, 2023
  Modified Date:  August 20, 2023
  Link:           https://wirelesshobo.com
#>

# Command line parameters
# OUSearchBase provides a search option for local Active Directory
# OutputPath provides a location for the report output
param(
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Enter search base path in Active Directory."
    )]
    [string]$OUSearchBase,

    [Parameter(
        Mandatory = $true,
        HelpMessage = "Enter local path to output report."
    )]
    [string]$OutputPath
)

# Define Action to take on Error
$ErrorActionPreference = "Stop"

# Capture current UI foreground color
$originalColor = $host.ui.RawUI.ForegroundColor

try {
    Resolve-Path -Path $OutputPath -ErrorAction Stop
}
catch {
    Write-Warning "OutputPath does not exist.  Please create the path before running this report again."
    exit 0;
}


# Try to import each of the needed PowerShell Modules and attempt helpful advice on how to resolve if missing.
try {
    Import-Module ActiveDirectory
}
catch {
    Write-Warning "Error loading ActiveDirectory module. Look into adding the module through optional feature Rsat.ActiveDirectory.DS-LDS.Tools."
    exit 0;
}

try{
Import-Module AzureAD;
}
catch {
    Write-Warning "Error loading AzureAD module.  Consider install-module AzureAD."
    exit 0;
}

try{
    Import-Module Microsoft.Graph.Intune 
} 
catch {
    Write-Warning "Error loading Microsoft.Graph.Intune module.  Consider install-module Microsoft.Graph.Intune."
    exit 0;
}



# Attempt to connect with Intune MSGraph
try {
    Connect-MSGraph -ErrorAction Stop;
    Write-Output "Connected to Intune."
} catch {
    $message = $_.Exception.$message
    Write-Output "Unable to connect to Intune MS Graph."
    Write-Output $message
}

# Attempt to connect with AzureAD
try {
    Connect-AzureAD -ErrorAction Stop;
    Write-Output "Connected to AAD."
} catch {
    $message = $_.Exception.$message
    Write-Output "Unable to connect to AAD."
    Write-Output $message
}

# AllWorkstations array initialization.
$AllWorkstations = @();

# Generate a timestamp that should guarantee a unique filename.
$timestamp = get-date -Format yyyyMMddhhmmss

# Generate the filename from the OutputPath, report name, and timestamp.
$filename = $outputpath + "\HAADJIntuneDeviceReport_" + $timestamp + ".csv"

# Get all devices listed in Active Directory's OUSearchBase passed in by parameter
$ADWorkstations = get-adcomputer -SearchBase $OUSearchBase -filter * -Properties LastLogonDate
Write-Output "Getting a list of computer objects from $($OUSearchBase).  $($ADWorkstations.count) objects found."

# Get all devices listed in Azure Active Directory
$AzureADDevices = Get-AzureADDevice -All $true
Write-Output "Getting a list of all AzureAD Devices. $($AzureADDevices.count) devices found."

# Get all devices enrolled in Intune
$IntuneManagedDevices = Get-IntuneManagedDevice
Write-Output "Getting a list of all Intune Managed Devices. $($IntuneManagedDevices.count) devices found."

# Initialize a number count for progress bar.
$i=0;

# Create a count of total workstations to process for the progress bar.
$ADWorkstationTotal = $ADWorkstations.count;

# Initialize and Output Progress Bar
$Progress = @{
    Activity = 'Processing Computer Objects'
    CurrentOperation = 'Processing'
    Status = 'Searching AzureAD and Intune'
    PercentComplete = 0
}
Write-Progress @Progress;

# For each workstation in AD check for Azure Active Directory registration and Intune enrollment
foreach ($workstation in $ADWorkstations) {

    # Increment the I variable.
    $i++;
    # Generate a rounded percentage of completed devices processed
    $roundedPercentageCompleted = [math]::Round((($i / $ADWorkstationTotal) * 100), [System.MidpointRounding]::AwayFromZero);
    
    # Assign more friendly variable name to Active Directory attributes name and ObjectGUID
    $ADDeviceName = $workstation.name;
    $ADObjectGUID = $workstation.ObjectGUID; 

    
    # Output the progress bar while we are performing lookups from AD workstations against AAD and Intune arrays
    $Progress.CurrentOperation = $ADDeviceName 
    $Progress.Status = 'Searching AzureAD and Intune: '
    $Progress.PercentComplete = $roundedPercentageCompleted
    Write-Progress @Progress
    Start-Sleep -Milliseconds 20


    # All AD devices share a guid with the three other systems.  This allows our lookups to be name agnostic.
    # Active Directory is ObjectGUID
    # AzureAD is DeviceID
    # Intune is AzureADDeviceID

    # Obtain the Azure AD Device from AzureADDevices with a matching AD objectGUID
    $AzureADDevice = $AzureADDevices | Where-Object {$_.deviceid -eq $ADObjectGUID}

    # Obtain the Intune enrolled device from IntuneManagedDevices that match the AD objectGUID
	$IntuneDevice = $IntuneManagedDevices | Where-Object {$_.azureADDeviceId -eq $ADObjectGUID};
    
    # Now for each AD device, determine its AAD registration and Intune enrollment status and create a new device object.

	# If the IntuneDevice is not enrolled and the AzureADDevice is not registered, we probably need to troubleshoot why it is not hybrid registered.
	if ( ($IntuneDevice -eq $NULL) -and ($AzureADDevice -eq $NULL) ) {
        #Create device object showing not enrolled for last check in time.
    		$tempDeviceObject = [PSCustomObject]@{
            ADName = $workstation.name
            ADLastLogonDate = $workstation.LastLogonDate
            ADEnabled = $workstation.Enabled
            AADName = 'Not AAD Registered'
            AADDeviceOSType = 'Not AAD Registered'
            AADosVersion = 'Not AAD Registered'
            AADLastDirSyncTime = 'Not AAD Registered'
            AADApproximateLastLogonTimeStamp = 'Not AAD Registered'
            IntuneName = 'Not MDM Enrolled'
            IntuneosVersion = 'Not MDM Enrolled'
            IntunelastCheckin = 'Not MDM Enrolled'
            IntuneRegisteredUPN = 'Not MDM Enrolled'
            UniversalGUID = $ADObjectGUID
        }
        # Add device object to AllWorkstations 
        $AllWorkstations += $tempDeviceObject;
    }  
    # If the IntuneDevice is enrolled and AzureADDevice is not registered -- this should probably never happen.
    elseif ( ($IntuneDevice -ne $NULL) -and ( $AzureADDevice -eq $NULL ))  {
            $tempDeviceObject = [PSCustomObject]@{
            ADName = $workstation.name
            ADLastLogonDate = $workstation.LastLogonDate
            ADEnabled = $workstation.Enabled
            AADName = 'Not AAD Registered'
            AADDeviceOSType = 'Not AAD Registered'
            AADosVersion = 'Not AAD Registered'
            AADLastDirSyncTime = 'Not AAD Registered'
            AADApproximateLastLogonTimeStamp = 'Not AAD Registered'
            IntuneName = $IntuneDevice.deviceName -join ", "
            IntuneosVersion = $IntuneDevice.osVersion -join ", "
            IntunelastCheckin = $IntuneDevice.lastSyncDateTime -join ", "
            IntuneRegisteredUPN = $IntuneDevice.userprincipalname -join ", "
            UniversalGUID = $ADObjectGUID
        }
        # Add device object to AllWorkstations 
        $AllWorkstations += $tempDeviceObject;
	}
    # If the Intune device is not enrolled, but is registered in Azure AD, troubleshoot the Intune enrollment process.
    elseif ( ($IntuneDevice -eq $NULL) -and ( $AzureADDevice -ne $NULL ))  {
            #Create device object not enrolled in Intune, but registered in AzureAD.
            $tempDeviceObject = [PSCustomObject]@{
            ADName = $workstation.name
            ADLastLogonDate = $workstation.LastLogonDate
            ADEnabled = $workstation.Enabled
            AADName = $AzureADDevice.DisplayName -join ", "
            AADDeviceOSType = $AzureADDevice.DeviceOSType -join ", "
            AADosVersion = $AzureADDevice.DeviceOSVersion -join ", "
            AADLastDirSyncTime = $AzureADDevice.LastDirSyncTime -join ", "
            AADApproximateLastLogonTimeStamp = $AzureADDevice.ApproximateLastLogonTimeStamp -join ", "
            IntuneName = 'Not MDM Enrolled'
            IntuneosVersion = 'Not MDM Enrolled'
            IntunelastCheckin = 'Not MDM Enrolled'
            IntuneRegisteredUPN = 'Not MDM Enrolled'
            UniversalGUID = $ADObjectGUID
        }
        # Add device object to AllWorkstations 
        $AllWorkstations += $tempDeviceObject;
	}
    # If the Intune device is enrolled and Azure AD registered, we likely have a healthy enrollment.
    else {
            $tempDeviceObject = [PSCustomObject]@{
            ADName = $workstation.name
            ADLastLogonDate = $workstation.LastLogonDate
            ADEnabled = $workstation.Enabled
            AADName = $AzureADDevice.DisplayName -join ", "
            AADDeviceOSType = $AzureADDevice.DeviceOSType -join ", "
            AADosVersion = $AzureADDevice.DeviceOSVersion -join ", "
            AADLastDirSyncTime = $AzureADDevice.LastDirSyncTime -join ", "
            AADApproximateLastLogonTimeStamp = $AzureADDevice.ApproximateLastLogonTimeStamp -join ", "
            IntuneName = $IntuneDevice.deviceName -join ", "
            IntuneosVersion = $IntuneDevice.osVersion -join ", "
            IntunelastCheckin = $IntuneDevice.lastSyncDateTime -join ", "
            IntuneRegisteredUPN = $IntuneDevice.userprincipalname -join ", "
            UniversalGUID = $ADObjectGUID
        }
        # Add device object to AllWorkstations 
        $AllWorkstations += $tempDeviceObject;
	
    }
}

# Output all workstations to CSV filename for further formatting
$AllWorkstationsCount = $AllWorkstations.count
$AllWorkstations | export-csv $filename -NoTypeInformation;
$host.ui.RawUI.ForegroundColor = "DarkGreen"
Write-Output "Writing $($AllWorkstations.Count) devices to $filename."
$host.ui.RawUI.ForegroundColor = $originalColor