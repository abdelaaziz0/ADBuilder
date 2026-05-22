# ADBuilder

ADBuilder turns a JSON file into a working Active Directory lab on a fresh
Windows Server virtual machine. You give it a disposable VM; it configures the
network, promotes the machine to a domain controller, then creates the OUs,
groups, users, computers, password policies and ACLs described in the JSON.

It is built for **throwaway labs** (CTF practice, AD security training, tooling
tests) on **Windows Server Core 2019 / 2022 / 2025**. It is not production
software and makes no attempt to be (see [Safety](#safety)).

---

## TL;DR  just run it

On a fresh, disposable Windows Server VM, open an **elevated Windows PowerShell**
window (see [Requirements](#requirements)  this must be PowerShell 5.1, "Run as
Administrator"), go to the folder where you put ADBuilder, and run:

```powershell
cd C:\ADBuilder
Set-ExecutionPolicy -Scope Process Bypass -Force
.\RUN-ME.ps1 -StaticIP 10.0.0.10 -PrefixLength 24 -Gateway 10.0.0.1
```

Replace the IP, prefix and gateway with values that match the VM's network.
The VM will reboot one or two times. **After each reboot, log back in and run
the same command again:**

```powershell
cd C:\ADBuilder
.\RUN-ME.ps1
```

When it prints `[RUN-ME] Done.` your lab is built. That is the whole workflow.
Everything below explains what happens, how to change it, and what to do when
something goes wrong.

---

## Requirements

| Requirement | Why |
|---|---|
| A **disposable** Windows Server VM (Core 2019/2022/2025) | ADBuilder promotes it to a domain controller  that is irreversible in practice. Never run it on a machine you care about. |
| **Windows PowerShell 5.1**, run **as Administrator** | The apply engine refuses to run on PowerShell 7 and refuses to run without admin rights. On Server Core the default `powershell.exe` *is* 5.1. |
| Network details you can reach: a free **static IP**, **prefix length**, **gateway** | The VM needs a fixed address before it becomes a DC. |
| A way to take a **VM snapshot** | So you can roll back instantly if anything goes wrong. |

You do **not** need to install anything else. You do **not** need to pre-create
passwords  ADBuilder generates strong random ones for you.

> If you only have PowerShell 7 open, start the right shell with:
> `powershell.exe` (that launches Windows PowerShell 5.1).

---

## The simple path: `RUN-ME.ps1`

`RUN-ME.ps1` is a single entry point. You run the **same command every time**;
it looks at where the build got to and does the next step automatically.

### Step by step

1. **First run**:  ADBuilder prepares the VM: sets the static IP and DNS,
   generates lab passwords, enables the built-in Administrator, and renames the
   computer (default name `DC01`). Renaming requires a reboot, so the VM
   restarts.
2. **Second run**: (after the reboot)  ADBuilder runs a quick self-test, then
   **Stage A**: it validates your JSON, does a dry run, and promotes the VM to a
   domain controller. Promotion requires a reboot, so the VM restarts again.
3. **Third run**: (after that reboot)  ADBuilder runs **Stage B**: it creates
   everything in the JSON (OUs, groups, users, computers, password policies,
   ACLs) and then prints a post-check summary of what now exists.

After step 3 you will see `[RUN-ME] Done.`  the lab is ready.

If you run `RUN-ME.ps1` again after that, it just re-prints the post-check; it
will not rebuild anything.

> **Tip:** take a VM snapshot right after step 1, before promotion. If a later
> step misbehaves, you can restore the snapshot and start clean.

### Defaults

If you pass nothing, these values are used:

```text
InterfaceAlias    : Ethernet
StaticIP          : 172.20.10.50
PrefixLength      : 24
Gateway           : 172.20.10.1
Pre-promotion DNS : same as Gateway
ComputerName      : DC01
Config            : .\examples\reference.json
```

The default IP range will almost certainly **not** match your network  set
`-StaticIP`, `-PrefixLength` and `-Gateway` to real values for your VM.

### Options you can pass to `RUN-ME.ps1`

| Switch / parameter | Effect |
|---|---|
| `-StaticIP <ip>` | Static IPv4 address to assign to the VM. |
| `-PrefixLength <n>` | Subnet prefix length (e.g. `24` for `255.255.255.0`). |
| `-Gateway <ip>` | Default gateway. |
| `-PrePromotionDns <ip>` | DNS server to use *before* promotion. Defaults to the gateway. |
| `-InterfaceAlias <name>` | Name of the network adapter to configure (see troubleshooting). |
| `-ComputerName <name>` | Hostname to give the VM. Default `DC01`. |
| `-ConfigPath <path>` | Which JSON lab to build. Default `examples\reference.json`. |
| `-NoAutoReboot` | Do not reboot automatically  ADBuilder tells you when to reboot by hand. |
| `-ResetState` | Discard saved progress and start the build from scratch. |
| `-SkipDryRun` | Skip the Stage A dry run (faster, less safe). |
| `-SkipNegativeTest` | Skip the built-in self-test. |
| `-IgnoreDrift` | Continue Stage B even if the JSON changed since Stage A. |
| `-NoReducedValidation` | Require full canonical schema validation (see [Canonical validation](#canonical-validation)). |

Example with overrides:

```powershell
.\RUN-ME.ps1 -InterfaceAlias 'Ethernet 2' -StaticIP 10.0.0.10 -PrefixLength 24 -Gateway 10.0.0.1 -ComputerName LAB-DC01
```

---

## What you get

Building the bundled `examples\reference.json` produces a new forest:

- Domain `reference.lab` (NetBIOS `REFERENCE`).
- An OU tree: `Lab` containing `Users`, `Admins`, `Groups`, `Computers` (with `Servers` and `Workstations` sub-OUs), `Service Accounts`, and `Sensitive`; plus a top-level `Staging` OU.
- Six groups: `Ref-Users`, `Ref-Helpdesk`, `Ref-Privileged-Delegates`, `Ref-Servers`, `Ref-App-Readers`, `Ref-ACL-Readers`.
- Users `alice` and `bob.helpdesk` (enabled) plus a `disabled.template` account example.
- Computer objects `WEB01` and `DB01` (servers), `WS01` (workstation, disabled).
- Two fine-grained password policies (`Ref-Users-FGPP` and `Ref-Alice-FGPP`).
- A helpdesk delegation (read/write on the Users OU) and a read-only ACL edge on the Sensitive OU.
- AD sites `HQ` and `BRANCH` linked by `HQ-BRANCH`.
- Assertions verifying existence and group membership.

To build a different lab, point `-ConfigPath` at your own JSON. See the
`examples\` folder for templates and `docs\ADBUILDER_LIMITATIONS.md` for the
fields the runtime actually supports.

---

## Lab passwords

You do not type any passwords. During the first run, ADBuilder generates strong
random passwords for the DSRM (Directory Services Restore Mode) account and for
the default lab user, and writes them **once**, in clear text, to:

```text
state\generated-secrets.txt
```

That file's permissions are restricted to Administrators and SYSTEM. **Read it,
note the passwords, and delete it when the lab is built.** The same values are
also stored as machine environment variables  see
[Lab secret exposure](#lab-secret-exposure) before you share or snapshot the VM.

---

## Troubleshooting

ADBuilder tries to fail early with a clear message instead of leaving the VM in
a half-built state. Here are the problems you are most likely to hit.

### "Run this script as Administrator."
You started PowerShell as a normal user. Close it, right-click Windows
PowerShell, choose **Run as administrator**, and start again.

### The script will not start at all / "running scripts is disabled"
Windows is blocking the script via its execution policy. Run this once in the
window, then start ADBuilder again:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
```

Or launch it directly without changing any policy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RUN-ME.ps1
```

### "Windows PowerShell 5.1 is required" / "Run from Windows PowerShell, not PowerShell 7"
You are in PowerShell 7 (`pwsh`). ADBuilder's apply engine only runs on Windows
PowerShell 5.1. Start the right shell by running `powershell.exe` and try again.

### "Network adapter '<name>' not found. Available adapters: ..."
The adapter name you passed (or the default `Ethernet`) does not exist on this
VM. ADBuilder lists the real adapter names in the error. Hyper-V, VirtualBox and
VMware often name them `Ethernet`, `Ethernet 2`, `Ethernet0`, etc. Check with:

```powershell
Get-NetAdapter | Select-Object Name, Status
```

then re-run with the correct name, e.g. `-InterfaceAlias 'Ethernet 2'`.

### "netsh failed to set the static IPv4 address ..."
The adapter exists but the address could not be applied  usually the IP,
prefix or gateway is invalid or conflicts with another device. ADBuilder stops
**before** renaming or rebooting the VM, so nothing is half-done. Fix the
`-StaticIP` / `-PrefixLength` / `-Gateway` values and run again.

### The VM has no network after a reboot
Almost always a wrong IP/gateway/DNS. Restore your pre-Stage-A snapshot (or fix
the address by hand on the console), then run `RUN-ME.ps1` again with correct
network values.

### "Missing ADBuilder machine secrets"
The generated passwords are not in the environment  usually because the
preparation step did not complete. Re-run the preparation tool:

```powershell
.\tools\00-Prepare-ServerCore.ps1 -StaticIP <ip> -PrefixLength <n> -Gateway <ip>
```

### "Existing incomplete state found ... Use -Resume or remove the state file"
A previous build was interrupted. To **continue** it, just run `RUN-ME.ps1`
again (it resumes automatically). To **start over** from scratch:

```powershell
.\RUN-ME.ps1 -ResetState
```

### "Config drift detected"
You edited the JSON after Stage A already ran. Either revert the JSON to what it
was when Stage A ran, or  if the change is intentional  continue with:

```powershell
.\RUN-ME.ps1 -IgnoreDrift
```

### "State is already Complete"
The lab is already built. `RUN-ME.ps1` will just re-print the post-check. To
build it again, start from a fresh VM snapshot, or use `-ResetState` (note:
`-ResetState` only resets ADBuilder's progress tracking  it does **not** undo
the domain that already exists).

### Warning: "schema validation is reduced ... not for production/CI"
This is expected. The canonical JSON Schema validator (NJsonSchema) is not
bundled. ADBuilder still does its own semantic checks; the warning just says the
strict schema pass was skipped. For a throwaway lab this is fine. See
[Canonical validation](#canonical-validation) to enable the strict pass.

### "Stage A ran, but AD is not ready"
The domain controller has not finished coming up in this boot. Let ADBuilder
reboot the VM (or reboot it yourself with `Restart-Computer -Force`), log back
in, and run `RUN-ME.ps1` again.

### A user, group or assertion failed during Stage B
Stage B reports each failure and stops short of `Complete`. Read the log under
`logs\`, fix the JSON (or the underlying cause), then run `RUN-ME.ps1` again —
it resumes and only re-runs the parts that did not finish. A failed **assertion**
deliberately keeps the run from reporting success; see
`docs\ADBUILDER_LIMITATIONS.md`.

---

## Manual / advanced paths

`RUN-ME.ps1` simply orchestrates the numbered tools. You can run them yourself.

### Manual fast path on a fresh Server Core VM

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\tools\00-Prepare-ServerCore.ps1 -StaticIP 10.0.0.10 -PrefixLength 24 -Gateway 10.0.0.1 -ComputerName DC01
```

If you do not pass passwords, the prep tool generates strong random ones, sets
the machine environment variables, and writes them once to
`state\generated-secrets.txt` (ACL restricted to Administrators and SYSTEM).
If it renames the machine it reboots. After the reboot, return to the project
folder, note the secrets, take a VM snapshot, then run Stage A:

```powershell
.\tools\01-Run-StageA.ps1
```

If Stage A succeeds, reboot, then run Stage B and the post-check:

```powershell
Restart-Computer -Force
# after reboot:
.\tools\02-Run-StageB.ps1
.\tools\03-PostCheck.ps1
```

### Engine directly

Set your own passwords and drive the engine yourself:

```powershell
$env:ADBUILDER_DSRM_PASSWORD = '<your strong DSRM password>'
$env:ADBUILDER_DEFAULT_USER_PASSWORD = '<your strong default lab user password>'

.\Validate-ADBuilderConfig.ps1 -ConfigPath .\examples\reference.json -PrintResolvedPlan -UnsafeReducedValidation -NonInteractive
.\Build-ADDomain.ps1 -ConfigPath .\examples\reference.json -DryRun -UnsafeReducedValidation -NonInteractive
.\Build-ADDomain.ps1 -ConfigPath .\examples\reference.json -UnsafeReducedValidation -NonInteractive
```

After AD DS promotion completes, reboot and resume:

```powershell
.\Build-ADDomain.ps1 -ConfigPath .\examples\reference.json -Resume -UnsafeReducedValidation -NonInteractive
```

---

## Canonical validation

ADBuilder can validate your JSON against the formal schema using vendored
NJsonSchema DLLs placed under:

```text
third_party/NJsonSchema/
```

Without those DLLs, the apply engine is blocked unless you pass
`-UnsafeReducedValidation` (which `RUN-ME.ps1` does by default). Reduced
validation prints a high-visibility warning because the strict schema pass is
skipped  fine for a disposable lab, not for CI. Pass `-NoReducedValidation` to
`RUN-ME.ps1` to require the strict pass instead. The older
`-AllowReducedValidation` switch still works as a deprecated alias.

---

## Safety

Only run ADBuilder on disposable lab VMs, and take a snapshot before Stage A.
Dangerous ACL rights require `labUnsafe: true` in the JSON **and** the
CLI-level `-LabUnsafe` switch at validation/apply time.

### Lab secret exposure

`tools\00-Prepare-ServerCore.ps1` stores `ADBUILDER_DSRM_PASSWORD` and
`ADBUILDER_DEFAULT_USER_PASSWORD` in cleartext, in two places: as machine-scoped
environment variables under `HKLM` (readable by any local administrator and
persisted in the registry hive) and in `state\generated-secrets.txt`. Neither is
encrypted. Any VM snapshot, disk image, or exported appliance that is shared,
uploaded, or kept after the lab leaks these passwords. Treat the whole VM as the
secret: use these values only for disposable labs, never reuse them anywhere
else, and destroy the VM (or at minimum delete `state\generated-secrets.txt` and
clear both machine environment variables) once the lab is done.

---

## Project layout

| Path | What it is |
|---|---|
| `RUN-ME.ps1` | One-command entry point; orchestrates everything below. |
| `tools\00-Prepare-ServerCore.ps1` | Network, hostname, passwords on a fresh VM. |
| `tools\01-Run-StageA.ps1` | Validate, dry run, promote to domain controller. |
| `tools\02-Run-StageB.ps1` | Create OUs, groups, users, computers, policies, ACLs. |
| `tools\03-PostCheck.ps1` | Print what now exists in the directory. |
| `tools\04-Test-NegativeModeBlock.ps1` | Built-in self-test of config validation. |
| `Build-ADDomain.ps1` | The apply engine (called by the tools). |
| `Validate-ADBuilderConfig.ps1` | Config validation only, no changes. |
| `examples\` | Sample lab JSON files. |
| `schemas\` | JSON Schema for the config format. |
| `docs\ADBUILDER_LIMITATIONS.md` | Which JSON fields the runtime supports / rejects. |
| `state\` | Saved build progress and `generated-secrets.txt` (git-ignored). |
| `logs\` | Per-run transcripts (git-ignored). |
| `CHANGELOG.md` | Release history. |

`AD DS promotion` supports `newForest`, `additionalDC` and `childDomain`;
`newForest` is the exercised path. The directory provider handles sites, OUs,
groups, users, computers, memberships, fine-grained password policies and simple
ACL edges. The assertions provider does read-only existence/membership checks.
DNS/GPO/Kerberos/ADCS are reserved and rejected if enabled.

---

## Running the tests

The Pester suite (`tests\`) is unit-level and does not need Active Directory; it
runs on Linux or Windows. It **requires Pester 5+**  the Pester 3.4 bundled with
Windows PowerShell 5.1 will not run it:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force
Invoke-Pester .\tests
```
