function Resolve-ADBuilderSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $SecretSpec,
        [Parameter(Mandatory=$true)] [string] $FieldPath,
        [switch] $NonInteractive
    )

    if ($null -eq $SecretSpec) {
        if ($NonInteractive) { throw "Secret '$FieldPath' would prompt but -NonInteractive is set." }
        Write-ADBuilderLog -Level Warning -Message "Prompting for missing secret: $FieldPath"
        return Read-Host -Prompt $FieldPath -AsSecureString
    }

    if ($SecretSpec -is [string]) {
        Write-ADBuilderLog -Level Warning -Message "Plaintext secret used at $FieldPath. Value will not be logged."
        return ConvertTo-SecureString $SecretSpec -AsPlainText -Force
    }

    $source = [string]$SecretSpec.source
    switch ($source) {
        'value' {
            Write-ADBuilderLog -Level Warning -Message "Plaintext secret used at $FieldPath. Value will not be logged."
            return ConvertTo-SecureString ([string]$SecretSpec.value) -AsPlainText -Force
        }
        'env' {
            $name = [string]$SecretSpec.name
            if ([string]::IsNullOrWhiteSpace($name)) { throw "Secret '$FieldPath' has source=env but no name." }
            $value = [Environment]::GetEnvironmentVariable($name)
            if ([string]::IsNullOrEmpty($value)) { throw "Environment variable for secret '$FieldPath' is missing: $name" }
            return ConvertTo-SecureString $value -AsPlainText -Force
        }
        'prompt' {
            if ($NonInteractive) { throw "Secret '$FieldPath' would prompt but -NonInteractive is set." }
            return Read-Host -Prompt $FieldPath -AsSecureString
        }
        'secretManagement' {
            $name = [string]$SecretSpec.name
            $vault = [string]$SecretSpec.vault
            if (!(Get-Command Get-Secret -ErrorAction SilentlyContinue)) { throw "SecretManagement requested for '$FieldPath' but Get-Secret is not available." }
            if ([string]::IsNullOrWhiteSpace($vault)) { return Get-Secret -Name $name -AsPlainText:$false }
            return Get-Secret -Name $name -Vault $vault -AsPlainText:$false
        }
        default { throw "Unsupported secret source '$source' at $FieldPath" }
    }
}

function New-ADBuilderCredential {
    param($CredentialSpec,[string]$FieldPath,[switch]$NonInteractive)
    if ($null -eq $CredentialSpec -or [string]::IsNullOrWhiteSpace([string]$CredentialSpec.username)) {
        throw "Credential username missing at $FieldPath"
    }
    $sec = Resolve-ADBuilderSecret -SecretSpec $CredentialSpec.password -FieldPath "$FieldPath.password" -NonInteractive:$NonInteractive
    return New-Object System.Management.Automation.PSCredential ([string]$CredentialSpec.username, $sec)
}
