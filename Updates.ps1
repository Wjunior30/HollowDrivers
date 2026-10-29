# Atualização de drivers pelo Catálogo do Microsoft Update, Windows Update e pontos de restauração.


$UpdXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Atualizações de driver" Width="980" Height="520" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="{StaticResource Bg}" Foreground="{StaticResource Text}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13">
  <Grid Margin="22,18,22,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="Head" FontSize="19" FontWeight="SemiBold" FontFamily="{StaticResource Display}"/>
    <TextBlock Grid.Row="1" Foreground="{StaticResource Dim}" TextWrapping="Wrap" Margin="0,6,0,0"
               Text="Drivers certificados pela Microsoft, baixados do servidor oficial do Windows Update. Antes de instalar é criado um ponto de restauração. O driver de vídeo e o firmware (BIOS) não entram aqui de propósito."/>
    <Border Grid.Row="2" Margin="0,14,0,14" Background="{StaticResource Surface}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="14" Padding="4">
      <DataGrid x:Name="G" AutoGenerateColumns="False" IsReadOnly="False">
        <DataGrid.Columns>
          <DataGridTemplateColumn Header="" Width="46">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate><CheckBox IsChecked="{Binding Instalar, UpdateSourceTrigger=PropertyChanged}" HorizontalAlignment="Center"/></DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTextColumn Header="Dispositivo" Binding="{Binding Dispositivo}" Width="*" IsReadOnly="True"/>
          <DataGridTextColumn Header="Versão atual" Binding="{Binding Atual}" Width="140" IsReadOnly="True"/>
          <DataGridTextColumn Header="Nova versão" Binding="{Binding Nova}" Width="140" IsReadOnly="True"/>
          <DataGridTextColumn Header="Data" Binding="{Binding Data}" Width="95" IsReadOnly="True"/>
          <DataGridTextColumn Header="Tamanho" Binding="{Binding Tamanho}" Width="85" IsReadOnly="True"/>
        </DataGrid.Columns>
      </DataGrid>
    </Border>
    <DockPanel Grid.Row="3">
      <Button x:Name="Install" DockPanel.Dock="Right" Style="{StaticResource PillAccent}" Content="Instalar selecionados" Margin="10,0,0,0"/>
      <Button x:Name="Close" DockPanel.Dock="Right" Style="{StaticResource Pill}" Content="Agora não" Margin="0" IsCancel="True"/>
      <TextBlock x:Name="Note" Foreground="{StaticResource Dim}" VerticalAlignment="Center" TextWrapping="Wrap"/>
    </DockPanel>
  </Grid>
</Window>
'@

$script:UpdState = 'idle'; $script:Updates = @(); $script:AfterUpdate = $null

function Start-UpdateCheck {
    if ($script:UpdState -in 'checking', 'installing') { return }
    $script:UpdState = 'checking'; $script:Prog.Text = 'Consultando o Catálogo do Microsoft Update...'
    $BtnUpd.IsEnabled = $false; $BtnUpd.Content = 'Procurando atualizações...'
    Update-Home
    Start-Bg ($LogicText + "`nGet-DriverUpdates") {
        param($out, $err)
        $BtnUpd.IsEnabled = $true; $BtnUpd.Content = 'Atualizar drivers'
        $script:Updates = @($out | Where-Object { $_ })
        $script:UpdState = if ($err -and -not $script:Updates.Count) { 'error' } else { 'done' }
        $st = Get-State; $st.LastUpd = (Get-Date).ToString('o'); $st.UpdKey = (@($script:Updates.Id) -join '|'); Save-State $st
        Update-Home
    }
}

function Act-Updates {
    if ($script:UpdState -eq 'checking') { return }
    if ($script:UpdState -ne 'done') { Start-UpdateCheck; return }
    Show-UpdatesWindow
}

function Show-UpdatesWindow {
    $ups = @($script:Updates)
    if (-not $ups.Count) { [void](Show-Dialog 'Drivers em dia' 'Não há versões mais novas no Catálogo do Microsoft Update para os drivers deste PC.' 'ok'); return }
    $w = [Windows.Markup.XamlReader]::Parse($UpdXaml)
    $w.FindName('Head').Text = (Get-Plural $ups.Count 'atualização de driver disponível' 'atualizações de driver disponíveis')
    $t = New-Object Data.DataTable
    [void]$t.Columns.Add('Instalar', [bool])
    foreach ($n in 'Dispositivo', 'Atual', 'Nova', 'Data', 'Tamanho', 'Id') { [void]$t.Columns.Add($n) }
    foreach ($u in $ups) { [void]$t.Rows.Add($true, $u.Dispositivo, $u.Atual, $u.Nova, $u.Data, $u.Tamanho, $u.Id) }
    $w.FindName('G').ItemsSource = $t.DefaultView
    $w.FindName('Note').Text = 'Desmarque o que não quiser atualizar.'
    $w.FindName('Install').add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
    $w.FindName('Close').add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).Close() })
    $w.add_SourceInitialized({ param($s, $e) Set-DarkTitle $s })
    $w.Owner = $script:Win
    if (-not $w.ShowDialog()) { return }
    foreach ($v in $t.DefaultView) { $v.EndEdit() }
    $ids = @($t.Rows | Where-Object { $_['Instalar'] } | ForEach-Object { $_['Id'] })
    if (-not $ids.Count) { return }
    Start-UpdateInstall @($ups | Where-Object { $_.Id -in $ids })
}

function Start-UpdateInstall($list) {
    $mb = 0; foreach ($u in $list) { if ($u.Tamanho -match '([\d\.,]+) ([KMG])B') { $v = [double]($matches[1] -replace ',', '.'); $mb += switch ($matches[2]) { 'K' { $v / 1024 } 'G' { $v * 1024 } default { $v } } } }
    $msg = "Vou:`n`n1.   Guardar uma cópia dos drivers que estão no PC agora`n2.   Baixar {0} ({1:N0} MB) do servidor oficial da Microsoft e conferir a assinatura digital`n3.   Criar um ponto de restauração do Windows`n4.   Instalar os drivers`n`nSe a versão nova não prestar, dá para voltar pelo botão Restaurar. O Windows vai pedir permissão de administrador." -f (Get-Plural $list.Count 'driver' 'drivers'), [math]::Max(1, $mb)
    $msg += "`n`nSe alguma tela apagar durante a instalação, NÃO desligue o PC: o HollowDrivers tem cópia do driver anterior e consegue voltar."
    if (-not (Show-Dialog 'Atualizar drivers' $msg 'ask' -YesNo -YesText 'Atualizar')) { return }
    $dir = Join-Path $DataDir ('updates\{0:yyyyMMdd-HHmmss}' -f (Get-Date))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $script:UpdDir = $dir; $script:UpdList = @($list)
    $script:UpdState = 'installing'; $script:Prog.Text = 'Preparando download...'
    $BtnUpd.IsEnabled = $false; $BtnUpd.Content = 'Atualizando drivers...'
    Update-Home
    # Antes de instalar, exige um dispositivo identificavel para cada driver ja instalado.
    $devices = @()
    foreach ($u in $script:UpdList) {
        if ($u.Atual -eq 'sem driver') { continue }
        $d = Get-DeviceForHw $u.Hw
        if (-not $d -or -not $d.Inf) {
            Stop-PreBackup ('Nao foi possivel identificar o driver atual de ' + $u.Dispositivo + ' para fazer backup.')
            return
        }
        $devices += $d
    }
    Start-PreBackup $devices { Start-UpdateDownload }
}

function Start-UpdateDownload {
    $json = ConvertTo-Json -InputObject @($script:UpdList | Select-Object Id, Dispositivo) -Compress
    Start-Bg (Expand-Tpl $DlTpl @{ '__JSON__' = $json; '__DIR__' = $script:UpdDir }) {
        param($out, $err)
        $r = if ($out -and $out.Count) { $out[$out.Count - 1] } else { $null }
        $failTxt = if ($r -and @($r.Fail).Count) { "`n`nNão baixados:`n" + (@($r.Fail) -join "`n") } else { '' }
        if ($err -or -not $r -or -not @($r.Ok).Count) {
            $script:UpdState = 'done'; $BtnUpd.IsEnabled = $true; $BtnUpd.Content = 'Atualizar drivers'
            [void](Show-Dialog 'Download falhou' ("Nenhum driver foi baixado, então nada foi alterado.$failTxt`n$err") 'bad')
            Update-Home; return
        }
        $script:UpdFailTxt = $failTxt
        $script:Prog.Text = 'Instalando (aceite a permissão de administrador)...'
        $pins = ConvertTo-Json -InputObject @($r.Pins | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Files = @($_.Files | ForEach-Object { [pscustomobject]@{ P = $_.P; H = $_.H } }) } }) -Compress -Depth 5
        Invoke-Elevated $UpdTpl @{ '__DIR__' = $script:UpdDir; '__PINS__' = $pins } 'atualizar' {
            param($log, $err)
            $BtnUpd.IsEnabled = $true; $BtnUpd.Content = 'Atualizar drivers'
            $script:UpdState = 'done'
            if ($err) {
                [void](Show-Dialog 'Atualização cancelada' "O Windows não deu permissão de administrador, então nada foi instalado.`n`n$err" 'warn')
                Update-Home; return
            }
            $script:UpdLog = $log
            $script:AfterUpdate = $script:UpdList
            Start-Scan
        }
    }
}

# Depois de instalar: confere na análise nova quais drivers realmente mudaram de versão.
function Show-UpdateResult($rows) {
    $list = $script:AfterUpdate; $script:AfterUpdate = $null
    $okN = @(); $keep = @()
    foreach ($u in $list) {
        if ($rows | Where-Object { $_.Dispositivo -eq $u.Dispositivo -and $_.Versao -eq $u.Nova }) { $okN += $u.Dispositivo } else { $keep += $u.Dispositivo }
    }
    Remove-Item $script:UpdDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $okN.Count -and $script:UpdLog -match 'RC=259' -and $script:UpdLog -notmatch 'RC=(?!259)\d+') {
        Remove-Item $script:UpdDir -Recurse -Force -ErrorAction SilentlyContinue
        [void](Show-Dialog 'Seus drivers já eram os melhores' "O Windows comparou e manteve os drivers que você já tinha, porque eles são mais recentes que os do catálogo. Nada foi trocado e não precisa reiniciar.`n`nOs pacotes baixados foram removidos." 'ok')
        $script:Updates = @(); Start-UpdateCheck
        return
    }
    $txt = if ($okN.Count) { "Atualizados:`n•   " + ($okN -join "`n•   ") } else { 'Nenhum driver mudou de versão.' }
    if ($keep.Count) { $txt += "`n`nSem mudança por enquanto (o Windows pode aplicar depois de reiniciar, ou manteve a versão atual por ser a mais adequada):`n•   " + ($keep -join "`n•   ") }
    $txt += "`n`nReinicie o PC para concluir. Se algo der errado, use o ponto de restauração criado agora.$($script:UpdFailTxt)"
    [void](Show-Dialog $(if ($okN.Count) { 'Drivers atualizados' } else { 'Atualização concluída' }) $txt $(if ($okN.Count) { 'ok' } else { 'warn' }))
    $script:Updates = @()
    Start-UpdateCheck
}

# ---------------------------------------------------------------- Windows Update e pontos de restauração

function Update-WuCard {
    $w = $script:Wu
    $WuText.Inlines.Clear(); $SrText.Inlines.Clear()
    if (-not $w) {
        Add-Line $WuText 'Lendo as configurações do Windows Update...' $Hex.info 13
        Add-Line $SrText 'Lendo a proteção do sistema...' $Hex.info 13
        return
    }
    if ($w.Pausado) {
        Add-Line $WuText ('Atualizações seguradas até {0:dd/MM/yyyy}' -f $w.PausadoAte) $Hex.ok 15 $true
    } else {
        Add-Line $WuText 'Atualizações liberadas (o Windows instala quando quiser)' '#E8EAED' 15 $true
    }
    Add-Line $WuText $(if ($w.SemAuto) { '●  Download e instalação automáticos: desligados' } else { '●  Download e instalação automáticos: ligados' }) $(if ($w.SemAuto) { $Hex.ok } else { $Hex.info }) 13
    Add-Line $WuText $(if ($w.SemDriver) { '●  O Windows NÃO pode trocar seus drivers' } else { '●  O Windows pode trocar seus drivers sozinho' }) $(if ($w.SemDriver) { $Hex.ok } else { $Hex.warn }) 13
    $keep = (Get-State).WuHold -and (Test-WuTask)
    Add-Line $WuText $(if ($keep) { '●  Manter segurado: ligado — se algo liberar, o HollowDrivers segura de novo' } else { '●  Manter segurado: desligado — a pausa do Windows vence sozinha em 35 dias' }) $(if ($keep) { $Hex.ok } else { $Hex.info }) 12.5
    Add-Line $WuText 'Segurar atualização é para investigar problema, não para sempre: correção de segurança também para de chegar.' $Hex.info 12.5
    $BtnWuHold.Content = $(if ($w.Pausado) { 'Liberar atualizações' } else { 'Segurar atualizações' })
    $BtnWuDrv.Content = $(if ($w.SemDriver) { 'Deixar o Windows trocar drivers' } else { 'Bloquear troca de drivers' })
    $BtnWuKeep.Content = $(if ($keep) { 'Manter segurado: ligado' } else { 'Manter segurado: desligado' })
    $BtnWuKeep.Foreground = Get-Brush $(if ($keep) { $Hex.ok } else { $Hex.info })

    if ($null -eq $w.Pontos) {
        Add-Line $SrText 'Pontos de restauração: precisa de permissão de administrador para listar' $Hex.info 15 $true
    } elseif ($w.Pontos) {
        Add-Line $SrText (Get-Plural $w.Pontos 'ponto de restauração guardado' 'pontos de restauração guardados') $Hex.ok 15 $true
        if ($w.UltimoPonto) { Add-Line $SrText ('Último: {0:dd/MM/yyyy HH:mm}' -f $w.UltimoPonto) '#C9CED6' 13 }
    } else {
        Add-Line $SrText 'Nenhum ponto de restauração guardado' $Hex.warn 15 $true
    }
    Add-Line $SrText $(if ($w.SrLigada) { '●  Proteção do sistema: ligada' } else { '●  Proteção do sistema: DESLIGADA — o Windows não guarda nada para voltar' }) $(if ($w.SrLigada) { $Hex.ok } else { $Hex.bad }) 13
    Add-Line $SrText 'O ponto de restauração reverte alterações do sistema. Não copia seus arquivos e não protege contra falha física do disco.' $Hex.info 12.5
}

function Start-WuCheck {
    Start-Bg ($LogicText + "`nGet-WuState") {
        param($out, $err)
        $script:Wu = if ($out -and $out.Count) { $out[$out.Count - 1] } else { $null }
        Update-WuCard
    }
}

function Act-WuHold {
    $ligar = -not ($script:Wu -and $script:Wu.Pausado)
    $msg = if ($ligar) {
        "Segurar as atualizações do Windows por 35 dias (o máximo que o Windows permite)?`n`n" +
        "•   Ele para de baixar e instalar sozinho`n" +
        "•   Você continua podendo atualizar na mão quando quiser`n" +
        "•   Serve para descobrir se uma atualização é a causa de um problema`n`n" +
        "Correções de segurança também ficam de fora nesse período."
    } else {
        "Liberar as atualizações do Windows de novo?`n`nEle volta a baixar e instalar normalmente."
    }
    if (-not (Show-Dialog $(if ($ligar) { 'Segurar atualizações do Windows?' } else { 'Liberar atualizações?' }) $msg 'ask' -YesNo -YesText $(if ($ligar) { 'Segurar' } else { 'Liberar' }))) { return }
    $BtnWuHold.IsEnabled = $false
    Invoke-Elevated $WuTpl @{ '__HOLD__' = $(if ($ligar) { '1' } else { '0' }); '__DRV__' = ''; '__SR__' = ''; '__DESC__' = '' } 'windows' {
        param($log, $err)
        $BtnWuHold.IsEnabled = $true
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador, então nada mudou.' 'warn'); return }
        if ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Não foi possível' $matches[1] 'bad'); return }
        if ($log -match 'HOLD=1') { [void](Show-Dialog 'Atualizações seguradas' 'O Windows não vai mais baixar nem instalar sozinho pelos próximos 35 dias.' 'ok') }
        else { [void](Show-Dialog 'Atualizações liberadas' 'O Windows voltou ao comportamento normal.' 'ok') }
        Start-WuCheck
    }
}

function Act-WuDrv {
    $ligar = -not ($script:Wu -and $script:Wu.SemDriver)
    $msg = if ($ligar) {
        "Impedir o Windows Update de instalar drivers?`n`nAs correções de segurança continuam chegando normalmente — só a troca automática de driver (vídeo, chipset, rede) fica bloqueada.`n`nÉ o ajuste que evita o Windows trocar o driver da sua placa de vídeo sem avisar."
    } else {
        "Deixar o Windows Update instalar drivers de novo?`n`nEle volta a poder trocar driver de vídeo e outros sozinho."
    }
    if (-not (Show-Dialog 'Drivers pelo Windows Update' $msg 'ask' -YesNo -YesText $(if ($ligar) { 'Bloquear' } else { 'Liberar' }))) { return }
    $BtnWuDrv.IsEnabled = $false
    Invoke-Elevated $WuTpl @{ '__HOLD__' = ''; '__DRV__' = $(if ($ligar) { '1' } else { '0' }); '__SR__' = ''; '__DESC__' = '' } 'windows' {
        param($log, $err)
        $BtnWuDrv.IsEnabled = $true
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador, então nada mudou.' 'warn'); return }
        if ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Não foi possível' $matches[1] 'bad'); return }
        Start-WuCheck
    }
}

function Act-WuKeep {
    $st = Get-State
    $ligar = -not ($st.WuHold -and (Test-WuTask))
    if ($ligar) {
        $msg = "Manter as atualizações seguradas mesmo depois?`n`n" +
            "A pausa do Windows vence sozinha em 35 dias, e uma atualização grande pode religar tudo. Com isto ligado, o HollowDrivers confere ao ligar o PC e uma vez por dia — se estiver liberado, segura de novo.`n`n" +
            "Para isso é criada uma tarefa do Windows. Ela só faz isso e nada mais. O Windows vai pedir permissão de administrador agora."
        if (-not (Show-Dialog 'Manter segurado?' $msg 'ask' -YesNo -YesText 'Ligar')) { return }
    } else {
        if (-not (Show-Dialog 'Parar de manter segurado?' "A pausa atual continua valendo até vencer, mas o HollowDrivers não vai mais renovar." 'ask' -YesNo -YesText 'Desligar')) { return }
    }
    $run = if (Test-Path $Exe) { $Exe } else { 'powershell.exe' }
    $args = if (Test-Path $Exe) { '-HoldWU' } else { '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -HoldWU' -f $ScriptPath }
    $BtnWuKeep.IsEnabled = $false
    Invoke-Elevated $TaskTpl @{ '__ON__' = $(if ($ligar) { '1' } else { '0' }); '__TASK__' = $WuTask; '__DAILY__' = '1'
        '__RUN__' = $run; '__ARGS__' = $args; '__USER__' = "$env:USERDOMAIN\$env:USERNAME" } 'tarefa' {
        param($log, $err)
        $BtnWuKeep.IsEnabled = $true
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador, então nada mudou.' 'warn'); return }
        if ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Não foi possível' $matches[1] 'bad'); return }
        $st = Get-State; $st.WuHold = [bool]($log -match 'TAREFA=criada'); Save-State $st
        Update-WuCard
        if ($st.WuHold -and -not ($script:Wu -and $script:Wu.Pausado)) { Act-WuHold }
    }
}

function Act-SrPoint {
    $msg = "Criar um ponto de restauração agora?`n`n" +
        "•   Guarda drivers, programas e configurações do jeito que estão hoje`n" +
        "•   Se uma atualização ou driver quebrar o PC, dá para voltar para este momento`n" +
        "•   Seus arquivos pessoais não entram e não são alterados`n`n" +
        "Se a Proteção do Sistema estiver desligada, ela é ligada antes. O Windows vai pedir permissão de administrador."
    if (-not (Show-Dialog 'Criar ponto de restauração?' $msg 'ask' -YesNo -YesText 'Salvar')) { return }
    $BtnSrPoint.IsEnabled = $false; $BtnSrPoint.Content = 'Salvando...'
    Invoke-Elevated $WuTpl @{ '__HOLD__' = ''; '__DRV__' = ''; '__SR__' = '1'
        '__DESC__' = ('HollowDrivers {0:dd/MM/yyyy HH:mm}' -f (Get-Date)) } 'windows' {
        param($log, $err)
        $BtnSrPoint.IsEnabled = $true; $BtnSrPoint.Content = 'Criar ponto de restauração'
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador, então nada mudou.' 'warn'); return }
        if ($log -match 'PONTO=ok') { [void](Show-Dialog 'Ponto de restauração salvo' 'Ponto de restauração criado. Se algo quebrar o PC, use "Restaurar o Windows" e escolha este ponto.' 'ok') }
        elseif ($log -match 'PONTO=aviso: (.+)') { [void](Show-Dialog 'Já existe um recente' ("O Windows só cria um ponto a cada 24 horas e já existe um recente — você está protegido.`n`n" + $matches[1].Trim()) 'info') }
        elseif ($log -match 'PONTO=falhou: (.+)') { [void](Show-Dialog 'Não foi possível' ("Detalhe: " + $matches[1].Trim()) 'warn') }
        else { [void](Show-Dialog 'Sem resposta' 'Não foi possível confirmar o resultado.' 'warn') }
        Start-WuCheck
    }
}

function Act-SrOpen {
    if (-not (Show-Dialog 'Restaurar o Windows' "Vou abrir a Restauração do Sistema do Windows.`n`nLá você escolhe um dos pontos salvos e o PC reinicia para voltar àquele momento. Drivers, programas e configurações voltam; seus arquivos pessoais ficam como estão." 'ask' -YesNo -YesText 'Abrir')) { return }
    try { Start-Process 'rstrui.exe' } catch { [void](Show-Dialog 'Não foi possível abrir' $_.Exception.Message 'bad') }
}
