# Assistente de preparacao. Nenhuma funcao deste arquivo grava setores ou formata discos.
function Get-CloneInventory {
    $disks = @(Get-Disk -ErrorAction Stop)
    $parts = @(Get-Partition -ErrorAction Stop)
    $hardware = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop)
    $os = @(Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction Stop)
    if ($os.Count -ne 1) { throw 'Não foi possível identificar o disco do Windows.' }
    $records = @(foreach ($d in $disks) {
        $physical = @($hardware | Where-Object { $_.Index -eq $d.Number })
        $serial = if ($physical.Count -eq 1 -and $physical[0].SerialNumber) { $physical[0].SerialNumber.Trim() } else { "$($d.SerialNumber)".Trim() }
        $letters = @($parts | Where-Object { $_.DiskNumber -eq $d.Number -and [int][char]$_.DriveLetter -gt 0 } | ForEach-Object { "$($_.DriveLetter):" }) -join ', '
        [pscustomobject]@{
            Number = [int]$d.Number; Model = "$($d.FriendlyName)"; Serial = $serial
            Size = [long]$d.Size; Sector = [int]$d.LogicalSectorSize; Bus = "$($d.BusType)"
            Style = "$($d.PartitionStyle)"; Offline = [bool]$d.IsOffline; ReadOnly = [bool]$d.IsReadOnly
            System = [bool]($d.IsSystem -or $d.IsBoot); Letters = $letters
            Label = ('Disco {0} • {1} • {2:N0} GB • {3}' -f $d.Number, $d.FriendlyName, ($d.Size / 1e9), $letters)
        }
    })
    $source = @($records | Where-Object { $_.Number -eq $os[0].DiskNumber })
    if ($source.Count -ne 1) { throw 'O disco do Windows não está disponível para clonagem.' }
    $usedWindows = $null
    try {
        $volume = Get-Volume -DriveLetter $env:SystemDrive.Substring(0,1) -ErrorAction Stop
        $usedWindows = [long]($volume.Size - $volume.SizeRemaining)
    } catch { }
    [pscustomobject]@{ Source = $source[0]; Disks = $records; UsedWindows = $usedWindows }
}

function Get-CloneBlockReason($Source, $Target, $Disks, [switch]$AllowSmaller) {
    if (-not $Source -or -not $Target) { return 'Selecione um disco de destino.' }
    if ($Source.Number -eq $Target.Number) { return 'Origem e destino são o mesmo disco.' }
    if ($Source.Offline -or $Target.Offline) { return 'Um dos discos está offline.' }
    if ($Target.ReadOnly) { return 'O destino está protegido contra gravação.' }
    if ($Target.System) { return 'Este disco contém o Windows ou arquivos de inicialização.' }
    if (@($Disks | Where-Object { $_.System -and $_.Number -ne $Source.Number }).Count) { return 'A inicialização depende de outro disco. Este layout precisa de avaliação manual.' }
    if ($Source.Bus -notin 'SATA','NVMe','ATA','SAS' -or $Target.Bus -notin 'SATA','NVMe','ATA','SAS','USB') { return 'Discos virtuais, RAID e Storage Spaces não são suportados neste assistente.' }
    if ($Source.Style -notin 'GPT','MBR') { return 'O layout do disco de origem não é suportado.' }
    if (-not $AllowSmaller -and $Target.Size -lt $Source.Size) { return 'Destino menor que o disco de origem. Use um disco com capacidade igual ou maior.' }
    if ($Source.Sector -le 0 -or $Source.Sector -ne $Target.Sector) { return 'Os tamanhos de setor dos discos são incompatíveis.' }
    foreach ($disk in @($Source, $Target)) {
        $serial = ("$($disk.Serial)" -replace '\s', '').ToUpperInvariant()
        if (-not $serial -or $serial -match '^(0+|UNKNOWN|NONE)$') { return 'Número de série ausente. Não é seguro identificar automaticamente os discos.' }
        if (@($Disks | Where-Object { (($_.Serial -replace '\s', '').ToUpperInvariant()) -eq $serial }).Count -ne 1) { return 'Número de série duplicado. Não é seguro identificar automaticamente os discos.' }
    }
    return $null
}

function New-CloneKit($Source, $Target, $Disks, [string]$Folder) {
    $reason = Get-CloneBlockReason $Source $Target $Disks
    if ($reason) { throw $reason }
    $template = Join-Path $PSScriptRoot 'clone-offline.sh'
    if (-not (Test-Path -LiteralPath $template)) { throw 'Reinstale o HollowDrivers: o componente de clonagem está ausente.' }
    # Apenas dados codificados entram no script; nomes/seriais nunca viram comandos.
    $encode = { param($value) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$value)) }
    $scriptText = [IO.File]::ReadAllText($template)
    $scriptText = $scriptText.Replace('__SOURCE_SERIAL__', (& $encode $Source.Serial)).Replace('__TARGET_SERIAL__', (& $encode $Target.Serial))
    $scriptText = $scriptText.Replace('__SOURCE_SIZE__', ([long]$Source.Size).ToString()).Replace('__TARGET_SIZE__', ([long]$Target.Size).ToString()).Replace('__SECTOR__', ([int]$Source.Sector).ToString())
    New-Item -ItemType Directory -Path $Folder -ErrorAction Stop | Out-Null
    [IO.File]::WriteAllText((Join-Path $Folder 'CLONAR.sh'), ($scriptText -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
    $plan = [ordered]@{ Created = (Get-Date).ToString('o'); Status = 'Preparado; clonagem e teste de boot pendentes'; Source = $Source; Target = $Target; Engine = 'Clonezilla Live / ocs-onthefly' }
    $plan | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Folder 'discos.json') -Encoding UTF8
    $guide = @"
HOLLOWDRIVERS — CLONE INICIALIZÁVEL
PREPARAÇÃO APENAS. NENHUM BACKUP FOI CRIADO AINDA.

ORIGEM (preservar): $($Source.Label)
Serial: $($Source.Serial) | Tamanho exato: $($Source.Size) bytes
DESTINO (será APAGADO): $($Target.Label)
Serial: $($Target.Serial) | Tamanho exato: $($Target.Size) bytes

1. Salve separadamente qualquer arquivo importante do DESTINO: todas as suas partições serão substituídas.
2. Tenha um pendrive de inicialização separado dos dois discos. Baixe o Clonezilla Live estável em https://clonezilla.org/downloads.php e prepare-o seguindo https://clonezilla.org/liveusb.php . A gravação da mídia apaga o pendrive selecionado.
3. Guarde esta pasta em uma segunda mídia USB (ou em uma partição de dados acessível da mídia de inicialização). Nunca a guarde somente na ORIGEM ou no DESTINO. Fotografe os modelos e seriais acima.
4. Se houver BitLocker/criptografia de dispositivo, salve a chave de recuperação fora do PC. Este assistente bloqueia volumes ainda criptografados no ambiente offline; suspender o BitLocker não descriptografa. Não desative a criptografia sem avaliar como proteger seus dados.
5. Feche os programas e use Reiniciar para entrar no menu de boot e iniciar o pendrive no mesmo modo UEFI/Legacy do Windows. Evite hibernar. O assistente não reinicia o computador sozinho.
6. No Clonezilla Live, escolha entrar no shell. Localize a mídia que contém esta pasta. O comando lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS ajuda a reconhecê-la. Monte SOMENTE essa mídia auxiliar, nunca os discos de origem ou destino.
7. Na pasta deste kit, execute: sudo bash CLONAR.sh
   O script identifica os discos pelo serial, tamanho e setor. Se os seriais mudarem com um adaptador, ele bloqueia: não remova as verificações. Use a interface do Clonezilla com ajuda técnica para esse caso.
8. Confira novamente os modelos/seriais. Digite APAGAR seguido do serial do destino somente se estiver correto. O Clonezilla ainda pedirá suas próprias confirmações. Não interrompa a energia durante a cópia.
9. Ao concluir, desligue o computador. Com ele desligado, desconecte o disco original e teste o clone na conexão interna adequada. Uma cópia em USB não significa que o Windows instalado conseguirá iniciar por USB.
10. Confirme que o Windows inicia sozinho e que programas e arquivos abrem. Só então considere o clone testado. O assistente não certifica boot automaticamente; pode haver pedidos de ativação/licenças.
11. Guarde o clone desconectado. Ele representa a data da cópia: novos arquivos e programas só entram depois de uma nova clonagem. Um segundo disco conectado não protege contra todos os riscos, como fonte danificada ou ransomware.

Todas as partições do DISCO DE ORIGEM são copiadas (Windows, programas, drivers, arquivos e partições de boot/recuperação). Dados e programas instalados em OUTROS discos não entram. Não é sincronização contínua e não é apenas um ponto de restauração.

Não há clonagem para disco menor, redimensionamento automático, RAID/Storage Spaces nem conserto automático de boot neste fluxo. Se a origem estiver falhando fisicamente, evite insistir em leituras e procure recuperação de dados.

Documentação: https://clonezilla.org/clonezilla-live-doc.php
"@
    [IO.File]::WriteAllText((Join-Path $Folder 'LEIA-ANTES.txt'), $guide, (New-Object Text.UTF8Encoding $true))
    return $Folder
}

function Show-AdvancedCloneAssistant {
    try { $inventory = Get-CloneInventory } catch {
        [void](Show-Dialog 'Não foi possível consultar os discos' ($_.Exception.Message + "`n`nTente abrir o HollowDrivers como administrador. Nenhum disco foi alterado.") 'warn'); return
    }
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Clone inicializável — HollowDrivers" Width="820" Height="690" MinWidth="680" MinHeight="580" WindowStartupLocation="CenterOwner" Background="#12151B" Foreground="#ECE7DD" FontFamily="Segoe UI">
 <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="28">
  <TextBlock Text="Um segundo disco para continuar" FontSize="25" FontWeight="SemiBold" TextWrapping="Wrap"/>
  <TextBlock Text="Windows, drivers, programas e arquivos do disco de origem." Margin="0,7,0,20" Foreground="#AAB4C4" TextWrapping="Wrap"/>
  <TextBlock Text="1. DISCO DO WINDOWS · ORIGEM" Foreground="#F5B65C"/>
  <TextBlock x:Name="Source" Margin="0,8,0,20" TextWrapping="Wrap"/>
  <TextBlock Text="2. DISCO QUE RECEBERÁ A CÓPIA · DESTINO" Foreground="#F5B65C"/>
  <ComboBox x:Name="Target" Margin="0,8,0,6" MinHeight="34" DisplayMemberPath="Label"/>
  <TextBlock x:Name="Eligibility" Margin="0,5,0,16" TextWrapping="Wrap"/>
  <Border Background="#292018" Padding="15" CornerRadius="8"><TextBlock Text="A clonagem apaga TODOS os dados do destino. Use um disco de capacidade igual ou maior. Programas e arquivos em outros discos não entram nesta cópia." TextWrapping="Wrap" Foreground="#FFD396"/></Border>
  <TextBlock Text="3. PREPARAR E CLONAR FORA DO WINDOWS" Foreground="#F5B65C" Margin="0,20,0,8"/>
  <TextBlock Text="Este assistente gera um kit para executar no Clonezilla Live por pendrive. A geração do kit não copia nem apaga discos. A cópia exige reiniciar pelo pendrive, conferir os discos e confirmar o apagamento lá." TextWrapping="Wrap"/>
  <TextBlock Text="Depois da cópia, teste a inicialização com o disco original desconectado. O clone não se atualiza sozinho. Se houver BitLocker, consulte as orientações do kit antes de começar." TextWrapping="Wrap" Foreground="#AAB4C4" Margin="0,10,0,16"/>
  <WrapPanel>
   <Button x:Name="Download" Content="Obter Clonezilla Live" Padding="15,10" Margin="0,0,10,10"/>
   <Button x:Name="Export" Content="Salvar kit de clonagem" Padding="15,10" Margin="0,0,10,10" Background="#F5B65C" IsEnabled="False"/>
   <Button x:Name="Close" Content="Fechar" Padding="15,10" Margin="0,0,0,10" IsCancel="True"/>
  </WrapPanel>
  <TextBlock x:Name="Result" TextWrapping="Wrap" Foreground="#AAB4C4"/>
 </StackPanel></ScrollViewer>
</Window>
'@
    $dialog = [Windows.Markup.XamlReader]::Parse($xaml)
    $dialog.Owner = $script:Win
    $dialog.Icon = $script:Win.Icon
    $dialog.FindName('Source').Text = $inventory.Source.Label + "`nSerial: " + $inventory.Source.Serial
    $selector = $dialog.FindName('Target')
    $selector.ItemsSource = @($inventory.Disks | Where-Object { $_.Number -ne $inventory.Source.Number })
    $state = @{ Inventory = $inventory; Dialog = $dialog; Target = $selector }
    $dialog.Tag = $state
    $selector.add_SelectionChanged({
        param($sender, $eventArgs)
        $w = [Windows.Window]::GetWindow($sender); $st = $w.Tag
        $reason = Get-CloneBlockReason $st.Inventory.Source $sender.SelectedItem $st.Inventory.Disks
        $w.FindName('Export').IsEnabled = -not [bool]$reason
        $w.FindName('Eligibility').Text = if ($reason) { $reason } else { 'Tamanho compatível. Serial do destino: ' + $sender.SelectedItem.Serial + '. Validação final no ambiente offline.' }
    })
    if ($selector.Items.Count -gt 0) { $selector.SelectedIndex = 0 } else { $dialog.FindName('Eligibility').Text = 'Conecte outro disco físico e reabra este assistente.' }
    $dialog.FindName('Download').add_Click({ Start-Process 'https://clonezilla.org/downloads.php' })
    $dialog.FindName('Export').add_Click({
        param($sender, $eventArgs)
        $w = [Windows.Window]::GetWindow($sender); $st = $w.Tag
        try {
            $fresh = Get-CloneInventory
            $selected = $st.Target.SelectedItem
            $target = @($fresh.Disks | Where-Object { $_.Number -eq $selected.Number -and $_.Serial -eq $selected.Serial -and $_.Size -eq $selected.Size })
            if ($target.Count -ne 1 -or $fresh.Source.Serial -ne $st.Inventory.Source.Serial) { throw 'Os discos mudaram. Feche e reabra o assistente.' }
            $folderDialog = New-Object Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = 'Onde guardar o kit? Transfira-o para uma mídia auxiliar antes de reiniciar.'
            try {
                if ($folderDialog.ShowDialog() -ne 'OK') { return }
                $folder = Join-Path $folderDialog.SelectedPath ('HollowDrivers-Clone-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
                $saved = New-CloneKit $fresh.Source $target[0] $fresh.Disks $folder
            } finally { $folderDialog.Dispose() }
            $w.FindName('Result').Text = "Kit salvo em $saved`nClonagem e teste de inicialização ainda pendentes. Leia LEIA-ANTES.txt."
            Start-Process notepad.exe -ArgumentList ('"' + (Join-Path $saved 'LEIA-ANTES.txt') + '"')
        } catch { $w.FindName('Result').Text = 'Não foi possível preparar: ' + $_.Exception.Message }
    })
    $dialog.FindName('Close').add_Click({ param($s,$e) [Windows.Window]::GetWindow($s).Close() })
    [void]$dialog.ShowDialog()
}

. (Join-Path $PSScriptRoot 'SimpleClone.ps1')
