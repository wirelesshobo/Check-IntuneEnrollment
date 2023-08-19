
# Define Action to take on Error
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory;
Import-Module AzureAD;
Import-Module Microsoft.Graph.Intune;


# Connect to MSGraph
try {
    Connect-MSGraph -ErrorAction Stop;
    Write-Output "Connected to Intune."
} catch {
    $message = $_.Exception.$message
    Write-Output "Unable to connect to Intune MS Graph."
    Write-Output $message
}

# Connect to AzureAD
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

# Output file with timestamp.
$timestamp = get-date -Format yyyyMMddhhmmss
$filename = "C:\notes\ADAzureADIntuneDeviceReport_" + $timestamp + ".csv"

# Set the base OU to search for computer objects.
$OUSearchBase = "OU=Workstations,OU=_CSU-Computers,DC=columbia,DC=local";

# ADWorkstations is an array of all computer objects under the Workstations OU
$ADWorkstations = get-adcomputer -SearchBase $OUSearchBase -filter * -Properties LastLogonDate
Write-Output "Getting a list of computer objects from $($OUSearchBase).  $($ADWorkstations.count) objects found."

# AzureDevices
$AzureADDevices = Get-AzureADDevice -All $true
Write-Output "Getting a list of all AzureAD Devices. $($AzureADDevices.count) devices found."

# IntuneDevices
$IntuneManagedDevices = Get-IntuneManagedDevice
Write-Output "Getting a list of all Intune Managed Devices. $($IntuneManagedDevices.count) devices found."

# Initialize a number count for progress bar.
$i=0;

# Create a count of total workstations to process.
$ADWorkstationTotal = $ADWorkstations.count;

# Initialize and Output Progress Bar
$Progress = @{
    Activity = 'Processing Computer Objects'
    CurrentOperation = 'Processing'
    Status = 'Searching AzureAD and Intune'
    PercentComplete = 0
}

Write-Progress @Progress;

# For each workstation in AD check for enrollment in Intune
foreach ($workstation in $ADWorkstations) {

    $i++;
    $roundedPercentageCompleted = [math]::Round((($i / $ADWorkstationTotal) * 100), [System.MidpointRounding]::AwayFromZero);
    

    #Assign device name to be the workstation.name
    $ADDeviceName = $workstation.name;
    $ADObjectGUID = $workstation.ObjectGUID; 

    #Write-Output "Computer Objects Processed: $($numbercount)  Percent Complete: $($Completed)"

    $Progress.CurrentOperation = $ADDeviceName 
    $Progress.Status = 'Searching AzureAD and Intune: '
    $Progress.PercentComplete = $roundedPercentageCompleted
    Write-Progress @Progress
    Start-Sleep -Milliseconds 20

	try {

		# Try to obtain the enrolled Intune device based on the computer object device name
		$IntuneDevice = $IntuneManagedDevices | Where-Object {$_.azureADDeviceId -eq $ADObjectGUID};
        

	}  catch { 

        # An error occurred accessing Intune in some way.
        $message = $_.Exception.$message
		Write-Output "An error occurred with obtaining data from Intune.";
        Write-Output $message

	}


    try {

         #Try to obtain Azure AD data on device.
         $AzureADDevice = $AzureADDevices | Where-Object {$_.deviceid -eq $ADObjectGUID}

    } catch {

        # An error occurred accessing Azure AD in some way.
        $message = $_.Exception.$message
        Write-Output "An error occurred with obtaining data from AzureAD."
        Write-Output $message


    }

	# If the IntuneDevice result is NULL generate a not found object, else generate the device object with full details.
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

    elseif ( ($IntuneDevice -ne $NULL) -and ( $AzureADDevice -eq $NULL ))  {
        #Create device object enrolled in Intune, but not returning value in AzureAD.
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

    else {
        #Create device object returning values in AzureAD and Intune.
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

# Output all workstations to CSV for formatting.
$AllWorkstations | export-csv $filename -NoTypeInformation;
Write-Output "Writing CSV to " + $filename