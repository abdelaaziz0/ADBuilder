[CmdletBinding()]
param()
Import-Module ActiveDirectory -ErrorAction Stop
Write-Host 'Domain:' -ForegroundColor Cyan
Get-ADDomain | Select-Object DNSRoot,NetBIOSName,DistinguishedName
Write-Host 'OUs:' -ForegroundColor Cyan
Get-ADOrganizationalUnit -Filter * | Select-Object Name,DistinguishedName | Format-Table -AutoSize
Write-Host 'Groups:' -ForegroundColor Cyan
Get-ADGroup -Filter * -SearchBase (Get-ADDomain).DistinguishedName | Where-Object {$_.Name -like 'Lab-*'} | Select-Object Name,GroupScope,DistinguishedName | Format-Table -AutoSize
Write-Host 'Users:' -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase (Get-ADDomain).DistinguishedName | Where-Object {$_.SamAccountName -eq 'alice'} | Select-Object SamAccountName,Enabled,DistinguishedName | Format-Table -AutoSize
Write-Host 'Membership:' -ForegroundColor Cyan
Get-ADGroupMember Lab-Users | Select-Object Name,SamAccountName,ObjectClass | Format-Table -AutoSize
