function Resolve-ADBuilderProviderOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable] $Providers,
        [string[]] $EnabledProviderNames,
        [string[]] $InitialCapabilities = @('domain.ready')
    )

    $enabled = @{}
    foreach ($name in @($EnabledProviderNames)) {
        if (-not $Providers.ContainsKey($name)) { throw "Provider '$name' is enabled but not registered." }
        $enabled[$name] = $Providers[$name]
    }

    $providedBy = @{}
    foreach ($cap in @($InitialCapabilities)) { $providedBy[$cap] = '__initial__' }

    foreach ($name in @($enabled.Keys)) {
        foreach ($cap in @($enabled[$name].Provides)) {
            if ($providedBy.ContainsKey($cap)) { throw "Capability '$cap' is provided by multiple sources: $($providedBy[$cap]) and $name" }
            $providedBy[$cap] = $name
        }
    }

    $edges = @{}
    $incoming = @{}
    foreach ($name in @($enabled.Keys)) {
        $edges[$name] = New-Object System.Collections.ArrayList
        $incoming[$name] = 0
    }

    foreach ($name in @($enabled.Keys)) {
        foreach ($req in @($enabled[$name].Requires)) {
            if (-not $providedBy.ContainsKey($req)) { throw "Provider '$name' requires missing capability '$req'." }
            $src = $providedBy[$req]
            if ($src -ne '__initial__' -and $src -ne $name) {
                if (-not ($edges[$src] -contains $name)) {
                    [void]$edges[$src].Add([string]$name)
                    $incoming[$name] = [int]$incoming[$name] + 1
                }
            }
        }
    }

    $ready = New-Object System.Collections.ArrayList
    foreach ($name in @($enabled.Keys | Sort-Object)) {
        if ([int]$incoming[$name] -eq 0) { [void]$ready.Add([string]$name) }
    }

    $order = New-Object System.Collections.ArrayList
    while ($ready.Count -gt 0) {
        $sortedReady = @($ready | Sort-Object)
        $ready = New-Object System.Collections.ArrayList
        foreach ($item in $sortedReady) { [void]$ready.Add([string]$item) }

        $n = [string]$ready[0]
        $ready.RemoveAt(0)
        [void]$order.Add($n)

        foreach ($m in @($edges[$n] | Sort-Object)) {
            $incoming[$m] = [int]$incoming[$m] - 1
            if ([int]$incoming[$m] -eq 0) { [void]$ready.Add([string]$m) }
        }
    }

    if ($order.Count -ne $enabled.Keys.Count) {
        $remaining = @()
        foreach ($name in @($enabled.Keys)) { if (-not ($order -contains $name)) { $remaining += $name } }
        throw "Provider dependency cycle detected or unresolved dependency among: $($remaining -join ', ')"
    }

    return @($order | ForEach-Object { [string]$_ })
}
