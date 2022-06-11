function Get-DWIPAddress{
    return (Get-NetIPAddress | Select-Object IPAddress)
}