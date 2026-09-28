$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = [IO.File]::ReadAllText((Join-Path $root 'HollowDrivers.ps1'))
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$start = $source.IndexOf('$instanceUser =')
$end = $source.IndexOf('Add-Type -AssemblyName PresentationFramework', $start)
$guard = $source.Substring($start, $end - $start)
# Isola o teste de qualquer instalacao aberta.
$guard = $guard.Replace('Local\HollowDrivers.UI.', ('Local\HollowDrivers.Test.' + [guid]::NewGuid().ToString('N') + '.'))
$work = Join-Path $root 'dist\single-instance-test'
New-Item -ItemType Directory -Force $work | Out-Null
$harness = 'param([string]$Log, [switch]$Rescue)' + "`r`n" + $guard + @'
[IO.File]::AppendAllText($Log, "owner`n")
$deadline = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($activateEvent.WaitOne(30)) { [IO.File]::AppendAllText($Log, "activate`n") }
    if ($rescueEvent.WaitOne(0)) { [IO.File]::AppendAllText($Log, "rescue`n") }
}
} finally {
    if ($ownsUiMutex) { $uiMutex.ReleaseMutex() }
    $uiMutex.Dispose(); $activateEvent.Dispose(); $rescueEvent.Dispose()
}
'@
$fixture = Join-Path $work 'fixture.ps1'
Set-Content $fixture $harness -Encoding UTF8
$log = Join-Path $work ('result-' + [guid]::NewGuid().ToString('N') + '.txt')
$arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $fixture + '" -Log "' + $log + '"'
$first = Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(10)
while (-not (Test-Path $log)) {
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Primeira instancia nao iniciou.' }
    Start-Sleep -Milliseconds 50
}
$second = Start-Process powershell.exe -ArgumentList ($arguments + ' -Rescue') -WindowStyle Hidden -PassThru
$third = Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
foreach ($p in @($second, $third, $first)) { $p.WaitForExit(); if ($p.ExitCode) { throw 'Processo falhou.' } }
$lines = @(Get-Content $log)
if (@($lines | Where-Object { $_ -eq 'owner' }).Count -ne 1) { throw 'Mais de uma instancia entrou.' }
if ('activate' -notin $lines -or 'rescue' -notin $lines) { throw 'Pedido nao encaminhado.' }
$reopen = Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
$reopen.WaitForExit()
if (@(Get-Content $log | Where-Object { $_ -eq 'owner' }).Count -ne 2) { throw 'Reabertura bloqueada.' }
'OK: instancias simultaneas, ativacao, socorro e reabertura.'
