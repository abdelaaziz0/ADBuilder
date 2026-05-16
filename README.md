# ADBuilder

ADBuilder builds a minimal Active Directory lab from JSON.

- AD DS promotion: `newForest`, `additionalDC`, `childDomain` paths are present, with `newForest` being the currently exercised path.
- Directory provider: sites, OUs, groups, users, computers, memberships, FGPP, simple ACL edges.
- Assertions provider: basic read-only checks.
- Reserved providers: DNS/GPO/Kerberos/ADCS are rejected if enabled.

Use **Windows PowerShell 5.1** as Administrator on Windows Server. PowerShell 7 is not supported for the apply engine.


## Fresh VM quickstart

Use this package from a fresh disposable Windows Server VM. Open an elevated Windows PowerShell 5.1 console in the project folder:

```powershell
cd C:\Users\vboxuser\AD\ADBuilder
Set-ExecutionPolicy -Scope Process Bypass -Force
.\RUN-ME.ps1
```

If the VM reboots, log back in and run the same command again:

```powershell
cd C:\Users\vboxuser\AD\ADBuilder
.\RUN-ME.ps1
```

`RUN-ME.ps1` detects the current state:

1. Fresh machine: configures static IP, DNS, generated passwords, localized Administrator, hostname.
2. After hostname reboot: validates, dry-runs, and runs Stage A AD DS promotion.
3. After promotion reboot: runs Stage B provider provisioning.
4. After completion: runs post-check.

Defaults:

```text
InterfaceAlias: Ethernet
StaticIP:       172.20.10.50
Gateway:        172.20.10.1
Pre-promotion DNS: same as Gateway
ComputerName:   DC01
Config:         .\examples\lab-newforest-m1.json
```

Override them like this:

```powershell
.\RUN-ME.ps1 -StaticIP 172.20.10.60 -Gateway 172.20.10.1 -ComputerName DC01
```

## Manual fast path on a fresh Server Core VM

From the project root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\tools\00-Prepare-ServerCore.ps1 -StaticIP 172.20.10.50 -Gateway 172.20.10.1 -ComputerName DC01
```

If you do not pass passwords, the prep script generates strong random lab passwords, sets the required machine environment variables, and writes them once to:

```text
state\generated-secrets.txt
```

The file ACL is restricted to Administrators and SYSTEM. Keep that file private and delete it after the lab is built. If the script renames the machine, it restarts. After reboot, return to the project folder, check `state\generated-secrets.txt`, take a VM snapshot, then run:

```powershell
.\tools\01-Run-StageA.ps1
```

If Stage A succeeds, reboot:

```powershell
Restart-Computer -Force
```

After reboot, run Stage B:

```powershell
cd C:\Users\vboxuser\AD\ADBuilder
.\tools\02-Run-StageB.ps1
```

Then verify:

```powershell
.\tools\03-PostCheck.ps1
```

## Manual path

Set your own non-public passwords:

```powershell
$env:ADBUILDER_DSRM_PASSWORD = '<your strong DSRM password>'
$env:ADBUILDER_DEFAULT_USER_PASSWORD = '<your strong default lab user password>'

.\Validate-ADBuilderConfig.ps1 -ConfigPath .\examples\lab-newforest-m1.json -PrintResolvedPlan -AllowReducedValidation -NonInteractive
.\Build-ADDomain.ps1 -ConfigPath .\examples\lab-newforest-m1.json -DryRun -AllowReducedValidation -NonInteractive
.\Build-ADDomain.ps1 -ConfigPath .\examples\lab-newforest-m1.json -AllowReducedValidation -NonInteractive
```

After AD DS promotion completes, reboot and run:

```powershell
.\Build-ADDomain.ps1 -ConfigPath .\examples\lab-newforest-m1.json -Resume -AllowReducedValidation -NonInteractive
```

## Canonical validation

The project supports canonical JSON Schema validation through vendored NJsonSchema DLLs placed under:

```text
third_party/NJsonSchema/
```

Without those DLLs, apply is blocked unless `-AllowReducedValidation` is supplied. The included helper scripts use reduced validation because the DLLs are not bundled in this package.

## Safety

Only run this on disposable lab VMs and take a snapshot before Stage A. Provider-local ACLs with `labUnsafe: true` require `-LabUnsafe`.
