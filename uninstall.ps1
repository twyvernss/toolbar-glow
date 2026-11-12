$hostName = 'com.toolbarglow.bridge'

foreach ($key in 'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave', 'HKCU:\SOFTWARE\Policies\Google\Chrome') {
  if (Test-Path $key) {
    $left = 1
    $k =[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($key.Substring(6), $true)
    if ($k) { $k.DeleteValue('BrowserThemeColor', $false); $left = $k.ValueCount + $k.SubKeyCount; $k.Close() }
    if ($left -eq 0) { Remove-Item $key -Recurse -ErrorAction SilentlyContinue }
  }
}

foreach ($nm in 'HKCU:\SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts', 'HKCU:\SOFTWARE\Google\Chrome\NativeMessagingHosts') {
  if (Test-Path "$nm\$hostName") { Remove-Item "$nm\$hostName" -Recurse }
}

foreach ($rel in 'BraveSoftware\Brave-Browser\Application\brave.exe', 'Google\Chrome\Application\chrome.exe') {
  $exe = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) |
    Where-Object { $_ } | ForEach-Object { Join-Path $_ $rel } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($exe) { & $exe --refresh-platform-policy --no-startup-window }
}

Write-Host 'Toolbar Glow helper removed; Brave and Chrome themes restored.' -ForegroundColor Green
Write-Host 'Last step: remove the extension in brave://extensions or chrome://extensions.' -ForegroundColor Cyan
