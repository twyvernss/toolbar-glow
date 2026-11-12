$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class BraveNotify {
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

  public static bool Send(string userDataDir, string braveExe, string workDir) {
    IntPtr hwnd = FindWindowEx(HWND_MESSAGE, IntPtr.Zero, "Chrome_MessageWindow", userDataDir);
    if (hwnd == IntPtr.Zero) return false;
    string cmd = "\"" + braveExe + "\" --refresh-platform-policy --no-startup-window";
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
$userData = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
$brave = @(
  (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'BraveSoftware\Brave-Browser\Application\brave.exe'),
  (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$workDir = if ($brave) { Split-Path $brave -Parent } else { $env:TEMP }

$stdin  = [Console]::OpenStandardInput()
$stdout = [Console]::OpenStandardOutput()

function Send-Msg($obj) {
  $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
  $stdout.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
  $stdout.Write($bytes, 0, $bytes.Length)
  $stdout.Flush()
}

function Apply-Value([string]$value) {
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('SOFTWARE\Policies\BraveSoftware\Brave')
  try {
    if ($value -eq 'reset') { $key.DeleteValue('BrowserThemeColor', $false) }
    else { $key.SetValue('BrowserThemeColor', $value, [Microsoft.Win32.RegistryValueKind]::String) }
  } finally { $key.Close() }

  if ([BraveNotify]::Send($userData, $brave, $workDir)) { return 'fast' }
  if (-not $brave) { throw 'brave.exe not found' }
  Start-Process $brave -ArgumentList '--refresh-platform-policy', '--no-startup-window' -WindowStyle Hidden -Wait
  return 'slow'
}

$script:pending = $null
$script:applied = $null
$script:lastRun = [DateTime]::MinValue

function Flush-Pending {
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
    if ($m -match 'denied|unauthori') { $m = 'Cannot write theme setting. Run install.bat once (it asks for admin).' }
    Send-Msg @{ type = 'error'; message = $m }
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
    'color' { if ($msg.hex -match '^#[0-9a-fA-F]{6}$') { $script:pending = $msg.hex.ToLower() } }
    'reset' { $script:pending = 'reset' }
    'ping'  { Send-Msg @{ type = 'pong'; ready = $true; brave = [bool]$brave } }
  }
  Flush-Pending
}
