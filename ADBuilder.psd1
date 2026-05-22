@{
    RootModule = 'ADBuilder.psm1'
    ModuleVersion = '0.3.3'
    GUID = 'c6b22c72-5c07-4c51-a5bc-52c5aaf4c8a1'
    Author = 'ADBuilder'
    CompanyName = 'ADBuilder'
    Copyright = '(c) ADBuilder. MIT-compatible lab scaffold.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport = @('Invoke-ADBuilder','Test-ADBuilderConfig','Get-ADBuilderSupportedProviders')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('ActiveDirectory','Lab','CTF','ADDS')
            ProjectUri = ''
        }
    }
}
