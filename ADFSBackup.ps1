#######################################################################################
##  Date: December 21, 2017
##  Authors: Andy Boell and Cody Ernesti
##
##  ADFS Automatic Backup Tool
##
##  This script performs the following tasks:
##  -tests if PSFTP is downloaded and if not, downloads from source
##  -tests if ADFSRapidRecreationTool.msi is installed and if not, downloads from source
##     and installs automatically
##  -Performs backup of ADFS
##  -Compresses backup
##  -Deletes original backup folder
##  -Uploads to SFTP site located at backup.nnnc.org
##########################################################################################

# Define main folder path
$folderPath = "C:\ADFS-Backup"

# Test for Log folder existence; creates folder if doesn't previously exist
$logPath = "$($folderPath)\Log"
If(!(Test-Path  $logPath)) {
    New-Item -ItemType Directory -Force -Path $logPath
}

$log = $logPath + "\log.log"
$FTPpasswordError = $false
$FTPusernameError = $false

"Processing started (on $(Get-Date)): " | Out-File $log -Append
"-------------------------------------------" | Out-File $log -Append

"[INFO] Log Folder Path: $($logPath)" | Out-File $log -Append

"[INFO] Main Folder Path: $($folderPath)" | Out-File $log -Append

# Define FTP folder path
$FTPpath = "$($folderPath)\location.txt"
"[INFO] FTP Folder Path: $($FTPpath)" | Out-File $log -Append

# Define FTP password path
$credPassword = "$($folderPath)\credentials.txt"
"[INFO] FTP Password Path: $($credPassword)" | Out-File $log -Append

# Define FTP Username path
$credUsername = "$($folderPath)\username.txt"
"[INFO] FTP Username Path: $($credUsername)" | Out-File $log -Append


# Set FTP folder
"`r`n[INFO] Entering FTP Folder Path" | Out-File $log -Append
If(Test-Path $FTPpath) {
    $folder = Get-Content $FTPpath
    "[INFO] FTP Folder Path: $($folder)" | Out-File $log -Append
}
Else {
    "[ERROR] Error setting FTP Folder Path: $($FTPpath) missing" | Out-File $log -Append
}


"`r`n[INFO] Entering FTP Credential Creation" | Out-File $log -Append
# Obtains password for psftp & ADFS Backup encryption
Try{
    $myCred = Import-Clixml $credPassword
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($myCred)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}
Catch{
    "[ERROR] Error setting FTP Password: $($_)" | Out-File $log -Append
    $FTPpasswordError = $true
}
if(!$FTPpasswordError) {
    "[INFO] FTP Password Set" | Out-File $log -Append
}

Try{
    $myCred = Import-Clixml $credUsername
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($myCred)
    $username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}
Catch {
    "[ERROR] Error setting FTP Username: $($_)" | Out-File $log -Append
    $FTPusernameError = $true
}
if(!$FTPusernameError) {
    "[INFO] FTP Username Set" | Out-File $log -Append
}

"`r`n[INFO] Import ADFS Rapid Recreation Tool" | Out-File $log -Append
# Imports module required for ADFS Backup
Try{
    Import-Module 'C:\Program Files (x86)\ADFS Rapid Recreation Tool\ADFSRapidRecreationTool.dll' -ErrorAction Stop
}
Catch{ 
    "[ERROR] Error importing ADFS Rapid Recreation Tool module: $($_)" | Out-File $log -Append
}

# Creates ADFS Backup
"`r`n[INFO] Begin ADFS Backup" | Out-File $log -Append
Backup-ADFS -StorageType "FileSystem" -StoragePath $folderPath -EncryptionPassword $password -BackupDKM
"[INFO] Completed ADFS Backup" | Out-File $log -Append

# Obtains most recent directory in the current path (which should be the backup)
$filename = Get-ChildItem -Path $folderPath -Directory | sort CreationTime -Descending | select -First 1

# Creates zip file name
$destination = $filename.FullName + ".zip"

# Zips folder into file
Add-Type -assembly "system.io.compression.filesystem"
[io.compression.zipfile]::CreateFromDirectory($filename.FullName, $destination)
"`r`n[INFO] Zip file created with filename: $($destination)" | Out-File $log -Append

# Deletes backup directory
"`r`n[INFO] Entering folder deletion" | Out-File $log -Append
Try{
    Remove-Item -LiteralPath $filename.FullName -Recurse -Force
}
Catch{
    "[ERROR] Error deleting folder: $($_)" | Out-File $log -Append
}
#$filename | Out-File -FilePath $folderPath\filename.txt
"[INFO] Original ADFS Backup folder $($filename) deleted" | Out-File $log -Append

# Creates script to upload file using PSFTP
$batchPSFTP = "cd $folder`nput $destination`nquit"
$batchPSFTP | out-file "$($folderPath)\batch.psftp" -force  -Encoding ASCII
"`r`n[INFO] PSFTP Batch file created: $($batchPSFTP)" | Out-File $log -Append

# Uploads file to destination
"`r`n[INFO] Begin PSFTP upload" | Out-File $log -Append
& "$folderPath\psftp.exe" -l $username -pw $password backup.nnnc.org -b $folderPath\batch.psftp -be -i $folderPath\private.ppk -hostkey e1:bd:d2:42:8e:dc:20:32:ed:7f:43:17:43:b9:28:6e
"[INFO] Completed PSFTP upload" | Out-File $log -Append


"-------------------------------------------" | Out-File $log -Append
"End File Processing (on $(Get-Date))" | Out-File $log -Append

# Pauses for 10 seconds to allow previous SFTP upload to complete
Start-Sleep 10

# Sends a copy of the log to the SFTP server
Rename-Item -Path $log -NewName "$logPath\$filename.log"
$batchPSFTP = "cd $folder`nput $logPath\$filename.log`nquit"
$batchPSFTP | out-file "$($folderPath)\batch.psftp" -force  -Encoding ASCII

& "$folderPath\psftp.exe" -l $username -pw $password backup.nnnc.org -b $folderPath\batch.psftp -be -i $folderPath\private.ppk -hostkey e1:bd:d2:42:8e:dc:20:32:ed:7f:43:17:43:b9:28:6e
