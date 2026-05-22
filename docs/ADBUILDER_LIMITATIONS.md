# ADBuilder Runtime Field Support

This document lists the important M1 runtime boundaries. If a field is accepted by the JSON schema but the runtime cannot apply it honestly, semantic validation rejects it before any provider action.

## Implemented Directory Fields

- `providers.directory.ous`: recursive OU creation.
- `providers.directory.groups`: group creation plus `members` and `memberOf` membership intent.
- `providers.directory.users`: basic user creation and attributes: `samAccountName`, names, UPN, enabled state, password, title, department, password-never-expires, change-password-at-logon, and `groups`.
- `providers.directory.computers`: basic computer creation.
- `providers.directory.fineGrainedPasswordPolicies`: FGPP creation/update and `appliesTo`.
- `providers.directory.aclEdges` and `delegations`: simple broad ACEs only, using trustee, target/OU, rights, and Allow access.
- `assertions`: existence checks and `memberOf`, including recursive membership when requested.

## Explicitly Rejected Fields

These are rejected because silently ignoring them would create a different lab than the JSON describes:

- `providers.directory.users[].spns` when non-empty.
- `providers.directory.users[].accountControlFlags` when non-empty.
- `providers.directory.aclEdges[].objectType` when non-empty.
- `providers.directory.aclEdges[].inheritedObjectType` when non-empty.
- `providers.directory.aclEdges[].inheritance` when set to anything other than the current default `None`.
- `providers.directory.aclEdges[].accessType` when set to anything other than the current default `Allow`.
- `providers.directory.aclEdges[].appliesTo` when non-empty.
- `providers.directory.delegations[].inheritance` when set to anything other than `None`.
- `providers.directory.delegations[].accessType` when set to anything other than `Allow`.
- `providers.directory.delegations[].appliesTo` when non-empty.

## Unsafe ACL Requirements

The following rights require `labUnsafe: true` on the ACL edge and also require the CLI-level `-LabUnsafe` switch:

`GenericAll`, `GenericWrite`, `WriteDacl`, `WriteOwner`, `CreateChild`, `DeleteChild`, `ExtendedRight`, `WriteProperty`.

This makes dangerous lab intent explicit in both the config and the command line.

## Reduced Validation

Canonical validation requires pinned NJsonSchema DLLs under `third_party/NJsonSchema`. If those DLLs are absent, ADBuilder fails unless `-UnsafeReducedValidation` is passed. Reduced validation prints a warning containing `schema validation is reduced` and `not for production/CI`.

`-AllowReducedValidation` still works as a deprecated compatibility switch, but new scripts should use `-UnsafeReducedValidation`.

## Assertions and Stage B Completion

Assertions are verification checks, not provisioning steps. ADBuilder treats a failed assertion as a hard failure of the assertions provider:

- Each failed assertion is recorded, then `Invoke-ADBuilderAssertions` throws once all assertions in the config have run (so every failure is reported, not just the first).
- Because the phase raised failures it is not checkpointed, the assertions provider is marked failed, and Stage B stays in the `Failed` state instead of reaching `Complete`. `Build-ADDomain.ps1` exits non-zero.

This is intentional: a lab whose assertions do not hold is not the lab the JSON describes, so the run is not allowed to report success. To re-run after fixing the cause, resume Stage B — already-completed providers are skipped and only the assertions phase re-executes.

Assertions that omit a field they require (`identity` for the `userExists`/`groupExists`/`computerExists`/`ouExists` checks, `group` and `principal` for `memberOf`) now fail with an explicit message instead of a `Set-StrictMode` error.
