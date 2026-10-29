$ErrorActionPreference='Stop'
# Tela inicial, navegação e gravação de configurações, sem PC real: estado de análise falso e janela fora da tela.
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root ('dist\home-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work)
Add-Type -AssemblyName PresentationFramework
$source=[IO.File]::ReadAllText((Join-Path $root 'HollowDrivers.ps1'))
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
function Import-Main([string]$name) {
    $node=$ast.Find({param($n) ($n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name) -or
        ($n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $name)},$true)
    if(-not $node){throw "Not found in HollowDrivers.ps1: $name"}
    $node.Extent.Text
}
foreach($n in 'Save-Json','Get-Settings','Save-Settings','Get-Plural','$Hex','$Glyph','$ResXaml','$WhqlLib','$ElevLib','$DlTpl'){ Invoke-Expression (Import-Main $n) }

# ---- uma única verificação WHQL, presente nos dois scripts que instalam ou baixam drivers
if(([regex]::Matches($source,'function Test-WhqlSigned')).Count -ne 1){throw 'WHQL check duplicated'}
if($ElevLib -notmatch 'function Test-WhqlSigned' -or $DlTpl -notmatch 'function Test-WhqlSigned'){throw 'WHQL check missing from a template'}

# ---- gravação atômica
$DataDir=$work; $SettingsFile=Join-Path $work 'settings.json'
Save-Json @{ A=1 } $SettingsFile
Save-Json @{ A=2 } $SettingsFile
if((Get-Content $SettingsFile -Raw | ConvertFrom-Json).A -ne 2 -or (Test-Path ($SettingsFile+'.tmp'))){throw 'Atomic JSON save failed'}
Remove-Item $SettingsFile
$st=Get-Settings
if(-not $st.AutoScan -or @($st.Ignored).Count){throw 'Settings defaults wrong'}

# ---- janela
$app=New-Object Windows.Application
$app.ShutdownMode='OnExplicitShutdown'
$app.Resources=[Windows.Markup.XamlReader]::Parse([regex]::Replace($ResXaml,'__[A-Z0-9_]+__','#FF9900'))
. (Join-Path $root 'Views.ps1')
$Win=[Windows.Markup.XamlReader]::Parse([regex]::Replace($MainXaml,'__[A-Z0-9_]+__','#FF9900'))
$homeSource=[IO.File]::ReadAllText((Join-Path $root 'Home.ps1'))
foreach($n in [regex]::Matches($homeSource,'\$([A-Z]\w+)\.') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique){
    $c=$Win.FindName($n); if($c){ Set-Variable -Name $n -Value $c -Scope Script }
}
foreach($n in 'NavHome','NavDrivers','NavGuard','NavTools','NavSettings','TabDrivers','TabVideo','TabWin','TabSystem','TabClean','TabExtras',
    'PanDrivers','PanVideo','PanWin','PanSystem','PanClean','PanGuard','PanExtras','BtnRail','ChipBad','CleanGrid'){ Set-Variable -Name $n -Value $Win.FindName($n) -Scope Script }
$BrushConv=New-Object Windows.Media.BrushConverter
function Get-Brush([string]$hex){ $BrushConv.ConvertFromString($hex) }
$script:Prog=[hashtable]::Synchronized(@{ Text='' }); $script:ProgRun=$null

# ---- PC falso: vídeo sem backup, Driver Booster, quedas, reinício pendente, driver com erro e atualizações
$script:calls=New-Object Collections.ArrayList
function Get-Baseline {}
function Get-Backup {}
function Get-AllBackupInfo {}
function Test-WatchEnabled { $false }
function Get-FixSteps { '' }
function Get-OfficialLinks { @{} }
function Write-OperationEvent {}
function Update-WatchButton {}
function Update-Cards {}
function Show-Dialog { $true }
foreach($f in 'Act-Restore','Act-MarkGood','Act-History','Act-KeyChanges','Act-RemoveDb','Act-Crashes','Act-Reboot','Act-AllBackup','Act-Watch',
    'Show-UpdatesWindow','Invoke-VideoBackup','Enable-Watch','Start-UpdateCheck','Start-Backup','Set-Chip',
    'Start-Scan','Start-WuCheck','Update-StorageInfo','Update-CleanDrive','Start-CleanScan'){
    Set-Item "function:$f" ([scriptblock]::Create("[void]`$script:calls.Add('$f')"))
}
$script:Gpu=[pscustomobject]@{ Code=0; Version='1.0'; Name='GPU teste' }
$script:Health=[pscustomobject]@{ DriverBooster=@([pscustomobject]@{Path='x'}); Crashes=2; Tdr=$false }
$script:History=@(); $script:SysInfo=$null; $script:Problems=1; $script:Old=0
$script:KeyChanges=@([pscustomobject]@{ Nome='Rede X'; Categoria='Rede' })
$script:NeedReboot=@([pscustomobject]@{ Dispositivo='Wi-Fi' })
$script:UpdState='done'; $script:Updates=@([pscustomobject]@{Id='u1';Dispositivo='Chipset'},[pscustomobject]@{Id='u2';Dispositivo='Áudio'})
$script:BackupBusy=$false; $script:AllBusy=$false; $script:Scanning=$false
$script:LastScan=Get-Date

. (Join-Path $root 'Home.ps1')
$Win.Left=-20000; $Win.ShowInTaskbar=$false; $Win.Show()
function Get-Buttons($parent){
    $Win.UpdateLayout()
    $stack=New-Object Collections.Stack; $stack.Push($parent); $found=@()
    while($stack.Count){ $e=$stack.Pop(); if($e -is [Windows.Controls.Button]){$found+=$e}
        for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($e);$i++){ $stack.Push([Windows.Media.VisualTreeHelper]::GetChild($e,$i)) } }
    $found
}
function Click($b){ $b.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
try {
    # ao abrir, só a tela inicial aparece (nenhuma seção por cima dela)
    foreach($p in $PanDrivers,$PanVideo,$PanWin,$PanSystem,$PanClean,$PanGuard,$PanExtras,$ConfigView,$TabBar){ if($p.Visibility -ne 'Collapsed'){throw "Visible at startup: $($p.Name)"} }
    Update-Home
    if($VerdictText.Text -ne '4 problemas encontrados'){throw "Verdict: $($VerdictText.Text)"}
    if(@($ProblemsList.ItemsSource).Count -ne 3){throw 'Home must list at most three problems'}
    if($BtnDetails.Content -ne 'Ver detalhes (6)'){throw "Details button: $($BtnDetails.Content)"}
    if($BtnFixAll.Content -ne 'Corrigir tudo (3)'){throw "Fix-all button: $($BtnFixAll.Content)"}
    $tiles=@($HomeTiles.ItemsSource)
    if($tiles.Count -ne 4 -or $tiles[0].Value -ne '1 com problema' -or $tiles[2].Value -ne 'Driver Booster' -or $tiles[3].Value -ne '2 quedas'){throw 'Tiles wrong'}

    # os modelos desenham os dados e o botão de cada aviso chama a ação certa
    $acts=@(Get-Buttons $ProblemsList | Where-Object { "$($_.Tag)" -like 'act|*' })
    if($acts.Count -ne 3 -or @($acts | Where-Object { $_.Tag -eq 'act|key-changes' })[0].Content -ne 'Ver quais'){throw 'Finding buttons not rendered'}
    Click @($acts | Where-Object { $_.Tag -eq 'act|crashes' })[0]
    if($calls -notcontains 'Act-Crashes'){throw 'Finding action not routed'}
    Click @(Get-Buttons $HomeTiles | Where-Object { $_.Tag -eq 'protecao' })[0]
    if($PanGuard.Visibility -ne 'Visible' -or -not $NavGuard.IsChecked -or $TabBar.Visibility -ne 'Collapsed'){throw 'Tile navigation failed'}
    Show-Page 'home'

    # detalhes: todos os problemas com explicação e as sugestões, que podem ser ignoradas
    Click $BtnDetails
    if(@($ProblemsList.ItemsSource).Count -ne 5 -or $DetailsPanel.Visibility -ne 'Visible' -or @($DetailsList.ItemsSource).Count -ne 4){throw 'Details view wrong'}
    $ignore=@(Get-Buttons $DetailsList | Where-Object { $_.Tag -eq 'ignore|watch-off' })[0]
    if(-not $ignore){throw 'Ignore button missing'}
    Click $ignore
    if(@($DetailsList.ItemsSource).Count -ne 3 -or (Get-Settings).Ignored -notcontains 'watch-off'){throw 'Ignore failed'}
    if($BtnFixAll.Content -ne 'Corrigir tudo (2)'){throw 'Ignored suggestion still fixed'}
    Clear-HomeIgnored
    if(@($DetailsList.ItemsSource).Count -ne 4){throw 'Unignore failed'}
    Click $BtnDetails

    # corrigir tudo roda só as correções seguras, uma vez cada
    $calls.Clear(); Invoke-FixAll
    if(($calls -join ',') -ne 'Show-UpdatesWindow,Invoke-VideoBackup,Enable-Watch'){throw "Fix-all ran: $($calls -join ',')"}

    # sem correção segura, o botão principal resolve o primeiro problema grave
    $script:Updates=@(); $script:Gpu.Code=43; function Test-WatchEnabled { $true }
    Update-Home
    if($BtnFixAll.Content -ne 'Como resolver' -or -not $script:FixPrimary){throw 'Primary action fallback failed'}

    # a última análise volta ao abrir o app
    $saved=$VerdictText.Text
    if(-not (Test-Path (Join-Path $work 'last-scan.json'))){throw 'Snapshot not saved'}
    $HomeTiles.ItemsSource=$null; $ProblemsList.ItemsSource=$null; $VerdictText.Text=''
    if(-not (Restore-HomeSnapshot) -or $VerdictText.Text -ne $saved -or @($HomeTiles.ItemsSource).Count -ne 4 -or $VerdictSub.Text -notlike 'Resultado da análise de hoje*'){throw 'Snapshot restore failed'}
    if(@(Get-Buttons $ProblemsList | Where-Object { $_.Visibility -eq 'Visible' -and "$($_.Tag)" -like 'act|*' }).Count){throw 'Restored findings must not be clickable'}

    # avisos temporários (rede de segurança do vídeo) substituem a lista
    Clear-Findings; Add-Finding 'Rede de segurança ligada' 'x' 'info' 'Cancelar' { [void]$script:calls.Add('cancel') }
    Click @(Get-Buttons $ProblemsList | Where-Object { $_.Tag -eq 'act|temp0' })[0]
    if($calls -notcontains 'cancel' -or $FixBar.Visibility -ne 'Collapsed'){throw 'Temporary finding failed'}

    # navegação: menu único com abas por grupo
    Show-Page 'limpeza'
    if($PanClean.Visibility -ne 'Visible' -or -not $NavTools.IsChecked -or -not $TabClean.IsChecked -or $TabDrivers.Visibility -ne 'Collapsed' -or $TabBar.Visibility -ne 'Visible' -or $HomeView.Visibility -ne 'Collapsed'){throw 'Tools navigation failed'}
    if($calls -notcontains 'Start-CleanScan'){throw 'Cleanup page did not scan'}
    Click $TabWin
    if($PanWin.Visibility -ne 'Visible' -or -not $NavDrivers.IsChecked -or $TabSystem.Visibility -ne 'Collapsed' -or $PanClean.Visibility -ne 'Collapsed'){throw 'Tab navigation failed'}
    Show-Page 'config'
    if($ConfigView.Visibility -ne 'Visible' -or -not $NavSettings.IsChecked -or $TabBar.Visibility -ne 'Collapsed'){throw 'Settings navigation failed'}
    Show-Page 'home'
    if($HomeView.Visibility -ne 'Visible' -or -not $NavHome.IsChecked -or $PanWin.Visibility -ne 'Collapsed'){throw 'Home navigation failed'}
    Set-Rail $false
    if($RailCol.Width.Value -ne 64 -or $NavDrivers.Content -or $NavDrivers.ToolTip -ne 'Drivers'){throw 'Collapsed menu failed'}
    Set-Rail $true
    if($NavDrivers.Content -ne 'Drivers'){throw 'Expanded menu failed'}
} finally { $Win.Close(); $app.Shutdown(); Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
'OK: home summary, tiles, fix-all, ignore, details, snapshot, temporary findings, navigation, atomic settings and shared WHQL check.'
