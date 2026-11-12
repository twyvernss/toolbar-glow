param([string]$UserSid, [string]$UserName)

$ErrorActionPreference = 'Stop'
$extId    = 'feojnoeihacbjocoeboibbhimlponagj'
$hostName = 'com.toolbarglow.bridge'
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$hostDir  = Join-Path $root 'host'

if (-not $UserSid) {
  $me = [Security.Principal.WindowsIdentity]::GetCurrent()
  $UserSid = $me.User.Value
  $UserName = $me.Name
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'Asking Windows for admin permission (needed once)...'
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-UserSid', $UserSid, '-UserName', "`"$UserName`"")
  try { Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList $argList }
  catch { Write-Host 'Admin permission was refused. Nothing was changed.' -ForegroundColor Red }
  exit
}

try {
  $hku = "Registry::HKEY_USERS\$UserSid"
  if (-not (Test-Path $hku)) { throw "Registry for $UserName is not loaded. Log in as that user and try again." }

  $parent = "$hku\SOFTWARE\Policies\BraveSoftware"
  $key    = "$parent\Brave"
  if (-not (Test-Path $parent)) { New-Item $parent | Out-Null }
  if (-not (Test-Path $key))    { New-Item $key | Out-Null }
  $acl  = Get-Acl $key
  $sid  = New-Object System.Security.Principal.SecurityIdentifier $UserSid
  $rule = New-Object System.Security.AccessControl.RegistryAccessRule($sid, 'ReadKey, SetValue, CreateSubKey, Delete', 'ContainerInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
  Set-Acl $key $acl
  Write-Host "[1/3] Brave theme setting ready for $UserName" -ForegroundColor Green

  $manifest = [ordered]@{
    name            = $hostName
    description     = 'Toolbar Glow helper'
    path            = (Join-Path $hostDir 'host.bat')
    type            = 'stdio'
    allowed_origins = @("chrome-extension://$extId/")
  }
  $manifestPath = Join-Path $hostDir "$hostName.json"
  [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
  $reg = "$hku\SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts\$hostName"
  if (-not (Test-Path $reg)) { New-Item $reg -Force | Out-Null }
  Set-Item $reg -Value $manifestPath
  Write-Host '[2/3] Helper registered with Brave' -ForegroundColor Green

  Get-ChildItem $root -Recurse -File | Unblock-File
  Write-Host '[3/3] Files unblocked' -ForegroundColor Green

  Write-Host ''
  Write-Host 'Done! Now in Brave: brave://extensions -> Developer mode ON -> Load unpacked -> pick this folder.' -ForegroundColor Cyan
  Write-Host '(Already loaded? Just press its reload button.)' -ForegroundColor Cyan
} catch {
  Write-Host ('Setup failed: ' + $_.Exception.Message) -ForegroundColor Red
}
Write-Host ''
Read-Host 'Press Enter to close'
