$hostName = 'com.toolbarglow.bridge'
$key = 'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave'
if (Test-Path $key) { Remove-Item $key -Recurse -ErrorAction SilentlyContinue }
$reg = "HKCU:\SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts\$hostName"
if (Test-Path $reg) { Remove-Item $reg -Recurse }
$old = "HKCU:\SOFTWARE\Google\Chrome\NativeMessagingHosts\$hostName"
if (Test-Path $old) { Remove-Item $old -Recurse }

$brave = @(
  (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'BraveSoftware\Brave-Browser\Application\brave.exe'),
  (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($brave) { & $brave --refresh-platform-policy --no-startup-window }

Write-Host 'Toolbar Glow helper removed; Brave theme restored.' -ForegroundColor Green
Write-Host 'Last step: remove the extension in brave://extensions.' -ForegroundColor Cyan
