<#PSScriptInfo
.AUTHOR 
Daniel Wahlgren
.COMPANYNAME 
None
.COPYRIGHT
Copyright (c) 2022 Daniel Wahlgren
.TAGS
module project build
.LICENSEURI 
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES 
.RELEASENOTES
Modified version of build-script from ScriptingChris (https://scriptingchris.tech)
Original code from https://github.com/ScriptingChris/New-ModuleProject, released under MIT-license https://github.com/ScriptingChris/New-ModuleProject/blob/main/LICENSE
Modified because I wanted some adaptations aswell as removing the dependency on the New-ModuleProject.
#>

param (
    [ValidateSet("release", "debug")]$Configuration = "debug",
    [Parameter(Mandatory=$false)][String]$NugetAPIKey,
    [Parameter(Mandatory=$false)][int]$CodeCoveragePercentTarget = 50,
    [Parameter(Mandatory=$false)][Switch]$ExportAlias
)

function Assert-Module {
    param (
        [Parameter()][String[]]$Name
    )

    foreach ($Module in $Name) {
        if (-not(Get-Module -Name $Module -ListAvailable)){
            Write-Warning "Module '$Module' is missing or out of date. Installing module now."
            Install-Module -Name $Module -Scope CurrentUser -Force
        }
    }
}

function Assert-Folder {
    param (
        [Parameter()][String[]]$Name
    )

    foreach ($Folder in $Name) {
        if(-not (Test-Path .\$Folder)){
            Write-Warning "Folder '$Folder' is missing. Creating folder now."
            New-Item -Path .\$Folder -ItemType directory
        }
    }
}

task Init {
    $Script:ModuleName = Split-Path -Path $PSScriptRoot -Leaf
    Write-Verbose -Message "Initializing Modules"
    $Modules = @("PSScriptAnalyzer","Pester","platyPS","PowerShellGet")
    Assert-Module -Name $Modules

    Write-Verbose -Message "Initializing folder structure"
    $Folders = @("Docs","Output","Output\Temp","Source","Source\Private","Source\Public","Tests")
    Assert-Folder -Name $Folders

    Write-Verbose -Message "Initializing Custom Files"

    Write-Verbose -Message "Initializing Module Manifest"
    if(-not (Test-Path ".\Source\$($ModuleName).psd1")){
        Write-Verbose -Message "Creating the Module Manifest"
        New-ModuleManifest -Path ".\Source\$($ModuleName).psd1" -ModuleVersion "0.0.1"
    }

    Write-Verbose -Message "Initializing .gitignore"
    if(-not (Test-Path ".gitignore")){
        Write-Verbose -Message "Creating .gitignore"
        $gitignore = '      Output/*
        coverage.xml
        testResults.xml'
        $gitignore | Set-Content -Path .gitignore
    }
}

task Test {
    try {
        Write-Verbose -Message "Running PSScriptAnalyzer on Public functions"
        Invoke-ScriptAnalyzer ".\Source\Public" -Recurse
        Write-Verbose -Message "Running PSScriptAnalyzer on Private functions"
        Invoke-ScriptAnalyzer ".\Source\Private" -Recurse
    }
    catch {
        throw "Couldn't run Script Analyzer"
    }

    if((Get-ChildItem .\Tests -Recurse).Count -gt 0){
        Write-Verbose -Message "Running Pester Tests"
        $files = @(Get-ChildItem .\Source -File -Recurse -Include *.ps1)
        $pesterConfiguration=New-PesterConfiguration
        $pesterConfiguration.Run.Path=".\Tests\*.ps1"
        $pesterConfiguration.TestResult.Enabled=$true
        $pesterConfiguration.TestResult.OutputFormat="NUnitXml"
        $pesterConfiguration.CodeCoverage.Enabled=$true
        $pesterConfiguration.CodeCoverage.CoveragePercentTarget=$CodeCoveragePercentTarget
        $pesterConfiguration.CodeCoverage.Path=$files 
        $Results = Invoke-Pester -Configuration:$pesterConfiguration
        if($Results.FailedCount -gt 0){
            throw "$($Results.FailedCount) Tests failed"
        }
    } else {
        Write-Warning "No tests to run"
    }
}

task Build {
    $Script:ModuleName = (Test-ModuleManifest -Path ".\Source\*.psd1").Name
    Write-Verbose $ModuleName

    $publicFunctions = Get-ChildItem -Path ".\Source\Public\*.ps1"
    $privateFunctions = Get-ChildItem -Path ".\Source\Private\*.ps1"

    if($Configuration -eq "release"){
        $OutputFolder = ".\Output\"
    } else {
        $OutputFolder = ".\Output\Temp"
    }
    if(Test-Path "$($OutputFolder)\$($ModuleName)") {
        Write-Verbose -Message "Output folder does exist, continuing build."
    } else {
        Write-Verbose -Message "Output temp folder does not exist. Creating it now"
        New-Item -Path "$($OutputFolder)\$($ModuleName)" -ItemType Directory -Force
    }

    if(!($ModuleVersion)) {
        Write-Verbose -Message "No new ModuleVersion was provided, locating existing version from psd file."
        $CurrentModuleVersion = (Test-ModuleManifest -Path ".\Source\$($ModuleName).psd1").Version
        if($Configuration -eq "release"){
            $totalFunctions = $publicFunctions.count + $privateFunctions.count
            $ModuleBuildNumber = $CurrentModuleVersion.Build + 1
            Write-Verbose -Message "Updating the Moduleversion"
            $Script:ModuleVersion = "$($CurrentModuleVersion.Major).$($totalFunctions).$($ModuleBuildNumber)"
            Write-Verbose "New ModuleVersion: $ModuleVersion"
            Update-ModuleManifest -Path ".\Source\$($ModuleName).psd1" -ModuleVersion $ModuleVersion
        } else {
            $ModuleVersion = "$($CurrentModuleVersion.Major).$($CurrentModuleVersion.Minor).$($CurrentModuleVersion.Build)"
            Write-Verbose "ModuleVersion found from psd file: $CurrentModuleVersion"
        }
    
    }

    if(Test-Path "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)"){
        Write-Warning -Message "Version: $($ModuleVersion) - folder was detected in .$($OutputFolder)\$($ModuleName). Removing old temp folder."
        Remove-Item "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)" -Recurse -Force | Out-null 
    }

    Write-Verbose -Message "Creating new module version folder: $($OutputFolder)\$($ModuleName)\$($ModuleVersion)."
    try {
        New-Item -Path "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)" -ItemType Directory | Out-null 
    }
    catch {
        throw "Failed creating the new module folder: $($OutputFolder)\$($ModuleName)\$($ModuleVersion)"
    }

    Write-Verbose -Message "Generating the Module Manifest for build and generating new Module File"
    try {
        Copy-Item -Path ".\Source\$($ModuleName).psd1" -Destination "$($OutputFolder)\$($ModuleName)\$ModuleVersion\"
        New-Item -Path "$($OutputFolder)\$($ModuleName)\$ModuleVersion\$($ModuleName).psm1" -ItemType File | Out-null 
    }
    catch {
        throw "Failed copying Module Manifest from: .\Source\$($ModuleName).psd1 to $($OutputFolder)\$($ModuleName)\$ModuleVersion\ or Generating the new psm file."
    }

    Write-Verbose -Message "Updating Module Manifest with Public Functions"
    try {
        Write-Verbose -Message "Appending Public functions to the psm file"
        $functionsToExport = New-Object -TypeName System.Collections.ArrayList
        foreach($function in $publicFunctions.Name){
            write-Verbose -Message "Exporting function: $(($function.split('.')[0]).ToString())"
            $functionsToExport.Add(($function.split('.')[0]).ToString()) | Out-null 
        }
        Update-ModuleManifest -Path "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)\$($ModuleName).psd1" -FunctionsToExport $functionsToExport
    }
    catch {
        throw "Failed updating Module manifest with public functions"
    }
    $ModuleFile = "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)\$($ModuleName).psm1"
    Write-Verbose -Message "Building the .psm1 file"
    Write-Verbose -Message "Appending Public Functions"
    Add-Content -Path $ModuleFile -Value "### --- PUBLIC FUNCTIONS --- ###"
    foreach($function in $publicFunctions.Name){
        try {
            Write-Verbose -Message "Updating the .psm1 file with function: $($function)"
            $content = Get-Content -Path ".\Source\Public\$($function)"
            Add-Content -Path $ModuleFile -Value "#Region - $function"
            Add-Content -Path $ModuleFile -Value $content
            if($ExportAlias.IsPresent){
                $AliasSwitch = $false
                $Sel = Select-String -Path ".\Source\Public\$($function)" -Pattern "CmdletBinding" -Context 0,1
                $mylist = $Sel.ToString().Split([Environment]::NewLine)
                foreach($s in $mylist){
                    if($s -match "Alias"){
                        $alias = (($s.split(":")[2]).split("(")[1]).split(")")[0]
                        Write-Verbose -Message "Exporting Alias: $($alias) to Function: $($function)"
                        Add-Content -Path $ModuleFile -Value "Export-ModuleMember -Function $(($function.split('.')[0]).ToString()) -Alias $alias"
                        $AliasSwitch = $true
                    }
                }
                if($AliasSwitch -eq $false){
                    Write-Verbose -Message "No alias was found in function: $($function))"
                    Add-Content -Path $ModuleFile -Value "Export-ModuleMember -Function $(($function.split('.')[0]).ToString())"
                }
            }
            else {
                Add-Content -Path $ModuleFile -Value "Export-ModuleMember -Function $(($function.split('.')[0]).ToString())"
            }
            Add-Content -Path $ModuleFile -Value "#EndRegion - $function"            
        }
        catch {
            throw "Failed adding content to .psm1 for function: $($function)"
        }
    }

    Write-Verbose -Message "Appending Private functions"
    Add-Content -Path $ModuleFile -Value "### --- PRIVATE FUNCTIONS --- ###"
    foreach($function in $privateFunctions.Name){
        try {
            Write-Verbose -Message "Updating the .psm1 file with function: $($function)"
            $content = Get-Content -Path ".\Source\Private\$($function)"
            Add-Content -Path $ModuleFile -Value "#Region - $function"
            Add-Content -Path $ModuleFile -Value $content
            Add-Content -Path $ModuleFile -Value "#EndRegion - $function"            
        }
        catch {
            throw "Failed adding content to .psm1 for function: $($function)"
        }
    }

    Write-Verbose -Message "Updating Module Manifest with root module"
    try {
        Write-Verbose -Message "Updating the Module Manifest"
        Update-ModuleManifest -Path "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)\$($ModuleName).psd1" -RootModule "$($ModuleName).psm1"
    }
    catch {
        Write-Warning -Message "Failed appinding the rootmodule to the Module Manifest"
    }

    Write-Verbose -Message "Compiling Help files"
    Try {
        Write-Verbose -Message "Importing the module to be able to output documentation $($OutputFolder)\$($ModuleName)\$ModuleVersion\$($ModuleName).psm1"
        Import-Module "$($OutputFolder)\$($ModuleName)\$ModuleVersion\$($ModuleName).psm1" -Force
    }
    catch {
        throw "Failed importing the module: $($ModuleName)"
    }

    if(!(Get-ChildItem -Path ".\Docs")){
        Write-Verbose -Message "Docs folder is empty, generating new files"
        if((Get-Module -Name $($ModuleName)).ExportedCommands.Count -gt 0) {
            Write-Verbose -Message "Module: $($ModuleName) is imported into session, generating Help Files"
            New-MarkdownHelp -Module $ModuleName -OutputFolder ".\Docs"
            New-MarkdownAboutHelp -OutputFolder ".\Docs" -AboutName $ModuleName
            New-ExternalHelp ".\Docs" -OutputPath "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)\en-US\"
        }
        else {
            Write-Warning "Module is not imported, cannot generate help files"
        }
    }
    else {
        Write-Verbose -Message "Removing old Help files, to generate new files."
        Remove-Item -Path ".\Docs\*.*" -Exclude "about_*"
        if((Get-Module -Name $($ModuleName)).ExportedCommands.Count -gt 0) {
            Write-Verbose -Message "Module: $($ModuleName) is imported into session, generating Help Files"
            New-MarkdownHelp -Module $ModuleName -OutputFolder ".\Docs"
            New-ExternalHelp ".\Docs" -OutputPath "$($OutputFolder)\$($ModuleName)\$($ModuleVersion)\en-US\"
        }
    }
}

task Publish -if($Configuration -eq "Release"){

    Write-Verbose -Message "Publishing Module to Modules-folder"
    Copy-Item -Path ".\Output\$($ModuleName)\$ModuleVersion\$($ModuleName).psm1" -Destination ..\ | Out-null
    Copy-Item -Path ".\Output\$($ModuleName)\$ModuleVersion\$($ModuleName).psd1" -Destination ..\ | Out-null

    if(-not [String]::IsNullOrEmpty($NugetAPIKey)){
        Write-Verbose -Message "Publishing Module to PowerShell gallery"
        Write-Verbose -Message "Importing Module .\Output\$($ModuleName)\$ModuleVersion\$($ModuleName).psm1"
        Import-Module ".\Output\$($ModuleName)\$ModuleVersion\$($ModuleName).psm1"
        If((Get-Module -Name $ModuleName) -and ($NugetAPIKey)) {
            try {
                write-Verbose -Message "Publishing Module: $($ModuleName)"
                Publish-Module -Name $ModuleName -NuGetApiKey $NugetAPIKey
            }
            catch {
                throw "Failed publishing module to PowerShell Gallery"
            }
        }
        else {
            Write-Warning -Message "Something went wrong, couldn't publish module to PSGallery. Did you provide a NugetKey?."
        }
    }
}

task Clean -if($Configuration -eq "Release") {
    if(Test-Path ".\Output\temp"){
        Write-Verbose -Message "Removing temp folders"
        Remove-Item ".\Output\temp" -Recurse -Force
    }
}

task . Init, Test, Build, Clean, Publish