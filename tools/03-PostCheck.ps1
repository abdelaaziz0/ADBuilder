[CmdletBinding()]
param()
Import-Module ActiveDirectory -ErrorAction Stop
Write-Host 'Domain:' -ForegroundColor Cyan
Get-ADDomain | Select-Object DNSRoot,NetBIOSName,DistinguishedName
Write-Host 'OUs:' -ForegroundColor Cyan
Get-ADOrganizationalUnit -Filter * | Select-Object Name,DistinguishedName | Format-Table -AutoSize
Write-Host 'Groups:' -ForegroundColor Cyan
Get-ADGroup -Filter * | Select-Object Name,GroupScope,GroupCategory,DistinguishedName | Format-Table -AutoSize
Write-Host 'Users:' -ForegroundColor Cyan
Get-ADUser -Filter * | Select-Object SamAccountName,Enabled,DistinguishedName | Format-Table -AutoSize
Write-Host 'Computers:' -ForegroundColor Cyan
Get-ADComputer -Filter * | Select-Object Name,Enabled,DistinguishedName | Format-Table -AutoSize
