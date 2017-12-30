﻿#Requires -RunAsAdministrator
<#
	.SYNOPSIS
		- Legitimately converts Windows 10 Home to Windows 10 Pro for Workstations.
		- Does NOT perform any actions that are against Microsoft's Terms of Service or in any ways illegal.
		- Microsoft offers a free Media Creation Tool for v1709 that will download their Fall Creator's Update v1709.
		- There are other legitimate 3rd party sources where this media can also be obtained.
	
	.DESCRIPTION
		- If an Install.WIM is supplied, it will copy it to a temporary directory.
		- If an ISO is supplied, it will mount the ISO, copy the Install.WIM to a temporary directory, then dismount the ISO.
		- Changes the WIM's Edition ID to Windows 10 Pro for Workstations.
		- Converts the WIM's default XML values to Windows 10 Pro for Workstations specific values.
		- Generates a Windows 10 Pro for Workstations EI.CFG.
		- Exports the new Windows 10 Pro for Workstations WIM, EI.CFG and XML info to the user's desktop.
	
	.PARAMETER SourcePath
		The path to a Windows Installation ISO or an Install.WIM.
	
	.EXAMPLE
		.\ConvertTo-PfW.ps1 -SourcePath "D:\install.wim"
		.\ConvertTo-PfW.ps1 -SourcePath "E:\Windows Images\Win10_1709_English_x64_ALL.iso"
	
	.NOTES
		- It does not matter if the source image contains multiple indexes or a single Home index.
		- The script's processes run silently, though it does output what it's doing to the console using proper verbosity.
		- Make sure to keep the imagex.exe in the same directory the script is in, as it's required for a full conversion.
		- ImageX is an official Microsoft tool that has been discontinued.
	
	.NOTES
		===========================================================================
		Created on:   	11/30/2017
		Created by:     DrEmpiricism
		Contact:        Ben@Omnic.Tech
		Filename:     	ConvertTo-PfW.ps1
		Version:        1.8
		Last updated:	12/30/2017
		===========================================================================
#>
[CmdletBinding()]
Param
(
	[Parameter(Mandatory = $true,
			   HelpMessage = 'The path to a Windows Installation ISO or an Install.WIM.')][ValidateScript({ Test-Path $(Resolve-Path $_) })][Alias('ISO', 'WIM')][string]$SourcePath
)

$Host.UI.RawUI.WindowTitle = "Converting image."
$Host.UI.RawUI.BackgroundColor = "Black"; Clear-Host
$ProgressPreference = "SilentlyContinue"
$Desktop = "$HOME\Desktop"

Function Create-WorkDirectory
{
	$WorkDir = [System.IO.Path]::GetTempPath()
	$WorkDir = [System.IO.Path]::Combine($WorkDir, [System.Guid]::NewGuid())
	[void][System.IO.Directory]::CreateDirectory($WorkDir)
	$WorkDir
}

Function Create-TempDirectory
{
	$TempDir = [System.IO.Path]::GetTempPath()
	$TempDir = [System.IO.Path]::Combine($TempDir, [System.Guid]::NewGuid())
	[void][System.IO.Directory]::CreateDirectory($TempDir)
	$TempDir
}

Function Create-ImageDirectory
{
	$ImageDir = [System.IO.Path]::GetTempPath()
	$ImageDir = [System.IO.Path]::Combine($ImageDir, [System.Guid]::NewGuid())
	[void][System.IO.Directory]::CreateDirectory($ImageDir)
	$ImageDir
}

Function Create-MountDirectory
{
	$MountDir = [System.IO.Path]::GetTempPath()
	$MountDir = [System.IO.Path]::Combine($MountDir, [System.Guid]::NewGuid())
	[void][System.IO.Directory]::CreateDirectory($MountDir)
	$MountDir
}

Function Create-SaveDirectory
{
	New-Item -ItemType Directory -Path $Desktop\ConvertTo-PfW"-[$((Get-Date).ToString('MM.dd.yy hh.mm.ss'))]"
}

If (Test-Path -Path "$PSScriptRoot\imagex.exe")
{
	[void](Copy-Item -Path "$PSScriptRoot\imagex.exe" -Destination $env:TEMP -Force)
	$Error.Clear()
}
Else
{
	Throw "ImageX was not found in the script's root directory."
}

If (([IO.FileInfo]$SourcePath).Extension -like ".ISO")
{
	$ISOPath = (Resolve-Path $SourcePath).Path
	$MountISO = Mount-DiskImage -ImagePath $ISOPath -StorageType ISO -PassThru
	$DriveLetter = ($MountISO | Get-Volume).DriveLetter
	$InstallWIM = "$($DriveLetter):\sources\install.wim"
	If (Test-Path -Path $InstallWIM)
	{
		Write-Verbose "Copying WIM from the ISO to a temporary directory." -Verbose
		[void](Copy-Item -Path $InstallWIM -Destination $env:TEMP -Force)
		Dismount-DiskImage -ImagePath $ISOPath -StorageType ISO
		If (([IO.FileInfo]"$env:TEMP\install.wim").IsReadOnly) { ATTRIB -R $env:TEMP\install.wim }
	}
	Else
	{
		Dismount-DiskImage -ImagePath $ISOPath -StorageType ISO
		Throw "$ISOPath does not contain valid Windows Installation media."
	}
}
ElseIf (([IO.FileInfo]$SourcePath).Extension -like ".WIM")
{
	$WIMPath = (Resolve-Path $SourcePath).Path
	If (Test-Path -Path $WIMPath)
	{
		Write-Verbose "Copying WIM to a temporary directory." -Verbose
		[void](Copy-Item -Path $SourcePath -Destination $env:TEMP\install.wim -Force)
		If (([IO.FileInfo]"$env:TEMP\install.wim").IsReadOnly) { ATTRIB -R $env:TEMP\install.wim }
	}
	Else
	{
		Throw "$WIMPath does not contain valid Windows Installation media."
	}
}

If ((Test-Path -Path $env:TEMP\install.wim) -and (Test-Path -Path $env:TEMP\imagex.exe))
{
	[void]($WorkFolder = Create-WorkDirectory)
	[void]($TempFolder = Create-TempDirectory)
	[void]($ImageFolder = Create-ImageDirectory)
	[void]($MountFolder = Create-MountDirectory)
	[void](Move-Item -Path $env:TEMP\install.wim -Destination $ImageFolder -Force)
	[void](Move-Item -Path $env:TEMP\imagex.exe -Destination $ImageFolder -Force)
	$ImageFile = "$ImageFolder\install.wim"
	[string[]]$IndexImages = @(
		"Windows 10 S", "Windows 10 S N", "Windows 10 Home N", "Windows 10 Home Single Language", "Windows 10 Education", "Windows 10 Education N", "Windows 10 Pro", "Windows 10 Pro N"
	)
	$HomeImage = "Windows 10 Home"
	$ImageInfo = Get-WindowsImage -ImagePath $ImageFile
}

If ($ImageInfo.Count -gt "1" -and $ImageInfo.ImageName.Contains($HomeImage))
{
	Write-Output ''
	Write-Output "$HomeImage detected. Converting to a single-index image file."
	ForEach ($IndexImage in $IndexImages)
	{
		[void]($ImageInfo.Where({ $_.ImageName -contains $IndexImage }) | Remove-WindowsImage -ImagePath $ImageFile -Name $IndexImage)
	}
	$Index = "1"
}
ElseIf ($ImageInfo.Count -eq "1" -and $ImageInfo.ImageName.Contains($HomeImage))
{
	Write-Output ''
	Write-Output "$HomeImage detected."
	$Index = "1"
}
Else
{
	Throw "$HomeImage not detected."
}

Try
{
	Write-Output ''
	Write-Verbose "Mounting Image." -Verbose
	[void](Mount-WindowsImage -ImagePath $ImageFile -Index $Index -Path $MountFolder -ScratchDirectory $TempFolder)
	Write-Output ''
	Write-Verbose "Changing Image Edition to Windows 10 Pro for Workstations." -Verbose
	[void](Set-WindowsEdition -Path $MountFolder -Edition "ProfessionalWorkstation" -ScratchDirectory $TempFolder)
	If (Test-Path -Path $MountFolder\Windows\Core.xml)
	{
		[void](Remove-Item -Path $MountFolder\Windows\Core.xml -Force)
	}
	Write-Output ''
	Write-Output "Image Edition successfully changed."
	Start-Sleep 3
	Write-Output ''
	Write-Verbose "Saving and Dismounting Image." -Verbose
	[void](Dismount-WindowsImage -Path $MountFolder -Save -CheckIntegrity -ScratchDirectory $TempFolder)
	$IndexChangeComplete = $true
}
Catch [System.IO.IOException]
{
	Write-Output ''
	Write-Error -Message "Unable to change Image Edition to Windows 10 Pro for Workstations." -Category WriteError
	Break
}

Try
{
	Write-Output ''
	Write-Verbose "Converting $HomeImage to Windows 10 Pro for Workstations." -Verbose
	Start-Process -Filepath CMD.exe -WorkingDirectory $ImageFolder -ArgumentList ('/c imagex /Info install.wim 1 "Windows 10 Pro for Workstations" "Windows 10 Pro for Workstations" /Flags ProfessionalWorkstation') -Verb runas -WindowStyle Hidden -Wait -ErrorAction Stop
	Start-Process -Filepath CMD.exe -WorkingDirectory $ImageFolder -ArgumentList ('/c imagex /Info install.wim 1 /Check /XML > ProfessionalWorkstation.xml') -Verb runas -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
	Write-Output ''
	Write-Output "Conversion successful."
	$ConversionComplete = $true
	Start-Sleep 3
}
Catch [System.ArgumentException]
{
	Write-Output ''
	Write-Error -Message "Unable to convert $HomeImage to Windows 10 Pro for Workstations." -Category InvalidArgument
	Break
}

If ($ConversionComplete -eq $true)
{
	$AddEICFG = {
		$EICFGStr = @"
[EditionID]
ProfessionalWorkstation

[Channel]
Retail

[VL]
0
"@
		$CreateEICFG = Join-Path -Path $WorkFolder -ChildPath "EI.CFG"
		Set-Content -Path $CreateEICFG -Value $EICFGStr -Force
	}
	Write-Output ''
	Write-Verbose "Creating a Pro for Workstations EI.CFG." -Verbose
	& $AddEICFG
	Start-Sleep 3
}

If ($ConversionComplete -eq $true)
{
	Write-Output ''
	Write-Verbose "Exporting Windows 10 Pro for Workstations." -Verbose
	[void](Export-WindowsImage -CheckIntegrity -CompressionType maximum -SourceImagePath $ImageFile -SourceIndex $Index -DestinationImagePath $WorkFolder\install.wim -ScratchDirectory $TempFolder)
	$SaveFolder = Create-SaveDirectory
	[void](Move-Item -Path $WorkFolder\install.wim -Destination $SaveFolder -Force)
	[void](Move-Item -Path $ImageFolder\*.xml -Destination $SaveFolder -Force)
	[void](Move-Item -Path $WorkFolder\*.CFG -Destination $SaveFolder -Force)
	[void](Remove-Item $TempFolder -Recurse -Force)
	[void](Remove-Item $ImageFolder -Recurse -Force)
	[void](Remove-Item $MountFolder -Recurse -Force)
	[void](Remove-Item $WorkFolder -Recurse -Force)
	[void](Clear-WindowsCorruptMountPoint)
	Write-Output ''
	Write-Output "Windows 10 Pro for Workstations saved to $SaveFolder"
	Start-Sleep 3
	Write-Output ''
}
# SIG # Begin signature block
# MIIJnAYJKoZIhvcNAQcCoIIJjTCCCYkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUK9HSZXxqmp3+7cGXTO44Oml1
# /WigggaRMIIDQjCCAi6gAwIBAgIQdLtQndqbgJJBvqGYnOa7JjAJBgUrDgMCHQUA
# MCkxJzAlBgNVBAMTHk9NTklDLlRFQ0gtQ0EgQ2VydGlmaWNhdGUgUm9vdDAeFw0x
# NzExMDcwMzM4MjBaFw0zOTEyMzEyMzU5NTlaMCQxIjAgBgNVBAMTGU9NTklDLlRF
# Q0ggUG93ZXJTaGVsbCBDU0MwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC61XYWFHD6Mf5tjbApbKSOWTlKYm9zYpVcHJ4bCXuRwUHaZEqd13GuvxA58oxL
# sj2PjV2lzV00zFk0RyswA20H2bjQtRJ45WZWUZMpgcf6hIiFGtQCuEQnytjD0AQu
# OTGBfwngyRsKLbaEDWk7B0dlWoYCvxt1zvXSIH2YcqpfP6QLejA+nyhvuLZm0O9E
# aFvBCPc+7G68VfQCQyn+aBTQpJpH34O9Qv06B2FGSiDk+lwrKQW4juEDmrabgpYF
# TACsxVUHK/1loejOvCZFyBXiyRoNaf8tJaSqmqzeB5zZz4rFAJesWEs+iAZutvfa
# x6TzMGFtjjevzl6ZrnF7Fv/9AgMBAAGjczBxMBMGA1UdJQQMMAoGCCsGAQUFBwMD
# MFoGA1UdAQRTMFGAEApGKFjm6hqPE+12gARxOhGhKzApMScwJQYDVQQDEx5PTU5J
# Qy5URUNILUNBIENlcnRpZmljYXRlIFJvb3SCEIgU76EmbFSeTMjPeYe5TN0wCQYF
# Kw4DAh0FAAOCAQEAte3lbQnd4Wnqf6qqmemtPLIHDna+382IRzBr4+ZaK4TXqXgl
# /sPzVkwkoqroJV9mMrQPvVXjgCaHie5h5W0HeGRVdQv7biG4zRNzbheVck2LPaOo
# MDNsNCc12ab9lvK/Y7eaj19iP1Yii/VBrnY3YsNt200icymp60R1QjgvXncPxZqK
# viMg7VQWBTfQ3n7LucBhuSZaMJItbVRTlJsbXzkmCQzvG88/TDRbFqukbmDVgiZL
# RONR2KTv0PRxopIews59WGMrJseuihET4z5a3L7xeUdwXCVPn87xgqIQGaCB5jui
# 0DHgpniWmxbBuAQMPMeuwSEQV0jb5KqVUegFGDCCA0cwggIzoAMCAQICEIgU76Em
# bFSeTMjPeYe5TN0wCQYFKw4DAh0FADApMScwJQYDVQQDEx5PTU5JQy5URUNILUNB
# IENlcnRpZmljYXRlIFJvb3QwHhcNMTcxMTA3MDMzMjIyWhcNMzkxMjMxMjM1OTU5
# WjApMScwJQYDVQQDEx5PTU5JQy5URUNILUNBIENlcnRpZmljYXRlIFJvb3QwggEi
# MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDMH3EMA2t/V0+BbvaWhgoezpQZ
# hY5NZcC/Yfs6YzAbCEBagmfT22NpAGKAd/fmsqL0DlZeBPDC8z5ga9BvxxWtvZQl
# QzCHx3wbmgrpc9AA99xEGms3lhcKea+wqEPCebK/OnSPVqqxEoGykoLQiR2BSO/m
# QL2hQPkM8kFGbX3ncUCMSdMWJR0XTcZL6zVPIpaLj0qJVEL6YoAFdlrd+6N2STex
# 9LKZhJ88dtfEiM0e81KyAkHHjPX03abSKppVTgOxG4+WZtMDZnvlpolEi5tgVy0e
# d04BBQmztKilRZILPkAgcmx89pf6Fa5Vss3Fp3Z7D+4e9nQ+4DZ/Vb1NIKZRAgMB
# AAGjczBxMBMGA1UdJQQMMAoGCCsGAQUFBwMDMFoGA1UdAQRTMFGAEApGKFjm6hqP
# E+12gARxOhGhKzApMScwJQYDVQQDEx5PTU5JQy5URUNILUNBIENlcnRpZmljYXRl
# IFJvb3SCEIgU76EmbFSeTMjPeYe5TN0wCQYFKw4DAh0FAAOCAQEAtj1/SaELGLyj
# DP2aRLpfMq1KIBoMjJvQhYfPWugzc6GJM/v+3LomDW8yylMhQRqy6749HMfDVXtJ
# oc4KU00H2q7M5xXGX7HJlh4tFEMrT4k1WDVdxF/TgXxTlMWBfRXV/rNzSFHtHVf6
# F+dY7INqxKlbMGpg3buF/Oh8ZtPk9xhyWtwraUTsyVBlmQlMeFeKwksbaSEy72mJ
# 5DhQfVmEv1PTv/wIJ/ff8OOZ63AeJqpLcmFARbTUmQVboFEG5mU30BHHntABspLj
# kdk4PCQjdVgG8Bd7uOC3XNbmrhTehi7Uu8uOBm7RQawF1wh65SlQm5HY2tntNPzD
# qHcndUPZwjGCAnUwggJxAgEBMD0wKTEnMCUGA1UEAxMeT01OSUMuVEVDSC1DQSBD
# ZXJ0aWZpY2F0ZSBSb290AhB0u1Cd2puAkkG+oZic5rsmMAkGBSsOAwIaBQCgggEN
# MBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgor
# BgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBS6k5rgmJS3vBooRwCvfNfQXm3gMjCB
# rAYKKwYBBAGCNwIBDDGBnTCBmqCBl4CBlABXAGkAbgBkAG8AdwBzACAAMQAwACAA
# SABvAG0AZQAgAHQAbwAgAFcAaQBuAGQAbwB3AHMAIAAxADAAIABQAHIAbwAgAGYA
# bwByACAAVwBvAHIAawBzAHQAYQB0AGkAbwBuAHMAIABmAHUAbABsACAAYwBvAG4A
# dgBlAHIAcwBpAG8AbgAgAHMAYwByAGkAcAB0AC4wDQYJKoZIhvcNAQEBBQAEggEA
# O9fcf7fQI76V41NHw9hwTrFSbJyc4ljAr3lCFvkWx0eqE5POWC6Y1BXobdQK9+0Q
# w3VRVCCUOk0iKXUdi+pBLLUfTuM1tgDgmBHQSxcaNsF0xF/Bkcay5ZOmIqlddHQa
# fxNkVnFAbgH1Em7q77BIacI45L3Prwc2IGfYZzrLSov7a2W0Bira75r/uoaTzc1w
# Cw3OZ3aoVpDnD1YAek9K8fvj0FvJSUioBsqyNXj4NPk4eCA1+VSljj8qo3Gv3aRJ
# eh9GcX5Cy00YM+rsqrR8tg8tPPda4xyvAnZj2Ou2TS9er44jTHKd9/EJnkqitqhx
# qSPIB/0kFgq2x9OfYeFaOA==
# SIG # End signature block
