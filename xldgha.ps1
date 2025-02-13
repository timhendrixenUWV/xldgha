param (
    [string]$GHGoal,
    [bool]$GHrollback,
    [string]$GHxldurl,
    [string]$GHxldusername,
    [string]$GHxldpassword,
    [string]$GHdarpackage,
    [string]$GHtargetenvironment
)


# Enable TLS1.2 for webrequests and set workspace directory
[System.Net.ServicePointManager]::SecurityProtocol = 'TLS12'
Set-Location -path $GITHUB_WORKSPACE

# Declare global variables
$Global:XLDgoal = $GHGoal
$Global:XLDserviceconnection = $serviceEndpoint
$Global:XLDdarPackage = $GHdarPackage
$Global:XLDappId = ""
$Global:XLDtargetEnvironment = $GHtargetEnvironment
$Global:taskId = ""
$Global:blockID = ""
$Global:baseUrl = ""
$Global:appIdStatus = "Nothing" 
$Global:Darfile = ""
$Global:manifestVersion = ""
$Global:manifestApplication = ""
$Global:Rollback = $GHrollback
$Global:ErrorInd = "FALSE"

# Check if the URL string ends with a slash or backslash and remove it if it does
if ($GHxldurl -match '[\\/]+$')
{
    $GHxldurl = $GHxldurl -replace '[\\/]+$'
}

#API calls are made in 2 steps:
# build the url defined as <procesvar>url Bv blocktreeUrl
# execute the api call as 
# <procesvar>call =Invoke-Webrequest -Uri $<procesvar>url // Bv blocktreeCall

function Get-BlockID {

    #### Monitoring
    $Global:baseUrl = $GHxldurl+"/deployit/tasks/v2/"+$Global:TaskId+"/step/"
    $Global:blockID = New-Object System.Collections.Generic.List[System.Object]
    $x = 1
    $y = 1
    $errorCount=0
    Write-host "Building Block ID tree"
    # Loop through until x errors out
    while ($true) {
        $blockTreeUrl = $Global:baseUrl + "0_" + "$x" + "_1_" + "$y"
        try {
            # Invoke the API endpoint
            $blockTreeCall=Invoke-WebRequest -Uri $blockTreeUrl -Credential $Global:Cred -ErrorAction Stop
            [xml]$blockTreeCallxml=$blockTreeCall.Content
            $Global:blockID.Add($blockTreeCallxml.step.metadata.blockPath)
            $y++ # Increment y
            $errorCount=0
        } catch {
            # If invoke-webrequest errors out, raise x and reset y
            $x++
            $y = 1
            $errorCount++
            if ($errorCount -eq 2) {
                break
            }
        }
      }
    Write-host "Building Block ID tree Done."

}

function Get-XLDLogs {
    #Wait until the last task has the status Failed or Done.
    Write-Host "Getting logs"
    $table = @()
    $errorText=""
    $monitoring=$true
    $monitoringUrl  = $GHxldurl+"/deployit/tasks/v2/"+ $Global:TaskId
    Write-host $monitoringUrl

    while($monitoring){
        
        $monitoringCall = Invoke-WebRequest -Uri $monitoringUrl -Credential $Global:Cred
        [xml]$monitoringCallXml = $monitoringCall.Content
        
        if(($monitoringCallXml.task.state -ne "FAILED") -and ($monitoringCallXml.task.state -ne "DONE") -and ($monitoringCallXml.task.state -ne "EXECUTED")){
            $monitoring=$true
        } else {
            $monitoring=$false
        }
    }
    Write-Host "Monitoring loop complete"

    #Generate Logoutput
    foreach($ID in $Global:blockID){
        $errorCheckUrl=$Global:baseUrl+$ID
        $errorCheckCall=Invoke-WebRequest -Uri $errorCheckUrl -Credential $Global:Cred
        [xml]$errorCheckCallXml=$errorCheckCall.Content
        
        if($null -eq $errorCheckCallXml.step.completionDate){
            $datetime = "N/A"
        }else{
            $datetime = Get-Date -Date $errorCheckCallXml.step.completionDate
            $time = $datetime.ToString("HH:mm:ss")
        }

        $row = [PSCustomObject]@{
            Task = $errorCheckCallXml.step.description
            State = $errorCheckCallXml.step.state
            Timestamp = $time
        }
        $table += $row

        if(($errorCheckCallXml.step.state -eq 'FAILED') -and ($errorText -eq "") )
        {
            $errorText=$errorCheckCallXml.step.log
            $Global:ErrorInd = "TRUE"
        }

    }

    $table | Format-Table -AutoSize
 
    if($errorText -ne ""){
        Write-Host "::error:: $errorText"
    }
}

function Get-ServiceConnectionCredentials {
    
    $password = ConvertTo-SecureString $GHxldpassword -AsPlainText -Force
    $Global:Cred = New-Object System.Management.Automation.PSCredential ($GHxldusername, $password); 

    #Check XL Deploy Server connection
    try {
        $connectionTestUrl = $GHxldurl+"/deployit/server/state"
        Write-Host "Testing connection with of the XLDServer: "$connectionTestUrl
        $connectionTestCall = Invoke-WebRequest -Uri $connectionTestUrl -Credential $Global:Cred
    
        # Parse the XML response
        $connectionTestXml = [xml]$connectionTestCall.Content
    
        # Extract the value of the <current-mode> element
        $currentMode = $connectionTestXml.'server-state'.'current-mode'
    
        # Check if the value is "RUNNING"
        if ($currentMode -eq 'RUNNING') {
            Write-Host "The XLDeploy Server is RUNNING"
        } else {
            Write-Host "The XLDeploy Server is OFFLINE"
        }
    } catch {
        Write-Host "::error::$($_.Exception.Message)"
        Write-Host "::error::Something whent wrong while trying to connect to the XLDeploy server"
        Exit 1
    }

    #Check the Target Environment
    try { $envID=[uri]::EscapeUriString($Global:XLDtargetEnvironment)
          $envTestUrl = $GHxldurl + "/deployit/repository/ci/" + $envID
          Write-Host "Checking Target Environment: "$Global:XLDtargetEnvironment
          $envTestCall = Invoke-WebRequest -Uri $envTestUrl -Credential $Global:Cred

    } catch {
        
        Write-Host "::error::$($_.Exception.Message)"
        Write-Host "::error::Something went wrong while trying to check the Target Environment on the XLDeploy server"
        Exit 1
    }
}



function Get-Status {
    
    $parentUrl = $GHxldurl + '/deployit/repository/query?namePattern=%25' + $Global:manifestApplication + '&&type=udm.Application'
    [xml]$parentCall = Invoke-WebRequest $parentUrl -Credential $Global:Cred
    
    if($parentCall.list.ci.ref -gt 0 -and $parentCall.list.ci.ref -like "*/$Global:manifestApplication"){
        
        foreach($appid in $parentCall.list.ci.ref){
            if($appid -like "*/$Global:manifestApplication")
            {
                $appURL=[uri]::EscapeUriString($appid)
            }

        }
    } else {    
        
        Write-Host ("::error::Unable to resolve application name $Global:manifestApplication in XLDeploy")
        Exit 1
    }    

    Write-host "Using:" $appURL "as parent"
    
    #Check if manifestVersion has been Uploaded
    $uploadedVersionsUrl = $GHxldurl + '/deployit/repository/query?parent=' + $appURL
    Write-Host $uploadedVersionsUrl
    [xml]$uploadedVersionCall = Invoke-Webrequest $uploadedVersionsUrl -Credential $Global:Cred 
    
    Foreach ($ciRef in $uploadedVersionCall.list.ci.ref) {
        if ( $ciRef -like "*$Global:manifestVersion*"){
                $Global:appIdStatus = "Uploaded"
                #hier nog de XLDappid bepalen om te gebruiken in Invoke-XLDdeployment
                $Global:XLDappId = $ciRef
        }
    }
    write-host "Uploaded appId: " $Global:XLDappId

    #Check if manifestVersion is currently deployed version    
    $deployedVersionUrl = $GHxldurl + '/deployit/repository/ci/'+ $Global:XLDtargetEnvironment + '/'+ $Global:manifestApplication    
       
       
    Try{
    
        $deployedVersionCall = Invoke-WebRequest $deployedVersionUrl -Credential $Global:Cred -ContentType "application/xml" -ErrorAction SilentlyContinue
    }
    catch{
        Write-host "No deployed version found on specified environment!"
    }
    if ( $deployedVersionCall.Content -like "*" +$manifestVersion + "*"){
        $Global:appIdStatus = "Deployed" 
    }

    Write-Host $Global:appIdStatus
}

function Get-DarFile {
    
    # Replace forward slashes with backslashes
    $Global:xlddarpackage = $Global:xlddarpackage -replace "/", "\"

    # Remove the backslash at the start of the string
    if ($Global:xlddarpackage -match "^\\") {
        $Global:xlddarpackage = $Global:xlddarpackage.TrimStart("\")
    }

    $file=Get-ChildItem -Path $Env:GITHUB_WORKSPACE -Filter "*.dar" -Recurse | Where-Object { $_.FullName -like $Env:GITHUB_WORKSPACE + "\" + $Global:xlddarpackage}   
    
    if ($file.count -gt 1){
        Write-Host ("::error::There where " + $file.count + " files found matching " + $Global:xlddarpackage + ", make sure the filter only matches one file.")
        Exit 1
    }elseif($null -eq $file) {
        Write-Host ("::error::File matching " + $Global:xlddarpackage + " does not exist")
        Exit 1
    } else {
        Write-Host ("Found file " + $file.FullName + " matching "  + $Global:xlddarpackage )
        $Global:Darfile = $file.FullName
    }
}   

function Get-ManifestInfoDarFile {

    Write-Host "Opening $Global:Darfile "
    New-Item -ItemType Directory -Path "XLDTemp" -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem   
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Global:Darfile,  "$Env:GITHUB_WORKSPACE\XLDTemp\")

    $file=Get-ChildItem -Path "$Env:GITHUB_WORKSPACE\XLDTemp\" -Filter "deployit-manifest.xml"
    if(Test-path -Path $file -IsValid){
        Write-Host "Found manifest file: " $file.FullName
    }else{
        Remove-Item -Path  "$Env:GITHUB_WORKSPACE\XLDTemp\" -Recurse -Force
        Write-Host "::error:: No manifest file found exiting"
        Exit 1
    }

    [xml]$XmlDocument = Get-Content $file.FullName
    
    $Global:manifestVersion = $XmlDocument.'udm.DeploymentPackage'.version
    $Global:manifestApplication = $XmlDocument.'udm.DeploymentPackage'.application

    Write-Host "Using: "$Global:manifestVersion" as XLdeploy version"
    Write-Host "Using: "$Global:manifestApplication" as XLdeploy application name"
    
    Remove-Item -Path  "$Env:GITHUB_WORKSPACE\XLDTemp\" -Recurse -Force
}


function Invoke-XLDUpload {

    $user= $GHxldusername
    $wachtwoord = $GHxldpassword
    $uploadUrl=$GHxldurl + '/deployit/package/upload/package.dar'
    $Upfile = get-childitem $Global:Darfile
    if ($env:OS -eq "Windows_NT") {
        [xml]$uploadCall = curl.exe --insecure -u $user':'$wachtwoord -X POST -H "content-type:multipart/form-data" $uploadUrl -F fileData=@$upfile
    } else {
        [xml]$uploadCall = curl --insecure -u $user':'$wachtwoord -X POST -H "content-type:multipart/form-data" $uploadUrl -F fileData=@$upfile
    }
    $Global:XLDappId = $uploadCall.'udm.DeploymentPackage'.id
    $Global:XLDappId=[uri]::EscapeUriString($Global:XLDappId)
}

function Invoke-XLDUndeployment {

    $undeployUrl = $GHxldurl + '/deployit/deployment/prepare/undeploy?deployedApplication=' + $Global:XLDtargetEnvironment + '/' + $Global:manifestApplication
    $undeployCall=Invoke-WebRequest $undeployUrl -Credential $Global:Cred -Method GET
    $taskUrl= $GHxldurl+'/deployit/deployment/'
    $taskCall = Invoke-WebRequest  $taskUrl -Credential $Global:Cred -ContentType "application/xml" -Method POST -Body $undeployCall.Content
    $Global:TaskId= $taskCall.content
    $startUndeployUrl= $GHxldurl+'/deployit/tasks/v2/'+$taskCall.Content+'/start'
    $startUndeployCall=Invoke-WebRequest $startUndeployUrl -ContentType 'application/json' -Credential $Global:Cred -Method Post
        
}

function Invoke-XLDDeployment {
   
    $deployUrl=$GHxldurl + "/deployit/deployment/prepare/initial?version=" + $Global:XLDappId + "&environment=" + $Global:XLDtargetEnvironment + "/"
    $deployCall=Invoke-WebRequest $deployUrl -Credential $Global:Cred -Method GET
    $stepUrl= $GHxldurl + "/deployit/deployment/prepare/deployeds" 
    $stepCall = Invoke-WebRequest $stepUrl -Credential $Global:Cred -ContentType "application/xml" -Method POST -Body $deployCall.Content
    
    # Select all validation-message nodes
    $validationMessages = $stepCall.content | Select-Xml "//validation-message"

    # Grab all validation messages and display those
    foreach ($validationMessage in $validationMessages) {
        $level = $validationMessage.Node.getAttribute("level")
        $ci = $validationMessage.Node.getAttribute("ci")
        $property = $validationMessage.Node.getAttribute("property")
        $value = $validationMessage.Node.InnerText

        Write-Output "Level: $level"
        Write-Output "CI: $ci"
        Write-Output "Property: $property"
        Write-Output "Value: $value"
        Write-Output "---------------------------------"
    }
    
    $taskUrl= $GHxldurl+ "/deployit/deployment/"
    $taskCall = Invoke-WebRequest  $taskUrl -Credential $Global:Cred -ContentType "application/xml" -Method POST -Body $stepCall.Content              
    $Global:TaskId= $taskCall.content
    $startDeployUrl=$GHxldurl+'/deployit/tasks/v2/'+$taskCall.Content+'/start'
    $startDeployCall=Invoke-WebRequest $startDeployUrl -ContentType 'application/json' -Credential $Global:Cred -Method Post 
    Write-Host "Started deployment to $Global:XLDtargetEnvironment"


}

function Invoke-Rollback {
    #determine taskprepcontent to be rolledback
    $GHrollbackUrl = $GHxldurl+"/deployit/deployment/rollback/"+$Global:TaskId
    write-host $GHrollbackPrepLink
    #creating the rollbacktask.    
    $GHrollbackCall = Invoke-WebRequest $GHrollbackUrl -Credential $Global:Cred -Method Post -ContentType 'application/xml'
    #storing api call output in $Global:TaskId so that logs can be retrieved.
    $Global:TaskId = $GHrollbackCall.content
    #starting the rollbacktask
    $startRollbackUrl=$GHxldurl+'/deployit/tasks/v2/'+$GHrollbackCall.Content+'/start'
    $startRollbackCall=Invoke-WebRequest $startRollbackUrl -ContentType 'application/json' -Credential $Global:Cred -Method Post 
}

function Invoke-TaskArchival {
    #This function cleans up the created task, and moves it to the XL Deploy task archive.
    $archiveUrl = $GHxldurl+"/deployit/task/"+$Global:TaskId+"/archive"
    try{
        $archiveCall = Invoke-WebRequest $archiveUrl -Credential $Global:Cred -Method Post -ContentType 'application/xml'
        Write-Host "Archiving task $Global:TaskId"
    } catch {
        Write-Host "::warning:: Task archival failure. Task has not been archived or closed. Please close the task manually in the XL Deploy web interface."
    }
}


#Main Script
#Removes the curl->Invoke-Webrequest alias, as the use of the actual curl executable is required.
if (Get-Alias -Name curl  -ErrorAction SilentlyContinue) {
    Remove-Item alias:curl
}


#The following switch evaluates the necessary steps based on the goal selected in the task
switch ($Global:XLDgoal) {
    "Deploy" {   
        
        Get-ServiceConnectionCredentials
        Get-DarFile
        Get-ManifestInfoDarFile
        Get-Status
        
        if($Global:appIdStatus -eq "Nothing"){
        #if status isnt Deployed or Uploaded, execute upload
            Invoke-XLDUpload
        }
        
        if($Global:appIdStatus -ne "Deployed") {
        #if status is not equal to Deployed, execute undeploy
           Invoke-XLDDeployment
        }else{
            Write-Host "::warning:: Nothing to do already uploaded and deployed"
            exit 0
        }
        Get-BlockID
        Get-XLDLogs
        if($Global:ErrorInd -eq "FALSE") {
            Invoke-TaskArchival
        }  elseif ($Global:ErrorInd -eq "TRUE" -and $Global:Rollback -eq "FALSE") {
            Write-Host "::error:: Version deploy failed and rollback is disabled. Please consult the XLDeploy web interface."
            Exit 1
        }      
        
    }
    "Undeploy" { 
        Get-ServiceConnectionCredentials
        
        Get-DarFile
        Get-ManifestInfoDarFile
        Get-Status
        if($Global:appIdStatus -eq "Deployed") {
        #if status is equal to Deployed, execute undeploy
           Invoke-XLDUndeployment
        }else{
            Write-Host "::error:: Version is not deployed. Can not undeploy." 
            exit 1
        }
        Get-BlockID
        Get-XLDLogs
        if($Global:ErrorInd -eq "FALSE") {
            Invoke-TaskArchival
        }  elseif ($Global:ErrorInd -eq "TRUE" -and $Global:Rollback -eq "FALSE") {
            Write-Host "::error:: Version undeploy failed and rollback is disabled. Please consult the XLDeploy web interface."
            Exit 1
        }                    
    }
    
    Default {
        Write-Host "::error::The goal does not match Deploy or Undeploy, nothing to do."
        exit 1      
    }
}



#Check for errors and whether a rollback is requested, if so execute rollback and gather logs.
#ErrorInd is reset to FALSE, as once again a deployment (in the form of a rollback) is executed.
#On success of this rollback, the task is archived. If it fails, the task remains unclosed.
if($Global:ErrorInd -eq "TRUE" -and $Global:Rollback -eq "TRUE"){
    $Global:ErrorInd="FALSE"
    Write-host "initiating rollback for task: "$Global:TaskId
    Invoke-Rollback
    Write-host "Rollback logs for task: "$Global:TaskId
    Get-BlockID
    Get-XLDLogs
    if($Global:ErrorInd -eq "TRUE")
    {
        Write-Host "::error:: Rollback failed, please consult the XLDeploy web interface"
        Exit 1
    }
    else
    {
        Invoke-TaskArchival
        Write-Host "::error:: Rollback executed."
        Exit 1
    }
}
