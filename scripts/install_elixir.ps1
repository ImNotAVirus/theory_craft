<#
.SYNOPSIS
  Installs Elixir on Windows and ensures the `mix` executable is available in PATH.

.DESCRIPTION
  Attempts to install Elixir using winget (preferred) or Chocolatey.
  After installation, locates `mix` and updates the current session PATH and,
  by default, the user PATH so future shells can use `mix` without extra setup.

.PARAMETER Force
  Forces reinstallation even if `mix` already exists.

.PARAMETER NoPersist
  Prevents persisting PATH changes to the user environment (current session only).

.EXAMPLE
  ./install_elixir.ps1

.EXAMPLE
  ./install_elixir.ps1 -Force -NoPersist
#>
[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$NoPersist
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Command {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Ensure-ElixirInstalled {
  param(
    [switch]$ForceInstall
  )

  if (-not $ForceInstall -and (Test-Command -Name 'mix')) {
    Write-Host "Elixir (mix) already available. Skipping installation."
    return
  }

  $installSucceeded = $false

  if (Test-Command -Name 'winget') {
    Write-Host "Installing Elixir via winget..."
    & winget install --id Elixir.Elixir -e --source winget --accept-package-agreements --accept-source-agreements

    if ($LASTEXITCODE -eq 0) {
      $installSucceeded = $true
    } else {
      Write-Warning "winget could not install Elixir (exit code $LASTEXITCODE)."
    }
  }

  if (-not $installSucceeded -and (Test-Command -Name 'choco')) {
    Write-Host "Installing Elixir via Chocolatey..."
    & choco install elixir -y

    if ($LASTEXITCODE -eq 0) {
      $installSucceeded = $true
    } else {
      Write-Warning "Chocolatey could not install Elixir (exit code $LASTEXITCODE)."
    }
  }

  if (-not $installSucceeded) {
    $message = "Unable to install Elixir automatically. Install manually from https://elixir-lang.org/install.html (ensure Erlang is installed) or install a package manager (winget/choco)."
    throw $message
  }
}

function Find-MixPath {
  $candidate = Get-Command -Name 'mix' -ErrorAction SilentlyContinue

  if ($candidate) {
    return (Split-Path -Path $candidate.Source -Parent)
  }

  $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
  $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  $localAppData = [Environment]::GetEnvironmentVariable('LocalAppData')
  $chocolateyInstall = [Environment]::GetEnvironmentVariable('ChocolateyInstall')

  $searchRoots = @()

  if ($programFiles) {
    $candidateDir = Join-Path -Path $programFiles -ChildPath 'Elixir\bin'
    if (Test-Path $candidateDir) {
      $searchRoots += $candidateDir
    }
  }

  if ($localAppData) {
    $candidateDir = Join-Path -Path $localAppData -ChildPath 'Programs\Elixir\bin'
    if (Test-Path $candidateDir) {
      $searchRoots += $candidateDir
    }
  }

  if ($programFilesX86) {
    $candidateDir = Join-Path -Path $programFilesX86 -ChildPath 'Elixir\bin'
    if (Test-Path $candidateDir) {
      $searchRoots += $candidateDir
    }
  }

  if ($chocolateyInstall) {
    $candidateDir = Join-Path -Path $chocolateyInstall -ChildPath 'lib\elixir\tools\bin'
    if (Test-Path $candidateDir) {
      $searchRoots += $candidateDir
    }
  }

  foreach ($root in $searchRoots) {
    $mixPath = Join-Path -Path $root -ChildPath 'mix.bat'
    if (Test-Path $mixPath) {
      return $root
    }
  }

  $rootsToScan = @()
  if ($programFiles -and (Test-Path $programFiles)) {
    $rootsToScan += $programFiles
  }
  if ($programFilesX86 -and (Test-Path $programFilesX86)) {
    $rootsToScan += $programFilesX86
  }
  if ($localAppData) {
    $programsDir = Join-Path -Path $localAppData -ChildPath 'Programs'
    if (Test-Path $programsDir) {
      $rootsToScan += $programsDir
    }
  }
  if ($chocolateyInstall) {
    $chocoLibDir = Join-Path -Path $chocolateyInstall -ChildPath 'lib'
    if (Test-Path $chocoLibDir) {
      $rootsToScan += $chocoLibDir
    }
  }

  foreach ($root in $rootsToScan) {
    try {
      $mixFile = Get-ChildItem -Path $root -Filter 'mix.bat' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

      if ($mixFile) {
        return $mixFile.DirectoryName
      }
    } catch {
      continue
    }
  }

  return $null
}

function Add-ToPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Directory,
    [switch]$Persist
  )

  $currentSegments = ($env:PATH -split ';') | Where-Object { $_ }
  if ($currentSegments -notcontains $Directory) {
    $env:PATH = "$Directory;$env:PATH"
    Write-Host "Added '$Directory' to current session PATH."
  } else {
    Write-Host "'$Directory' already present in current session PATH."
  }

  if ($Persist) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userSegments = if ([string]::IsNullOrEmpty($userPath)) { @() } else { $userPath -split ';' }

    if ($userSegments -notcontains $Directory) {
      $newPath = if ($userPath) { "$Directory;$userPath" } else { $Directory }
      [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
      Write-Host "Persisted '$Directory' to user PATH."
    } else {
      Write-Host "'$Directory' already present in user PATH."
    }
  }
}

function Main {
  Ensure-ElixirInstalled -ForceInstall:$Force

  $mixDir = Find-MixPath

  if (-not $mixDir) {
    throw "Unable to locate mix after installation. Ensure Elixir installed correctly."
  }

  Add-ToPath -Directory $mixDir -Persist:(!$NoPersist)

  $mixCommand = Get-Command -Name 'mix' -ErrorAction SilentlyContinue
  if (-not $mixCommand) {
    Write-Warning "mix is still not immediately available. Open a new PowerShell session to pick up PATH changes."
  } else {
    Write-Host "mix located at: $($mixCommand.Source)"
  }

  Write-Host "Elixir installation and PATH update complete."
}

Main
