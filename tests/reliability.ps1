$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root ('dist\reliability-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work)
Add-Type -Path (Join-Path $root 'src\InstallTransaction.cs')
$target=Join-Path $work 'app';$stage=Join-Path $work 'stage'
[void](New-Item -ItemType Directory $target,$stage)
Set-Content (Join-Path $target 'version') 'old';Set-Content (Join-Path $stage 'version') 'new'
try {[DG.InstallTransaction]::Replace($stage,$target,[Action]{throw 'simulated failure'});throw 'Failure ignored'}catch{if($_ -match 'Failure ignored'){throw}}
if((Get-Content (Join-Path $target 'version')) -ne 'old'){throw 'Rollback failed'}
[void](New-Item -ItemType Directory $stage);Set-Content (Join-Path $stage 'version') 'new'
[DG.InstallTransaction]::Replace($stage,$target,$null)
if((Get-Content (Join-Path $target 'version')) -ne 'new'){throw 'Swap failed'}
if(-not @(Get-ChildItem $work -Directory -Filter 'app.previous-*').Count){throw 'Previous version lost'}
Move-Item $target ($target+'.rollback');[void](New-Item -ItemType Directory $target);Set-Content (Join-Path $target 'partial') 'incomplete'
[DG.InstallTransaction]::Recover($target)
if((Get-Content (Join-Path $target 'version')) -ne 'new'){throw 'Crash recovery failed'}
$lock=Join-Path $work 'session.lock'
$shared=[IO.File]::Open($lock,'OpenOrCreate','ReadWrite','ReadWrite')
try {try{$exclusive=[IO.File]::Open($lock,'OpenOrCreate','ReadWrite','None');$exclusive.Dispose();throw 'Exclusive lock bypassed'}catch [IO.IOException]{}}finally{$shared.Dispose()}
$exclusive=[IO.File]::Open($lock,'OpenOrCreate','ReadWrite','None');$exclusive.Dispose()
Add-Type -AssemblyName PresentationFramework
$DataDir=$work
. (Join-Path $root 'History.ps1')
. (Join-Path $root 'Operations.ps1')
$script:results=@{}
Start-Bg 'Start-Sleep -Milliseconds 100; "first"' {param($out,$err,$ctx) $script:results[$ctx.Id]="$out"} @{} @{Id='a'}
Start-Bg '"second"' {param($out,$err,$ctx) $script:results[$ctx.Id]="$out"} @{} @{Id='b'}
Start-Bg 'Write-Error "controlled error"' {param($out,$err,$ctx) $script:results[$ctx.Id]=$err} @{} @{Id='error'}
$deadline=(Get-Date).AddSeconds(10)
while($script:Tasks.Count -and (Get-Date) -lt $deadline){
 $frame=New-Object Windows.Threading.DispatcherFrame
 [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
 [Windows.Threading.Dispatcher]::PushFrame($frame);Start-Sleep -Milliseconds 30
}
if($results.a -ne 'first' -or $results.b -ne 'second' -or $results.error -notmatch 'controlled error'){throw 'Background context/error routing failed'}
# Simulate UAC completion without launching any administrator process.
$Win=[pscustomobject]@{IsEnabled=$true};$ElevLib='log=__LOG__'
function Expand-Tpl($template,$map) { $template }
function Start-Bg($code,$done,$vars,$context) { $script:pending=@{Done=$done;Context=$context} }
$script:ElevBusy=$false
Invoke-Elevated '' @{} 'first-admin' {param($log,$err) $script:firstResult=$log}
$first=$pending
Invoke-Elevated '' @{} 'overlap' {param($log,$err) $script:busyError=$err}
if(-not $busyError -or $Win.IsEnabled){throw 'Overlapping elevation permitted'}
Set-Content $first.Context.Log 'OK=first'
& $first.Done $null $null $first.Context
if(-not $Win.IsEnabled -or $ElevBusy -or $firstResult -notmatch 'OK=first'){throw 'First elevation routing failed'}
Invoke-Elevated '' @{} 'second-admin' {param($log,$err) $script:secondError=$err}
$second=$pending
& $second.Done $null 'UAC cancelled' $second.Context
if($secondError -ne 'UAC cancelled' -or -not (Test-Path $first.Context.Log) -or $first.Context.Log -eq $second.Context.Log){throw 'Elevation error routing or log preservation failed'}
# Invoke the real backup completion code with fake driver packages.
$source=[IO.File]::ReadAllText((Join-Path $root 'HollowDrivers.ps1'))
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$fn=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Start-Backup'},$true)
Invoke-Expression $fn.Extent.Text
$BackupDir=Join-Path $work 'backups';[void](New-Item -ItemType Directory (Join-Path $BackupDir 'network'),(Join-Path $BackupDir 'old-video'))
Set-Content (Join-Path $BackupDir 'network\driver.inf') 'keep-network';Set-Content (Join-Path $BackupDir 'old-video\driver.inf') 'keep-video'
function Get-DriverPackage { @{Folder='fake';Inf='fake.inf'} }
function Get-Backup { $true }
function Expand-Tpl { 'mock' }
function Update-Cards {}
function Update-Home {}
function Show-Dialog { throw 'Backup unexpectedly failed' }
function Start-Bg($code,$done) { & $done @(0) $null }
Start-Backup ([pscustomobject]@{Inf='fake';Version='new-video';Name='Fake';Vendor='Fake'})
if((Get-Content (Join-Path $BackupDir 'network\driver.inf')) -ne 'keep-network' -or (Get-Content (Join-Path $BackupDir 'old-video\driver.inf')) -ne 'keep-video'){throw 'Backups deleted'}
. (Join-Path $root 'CloneAssistant.ps1')
$inv=@{Source=@{Serial='source'}};$dst=@{Serial='target';Label='test'}
Save-CloneProgress $inv $dst 'roteiro preparado'
try{Save-CloneProgress $inv $dst 'boot testado pelo usuário';throw 'Boot order bypassed'}catch{if($_ -match 'Boot order bypassed'){throw}}
Save-CloneProgress $inv $dst 'cópia concluída; boot pendente'
Save-CloneProgress $inv $dst 'boot testado pelo usuário'
Save-CloneProgress $inv $dst 'roteiro preparado'
if((Get-CloneProgress $inv $dst).Status -ne 'boot testado pelo usuário'){throw 'Guide overwrote boot history'}
if(Get-CloneProgress $inv @{Serial='other'}){throw 'Wrong disk history'}
if(-not (Test-Path (Join-Path $work 'history.jsonl'))){throw 'History missing'}
'OK: rollback, crash recovery, version retention, maintenance lock, background isolation/errors, backup preservation, clone state transitions and history.'
