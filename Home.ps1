# Tela inicial e navegação.
# A tela inicial mostra só o essencial: veredito, quatro blocos de status, um botão principal e até três problemas.
# Os avisos são montados como dados (Get-HomeItems) e desenhados pelos modelos FindingTpl/TileTpl do Views.ps1.

# ---------------------------------------------------------------- veredito e botão grande

function Set-Verdict([string]$kind, [string]$text, [string]$sub) {
    $col = $Hex[$kind]
    $script:VerdictKind = $kind
    $VerdictText.Text = $text; $VerdictSub.Text = $sub
    $VerdictIcon.Text = $Glyph[$kind]; $VerdictIcon.Foreground = Get-Brush $col
    $VerdictBadge.Background = Get-Brush ('#26' + $col.Substring(1))
}

$SpinAnim = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, (New-Object Windows.Duration([TimeSpan]::FromSeconds(1))))
$SpinAnim.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever

function Set-BigBusy([bool]$busy) {
    if ($busy) {
        $BigLabel.Text = 'ANALISANDO'; $BigLabel.FontSize = 18; $BigIcon.Visibility = 'Collapsed'
        $Spinner.Opacity = 1; $SpinRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $SpinAnim)
        $BigBtn.IsHitTestVisible = $false
    } else {
        $SpinRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null); $Spinner.Opacity = 0
        $BigLabel.Text = 'ANALISAR'; $BigLabel.FontSize = 23; $BigIcon.Visibility = 'Visible'
        if ($script:LastScan) { $BigIcon.Text = [string][char]0xE72C }
        $BigBtn.IsHitTestVisible = $true
    }
}

# ---------------------------------------------------------------- avisos como dados

# Tip = sugestão (fica em "Ver detalhes" e pode ser ignorada). FixText/FixAction = entra no "Corrigir tudo".
function New-HomeItem([hashtable]$h) {
    $item = [ordered]@{ Id = ''; Kind = 'info'; Title = ''; Desc = ''; BtnText = ''; Action = $null; Tip = $false; IgnoreKey = ''; FixText = ''; FixAction = $null }
    foreach ($k in $h.Keys) { $item[$k] = $h[$k] }
    if (-not $item.IgnoreKey) { $item.IgnoreKey = $item.Id }
    [pscustomobject]$item
}

function Get-HomeItems {
    $items = New-Object Collections.ArrayList
    $g = $script:Gpu; $b = Get-Baseline; $hl = $script:Health
    $bk = if ($b) { Get-Backup $b.Version } else { $null }

    if ($g -and $g.Code -ne 0) {
        if ($bk) {
            [void]$items.Add((New-HomeItem @{ Id = 'gpu-broken'; Kind = 'bad'; Title = 'O driver da placa de vídeo está quebrado'; BtnText = 'Restaurar driver'; Action = { Act-Restore }
                Desc = ("A tela funciona, mas jogos e aceleração 3D não. Você tem um backup do driver que funcionava ({0}) — um clique reinstala ele." -f $bk.Version) }))
        } else {
            [void]$items.Add((New-HomeItem @{ Id = 'gpu-broken'; Kind = 'bad'; Title = 'O driver da placa de vídeo está quebrado'; BtnText = 'Como resolver'
                Desc = 'O Windows passou a usar um modo de vídeo básico: a tela funciona, mas jogos e aceleração 3D não. Reinstale o driver oficial.'
                Action = {
                    [void](Show-Dialog 'Como resolver' ((Get-FixSteps) + "`n`nVou abrir o site oficial agora.") 'info' -YesText 'Abrir site')
                    Start-Process @((Get-OfficialLinks).Values)[0]
                } }))
        }
    }
    if ($g -and $g.Code -eq 0 -and $b -and $b.Version -ne $g.Version) {
        $origin = if ($script:History.Count) { $script:History[0].Origem } else { '' }
        if ($origin -like 'Instalador oficial*') {
            [void]$items.Add((New-HomeItem @{ Id = 'video-updated'; Kind = 'warn'; Title = 'O driver de vídeo foi atualizado'; BtnText = 'Salvar nova versão'; Action = { Act-MarkGood }
                Desc = ("Nova versão {0} instalada pelo {1}. Se o vídeo e os jogos estão funcionando bem, salve esta versão como a nova referência." -f $g.Version, $origin.ToLower()) }))
        } else {
            $who = if ($origin) { " (por: $origin)" } else { '' }
            if ($bk) {
                [void]$items.Add((New-HomeItem @{ Id = 'video-changed'; Kind = 'bad'; Title = "O driver de vídeo foi trocado sem você saber$who"; BtnText = 'Restaurar driver'; Action = { Act-Restore }
                    Desc = ("Se o vídeo ou os jogos começaram a falhar, essa troca é a causa mais provável. Você pode voltar para o driver salvo ({0}) com um clique." -f $bk.Version) }))
            } else {
                [void]$items.Add((New-HomeItem @{ Id = 'video-changed'; Kind = 'bad'; Title = "O driver de vídeo foi trocado sem você saber$who"; BtnText = 'Ver quem trocou'; Action = { Act-History }
                    Desc = 'Se o vídeo ou os jogos começaram a falhar, essa troca é a causa mais provável. Veja quem trocou e reinstale o driver oficial.' }))
            }
        }
    }
    if (@($script:KeyChanges).Count) {
        $n = @($script:KeyChanges)
        $quais = (@($n | Select-Object -First 3 | ForEach-Object { '{0} ({1})' -f $_.Categoria.ToLower(), $_.Nome }) -join ', ')
        [void]$items.Add((New-HomeItem @{ Id = 'key-changes'; Kind = 'bad'; Title = (Get-Plural $n.Count 'driver principal foi trocado' 'drivers principais foram trocados'); BtnText = 'Ver quais'; Action = { Act-KeyChanges }
            Desc = "Mudaram de versão desde a última vez: $quais. Se algo parou de funcionar, foi provavelmente isso." }))
    }
    if ($hl.DriverBooster.Count) {
        [void]$items.Add((New-HomeItem @{ Id = 'driver-booster'; Kind = 'bad'; Title = 'O Driver Booster está instalado'; BtnText = 'Remover'; Action = { Act-RemoveDb }
            Desc = 'Ele instala drivers de fontes próprias por cima dos oficiais, sem pedir. Isso pode deixar a placa de vídeo instável ou impedir jogos de abrir.' }))
    }
    if ($hl.Crashes) {
        $why = if (-not $hl.Tdr) { 'Nenhuma dessas quedas teve erro de driver. Isso costuma ser a fonte de energia não aguentando a placa de vídeo em jogos pesados, e não o driver.' }
               else { 'O Windows registrou falhas do driver de vídeo junto com as quedas. Veja os detalhes para saber quando aconteceram.' }
        [void]$items.Add((New-HomeItem @{ Id = 'crashes'; Kind = 'bad'; Title = ('O PC desligou sozinho {0} no último mês' -f (Get-Plural $hl.Crashes 'vez' 'vezes')); BtnText = 'Ver quedas'; Action = { Act-Crashes }; Desc = $why }))
    }
    if ($script:NeedReboot.Count) {
        $quais = ($script:NeedReboot | Select-Object -First 3 -Expand Dispositivo) -join ', '
        [void]$items.Add((New-HomeItem @{ Id = 'reboot'; Kind = 'warn'; Title = (Get-Plural $script:NeedReboot.Count 'driver está esperando você reiniciar' 'drivers estão esperando você reiniciar')
            BtnText = 'Reiniciar agora'; Action = { Act-Reboot }
            Desc = "$quais só vai funcionar depois de reiniciar o PC. Use Iniciar → Reiniciar: desligar e ligar não resolve, porque o Windows 11 não desliga de verdade (Inicialização Rápida)." }))
    }
    if ($script:Problems) {
        [void]$items.Add((New-HomeItem @{ Id = 'device-problems'; Kind = 'bad'; Title = (Get-Plural $script:Problems 'dispositivo com problema no driver' 'dispositivos com problema no driver'); BtnText = 'Ver quais'
            Desc = 'Algum componente do PC está sem driver ou com erro e pode não funcionar direito. A lista mostra qual.'
            Action = { Show-Page 'drivers'; Set-Chip $ChipBad } }))
    }
    if ($script:UpdState -eq 'error') {
        [void]$items.Add((New-HomeItem @{ Id = 'updates-error'; Kind = 'info'; Title = 'Não foi possível buscar atualizações'; BtnText = 'Tentar de novo'; Action = { Start-UpdateCheck }
            Desc = 'Sem internet ou o catálogo da Microsoft não respondeu. Tente de novo mais tarde.' }))
    }

    # ---- sugestões
    if ($script:UpdState -eq 'done' -and $script:Updates.Count) {
        $names = (@($script:Updates | Select-Object -First 3 | ForEach-Object Dispositivo) -join ', ')
        if ($script:Updates.Count -gt 3) { $names += '...' }
        [void]$items.Add((New-HomeItem @{ Id = 'updates'; Kind = 'warn'; Tip = $true; IgnoreKey = ('updates:' + (@($script:Updates | ForEach-Object Id) -join '|'))
            Title = ((Get-Plural $script:Updates.Count 'driver tem versão nova' 'drivers têm versão nova') + ' oficial'); BtnText = 'Atualizar'; Action = { Show-UpdatesWindow }
            Desc = "Versões mais novas certificadas pela Microsoft: $names. Antes de instalar é criado um ponto de restauração."
            FixText = ('Escolher quais dos {0} atualizar (abre a lista)' -f (Get-Plural $script:Updates.Count 'driver' 'drivers')); FixAction = { Show-UpdatesWindow } }))
    }
    if (-not $script:BackupBusy -and $g -and $g.Code -eq 0) {
        if (-not $b) {
            [void]$items.Add((New-HomeItem @{ Id = 'video-backup'; Kind = 'warn'; Tip = $true; Title = 'Faça backup do seu driver de vídeo'; BtnText = 'Fazer backup'; Action = { Act-MarkGood }
                Desc = 'Seu vídeo está funcionando agora. Guardando uma cópia deste driver, se algum programa ou o Windows trocar ele, é só um clique para voltar.'
                FixText = 'Fazer backup do driver de vídeo atual (cerca de 1 GB)'; FixAction = { Invoke-VideoBackup } }))
        } elseif ($b.Version -eq $g.Version -and -not $bk) {
            [void]$items.Add((New-HomeItem @{ Id = 'video-copy'; Kind = 'warn'; Tip = $true; Title = 'Faça o backup do seu driver de vídeo'; BtnText = 'Fazer backup'; Action = { Start-Backup $script:Gpu }
                Desc = 'Seu driver está salvo como referência, mas ainda sem cópia de segurança. Com o backup, dá para restaurar com um clique se algo trocar o driver.'
                FixText = 'Fazer a cópia de segurança do driver de vídeo'; FixAction = { Start-Backup $script:Gpu } }))
        }
    }
    if (-not $script:AllBusy -and -not (Get-AllBackupInfo)) {
        $dev = if ($script:SysInfo -and $script:SysInfo.IsLaptop) { 'Notebooks dependem' } else { 'Seu PC depende' }
        [void]$items.Add((New-HomeItem @{ Id = 'all-backup'; Kind = 'warn'; Tip = $true; Title = 'Guarde todos os drivers num pendrive'; BtnText = 'Fazer backup'; Action = { Act-AllBackup }
            Desc = "$dev de drivers do fabricante (chipset, Wi-Fi, áudio, touchpad) que o Windows nem sempre instala sozinho depois de formatar. Salve todos agora e reinstale com dois cliques." }))
    }
    if (-not (Test-WatchEnabled)) {
        [void]$items.Add((New-HomeItem @{ Id = 'watch-off'; Kind = 'warn'; Tip = $true; Title = 'A proteção automática está desligada'; BtnText = 'Ligar'; Action = { Act-Watch }
            Desc = 'Quando ligada, um escudo fica perto do relógio e só avisa se o driver de vídeo for trocado, a placa der erro, o PC cair ou o Driver Booster voltar. Não instala nada e não deixa o PC lento.'
            FixText = 'Ligar a proteção automática (escudo perto do relógio)'; FixAction = { Enable-Watch } }))
    }
    $items
}

$TileGlyph = @{ drivers = [string][char]0xE896; video = [string][char]0xE7F4; protecao = [string][char]0xEA18; sistema = [string][char]0xE770 }
function New-HomeTile([string]$page, [string]$label, [string]$value, [string]$kind, [string]$tip) {
    [pscustomobject]@{ Page = $page; Glyph = $TileGlyph[$page]; Label = $label; Value = $value; Kind = $kind; Color = $Hex[$kind]; Tip = $tip }
}

function Get-HomeTiles {
    $g = $script:Gpu; $b = Get-Baseline; $hl = $script:Health
    $bk = if ($b) { Get-Backup $b.Version } else { $null }
    $d = if ($script:Problems) { @((Get-Plural $script:Problems 'com problema' 'com problema'), 'bad') }
         elseif ($script:UpdState -eq 'checking') { @('Procurando...', 'info') }
         elseif ($script:UpdState -eq 'installing') { @('Atualizando...', 'info') }
         elseif ($script:Updates.Count) { @((Get-Plural $script:Updates.Count 'atualização' 'atualizações'), 'warn') }
         elseif ($script:UpdState -eq 'error') { @('Sem conexão', 'info') }
         else { @('Em dia', 'ok') }
    $v = if (-not $g) { @('Não encontrada', 'info') }
         elseif ($g.Code -ne 0) { @('Com erro', 'bad') }
         elseif ($b -and $b.Version -ne $g.Version) { @('Driver trocado', 'bad') }
         elseif ($script:BackupBusy) { @('Copiando...', 'info') }
         elseif ($bk) { @('Backup ok', 'ok') }
         else { @('Sem backup', 'warn') }
    $p = if ($hl.DriverBooster.Count) { @('Driver Booster', 'bad') }
         elseif (Test-WatchEnabled) { @('Ligada', 'ok') }
         else { @('Desligada', 'warn') }
    $s = if ($hl.Crashes) { @((Get-Plural $hl.Crashes 'queda' 'quedas'), 'bad') }
         elseif ($script:NeedReboot.Count) { @('Reiniciar', 'warn') }
         else { @('Estável', 'ok') }
    @(
        (New-HomeTile 'drivers' 'Drivers' $d[0] $d[1] 'Lista completa e atualizações oficiais'),
        (New-HomeTile 'video' 'Vídeo' $v[0] $v[1] 'Placa de vídeo e backups dos drivers'),
        (New-HomeTile 'protecao' 'Proteção' $p[0] $p[1] 'Vigia automático e socorro do vídeo'),
        (New-HomeTile 'sistema' 'Sistema' $s[0] $s[1] 'Quedas do PC nos últimos 30 dias e reinícios pendentes')
    )
}

# ---------------------------------------------------------------- desenho

$script:HomeItems = @(); $script:HomeTileData = @(); $script:HomeActions = @{}
$script:HomeDetails = $false; $script:HomeOverride = @(); $script:FixPrimary = $null
function Get-Vis([bool]$on) { if ($on) { 'Visible' } else { 'Collapsed' } }

# objeto que o FindingTpl desenha; a ação fica guardada à parte e é achada pelo Tag do botão
function ConvertTo-HomeView($item, [bool]$withDesc, [bool]$withButtons = $true) {
    $col = $Hex[$item.Kind]
    $act = $withButtons -and $item.BtnText -and $item.Action
    if ($act) { $script:HomeActions[$item.Id] = $item.Action }
    [pscustomobject]@{
        Title = $item.Title; Desc = $item.Desc; Glyph = $Glyph[$item.Kind]; Color = $col; Halo = ('#26' + $col.Substring(1))
        DescShown = (Get-Vis ($withDesc -and $item.Desc)); TipOn = (-not $withDesc -and [bool]$item.Desc)
        BtnText = $item.BtnText; ActTag = ('act|' + $item.Id); BtnShown = (Get-Vis $act); Accent = ($item.Kind -eq 'bad')
        IgnoreTag = ('ignore|' + $item.IgnoreKey); IgnoreShown = (Get-Vis ($withButtons -and $item.Tip))
    }
}

function Update-HomeBusy {
    $busy = @()
    if ($script:BackupBusy) { $busy += 'Fazendo backup do driver de vídeo...' }
    if ($script:AllBusy) { $busy += 'Salvando todos os drivers...' }
    $HomeBusy.Text = $busy -join '  •  '
    $HomeBusy.Visibility = Get-Vis ([bool]$HomeBusy.Text)
    if ($script:UpdState -in 'checking', 'installing') {
        $HomeProgress.Text = $(if ($script:Prog.Text) { $script:Prog.Text } else { 'Procurando atualizações de driver...' })
        $script:ProgRun = $HomeProgress
    } else {
        $HomeProgress.Text = ''
        if (-not $script:Scanning) { $script:ProgRun = $null }
    }
    $HomeProgress.Visibility = Get-Vis ([bool]$HomeProgress.Text)
}

function Show-Home {
    $script:HomeActions = @{}; $script:FixPrimary = $null
    $HomeTiles.ItemsSource = $script:HomeTileData
    $problems = @($script:HomeItems | Where-Object { -not $_.Tip })
    $tips = @($script:HomeItems | Where-Object { $_.Tip })
    $shown = if ($script:HomeDetails) { $problems } else { @($problems | Select-Object -First 3) }
    $ProblemsList.ItemsSource = @($shown | ForEach-Object { ConvertTo-HomeView $_ $script:HomeDetails })
    $DetailsList.ItemsSource = @($tips | ForEach-Object { ConvertTo-HomeView $_ $true })
    $DetailsPanel.Visibility = Get-Vis ($script:HomeDetails -and $tips.Count)
    $hidden = $problems.Count - $shown.Count + $tips.Count
    $BtnDetails.Content = $(if ($script:HomeDetails) { 'Ocultar detalhes' } else { 'Ver detalhes ({0})' -f $hidden })
    $BtnDetails.Visibility = Get-Vis ($script:HomeDetails -or $hidden -gt 0)

    # botão principal: corrige tudo o que é seguro; sem isso, resolve o primeiro problema grave
    $fix = @($script:HomeItems | Where-Object { $_.FixAction })
    $first = @($problems | Where-Object { $_.Kind -eq 'bad' -and $_.Action })[0]
    if ($fix.Count) { $BtnFixAll.Content = 'Corrigir tudo ({0})' -f $fix.Count }
    elseif ($first) { $BtnFixAll.Content = $first.BtnText; $script:FixPrimary = $first.Action }
    $BtnFixAll.Visibility = Get-Vis ($fix.Count -or $first)
    $FixBar.Visibility = Get-Vis ($BtnFixAll.Visibility -eq 'Visible' -or $BtnDetails.Visibility -eq 'Visible')
    Update-HomeBusy
}

function Update-Home {
    if (-not $script:LastScan) { return }
    $script:HomeOverride = @()
    $ign = @(Get-HomeIgnored)
    $script:HomeItems = @(Get-HomeItems | Where-Object { -not $_.Tip -or $ign -notcontains $_.IgnoreKey })
    $problems = @($script:HomeItems | Where-Object { -not $_.Tip })
    $bad = @($problems | Where-Object { $_.Kind -eq 'bad' }).Count
    $warn = @($problems | Where-Object { $_.Kind -eq 'warn' }).Count
    $tips = @($script:HomeItems | Where-Object { $_.Tip }).Count
    $sub = 'Última análise às {0:HH:mm}' -f $script:LastScan
    if ($script:UpdState -eq 'done' -and -not $script:Updates.Count) { $sub += '  •  drivers em dia' }
    if ($bad) { Set-Verdict 'bad' (Get-Plural $bad 'problema encontrado' 'problemas encontrados') $sub }
    elseif ($warn) { Set-Verdict 'warn' (Get-Plural $warn 'ponto de atenção' 'pontos de atenção') $sub }
    elseif ($tips) { Set-Verdict 'ok' 'Tudo certo' ('{0}  •  {1} para ficar mais protegido' -f $sub, (Get-Plural $tips 'sugestão' 'sugestões')) }
    else { Set-Verdict 'ok' 'Tudo certo — seu PC está protegido' $sub }
    $script:HomeTileData = @(Get-HomeTiles)
    Show-Home
    Save-HomeSnapshot
}

# avisos temporários (rede de segurança do vídeo, socorro): substituem a lista até a próxima análise
function Clear-Findings {
    $script:HomeOverride = @(); $script:HomeActions = @{}
    $ProblemsList.ItemsSource = $null; $DetailsList.ItemsSource = $null
    $DetailsPanel.Visibility = 'Collapsed'; $FixBar.Visibility = 'Collapsed'
}
function Add-Finding([string]$text, [string]$desc, [string]$kind, [string]$btnText, [scriptblock]$action) {
    $script:HomeOverride += New-HomeItem @{ Id = ('temp' + $script:HomeOverride.Count); Kind = $kind; Title = $text; Desc = $desc; BtnText = $btnText; Action = $action }
    $ProblemsList.ItemsSource = @($script:HomeOverride | ForEach-Object { ConvertTo-HomeView $_ $true })
}

# ---------------------------------------------------------------- corrigir tudo e avisos ignorados

function Invoke-FixAll {
    if ($script:FixPrimary) { & $script:FixPrimary; return }
    $fix = @($script:HomeItems | Where-Object { $_.FixAction })
    if (-not $fix.Count) { return }
    $lista = (@($fix | ForEach-Object { '•   ' + $_.FixText }) -join "`n")
    $msg = "Vou fazer agora:`n`n$lista`n`nNada é removido e nenhum driver é trocado sem você escolher. Problemas que pedem decisão (restaurar driver, reiniciar) continuam com o próprio botão."
    if (-not (Show-Dialog 'Corrigir tudo' $msg 'ask' -YesNo -YesText 'Corrigir')) { return }
    foreach ($f in $fix) {
        try { & $f.FixAction } catch { Write-OperationEvent 'corrigir-tudo' 'falhou' ($f.Id + ': ' + $_.Exception.Message) }
    }
    Update-WatchButton; Update-Cards; Update-Home
}

function Get-HomeIgnored { @((Get-Settings).Ignored | Where-Object { $_ }) }
function Set-HomeIgnored([string]$key) {
    $st = Get-Settings
    $st.Ignored = @(@($st.Ignored | Where-Object { $_ }) + $key | Select-Object -Unique)
    Save-Settings $st
    Update-ConfigHome
}
function Clear-HomeIgnored {
    $st = Get-Settings; $st.Ignored = @(); Save-Settings $st
    Update-ConfigHome; Update-Home
}
function Update-ConfigHome {
    $ChkAutoScan.IsChecked = [bool](Get-Settings).AutoScan
    $n = @(Get-HomeIgnored).Count
    $ConfigIgnored.Text = $(if ($n) { '{0} na tela inicial. Eles voltam a aparecer se a situação mudar.' -f (Get-Plural $n 'aviso ignorado' 'avisos ignorados') } else { 'Nenhum aviso ignorado. Use o ✕ de uma sugestão na tela inicial para escondê-la.' })
    $BtnUnignore.IsEnabled = ($n -gt 0)
}

# ---------------------------------------------------------------- última análise guardada (aparece ao abrir o app)

$HomeSnapshotFile = Join-Path $DataDir 'last-scan.json'
function Save-HomeSnapshot {
    if (-not $script:LastScan) { return }
    $snap = [pscustomobject]@{
        Date = $script:LastScan.ToString('o'); Kind = $script:VerdictKind; Text = $VerdictText.Text
        Tiles = @($script:HomeTileData | ForEach-Object { [pscustomobject]@{ Page = $_.Page; Label = $_.Label; Value = $_.Value; Kind = $_.Kind; Tip = $_.Tip } })
        Problems = @($script:HomeItems | Where-Object { -not $_.Tip } | ForEach-Object { [pscustomobject]@{ Kind = $_.Kind; Title = $_.Title; Desc = $_.Desc } })
    }
    try { Save-Json $snap $HomeSnapshotFile 4 } catch { }
}
function Format-When([datetime]$when) {
    if ($when.Date -eq (Get-Date).Date) { 'hoje às {0:HH:mm}' -f $when }
    elseif ($when.Date -eq (Get-Date).Date.AddDays(-1)) { 'ontem às {0:HH:mm}' -f $when }
    else { '{0:dd/MM} às {0:HH:mm}' -f $when }
}
function Restore-HomeSnapshot {
    if (-not (Test-Path $HomeSnapshotFile)) { return $false }
    try { $s = Get-Content $HomeSnapshotFile -Raw | ConvertFrom-Json; $when = [datetime]$s.Date } catch { return $false }
    if (-not $Hex.ContainsKey("$($s.Kind)")) { return $false }
    Set-Verdict $s.Kind $s.Text ('Resultado da análise de {0}' -f (Format-When $when))
    $HomeTiles.ItemsSource = @($s.Tiles | Where-Object { $TileGlyph.ContainsKey("$($_.Page)") -and $Hex.ContainsKey("$($_.Kind)") } |
        ForEach-Object { New-HomeTile $_.Page $_.Label $_.Value $_.Kind $_.Tip })
    $ProblemsList.ItemsSource = @($s.Problems | Where-Object { $Hex.ContainsKey("$($_.Kind)") } | Select-Object -First 3 |
        ForEach-Object { ConvertTo-HomeView (New-HomeItem @{ Kind = $_.Kind; Title = $_.Title; Desc = $_.Desc }) $false $false })
    $true
}

# ---------------------------------------------------------------- navegação: barra lateral única + abas

$PageGroup = [ordered]@{ drivers = 'NavDrivers'; video = 'NavDrivers'; windows = 'NavDrivers'; protecao = 'NavGuard'; sistema = 'NavTools'; limpeza = 'NavTools'; extras = 'NavTools' }
$PageParts = @{ drivers = 'TabDrivers,PanDrivers'; video = 'TabVideo,PanVideo'; windows = 'TabWin,PanWin'; protecao = ',PanGuard'
    sistema = 'TabSystem,PanSystem'; limpeza = 'TabClean,PanClean'; extras = 'TabExtras,PanExtras' }
$NavNames = 'NavHome', 'NavDrivers', 'NavGuard', 'NavTools', 'NavSettings'
$script:Page = 'home'

function Show-Page([string]$page) {
    if ($page -notin 'home', 'config' -and -not $PageGroup.Contains($page)) { $page = 'drivers' }
    $script:Page = $page
    $nav = switch ($page) { 'home' { 'NavHome' } 'config' { 'NavSettings' } default { $PageGroup[$page] } }
    foreach ($n in $NavNames) { (Get-Variable $n -Scope Script -ValueOnly).IsChecked = ($n -eq $nav) }
    $HomeView.Visibility = Get-Vis ($page -eq 'home')
    $ConfigView.Visibility = Get-Vis ($page -eq 'config')
    foreach ($k in $PageGroup.Keys) {
        $tab, $pan = $PageParts[$k] -split ','
        (Get-Variable $pan -Scope Script -ValueOnly).Visibility = Get-Vis ($k -eq $page)
        if ($tab) {
            $t = Get-Variable $tab -Scope Script -ValueOnly
            $t.IsChecked = ($k -eq $page); $t.Visibility = Get-Vis ($PageGroup[$k] -eq $nav)
        }
    }
    $TabBar.Visibility = Get-Vis ($nav -in 'NavDrivers', 'NavTools')
    switch ($page) {
        'drivers' { if (-not $script:LastScan -and -not $script:Scanning) { Start-Scan } }
        'windows' { Start-WuCheck }
        'sistema' { Update-StorageInfo }
        'limpeza' { Update-CleanDrive; if (-not $CleanGrid.ItemsSource) { Start-CleanScan } }
        'config' { Update-ConfigHome }
    }
}

$script:RailOpen = $true
$RailItems = 'BtnRail', 'NavHome', 'NavDrivers', 'NavGuard', 'NavTools', 'NavSettings'
$RailText = @{}
function Set-Rail([bool]$open) {
    $script:RailOpen = $open
    if (-not $RailText.Count) { foreach ($n in $RailItems) { $RailText[$n] = (Get-Variable $n -Scope Script -ValueOnly).Content } }
    foreach ($n in $RailItems) {
        $b = Get-Variable $n -Scope Script -ValueOnly
        $b.Content = $(if ($open) { $RailText[$n] } else { '' })
        $b.ToolTip = $(if ($open) { $null } else { $RailText[$n] })
    }
    $RailCol.Width = $(if ($open) { 228 } else { 64 })
    $RailBox.Margin = $(if ($open) { '14,18,14,14' } else { '6,18,6,14' })
    $LogoText.Visibility = Get-Vis $open
    $BtnRail.ToolTip = $(if ($open) { $null } else { 'Expandir menu' })
}

# ---------------------------------------------------------------- eventos da tela inicial

$HomeClick = [Windows.RoutedEventHandler] { param($s, $e)
    $b = $e.OriginalSource -as [Windows.Controls.Button]
    if (-not $b -or -not $b.Tag) { return }
    $what, $id = "$($b.Tag)" -split '\|', 2
    if ($what -eq 'ignore') { Set-HomeIgnored $id; Update-Home; return }
    $a = $script:HomeActions[$id]
    if ($a) { & $a }
}
$ProblemsList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, $HomeClick)
$DetailsList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, $HomeClick)
$HomeTiles.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] { param($s, $e)
    $b = $e.OriginalSource -as [Windows.Controls.Button]
    if ($b -and $b.Tag) { Show-Page "$($b.Tag)" }
})
$BtnFixAll.add_Click({ Invoke-FixAll })
$BtnDetails.add_Click({ $script:HomeDetails = -not $script:HomeDetails; Show-Home })
$NavHome.add_Click({ Show-Page 'home' })
$NavDrivers.add_Click({ Show-Page 'drivers' })
$NavGuard.add_Click({ Show-Page 'protecao' })
$NavTools.add_Click({ Show-Page 'sistema' })
$NavSettings.add_Click({ Show-Page 'config' })
$BtnRail.add_Click({ Set-Rail (-not $script:RailOpen) })
foreach ($t in $TabDrivers, $TabVideo, $TabWin, $TabSystem, $TabClean, $TabExtras) { $t.add_Click({ param($s, $e) Show-Page "$($s.Tag)" }) }
$ChkAutoScan.add_Click({ $st = Get-Settings; $st.AutoScan = [bool]$ChkAutoScan.IsChecked; Save-Settings $st })
$BtnUnignore.add_Click({ Clear-HomeIgnored })
