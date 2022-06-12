### --- PUBLIC FUNCTIONS --- ###
#Region - Get-DWIPAddress.ps1
function Get-DWIPAddress{
    return (Get-NetIPAddress | Select-Object IPAddress)
}
Export-ModuleMember -Function Get-DWIPAddress
#EndRegion - Get-DWIPAddress.ps1
### --- PRIVATE FUNCTIONS --- ###
