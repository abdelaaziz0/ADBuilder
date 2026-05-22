function Get-ADBuilderAssertionsProvider {
    return [pscustomobject]@{
        Name = 'assertions'
        Requires = @('directory.principalsReady')
        Provides = @('assertions.complete')
        Phases = @(@{ Name='RunAssertions'; Function='Invoke-ADBuilderAssertions' })
    }
}

function Get-ADBuilderRequiredAssertionField {
    param($Assertion,[string]$Field,[string]$Type)
    $value = Get-ADBuilderProperty $Assertion $Field $null
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        throw "Assertion of type '$Type' requires a non-empty '$Field' field."
    }
    return [string]$value
}

function Invoke-ADBuilderAssertions {
    param($Context)
    if ($null -eq $Context.Config.assertions) { return }
    $beforeFailures = Get-ADBuilderAssertionFailureCount
    foreach ($a in @($Context.Config.assertions)) {
        $type = [string]$a.type
        if ($Context.DryRun) { Write-ADBuilderLog -Level DryRun -Message "Would run assertion: $type"; continue }
        try {
            switch ($type) {
                'userExists' { Get-ADUser -Identity (Get-ADBuilderRequiredAssertionField $a 'identity' $type) -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'groupExists' { Get-ADGroup -Identity (Get-ADBuilderRequiredAssertionField $a 'identity' $type) -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'computerExists' { Get-ADComputer -Identity (Get-ADBuilderRequiredAssertionField $a 'identity' $type) -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'ouExists' { Get-ADOrganizationalUnit -Identity (Get-ADBuilderRequiredAssertionField $a 'identity' $type) -ErrorAction Stop | Out-Null; Add-ADBuilderSummary -Bucket 'assertions' -Action AssertPassed }
                'memberOf' {
                    $group = Get-ADBuilderRequiredAssertionField $a 'group' $type
                    $principal = Get-ADBuilderRequiredAssertionField $a 'principal' $type
                    $recursive = [bool](Get-ADBuilderProperty $a 'recursive' $false)
                    $found = Get-ADGroupMember -Identity $group -Recursive:$recursive -ErrorAction Stop | Where-Object { $_.SamAccountName -eq $principal -or $_.Name -eq $principal }
                    if (-not $found) { throw "Principal '$principal' is not member of '$group'" }
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
    $afterFailures = Get-ADBuilderAssertionFailureCount
    if ($afterFailures -gt $beforeFailures) {
        throw "Assertions completed with $($afterFailures - $beforeFailures) failure(s)."
    }
}
