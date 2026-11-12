$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class BrowserNotify {
  [StructLayout(LayoutKind.Sequential)]
  struct COPYDATASTRUCT { public IntPtr dwData; public int cbData; public IntPtr lpData; }

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, ref COPYDATASTRUCT lParam,
                                          uint flags, uint timeout, out IntPtr result);

  static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);
  const uint WM_COPYDATA = 0x004A;
  const uint SMTO_ABORTIFHUNG = 0x0002;

  public static bool Send(string userDataDir, string exePath, string workDir) {
    IntPtr hwnd = FindWindowEx(HWND_MESSAGE, IntPtr.Zero, "Chrome_MessageWindow", userDataDir);
    if (hwnd == IntPtr.Zero) return false;
    string cmd = "\"" + exePath + "\" --refresh-platform-policy --no-startup-window";
    string payload = "START\0" + workDir + "\0" + cmd + "\0";
    IntPtr mem = Marshal.StringToHGlobalUni(payload);
    try {
      COPYDATASTRUCT cds = new COPYDATASTRUCT();
      cds.dwData = IntPtr.Zero;
      cds.cbData = (payload.Length + 1) * 2;
      cds.lpData = mem;
      IntPtr res;
      IntPtr ok = SendMessageTimeout(hwnd, WM_COPYDATA, IntPtr.Zero, ref cds, SMTO_ABORTIFHUNG, 3000, out res);
      return ok != IntPtr.Zero && res != IntPtr.Zero;
    } finally { Marshal.FreeHGlobal(mem); }
  }
}
'@

$MinGapMs = 120
$browsers = [ordered]@{
  'brave.exe'  = @{ Name = 'Brave';  Policy = 'SOFTWARE\Policies\BraveSoftware\Brave'; Data = 'BraveSoftware\Brave-Browser\User Data'; Rel = 'BraveSoftware\Brave-Browser\Application\brave.exe' }
  'chrome.exe' = @{ Name = 'Chrome'; Policy = 'SOFTWARE\Policies\Google\Chrome';        Data = 'Google\Chrome\User Data';               Rel = 'Google\Chrome\Application\chrome.exe' }
}

function Find-Exe($rel) {
  @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) |
    Where-Object { $_ } | ForEach-Object { Join-Path $_ $rel } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
}

$browser = $null; $exe = $null; $cmdLine = ''
try {
  $procId = $PID
  for ($i = 0; $i -lt 6 -and -not $browser; $i++) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$procId"
    if (-not $p) { break }
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)"
    if (-not $parent) { break }
    $n = $parent.Name.ToLower()
    if ($browsers.Contains($n)) { $browser = $browsers[$n]; $exe = $parent.ExecutablePath; $cmdLine = [string]$parent.CommandLine }
    $procId = $parent.ProcessId
  }
} catch {}

if (-not $browser) {
  foreach ($n in $browsers.Keys) {
    $found = Find-Exe $browsers[$n].Rel
    if ($found) { $browser = $browsers[$n]; $exe = $found; break }
  }
}
if (-not $exe -and $browser) { $exe = Find-Exe $browser.Rel }

$userData = Join-Path $env:LOCALAPPDATA $browser.Data
if ($cmdLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))') { $userData = if ($Matches[1]) { $Matches[1] } else { $Matches[2] } }
$workDir = if ($exe) { Split-Path $exe -Parent } else { $env:TEMP }

$stdin  = [Console]::OpenStandardInput()
$stdout = [Console]::OpenStandardOutput()

function Send-Msg($obj) {
  $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
  $stdout.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
  $stdout.Write($bytes, 0, $bytes.Length)
  $stdout.Flush()
}

function Apply-Value([string]$value) {
  if (-not $browser) { throw 'Brave or Chrome not found' }
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($browser.Policy)
  try {
    if ($value -eq 'reset') { $key.DeleteValue('BrowserThemeColor', $false) }
    else { $key.SetValue('BrowserThemeColor', $value, [Microsoft.Win32.RegistryValueKind]::String) }
  } finally { $key.Close() }

  if ([BrowserNotify]::Send($userData, $exe, $workDir)) { return 'fast' }
  if (-not $exe) { throw ($browser.Name + ' not found') }
  Start-Process $exe -ArgumentList '--refresh-platform-policy', '--no-startup-window' -WindowStyle Hidden -Wait
  return 'slow'
}

$script:pending = $null
$script:applied = $null
$script:wanted  = $null
$script:lastRun = [DateTime]::MinValue
$script:setup   = $null
$root = Split-Path $PSScriptRoot -Parent

function Start-Setup {
  if ($script:setup -and -not $script:setup.HasExited) { return }
  $installer = Join-Path $root 'install.ps1'
  $script:setup = Start-Process powershell.exe -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$installer`"")
  Send-Msg @{ type = 'setup'; state = 'started' }
}

function Check-Setup {
  if ($script:setup -and $script:setup.HasExited) {
    $script:setup = $null
    $script:applied = $null
    if ($script:wanted) { $script:pending = $script:wanted }
    Send-Msg @{ type = 'setup'; state = 'finished' }
  }
}

function Flush-Pending {
  Check-Setup
  if ($null -eq $script:pending) { return }
  if ($script:pending -eq $script:applied) { $script:pending = $null; return }
  if (([DateTime]::UtcNow - $script:lastRun).TotalMilliseconds -lt $MinGapMs) { return }
  $value = $script:pending
  $script:pending = $null
  $script:lastRun = [DateTime]::UtcNow
  try {
    $mode = Apply-Value $value
    $script:applied = $value
    Send-Msg @{ type = 'applied'; value = $value; mode = $mode }
  } catch {
    $m = $_.Exception.Message
    if ($m -match 'denied|unauthori') {
      Send-Msg @{ type = 'error'; code = 'no-permission'; browser = $browser.Name; folder = $root
                  message = ('Setup needed for ' + $browser.Name + '.') }
    } else {
      Send-Msg @{ type = 'error'; code = 'other'; message = $m }
    }
  }
}

function Read-Exact([byte[]]$buf, [int]$start, [int]$count) {
  $got = $start
  while ($got -lt $count) {
    $r = $stdin.Read($buf, $got, $count - $got)
    if ($r -le 0) { exit 0 }
    $got += $r
  }
}

$head = New-Object byte[] 4
while ($true) {
  $task = $stdin.ReadAsync($head, 0, 4)
  while (-not $task.Wait(40)) { Flush-Pending }
  $n = $task.Result
  if ($n -le 0) { exit 0 }
  Read-Exact $head $n 4
  $len = [BitConverter]::ToInt32($head, 0)
  if ($len -le 0 -or $len -gt 65536) { exit 1 }
  $body = New-Object byte[] $len
  Read-Exact $body 0 $len

  try { $msg = [Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json } catch { continue }
  switch ($msg.type) {
    'color' { if ($msg.hex -match '^#[0-9a-fA-F]{6}$') { $script:pending = $msg.hex.ToLower(); $script:wanted = $script:pending } }
    'reset' { $script:pending = 'reset'; $script:wanted = 'reset' }
    'setup' { Start-Setup }
    'ping'  { Send-Msg @{ type = 'pong'; ready = $true; browser = $browser.Name; exe = $exe; userData = $userData } }
  }
  Flush-Pending
}
