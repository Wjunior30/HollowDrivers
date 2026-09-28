# Shared by the user interface, elevated worker and offline tests.
$GameComponentLogic = {
function Get-GameCatalog {
    [pscustomobject]@{Id='vc-x86';Name='Visual C++ v14 — jogos de 32 bits';Kind='VC';Arch='x86';Url='https://aka.ms/vc14/vc_redist.x86.exe'}
    if([Environment]::Is64BitOperatingSystem){[pscustomobject]@{Id='vc-x64';Name='Visual C++ v14 — jogos de 64 bits';Kind='VC';Arch='x64';Url='https://aka.ms/vc14/vc_redist.x64.exe'}}
    if($env:PROCESSOR_ARCHITECTURE -ne 'ARM64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'ARM64'){
        [pscustomobject]@{Id='directx';Name='DirectX — componentes para jogos antigos';Kind='DX';Arch='';Url='https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe'}
    }
}
function Get-GameVcVersion([string]$Arch) {
    $versions=@(foreach($view in [Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64){
        $base=$null;$key=$null
        try {
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
            $key=$base.OpenSubKey("SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$Arch")
            if($key -and $key.GetValue('Installed') -eq 1){[version](([string]$key.GetValue('Version')).TrimStart('v'))}
        }catch{}finally{if($key){$key.Dispose()};if($base){$base.Dispose()}}
    })
    $versions|Sort-Object -Descending|Select-Object -First 1
}
function Get-GameComponentStatus($Component) {
    if($Component.Kind -eq 'VC'){
        $version=Get-GameVcVersion $Component.Arch
        if($version){return "Instalado: $version. Você pode atualizar ou reparar. A versão mais recente é conferida no instalador oficial."}
        return 'Não identificado no registro. Instale se o jogo solicitar Visual C++ v14.'
    }
    $folders=@('System32');if([Environment]::Is64BitOperatingSystem){$folders+='SysWOW64'}
    $missing=@(foreach($folder in $folders){foreach($dll in 'd3dx9_43.dll','d3dx11_43.dll','xinput1_3.dll','xaudio2_7.dll'){
        if(-not (Test-Path -LiteralPath (Join-Path $env:windir "$folder\$dll"))){"$folder\$dll"}
    }})
    if($missing.Count){return "Verificação parcial: $($missing.Count) bibliotecas de referência ausentes. Instale se o jogo exigir esses componentes."}
    return 'Bibliotecas de referência presentes. Verificação parcial: não comprova integridade de todo o DirectX antigo.'
}
function Assert-GameMicrosoftSignature([string]$Path) {
    $sig=Get-AuthenticodeSignature -LiteralPath $Path
    if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch '(?:^|,\s*)O="?Microsoft Corporation"?(?:,|$)'){
        throw 'O arquivo não possui uma assinatura válida da Microsoft. Nada será executado.'
    }
}
function Get-GameExitMessage([int]$Code) {
    switch($Code){
        0 {'Concluído pelo instalador oficial. Teste novamente o jogo.'}
        3010 {'Concluído. Reinicie o Windows para finalizar; o aplicativo não reiniciará sozinho.'}
        1641 {'O instalador informou reinicialização iniciada.'}
        1638 {'O instalador identificou outra versão já instalada e não a substituiu. Confira a versão detectada.'}
        1602 {throw 'Instalação cancelada pelo usuário.'}
        default {throw "O instalador retornou código $Code. Consulte o histórico e tente novamente."}
    }
}
function Get-GameVcAction($Installed,[version]$Downloaded) {
    if($Installed -and [version]$Installed -gt $Downloaded){return 'keep'}
    if($Installed -and [version]$Installed -eq $Downloaded){return '/repair'}
    return '/install'
}
}
. $GameComponentLogic

$GameInstallWorker = {
$ErrorActionPreference='Stop'
$folder=$null
try {
    $component=@(Get-GameCatalog|Where-Object Id -eq '__COMPONENT__')
    if($component.Count -ne 1){throw 'Componente inválido ou incompatível com a arquitetura.'}
    $component=$component[0]
    # Fresh Program Files directory: standard users cannot replace elevated payloads.
    $parent=[Environment]::GetFolderPath('ProgramFiles')
    if((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Pasta de programas redirecionada.'}
    $folder=Join-Path $parent ('HollowDrivers-runtime-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $folder -ErrorAction Stop)
    $exe=Join-Path $folder 'package.exe'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $client=New-Object Net.WebClient
    try{$client.DownloadFile($component.Url,$exe)}finally{$client.Dispose()}
    Assert-GameMicrosoftSignature $exe
    W ('PACOTE='+$component.Name)
    if($component.Kind -eq 'DX'){
        $extract=Join-Path $folder 'directx';[void](New-Item -ItemType Directory $extract)
        $process=Start-Process -FilePath $exe -ArgumentList ('/Q /T:"'+$extract+'"') -Wait -PassThru
        if($process.ExitCode -ne 0){throw "Falha na extração: $($process.ExitCode)"}
        $exe=Join-Path $extract 'DXSETUP.exe';Assert-GameMicrosoftSignature $exe
        $arguments='/silent'
    }else{
        $installed=Get-GameVcVersion $component.Arch
        $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        $downloaded=[version]('{0}.{1}.{2}.{3}' -f $info.FileMajorPart,$info.FileMinorPart,$info.FileBuildPart,$info.FilePrivatePart)
        $mode=Get-GameVcAction $installed $downloaded
        if($mode -eq 'keep'){W 'RESULTADO=Uma versão mais recente já está instalada; nenhuma alteração realizada.';return}
        $arguments=$mode+' /passive /norestart /log "'+(Join-Path $folder 'installer.log')+'"'
    }
    $process=Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru
    W ('CODIGO='+$process.ExitCode)
    W ('RESULTADO='+(Get-GameExitMessage $process.ExitCode))
}catch{W ('ERRO='+$_.Exception.Message)}finally{
    if($folder -and (Test-Path -LiteralPath (Join-Path $folder 'installer.log'))){W ((Get-Content -LiteralPath (Join-Path $folder 'installer.log') -Tail 60)|Out-String)}
    Save-Log
    if($folder -and (Split-Path $folder -Parent) -eq [Environment]::GetFolderPath('ProgramFiles') -and (Split-Path $folder -Leaf) -match '^HollowDrivers-runtime-[a-f0-9]{32}$'){
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
}

function Show-GameComponents {
    $xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Componentes para jogos — HollowDrivers" Width="720" Height="530" MinWidth="620" MinHeight="480" WindowStartupLocation="CenterOwner" Background="#12151B" Foreground="#ECE7DD" FontFamily="Segoe UI" FontSize="15">
 <Grid Margin="28"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
 <TextBlock Text="Componentes para jogos" FontSize="26" FontWeight="SemiBold"/>
 <TextBlock Text="Ajuda para jogos que não abrem ou pedem bibliotecas ausentes." TextWrapping="Wrap" Margin="0,10,0,22"/>
 <ComboBox x:Name="Components" DisplayMemberPath="Name" MinHeight="38"/>
 <Border Background="#252C38" Padding="16" CornerRadius="8" Margin="0,16,0,16"><TextBlock x:Name="Status" TextWrapping="Wrap"/></Border>
 <TextBlock Text="Visual C++: jogos de 32 bits podem precisar do pacote x86 mesmo em Windows de 64 bits. Versões antigas do Visual C++ não são removidas nem substituídas por este pacote." TextWrapping="Wrap" Margin="0,0,0,14"/>
 <TextBlock Text="DirectX: adiciona bibliotecas para jogos antigos, sem trocar o DirectX do Windows. Instale somente quando necessário. Não oferece desinstalação individual." TextWrapping="Wrap" Margin="0,0,0,18"/>
 <TextBlock x:Name="Result" TextWrapping="Wrap" Foreground="#FFC477"/>
 </StackPanel></ScrollViewer>
 <WrapPanel Grid.Row="1" Margin="0,18,0,0"><Button x:Name="Install" Content="Instalar / reparar selecionado" Padding="14,10" Margin="0,0,10,8"/><Button x:Name="Refresh" Content="Verificar novamente" Padding="14,10" Margin="0,0,10,8"/><Button x:Name="Close" Content="Fechar" Padding="14,10" Margin="0,0,0,8"/></WrapPanel>
 </Grid>
</Window>
'@
    $dialog=[Windows.Markup.XamlReader]::Parse($xaml)
    $dialog.Owner=$Win;$dialog.Icon=$Win.Icon
    $dialog.Tag=@{Busy=$false}
    $dialog.FindName('Components').ItemsSource=@(Get-GameCatalog)
    $refresh={param($s,$e) $w=[Windows.Window]::GetWindow($s);$item=$w.FindName('Components').SelectedItem;if($item){$w.FindName('Status').Text=Get-GameComponentStatus $item}}
    $dialog.FindName('Components').add_SelectionChanged($refresh)
    $dialog.FindName('Refresh').add_Click($refresh)
    $dialog.FindName('Components').SelectedIndex=0
    $dialog.FindName('Install').add_Click({param($s,$e)
        $w=[Windows.Window]::GetWindow($s);$item=$w.FindName('Components').SelectedItem
        if($w.Tag.Busy -or $script:ElevBusy -or -not $item){return}
        $message="Baixar da Microsoft e instalar ou reparar $($item.Name)? Salve e feche seus jogos. O Windows solicitará permissão de administrador. Nenhum reinício será solicitado automaticamente pelo HollowDrivers."
        if($item.Kind -eq 'DX'){$message+=" Download de aproximadamente 96 MB. Esses componentes não possuem desinstalação individual."}
        if([Windows.MessageBox]::Show($w,$message,'Confirmar componente','YesNo','Question') -ne 'Yes'){return}
        $w.Tag.Busy=$true;$w.FindName('Install').IsEnabled=$false;$w.FindName('Components').IsEnabled=$false;$w.FindName('Refresh').IsEnabled=$false
        $w.FindName('Result').Text='Baixando e executando o instalador oficial. Aguarde; isso pode levar alguns minutos.'
        $script:GameDialog=$w
        $worker=$GameComponentLogic.ToString()+[Environment]::NewLine+$GameInstallWorker.ToString()
        Invoke-Elevated $worker @{'__COMPONENT__'=$item.Id} 'componentes-jogos' {
            param($log,$err)
            $w=$script:GameDialog
            try{
                $message=if($err){$err}elseif($log -match '(?m)^ERRO=(.+)'){$matches[1]}elseif($log -match '(?m)^RESULTADO=(.+)'){$matches[1]}else{'Não foi possível confirmar o resultado. Consulte o histórico.'}
                $w.FindName('Result').Text=$message
                $w.FindName('Status').Text=Get-GameComponentStatus $w.FindName('Components').SelectedItem
            }finally{$w.Tag.Busy=$false;$w.FindName('Install').IsEnabled=$true;$w.FindName('Components').IsEnabled=$true;$w.FindName('Refresh').IsEnabled=$true}
        }
    })
    $dialog.add_Closing({param($s,$e) if($s.Tag.Busy){$e.Cancel=$true}})
    $dialog.FindName('Close').add_Click({param($s,$e) [Windows.Window]::GetWindow($s).Close()})
    [void]$dialog.ShowDialog()
}
