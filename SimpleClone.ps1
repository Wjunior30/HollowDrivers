# Interface guiada: opera apenas arquivos de instrucoes e abre ferramentas oficiais.
function Get-ClonePreference {
    if (-not $DataDir) { return $null }
    $path=Join-Path $DataDir 'clone-preferences.json'
    if(Test-Path -LiteralPath $path){try{Get-Content -LiteralPath $path -Raw | ConvertFrom-Json}catch{$null}}
}

function Get-SimpleCloneAssessment($Inventory, $Target) {
    $reason = Get-CloneBlockReason $Inventory.Source $Target $Inventory.Disks -AllowSmaller
    if ($Target -and $Target.Size -lt $Inventory.Source.Size -and $null -ne $Inventory.UsedWindows) {
        if (($Inventory.UsedWindows + 10GB) -ge $Target.Size) { $reason += ' Espaço insuficiente para C: e a margem mínima de 10 GiB. Use outro destino.' }
    }
    $smaller=$Target -and $Target.Size -lt $Inventory.Source.Size
    if($smaller -and $null -eq $Inventory.UsedWindows){$reason+=' Não foi possível medir o espaço ocupado em C:.'}
    [pscustomobject]@{ Allowed = -not [bool]$reason; Migration=$smaller; Message = $(if ($reason) { $reason } elseif($smaller){ 'Candidato para migração pelo DiskGenius. Ajuste somente o DESTINO; não reduza C:. A ferramenta externa deve validar todas as partições. O destino será apagado.' } else { 'Compatível em tamanho com a cópia de disco inteiro. O destino será apagado; a ferramenta externa ainda precisa validar o layout.' }) }
}

function Save-SimpleCloneGuide($Inventory, $Target, [string]$Path) {
    $assessment = Get-SimpleCloneAssessment $Inventory $Target
    if (-not $assessment.Allowed) { throw $assessment.Message }
    $htmlEscape = { param($text) [Net.WebUtility]::HtmlEncode([string]$text) }
    $src = & $htmlEscape $Inventory.Source.Label
    $dst = & $htmlEscape $Target.Label
    $srcSerial = & $htmlEscape $Inventory.Source.Serial
    $dstSerial = & $htmlEscape $Target.Serial
    $html = @"
<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Seu roteiro de clonagem — HollowDrivers</title>
<style>body{font:17px/1.6 system-ui,sans-serif;max-width:850px;margin:40px auto;padding:0 24px;color:#202631}h1{line-height:1.2}h2{margin-top:32px}.card{padding:20px;background:#f3f5f7;border-radius:12px}.warn{border-left:5px solid #cb6600;padding-left:18px}small{color:#536171}@media print{button{display:none}body{margin:0;max-width:none}}</style>
<button onclick="window.print()">Imprimir / salvar como PDF</button>
<h1>Seu segundo disco, passo a passo</h1><p><strong>Preparação apenas: a cópia e o teste de inicialização ainda não foram feitos.</strong></p>
<div class="card"><strong>ORIGEM — preservar</strong><br>$src<br>Serial: $srcSerial<br><br><strong>DESTINO — será apagado</strong><br>$dst<br>Serial: $dstSerial</div>
<h2>1. Preparar o pendrive</h2><ol><li>Salve os arquivos importantes do destino e de um pendrive separado. Não use o disco de destino como pendrive de inicialização.</li><li>Baixe a imagem ISO estável de 64 bits no <a href="https://rescuezilla.com/download">site oficial do Rescuezilla</a> e o <a href="https://rufus.ie/pt_BR/">Rufus</a>.</li><li>Abra o Rufus. Em <strong>Dispositivo</strong>, selecione somente o pendrive. Em <strong>Selecionar</strong>, escolha a ISO do Rescuezilla. Confira o dispositivo e clique em <strong>Iniciar</strong>. O Rufus apagará o pendrive. Siga os padrões compatíveis com a ISO e o modo de boot do seu PC.</li><li>Fotografe ou imprima este roteiro: ele não aparece automaticamente depois de reiniciar. Não é necessário copiar scripts ou usar uma segunda mídia.</li></ol>
<h2>2. Copiar pelas telas do Rescuezilla</h2><ol><li>Se houver BitLocker, guarde a chave de recuperação fora do computador. Não prossiga se a ferramenta indicar criptografia não suportada. Este roteiro não desativa a proteção.</li><li>Feche os programas e use <strong>Reiniciar</strong>. Abra o menu de inicialização do fabricante (frequentemente F12, F11 ou Esc) e escolha o pendrive no modo UEFI/Legacy adequado. Não use hibernação.</li><li>No Rescuezilla, escolha <strong>Clone / Clonar</strong>. Selecione o disco de origem identificado acima, depois o destino. Os nomes e números dos discos podem mudar; compare modelo, capacidade e serial.</li><li>Copie o disco inteiro, com todas as partições. Confirme o resumo somente se o destino correto estiver indicado. <strong>Todo o destino será apagado.</strong></li><li>Aguarde o término, sem interromper a energia. Se houver falha, preserve o original e não considere o clone pronto.</li></ol>
<h2>3. Confirmar que funciona</h2><ol><li>Desligue o PC. Desconecte o disco original com o computador desligado e teste o destino na conexão interna apropriada. O Windows instalado pode não iniciar por USB.</li><li>Confirme que Windows, programas e arquivos abrem. Só depois desse teste considere o clone pronto. Alguns programas podem pedir reativação.</li><li>Guarde o clone desconectado. Ele guarda a data da cópia: novos arquivos e programas exigem uma nova clonagem.</li></ol>
<p class="warn">Arquivos e programas instalados em outros discos não entram nesta cópia. Capacidade compatível não comprova saúde do disco nem inicialização. O HollowDrivers não acompanha nem valida automaticamente o trabalho executado no Rescuezilla.</p>
<small>Não há ajuste automático para discos menores neste fluxo. Consulte a <a href="https://rescuezilla.com/help">documentação do Rescuezilla</a> para layouts especiais. Roteiro gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm').</small></html>
"@
    if($assessment.Migration){
        $html=@"
<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Migração HollowDrivers</title><style>body{max-width:850px;margin:40px auto;font:18px/1.6 system-ui;padding:20px}strong{color:#9c4800}</style><h1>Migração para disco menor</h1><p>ORIGEM: $src — serial $srcSerial<br>DESTINO: $dst — serial $dstSerial</p><p><strong>Preparação apenas. Todo o destino será apagado. O C: original não deve ser reduzido nem movido.</strong></p><ol><li>Baixe o <a href="https://www.diskgenius.com/download.php">DiskGenius oficial</a>. Salve os arquivos importantes do destino.</li><li>Abra OS Migration / Migração do Sistema. Selecione o DESTINO pelo modelo, tamanho e serial acima.</li><li>Em Gerenciar Partições, inclua ESP, MSR, Windows e recuperação. Ajuste o tamanho somente na representação do DESTINO. Dados em outros discos não são incluídos.</li><li>Deixe desmarcada a opção de alterar a ordem de inicialização. Confira o resumo e confirme o apagamento do destino somente quando estiver correto.</li><li>Salve trabalhos abertos e escolha Migração Ativa. Não interrompa a cópia. Se a ferramenta recusar o layout, pare; não force nem redimensione o original.</li><li>Após concluir sem erros, desligue e teste a inicialização pelo destino com o original desconectado. Só registre o teste como concluído após verificar Windows, programas e arquivos.</li></ol><p>Se houver BitLocker, conserve sua chave de recuperação fora do PC e siga as restrições da ferramenta. A cópia não é sincronizada automaticamente. O HollowDrivers não executa nem certifica a migração externa.</p><a href="https://www.diskgenius.com/manual/system-migration.php">Manual oficial</a></html>
"@
    }
    [IO.File]::WriteAllText($Path, $html, (New-Object Text.UTF8Encoding $true))
    Save-CloneProgress $Inventory $Target 'roteiro preparado'
}

function Get-CloneProgress($Inventory,$Target) {
    if(-not $DataDir -or -not $Target){return $null}
    try {
        $entry=Get-Content -LiteralPath (Join-Path $DataDir 'clone-progress.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        if($entry.SourceSerial -eq $Inventory.Source.Serial -and $entry.TargetSerial -eq $Target.Serial){return $entry}
    }catch{}
    return $null
}
function Save-CloneProgress($Inventory,$Target,[string]$Status) {
    if(-not $DataDir){return}
    $previous=Get-CloneProgress $Inventory $Target
    if($Status -eq 'roteiro preparado' -and $previous){return}
    if($Status -eq 'boot testado pelo usuário' -and (-not $previous -or $previous.Status -eq 'roteiro preparado')){throw 'Registre primeiro a conclusão da cópia.'}
    $entry=[ordered]@{Date=(Get-Date).ToString('o');Status=$Status;SourceSerial=$Inventory.Source.Serial;TargetSerial=$Target.Serial;Target=$Target.Label;Verification='declarado pelo usuário; não validado automaticamente'}
    $path=Join-Path $DataDir 'clone-progress.json'
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $entry|ConvertTo-Json|Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
    if(Get-Command Write-OperationEvent -ErrorAction SilentlyContinue){Write-OperationEvent 'clone externo' $Status $Target.Label}
}

function Update-SimpleClonePage($Window) {
    $state = $Window.Tag
    $record=Get-CloneProgress $state.Inventory $Window.FindName('Target').SelectedItem
    $Window.FindName('SavedStatus').Text=if($record){'Último registro: '+$record.Status+' — '+([datetime]$record.Date).ToString('dd/MM/yyyy HH:mm')+'. Informado pelo usuário; não é uma verificação automática.'}else{'Sem cópia ou teste registrado para estes discos.'}
    $Window.FindName('BootDone').IsEnabled=[bool]($record -and $record.Status -ne 'roteiro preparado')
    foreach ($i in 1..3) { $Window.FindName("Step$i").Visibility = if ($i -eq $state.Step) { 'Visible' } else { 'Collapsed' } }
    $migration=(Get-SimpleCloneAssessment $state.Inventory $Window.FindName('Target').SelectedItem).Migration
    $Window.FindName('Migration').Visibility=if($state.Step -eq 2 -and $migration){'Visible'}else{'Collapsed'}
    if($state.Step -eq 2 -and $migration){$Window.FindName('Step2').Visibility='Collapsed'}
    $Window.FindName('Progress').Text = "ETAPA $($state.Step) DE 3  ·  " + @('Escolher o disco','Preparar o pendrive','Clonar e testar')[$state.Step-1]
    $Window.FindName('Back').IsEnabled = $state.Step -gt 1
    $Window.FindName('Next').Visibility = if ($state.Step -lt 3) { 'Visible' } else { 'Collapsed' }
    $Window.FindName('Next').IsEnabled = if ($state.Step -eq 1) { (Get-SimpleCloneAssessment $state.Inventory $Window.FindName('Target').SelectedItem).Allowed } elseif($migration){[bool]$Window.FindName('MigrationReady').IsChecked}else { [bool]$Window.FindName('UsbReady').IsChecked }
    if($migration){$Window.FindName('Progress').Text="ETAPA $($state.Step) DE 3 · Migração para disco menor (ferramenta externa)"}
    $Window.FindName('CopyInstructions').Text=if($migration){'No DiskGenius, use OS Migration. Selecione o destino pelo modelo e serial, inclua as partições de boot e recuperação e ajuste SOMENTE o destino. Mantenha a ordem de boot original e use Migração Ativa. O destino será apagado.'}else{'Reinicie pelo pendrive e escolha Clone no Rescuezilla. Confira origem, destino e todas as partições. O destino será apagado.'}
}

function Show-CloneAssistant {
    try { $inventory = Get-CloneInventory } catch {
        [void](Show-Dialog 'Não consegui consultar os discos' ($_.Exception.Message + "`nTente abrir o aplicativo como administrador.") 'warn'); return
    }
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Preparar segundo disco — HollowDrivers" Width="840" Height="740" MinWidth="720" MinHeight="650" WindowStartupLocation="CenterOwner" Background="#12151B" Foreground="#ECE7DD" FontFamily="Segoe UI" FontSize="14">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="16,10"/><Setter Property="Margin" Value="0,0,10,8"/><Setter Property="Background" Value="#303744"/><Setter Property="Foreground" Value="#FFFFFF"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Bg" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bg" Property="Background" Value="#536078"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
  <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#ECE7DD"/></Style>
 </Window.Resources>
 <Grid Margin="28"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Margin="0,0,0,20"><TextBlock Text="Seu Windows em um segundo disco" FontSize="26" FontWeight="SemiBold"/><TextBlock x:Name="Progress" Foreground="#F5B65C" Margin="0,10,0,0"/></StackPanel>
  <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel>
   <StackPanel x:Name="Step1">
    <TextBlock Text="O que será copiado" FontSize="19" FontWeight="SemiBold"/>
    <TextBlock x:Name="Source" Margin="0,8,0,8"/><TextBlock x:Name="Usage" Foreground="#AAB4C4" Margin="0,0,0,18"/>
    <TextBlock Text="Escolha o disco que receberá a cópia" FontSize="19" FontWeight="SemiBold"/>
    <ComboBox x:Name="Target" DisplayMemberPath="Label" MinHeight="36" Margin="0,10,0,12"/>
    <Border Background="#292018" CornerRadius="8" Padding="16"><TextBlock x:Name="Eligibility" Foreground="#FFD396"/></Border>
    <TextBlock Text="Windows, drivers, programas e arquivos do disco de origem entram na cópia. Dados de outros discos não entram." Margin="0,16,0,14" Foreground="#AAB4C4"/>
    <Button x:Name="Refresh" Content="Atualizar discos" HorizontalAlignment="Left"/>
   </StackPanel>
   <StackPanel x:Name="Step2" Visibility="Collapsed">
    <TextBlock Text="Prepare um pendrive separado" FontSize="21" FontWeight="SemiBold"/>
    <TextBlock Text="1. Baixe a imagem do Rescuezilla e o Rufus nos sites oficiais." Margin="0,16,0,10"/>
    <WrapPanel><Button x:Name="Download" Content="Baixar Rescuezilla"/><Button x:Name="Rufus" Content="Baixar Rufus"/><Button x:Name="OpenRufus" Content="Abrir Rufus baixado"/></WrapPanel>
    <TextBlock Text="2. No Rufus, selecione o PENDRIVE em Dispositivo e a imagem do Rescuezilla em Selecionar. Confira e clique em Iniciar." Margin="0,12,0,12"/>
    <Border Background="#292018" Padding="15" CornerRadius="8"><TextBlock Text="A gravação apaga o pendrive. Não selecione o disco do Windows nem o disco que receberá o clone. A escolha e a gravação acontecem no Rufus." Foreground="#FFD396"/></Border>
    <TextBlock Text="3. Salve o roteiro com os seus discos identificados. Fotografe ou imprima antes de reiniciar. Você não precisará executar comandos." Margin="0,16,0,12"/>
    <Button x:Name="SaveGuide" Content="Salvar meu roteiro" HorizontalAlignment="Left"/>
    <CheckBox x:Name="UsbReady" Margin="0,16,0,10"><TextBlock Text="Já preparei o pendrive e guardei o roteiro."/></CheckBox>
   </StackPanel>
   <StackPanel x:Name="Migration" Visibility="Collapsed">
    <TextBlock Text="Migrar sem diminuir o C: original" FontSize="21" FontWeight="SemiBold"/>
    <TextBlock Text="Use a migração do sistema do DiskGenius. O programa ajusta as partições na cópia de destino. Este fluxo não precisa do pendrive do Rescuezilla." Margin="0,16,0,16"/>
    <Button x:Name="DiskGenius" Content="Abrir site oficial do DiskGenius"/>
    <Button x:Name="MigrationGuide" Content="Salvar roteiro de migração"/>
    <TextBlock Text="Selecione o destino correto e inclua Windows, inicialização e recuperação. Não use as funções de reduzir ou mover partições no disco original." Margin="0,16,0,16"/>
    <CheckBox x:Name="MigrationReady" Content="Li o roteiro e vou conferir o destino na ferramenta."/>
   </StackPanel>
   <StackPanel x:Name="Step3" Visibility="Collapsed">
    <TextBlock Text="Executar a cópia e testar" FontSize="21" FontWeight="SemiBold"/>
    <TextBlock x:Name="Summary" Margin="0,16,0,14"/>
    <TextBlock x:Name="CopyInstructions" Margin="0,0,0,14"/>
    <TextBlock Text="Ao terminar sem erros, desligue o PC e teste o destino com o disco original desconectado. Confira Windows, programas e arquivos. O clone não se atualiza sozinho." Margin="0,0,0,14"/>
    <TextBlock Text="Registrar resultado informado por você (não é verificação automática):" Margin="0,10,0,10"/>
    <Button x:Name="CopyDone" Content="Já concluí a cópia sem erros"/>
    <Button x:Name="BootDone" Content="Já testei o clone com o original desconectado"/>
   </StackPanel>
   <TextBlock x:Name="SavedStatus" Foreground="#F5B65C" Margin="0,16,0,10"/>
   <TextBlock x:Name="Result" Foreground="#AAB4C4" Margin="0,16,0,10"/>
  </StackPanel></ScrollViewer>
  <WrapPanel Grid.Row="2" HorizontalAlignment="Right" Margin="0,20,0,0"><Button x:Name="Back" Content="Voltar"/><Button x:Name="Next" Content="Continuar" Background="#BB691A"/><Button x:Name="Close" Content="Fechar" IsCancel="True"/></WrapPanel>
 </Grid>
</Window>
'@
    $dialog = [Windows.Markup.XamlReader]::Parse($xaml)
    $dialog.Owner = $script:Win; $dialog.Icon = $script:Win.Icon
    $dialog.Tag = @{ Step=1; Inventory=$inventory }
    $refreshView = {
        param($w)
        $inv=$w.Tag.Inventory
        $w.FindName('Source').Text=$inv.Source.Label
        $w.FindName('Usage').Text=if($null -ne $inv.UsedWindows){ '{0:N0} GB ocupados em {1}. A compatibilidade também depende do tamanho e do layout das partições.' -f ($inv.UsedWindows/1e9),$env:SystemDrive } else { 'Não foi possível consultar o espaço ocupado. A verificação de tamanho usa o disco inteiro.' }
        $w.FindName('Target').ItemsSource=@($inv.Disks | Where-Object { $_.Number -ne $inv.Source.Number } | Sort-Object @{ Expression={ -not (Get-SimpleCloneAssessment $inv $_).Allowed } }, Size)
        $preference=Get-ClonePreference
        $preferred=@($w.FindName('Target').Items | Where-Object { $preference -and (($_.Serial -replace '\s','') -eq ($preference.TargetSerial -replace '\s','')) })
        if($preferred.Count -eq 1){$w.FindName('Target').SelectedItem=$preferred[0]}
        elseif($w.FindName('Target').Items.Count){$w.FindName('Target').SelectedIndex=0}
        else{$w.FindName('Eligibility').Text='Conecte outro disco e clique em Atualizar discos.'}
        Update-SimpleClonePage $w
    }
    $dialog.Tag.Refresh=$refreshView
    $dialog.FindName('Target').add_SelectionChanged({param($s,$e)
        $w=[Windows.Window]::GetWindow($s)
        $w.FindName('Eligibility').Text=(Get-SimpleCloneAssessment $w.Tag.Inventory $s.SelectedItem).Message
        $w.FindName('UsbReady').IsChecked=$false; $w.FindName('MigrationReady').IsChecked=$false
        Update-SimpleClonePage $w
    })
    $dialog.FindName('Refresh').add_Click({param($s,$e)
        $w=[Windows.Window]::GetWindow($s)
        try{$w.Tag.Inventory=Get-CloneInventory; & $w.Tag.Refresh $w; $w.FindName('Result').Text='Lista atualizada.'}catch{$w.FindName('Result').Text=$_.Exception.Message; $w.FindName('Next').IsEnabled=$false}
    })
    $dialog.FindName('Next').add_Click({param($s,$e)
        $w=[Windows.Window]::GetWindow($s)
        try {
            $fresh=Get-CloneInventory; $old=$w.FindName('Target').SelectedItem
            $target=@($fresh.Disks | Where-Object { $_.Serial -eq $old.Serial -and $_.Size -eq $old.Size -and $_.Number -eq $old.Number })
            if($target.Count -ne 1 -or $fresh.Source.Serial -ne $w.Tag.Inventory.Source.Serial){throw 'Os discos mudaram. Volte e atualize a lista.'}
            $assessment=Get-SimpleCloneAssessment $fresh $target[0]
            if(-not $assessment.Allowed){throw $assessment.Message}
            $w.Tag.Inventory=$fresh
            $w.FindName('Summary').Text="ORIGEM: $($fresh.Source.Label)`nSerial: $($fresh.Source.Serial)`n`nDESTINO: $($target[0].Label)`nSerial: $($target[0].Serial)"
            $w.Tag.Step++; $w.FindName('Result').Text=''; Update-SimpleClonePage $w
        }catch{$w.FindName('Result').Text=$_.Exception.Message}
    })
    $dialog.FindName('Back').add_Click({param($s,$e) $w=[Windows.Window]::GetWindow($s); $w.Tag.Step--; Update-SimpleClonePage $w})
    foreach($eventName in 'Checked','Unchecked'){$dialog.FindName('UsbReady').("add_$eventName")({param($s,$e) Update-SimpleClonePage ([Windows.Window]::GetWindow($s))})}
        $dialog.FindName('DiskGenius').add_Click({Start-Process 'https://www.diskgenius.com/download.php'})
    $dialog.FindName('MigrationReady').add_Checked({param($s,$e) Update-SimpleClonePage ([Windows.Window]::GetWindow($s))})
    $dialog.FindName('MigrationReady').add_Unchecked({param($s,$e) Update-SimpleClonePage ([Windows.Window]::GetWindow($s))})
    foreach($pair in @(@('CopyDone','cópia concluída; boot pendente'),@('BootDone','boot testado pelo usuário'))){
        $button=$dialog.FindName($pair[0]);$button.Tag=$pair[1]
        $button.add_Click({param($s,$e)
            $w=[Windows.Window]::GetWindow($s)
            if([Windows.MessageBox]::Show($w,('Confirmar este resultado? '+$s.Tag),'Registrar resultado','YesNo','Question') -eq 'Yes'){
                try{Save-CloneProgress $w.Tag.Inventory $w.FindName('Target').SelectedItem $s.Tag;Update-SimpleClonePage $w;$w.FindName('Result').Text='Registrado: '+$s.Tag}catch{$w.FindName('Result').Text=$_.Exception.Message}
            }
        })
    }
    $dialog.FindName('Download').add_Click({Start-Process 'https://rescuezilla.com/download'})
    $dialog.FindName('Rufus').add_Click({Start-Process 'https://rufus.ie/pt_BR/'})
    $dialog.FindName('OpenRufus').add_Click({param($s,$e)
        $w=[Windows.Window]::GetWindow($s)
        $picker=New-Object Microsoft.Win32.OpenFileDialog; $picker.Filter='Rufus (*.exe)|*.exe'
        if($picker.ShowDialog($w)){
            try {
                $signature=Get-AuthenticodeSignature -LiteralPath $picker.FileName
                if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O="?Akeo Consulting"?(?:,|$)'){throw 'Escolha o Rufus oficial com assinatura válida da Akeo Consulting.'}
                Start-Process -FilePath $picker.FileName
            }catch{$w.FindName('Result').Text=$_.Exception.Message}
        }
    })
    $dialog.FindName('SaveGuide').add_Click({param($s,$e)
        $w=[Windows.Window]::GetWindow($s)
        $picker=New-Object Microsoft.Win32.SaveFileDialog; $picker.Filter='Roteiro HTML (*.html)|*.html'; $picker.FileName='Meu-roteiro-HollowDrivers.html'
        if($picker.ShowDialog($w)){
            try{Save-SimpleCloneGuide $w.Tag.Inventory $w.FindName('Target').SelectedItem $picker.FileName; $w.FindName('Result').Text='Roteiro salvo. Fotografe ou imprima para consultar após reiniciar.'; Start-Process $picker.FileName}catch{$w.FindName('Result').Text=$_.Exception.Message}
        }
    })
        $dialog.FindName('MigrationGuide').add_Click({param($s,$e)
        $w=[Windows.Window]::GetWindow($s)
        $w.FindName('SaveGuide').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    })
    $dialog.FindName('Close').add_Click({param($s,$e) [Windows.Window]::GetWindow($s).Close()})
    & $refreshView $dialog
    [void]$dialog.ShowDialog()
}
