# PSWayforge Tests

This directory contains [Pester](https://pester.dev) tests for the PSWayforge module.

## Requirements

- PowerShell 7.3 or later
- Pester 5.0 or later (developed against Pester 6.0.0)

## Running the tests

From the repository root:

```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

To run a single test file:

```powershell
Invoke-Pester -Path ./tests/New-WayforgeProject.Tests.ps1 -Output Detailed
```

## Design notes

- Tests import the module via `PSWayforge.psd1` in the repository root.
- File-system tests use Pester's `TestDrive:` PSDrive for isolation.
- Utility tests create minimal `.workflow/` layouts directly so they do not depend on `New-WayforgeProject`.
- These tests assume the public cmdlets expose the following parameter names:
  - `New-WayforgeProject`: `-Name`, `-Path`, `-InitializeExisting`
  - `Invoke-WayforgeHook`: `-HookName`, `-ProjectPath`, `-Parameters`
  - `Test-WayforgeSchema`: `-Artifact`, `-SchemaName`, `-ProjectPath`
  - `Get-WayforgeWorkflow`: `-Name`, `-ProjectPath`

## Current state

The module implementation now exists in the repository root, so these tests import and run successfully with `Invoke-Pester`.
