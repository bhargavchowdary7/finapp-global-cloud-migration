<#
.SYNOPSIS
    Creates volume configuration objects for NAS to Azure Storage migration.
.DESCRIPTION
    This script defines a function to create standardized volume configuration objects that encapsulate
    all necessary details for migrating NAS volumes to Azure Storage.
#>

function New-VolumeConfiguration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VolumeId,
        
        [Parameter(Mandatory=$true)]
        [string]$VolumeName,
        
        [Parameter(Mandatory=$true)]
        [string]$NASServer,
        
        [Parameter(Mandatory=$true)]
        [string]$VolumePath,
        
        [Parameter(Mandatory=$true)]
        [string]$ShareName,
        
        [Parameter(Mandatory=$true)]
        [int]$SizeGB,
        
        [Parameter(Mandatory=$false)]
        [string]$VolumeType = "General",
        
        [Parameter(Mandatory=$false)]
        [int]$Priority = 3
    )

    return [PSCustomObject]@{
        VolumeId = $VolumeId
        VolumeName = $VolumeName
        NASServer = $NASServer
        VolumePath = $VolumePath
        ShareName = $ShareName
        SizeGB = $SizeGB
        VolumeType = $VolumeType
        Priority = $Priority
        Status = "Pending"
        MigrationMethod = ""
    }
}

Export-ModuleMember -Function New-VolumeConfiguration