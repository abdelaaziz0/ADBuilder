function Get-ADBuilderAssertionsProvider {
    return [pscustomobject]@{
        Name = 'assertions'
        Requires = @('directory.principalsReady')
        Provides = @('assertions.complete')
        Phases = @(@{ Name='RunAssertions'; Function='Invoke-ADBuilderAssertions' })
    }
}

function Invoke-ADBuilderAssertions {
    param($Context)
    if ($null -eq $Context.Config.assertions) { return }
    foreach ($a in @($Context.Config.assertions)) {
        $type = [string]$a.type
        if ($Context.DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would run assertion: $type"; continue }
        try {
            switch ($type) {
                'userExists' { Get-ADUser -Identity $a.identity -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'groupExists' { Get-ADGroup -Identity $a.identity -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'computerExists' { Get-ADComputer -Identity $a.identity -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'ouExists' { Get-ADOrganizationalUnit -Identity $a.identity -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'memberOf' {
                    $found = Get-ADGroupMember -Identity $a.group -Recursive:([bool](Get-ADBuilderProperty $a 'recursive' $false)) -ErrorAction Stop | Where-Object { $_.SamAccountName -eq $a.principal -or $_.Name -eq $a.principal }
                    if (-not $found) { throw "Principal '$($a.principal)' is not member of '$($a.group)'" }
                    Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed
                }
                default { throw "Unsupported assertion type in M1: $type" }
            }
            Write-ADBuilderLog -Level Success -Message "Assertion passed: $type"
        } catch {
            Write-ADBuilderLog -Level Error -Message "Assertion failed '$type': $($_.Exception.Message)"
            Add-ADBuilderSummary -Bucket 'assertions' -Action AssertFailed
        }
    }
}
