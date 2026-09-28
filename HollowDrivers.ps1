param([switch]$SelfTest, [switch]$Watch, [switch]$Rescue, [switch]$AutoRescue, [switch]$HoldWU)

$AppVersion = '1.5.0'
$UpdateRepo = 'Wjunior30/DriverGuard'   # onde as versões novas são publicadas (GitHub Releases)
# Chave pública das versões. Uma atualização só é aceita se vier assinada pela chave privada correspondente,
# que fica fora do GitHub (%USERPROFILE%\.HollowDrivers). Assim, quem invadir a conta do GitHub não consegue publicar malware.
$UpdatePubKey = '<RSAKeyValue><Modulus>uPHjdxzzM6NPQ+25NkI5EIxWOi7qwZU8E2bNEebugIquc2DEW12CjNUKaeZUoe90KK/yRYaOp5y37vGq2lOpcgRKqcn9egoqik4hi0XhLE1OGiLYKbEKtf2/Uf6JWPEb+B/+eOVyrB93RWnkuGL7x/cTdCviu+oiWuE4gE0/abABq/4WRVf6FZgxiHP7VAsM/6Rk9Yu0tysaFOHMkSZEx0b4Nt4SgGtt70KCOS0mCPdmM9EO19oJqdd4gAWjbc9kUrVNmL3yqydXewqDL7coDwUA+SypHrFR/WXmR2C8+/wBPguJGDX+6swklq2hGAH+eA37rwydt46he2pFjvLoHXMNTVdZctj6Im+NE+hefr+k/0lT4SO43wKEodmCn8RYekJpZ7kEgWfxgHsTCrcbM0gFQCLAHzTyGElNq8jS8u4ZD3Ia+B4+iGl0Kva+CA5dzbpbWEDqTgVMiq3BJUaM38yvAOcP0UPGugxlshOjuc7Yfaf7znEG9Eaknw8TJUat</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$DataDir = Join-Path $env:LOCALAPPDATA 'HollowDrivers'
$LegacyDir = Join-Path $env:LOCALAPPDATA 'DriverGuard'   # nome antigo do app: leva backup e configurações junto
if ((Test-Path $LegacyDir) -and -not (Test-Path $DataDir)) { try { Move-Item $LegacyDir $DataDir -Force -ErrorAction Stop } catch { } }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
try { $sessionLease=[IO.File]::Open((Join-Path $DataDir 'session.lock'),'OpenOrCreate','ReadWrite','ReadWrite') }
catch { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show('Instalação ou manutenção em andamento. Tente novamente ao terminar.','HollowDrivers'); return }
try {
if (Test-Path -LiteralPath (Join-Path $Here '.uninstall-pending')) { return }
. (Join-Path $Here 'History.ps1')
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
# Mantem os backups feitos pelas versoes DriverGuard durante a troca de nome.
Get-ChildItem $DataDir -Recurse -File -Filter 'driverguard-backup.json' -ErrorAction SilentlyContinue | ForEach-Object {
    $newMeta = Join-Path $_.DirectoryName 'HollowDrivers-backup.json'
    if (-not (Test-Path $newMeta)) { Move-Item -LiteralPath $_.FullName -Destination $newMeta }
}
foreach ($f in 'baseline-video.json', 'watch-state.json') {
    foreach ($old in @((Join-Path $Here $f), (Join-Path $env:USERPROFILE "HollowDrivers\$f"))) {
        if ((Test-Path $old) -and -not (Test-Path (Join-Path $DataDir $f))) { Copy-Item $old (Join-Path $DataDir $f) }
    }
}
$BaselineFile = Join-Path $DataDir 'baseline-video.json'
$WatchState = Join-Path $DataDir 'watch-state.json'
$BackupDir = Join-Path $DataDir 'backup'
$Exe = Join-Path $Here 'HollowDrivers.exe'
$Launcher = Join-Path $Here 'HollowDrivers.vbs'
$IconFile = Join-Path $Here 'HollowDrivers.ico'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Start-Launcher([string]$arg) {
    if (Test-Path $Exe) {
        if ($arg) { Start-Process $Exe -ArgumentList $arg } else { Start-Process $Exe }
    } else {
        $a = '"{0}"' -f $Launcher; if ($arg) { $a += " $arg" }
        Start-Process wscript.exe -ArgumentList $a
    }
}

# ================================================================ coleta (também roda em segundo plano)
. (Join-Path $Here 'DriverLogic.ps1')
. $Logic

# ================================================================ referência, backup e vigia

function Get-Baseline {
    if (Test-Path $BaselineFile) { try { Get-Content $BaselineFile -Raw | ConvertFrom-Json } catch { $null } }
}
function Save-Baseline($gpu) {
    [pscustomobject]@{ Name = $gpu.Name; Version = $gpu.Version; Inf = $gpu.Inf; Vendor = $gpu.Vendor; Marcado = (Get-Date).ToString('dd/MM/yyyy HH:mm') } |
        ConvertTo-Json | Set-Content $BaselineFile -Encoding UTF8
}

# ---- referência ("guardião") de TODOS os drivers principais, não só o vídeo
$KeyFile = Join-Path $DataDir 'baselines.json'
function Get-KeyBaselines {
    $h = @{}
    if (Test-Path $KeyFile) {
        # o PS 5 devolve a lista inteira como um item só; o ForEach-Object desmonta
        try { foreach ($b in @(Get-Content $KeyFile -Raw | ConvertFrom-Json | ForEach-Object { $_ })) { if ($b.Id) { $h[$b.Id] = $b } } } catch { }
    }
    $h
}
function Save-KeyBaselines($keys) {
    $agora = (Get-Date).ToString('dd/MM/yyyy HH:mm')
    @($keys | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Nome = $_.Nome; Categoria = $_.Categoria; Versao = $_.Versao; Inf = $_.Inf; Marcado = $agora } }) |
        ConvertTo-Json -Depth 4 | Set-Content $KeyFile -Encoding UTF8
}
# devolve os drivers principais que mudaram de versão desde a referência
function Get-KeyChanges($keys) {
    $base = Get-KeyBaselines
    if (-not $base.Count) { return @() }
    @($keys | Where-Object { $base.ContainsKey($_.Id) -and $base[$_.Id].Versao -ne $_.Versao } |
        ForEach-Object { [pscustomobject]@{ Nome = $_.Nome; Categoria = $_.Categoria; Antes = $base[$_.Id].Versao; Agora = $_.Versao; VenDev = $_.VenDev; Id = $_.Id } })
}

# backup por dispositivo (o de vídeo continua no seu lugar de sempre)
function Get-DeviceBackup([string]$id) {
    foreach ($d in Get-ChildItem $BackupDir -Directory -Filter 'dev-*' -ErrorAction SilentlyContinue) {
        $j = Join-Path $d.FullName 'HollowDrivers-backup.json'
        if (-not (Test-Path $j)) { continue }
        try {
            $o = Get-Content $j -Raw | ConvertFrom-Json
            if ($o.DeviceId -eq $id) { $o | Add-Member -NotePropertyName Path -NotePropertyValue $d.FullName -Force; return $o }
        } catch { }
    }
    $null
}

function Get-Backup([string]$version) {
    if ($version -notmatch '^[\d\.]+$') { return $null }   # nunca vira caminho tipo ..\..\
    $d = Join-Path $BackupDir $version
    $j = Join-Path $d 'HollowDrivers-backup.json'
    if (-not (Test-Path $j)) { return $null }
    try { $o = Get-Content $j -Raw | ConvertFrom-Json; $o | Add-Member -NotePropertyName Path -NotePropertyValue $d -Force; $o } catch { $null }
}

function Test-WatchEnabled { $null -ne (Get-ItemProperty $RunKey -Name HollowDrivers -ErrorAction SilentlyContinue) }
function Set-WatchEnabled([bool]$on) {
    if ($on) {
        $cmd = if (Test-Path $Exe) { '"{0}" -Watch' -f $Exe } else { 'wscript.exe "{0}" -Watch' -f $Launcher }
        Set-ItemProperty $RunKey -Name HollowDrivers -Value $cmd
    } else { Remove-ItemProperty $RunKey -Name HollowDrivers -ErrorAction SilentlyContinue }
}
function Stop-Tray {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*HollowDrivers.ps1*-Watch*' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Get-State {
    $s = $null
    if (Test-Path $WatchState) { try { $s = Get-Content $WatchState -Raw | ConvertFrom-Json } catch { } }
    $h = @{ LastCheck = $null; LastUpd = $null; UpdKey = ''; AppKey = '' }
    if ($s) { foreach ($p in $s.PSObject.Properties) { $h[$p.Name] = $p.Value } }
    $h
}
function Save-State($h) { $h | ConvertTo-Json | Set-Content $WatchState -Encoding UTF8 }

function Get-WatchIssues {
    $st = Get-State
    $last = $null
    if ($st.LastCheck) { try { $last = [datetime]$st.LastCheck } catch { } }
    $issues = @()
    $g = Get-GpuInfo; $b = Get-Baseline
    if ($g -and $g.Code -ne 0) { $issues += 'Placa de vídeo com erro ({0}) — jogos não vão abrir.' -f (Get-ProblemText $g.Code) }
    if ($g -and $b -and $b.Version -ne $g.Version) {
        $h = @(Get-InstallHistory $g.VenDev)[0]
        $issues += 'Driver de vídeo trocado: {0} → {1}{2}' -f $b.Version, $g.Version, $(if ($h) { " ($($h.Origem))" } else { '' })
    }
    if ($last) {
        $new = @(Get-CrashList 30 | Where-Object { $_.Quando -gt $last })
        if ($new.Count) { $issues += 'O PC caiu {0}x desde a última verificação (última {1:dd/MM HH:mm}).' -f $new.Count, $new[0].Quando }
    }
    # placa de vídeo quebrada + cópia salva = abre o app em modo socorro (ele restaura sozinho)
    if ($g -and $g.Code -ne 0) {
        $b = Get-Baseline
        if ($b -and (Get-Backup $b.Version)) { Start-Launcher '-Rescue' }
    }
    $ch = @(Get-KeyChanges @(Get-KeyDrivers))
    if ($ch.Count) {
        $issues += $(if ($ch.Count -eq 1) { 'Driver de {0} trocado: {1} → {2}' -f $ch[0].Categoria.ToLower(), $ch[0].Antes, $ch[0].Agora }
            else { '{0} drivers principais trocados ({1})' -f $ch.Count, ((@($ch | Select-Object -First 3 | ForEach-Object { $_.Categoria.ToLower() }) | Sort-Object -Unique) -join ', ') })
    }
    if ((Find-DriverBooster).Count) { $issues += 'Driver Booster instalado.' }
    $st = Get-State; $st.LastCheck = (Get-Date).ToString('o'); Save-State $st
    $issues
}

# modelos de script que rodam com permissão de administrador (só quando o usuário confirma)
# Funções usadas por TODO script que roda como administrador. O script vai direto na linha de comando
# (-EncodedCommand), nunca num arquivo que outro programa poderia trocar antes do "Sim" do UAC.
$ElevLib = @'
$operationLease=[IO.File]::Open((Join-Path (Split-Path '__LOG__') 'session.lock'),'OpenOrCreate','ReadWrite','ReadWrite')
$L = New-Object Collections.ArrayList
function W([string]$t) { [void]$L.Add($t) }
# log em arquivo NOVO (CreateNew): nunca sobrescreve nada, nem segue link simbólico plantado antes
function Save-Log {
    try {
        $dir = Split-Path '__LOG__'
        if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
        $fs = [IO.File]::Open('__LOG__', 'CreateNew', 'Write')
        $sw = New-Object IO.StreamWriter($fs, (New-Object Text.UTF8Encoding $true))
        foreach ($x in $L) { $sw.WriteLine($x) }
        $sw.Close()
    } catch { }
}
# driver só é aceito com a assinatura oficial de drivers da Microsoft (WHQL)
function Test-WhqlSigned([string]$file) {
    $s = Get-AuthenticodeSignature -LiteralPath $file
    $s.Status -eq 'Valid' -and
        $s.SignerCertificate.Subject -like 'CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation*' -and
        $s.SignerCertificate.Issuer -like '*O=Microsoft Corporation*'
}
# copia o pacote para uma pasta que SÓ administradores podem alterar; tudo é conferido e instalado de lá
function Copy-Protected([string]$src) {
    $dst = Join-Path $env:SystemRoot ('Temp\HollowDrivers-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dst | Out-Null
    icacls $dst /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
    robocopy $src $dst /E /R:0 /W:0 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
    $dst
}
function New-RestorePoint([string]$desc) {
    try {
        Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable wv
        if ($wv) { W ('PONTO=aviso: ' + $wv[0]) } else { W 'PONTO=ok' }
    } catch { W ('PONTO=falhou: ' + $_.Exception.Message) }
}
'@

$EnableTpl = @'
try {
    $id = '__PNP__'
    if ($id -notmatch '^[A-Za-z0-9\\&_\.\-]+$') { throw 'identificador de dispositivo inválido' }
    $d = Get-PnpDevice -InstanceId $id -ErrorAction Stop
    W ('ANTES=' + $d.Status + '/' + $d.Problem)
    try { Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop } catch { W ('ENABLE=' + $_.Exception.Message) }
    $out = (& pnputil.exe /enable-device $id 2>&1 | Out-String).Trim()
    W ('PNPUTIL=' + ($out -replace '\s*\r?\n\s*', ' | '))
    Start-Sleep -Seconds 2
    $d2 = Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue
    W ('DEPOIS=' + $d2.Status + '/' + $d2.Problem)
} catch { W ('ERRO=' + $_.Exception.Message) }
finally { Save-Log }
'@

$RestoreTpl = @'
try {
    $inf = '__INFNAME__'
    if ($inf -notmatch '^[\w\-\.]+\.inf$') { throw 'nome de arquivo INF inválido no backup' }
    $deviceId = '__DEVID__'
    $currentInf = '__CURRENTINF__'
    if (-not $deviceId) { throw 'dispositivo nao identificado com seguranca' }
    if ($currentInf) {
        if ($currentInf -notmatch '^oem\d+\.inf$') { throw 'nome do driver atual invalido' }
        $active = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.InfName -ieq $currentInf })
        if (@($active | Where-Object { $_.DeviceID -eq $deviceId }).Count -ne 1) { throw 'o driver atual do dispositivo mudou; examine o PC novamente' }
        if ($active.Count -ne 1) { throw 'o pacote atual tambem e usado por outro dispositivo; restauracao cancelada' }
    }
    $dst = Copy-Protected '__SRC__'
    try {
        # confere TUDO antes de mexer no driver atual
        $infPath = Join-Path $dst $inf
        if (-not (Test-Path -LiteralPath $infPath)) { throw 'o INF do backup não foi encontrado' }
        $txt = Get-Content -LiteralPath $infPath -Raw
        if ($txt -notmatch '(?im)^\s*ClassGuid\s*=\s*\{?__CLASSGUID__\}?') { throw 'o backup não é do tipo de driver esperado' }
        if ($txt -notmatch ('(?im)^\s*DriverVer\s*=[^\r\n]*' + [regex]::Escape('__VER__'))) { throw 'a versão do backup não confere com a salva' }
        $cats = @(Get-ChildItem -LiteralPath $dst -Recurse -Filter '*.cat')
        if (-not $cats.Count -or @($cats | Where-Object { -not (Test-WhqlSigned $_.FullName) }).Count) { throw 'o backup não tem a assinatura oficial da Microsoft' }
        New-RestorePoint 'HollowDrivers - antes de restaurar driver de video'
        # Registra o backup antes de remover o pacote atual.
        $stage = pnputil /add-driver $infPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw ('falha ao preparar backup: ' + $stage.Trim()) }
        if ($currentInf) {
            $o = pnputil /delete-driver $currentInf /uninstall /force 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw ('falha ao remover driver atual: ' + $o.Trim()) }
            W ('REMOVIDO=' + $currentInf)
        }
        $o = pnputil /add-driver $infPath /install 2>&1 | Out-String
        W ('INSTALAR=' + $LASTEXITCODE)
        W $o.Trim()
        if ($LASTEXITCODE -ne 0) { throw ('falha ao instalar backup: ' + $o.Trim()) }
        pnputil /scan-devices | Out-Null
    } finally { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
} catch { W ('ERRO=' + $_.Exception.Message) }
finally { Save-Log }
'@

$PointTpl = @'
try { New-RestorePoint 'HollowDrivers - ponto manual' } finally { Save-Log }
'@

$WuTpl = @'
try {
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au = "$pol\AU"
    $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $inicio = 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime'
    $fim = 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime'
    if ('__HOLD__' -eq '1') {
        New-Item $au -Force | Out-Null
        New-Item $ux -Force | Out-Null
        Set-ItemProperty $au -Name NoAutoUpdate -Value 1 -Type DWord
        Set-ItemProperty $au -Name AUOptions -Value 2 -Type DWord
        $ini = (Get-Date).ToUniversalTime()
        foreach ($n in $inicio) { Set-ItemProperty $ux -Name $n -Value $ini.ToString('yyyy-MM-ddTHH:mm:ssZ') -Type String }
        foreach ($n in $fim) { Set-ItemProperty $ux -Name $n -Value $ini.AddDays(35).ToString('yyyy-MM-ddTHH:mm:ssZ') -Type String }
        W 'HOLD=1'
    } elseif ('__HOLD__' -eq '0') {
        Remove-ItemProperty $au -Name NoAutoUpdate, AUOptions -ErrorAction SilentlyContinue
        foreach ($n in ($inicio + $fim)) { Remove-ItemProperty $ux -Name $n -ErrorAction SilentlyContinue }
        W 'HOLD=0'
    }
    if ('__DRV__' -eq '1') {
        New-Item $pol -Force | Out-Null
        Set-ItemProperty $pol -Name ExcludeWUDriversInQualityUpdate -Value 1 -Type DWord
        W 'DRV=1'
    } elseif ('__DRV__' -eq '0') {
        Remove-ItemProperty $pol -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
        W 'DRV=0'
    }
    if ('__SR__' -eq '1') {
        try { Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop; W 'SR=1' } catch { W ('SR=falhou: ' + $_.Exception.Message) }
        try { vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10% 2>&1 | Out-Null } catch { }
        New-RestorePoint '__DESC__'
    }
} catch { W ('ERRO=' + $_.Exception.Message) }
finally { Save-Log }
'@

$KeyAllTpl = @'
$itens = @(ConvertFrom-Json '__JSON__' | ForEach-Object { $_ })
$ok = 0
foreach ($i in $itens) {
    if ($Prog) { $Prog.Text = "Copiando: $($i.Nome)" }
    New-Item -ItemType Directory -Force -Path $i.Dst | Out-Null
    robocopy $i.Src $i.Dst /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -lt 8) {
        $size = (Get-ChildItem $i.Dst -Recurse -File | Measure-Object Length -Sum).Sum
        [pscustomobject]@{ Version = $i.Ver; Name = $i.Nome; Inf = $i.Inf; Vendor = $i.Vendor; DeviceId = $i.Id; ClassGuid = $i.ClassGuid; Categoria = $i.Cat
            Date = (Get-Date).ToString('dd/MM/yyyy HH:mm'); SizeMB = [math]::Round($size / 1MB) } |
            ConvertTo-Json | Set-Content (Join-Path $i.Dst 'HollowDrivers-backup.json') -Encoding UTF8
        $ok++
    }
}
[pscustomobject]@{ Ok = $ok; Total = $itens.Count }
'@

$BackupTpl = @'
robocopy '__SRC__' '__DST__' /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
$rc = $LASTEXITCODE
if ($rc -lt 8) {
    $size = (Get-ChildItem '__DST__' -Recurse -File | Measure-Object Length -Sum).Sum
    [pscustomobject]@{ Version = '__VER__'; Name = '__NAME__'; Inf = '__INF__'; Vendor = '__VENDOR__'; DeviceId = '__DEVID__'; ClassGuid = '__CLASSGUID__'; Categoria = '__CAT__'; Date = (Get-Date).ToString('dd/MM/yyyy HH:mm'); SizeMB = [math]::Round($size / 1MB) } |
        ConvertTo-Json | Set-Content (Join-Path '__DST__' 'HollowDrivers-backup.json') -Encoding UTF8
}
$rc
'@

$DlTpl = @'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$items = @(ConvertFrom-Json '__JSON__' | ForEach-Object { $_ })   # PS 5 devolve a lista inteira como um item só
function Test-WhqlSigned([string]$file) {
    $s = Get-AuthenticodeSignature -LiteralPath $file
    $s.Status -eq 'Valid' -and
        $s.SignerCertificate.Subject -like 'CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation*' -and
        $s.SignerCertificate.Issuer -like '*O=Microsoft Corporation*'
}
$ok = @(); $fail = @(); $pins = @(); $i = 0
foreach ($u in $items) {
    $i++
    if ($Prog) { $Prog.Text = "Baixando $i de $($items.Count): $($u.Dispositivo)" }
    $dir = Join-Path '__DIR__' $u.Id
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $post = 'updateIDs=' + [uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $u.Id + '","updateID":"' + $u.Id + '"}]')
        $d = Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Body $post -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 60
        $urls = @([regex]::Matches($d.Content, "downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -like '*.cab' })
        if (-not $urls.Count) { throw 'link de download não encontrado' }
        $x = Join-Path $dir 'arquivos'
        New-Item -ItemType Directory -Force -Path $x | Out-Null
        foreach ($url in $urls) {
            if ($url -notmatch '^https?://[^/]*\.(windowsupdate|microsoft)\.com/') { throw 'link fora dos servidores da Microsoft' }
            $cab = Join-Path $dir ([IO.Path]::GetFileName(([uri]$url).AbsolutePath))
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $cab -TimeoutSec 900
            if (-not (Test-WhqlSigned $cab)) { throw 'o download não tem a assinatura oficial de drivers da Microsoft' }
            & expand.exe -F:* $cab $x | Out-Null
            Remove-Item $cab -Force
        }
        # "impressão digital" dos arquivos que definem o driver (.inf e .cat): o script de administrador
        # reconfere cada uma antes de instalar, então trocar o pacote depois do download não adianta
        $files = @(Get-ChildItem -LiteralPath $x -Recurse -File | Where-Object { $_.Extension -in '.inf', '.cat' } | ForEach-Object {
            [pscustomobject]@{ P = $_.FullName.Substring($x.Length + 1); H = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        })
        if (-not ($files | Where-Object { $_.P -like '*.inf' })) { throw 'pacote sem arquivo .inf' }
        foreach ($c in @($files | Where-Object { $_.P -like '*.cat' })) { if (-not (Test-WhqlSigned (Join-Path $x $c.P))) { throw 'catálogo do driver sem assinatura da Microsoft' } }
        if (-not ($files | Where-Object { $_.P -like '*.cat' })) { throw 'pacote sem catálogo assinado' }
        $ok += $u.Id
        $pins += [pscustomobject]@{ Id = $u.Id; Files = $files }
    } catch {
        $fail += ('{0}: {1}' -f $u.Dispositivo, $_.Exception.Message)
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
[pscustomobject]@{ Ok = @($ok); Fail = @($fail); Pins = @($pins) }
'@

$UpdTpl = @'
try {
    New-RestorePoint 'HollowDrivers - antes de atualizar drivers'
    $pins = @(ConvertFrom-Json '__PINS__' | ForEach-Object { $_ })
    foreach ($p in $pins) {
        if ($p.Id -notmatch '^[0-9a-f\-]{36}$') { W ('RECUSADO=' + $p.Id + ' id inválido'); continue }
        $dst = Copy-Protected (Join-Path '__DIR__' ($p.Id + '\arquivos'))
        try {
            $bad = $null
            foreach ($f in @($p.Files)) {
                $fp = Join-Path $dst $f.P
                if (-not (Test-Path -LiteralPath $fp) -or (Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash -ne $f.H) { $bad = 'arquivo alterado depois do download: ' + $f.P; break }
                if ($f.P -like '*.cat' -and -not (Test-WhqlSigned $fp)) { $bad = 'catálogo sem assinatura da Microsoft: ' + $f.P; break }
            }
            if (-not $bad) {
                $known = @($p.Files | ForEach-Object { $_.P })
                $extra = @(Get-ChildItem -LiteralPath $dst -Recurse -File | Where-Object { $_.Extension -in '.inf', '.cat' -and $known -notcontains $_.FullName.Substring($dst.Length + 1) })
                if ($extra.Count) { $bad = 'arquivo inesperado no pacote: ' + $extra[0].Name }
            }
            if ($bad) { W ('RECUSADO=' + $p.Id + ' ' + $bad); continue }
            $o = pnputil /add-driver (Join-Path $dst '*.inf') /subdirs /install 2>&1 | Out-String
            $rc = $LASTEXITCODE
            W ('PACOTE=' + $p.Id + ' RC=' + $rc)
            if ($rc -eq 259) {
                foreach ($m in [regex]::Matches($o, 'oem\d+\.inf')) { pnputil /delete-driver $m.Value 2>&1 | Out-Null; W ('LIMPO=' + $m.Value) }
            }
        } finally { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
    }
} catch { W ('ERRO=' + $_.Exception.Message) }
finally { Save-Log }
'@

function Expand-Tpl([string]$tpl, [hashtable]$map) {
    foreach ($k in $map.Keys) { $tpl = $tpl.Replace($k, "$($map[$k])".Replace("'", "''")) }
    $tpl
}

# ================================================================ segurar o Windows Update (tarefa agendada)
# Roda no logon e uma vez por dia COM permissão de administrador. Só faz uma coisa: se o usuário pediu
# para manter as atualizações seguradas e alguém (ou o próprio Windows) religou, aplica a pausa de novo.
$WuTask = 'HollowDrivers-Windows'
function Test-WuTask { [bool](Get-ScheduledTask -TaskName $WuTask -ErrorAction SilentlyContinue) }

if ($HoldWU) {
    $st = Get-State
    if (-not $st.WuHold) { return }
    $w = Get-WuState
    if ($w.Pausado -and $w.SemAuto) { return }              # já está segurado: nada a fazer
    $log = Join-Path $DataDir ('windows-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    $code = (Expand-Tpl $ElevLib @{ '__LOG__' = $log }) + "`n" +
        (Expand-Tpl $WuTpl @{ '__HOLD__' = '1'; '__DRV__' = ''; '__SR__' = ''; '__DESC__' = '' })
    & ([scriptblock]::Create($code))
    return
}

# ================================================================ socorro automático (tarefa agendada)
# Roda no logon COM permissão de administrador, mas só faz uma coisa: se a placa de vídeo estiver
# com erro e existir cópia validada, reinstala essa cópia. Uma tentativa por inicialização.
$RescueTask = 'HollowDrivers-Socorro'
function Test-RescueTask { [bool](Get-ScheduledTask -TaskName $RescueTask -ErrorAction SilentlyContinue) }

if ($AutoRescue) {
    $log = Join-Path $DataDir ('socorro-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    $st = Get-State
    $boot = ''
    try { $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o') } catch { }
    if ($st.RescueBoot -eq $boot -and $boot) { return }      # já tentou nesta inicialização
    $g = Get-GpuInfo
    if (-not $g -or $g.Code -eq 0) { return }                # vídeo está bem: nada a fazer
    $b = Get-Baseline
    $bk = if ($b) { Get-Backup $b.Version } else { $null }
    if (-not $bk -or "$($bk.Inf)" -notmatch '^[\w\-\.]+\.inf$') { return }
    $st.RescueBoot = $boot; Save-State $st
    $vendorRx = switch ($bk.Vendor) {
        'AMD' { 'Advanced Micro Devices|\bAMD\b|ATI Technologies' }
        'NVIDIA' { 'NVIDIA' }
        'Intel' { '\bIntel\b' }
        default { [regex]::Escape("$($bk.Vendor)") }
    }
    $code = (Expand-Tpl $ElevLib @{ '__LOG__' = $log }) + "`n" +
        (Expand-Tpl $RestoreTpl @{ '__VENDOR__' = $vendorRx; '__SRC__' = $bk.Path; '__INFNAME__' = $bk.Inf
            '__VER__' = $bk.Version; '__CLASSGUID__' = '4d36e968-e325-11ce-bfc1-08002be10318'; '__DEVID__' = $g.Pnp; '__CURRENTINF__' = $g.Inf })
    & ([scriptblock]::Create($code))
    return
}

# ================================================================ vigia: ícone fixo perto do relógio
if ($Watch) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $mtx = New-Object Threading.Mutex($false, 'Local\HollowDriversTray')
    if (-not $mtx.WaitOne(0)) { return }

    function New-TrayIcon([Drawing.Color]$c1, [Drawing.Color]$c2) {
        $bmp = New-Object Drawing.Bitmap(32, 32)
        $gr = [Drawing.Graphics]::FromImage($bmp); $gr.SmoothingMode = 'AntiAlias'; $gr.TextRenderingHint = 'AntiAliasGridFit'
        $r = New-Object Drawing.Rectangle(1, 1, 30, 30)
        $gr.FillEllipse((New-Object Drawing.Drawing2D.LinearGradientBrush($r, $c1, $c2, 45)), $r)
        $f = New-Object Drawing.Font('Segoe MDL2 Assets', 15, [Drawing.GraphicsUnit]::Pixel)
        $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $gr.DrawString([string][char]0xEA18, $f, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(0, 1, 32, 32)), $sf)
        $gr.Dispose()
        [Drawing.Icon]::FromHandle($bmp.GetHicon())
    }
    $icoOk = New-TrayIcon ([Drawing.Color]::FromArgb(52, 211, 153)) ([Drawing.Color]::FromArgb(16, 150, 110))
    $icoBad = New-TrayIcon ([Drawing.Color]::FromArgb(255, 90, 69)) ([Drawing.Color]::FromArgb(212, 20, 90))

    $ni = New-Object Windows.Forms.NotifyIcon
    $ni.Icon = $icoOk; $ni.Text = 'HollowDrivers'; $ni.Visible = $true
    $script:LastIssues = ''

    function Invoke-WatchCheck([bool]$manual) {
        $updLine = ''
        $st = Get-State
        $lastU = $null; if ($st.LastUpd) { try { $lastU = [datetime]$st.LastUpd } catch { } }
        if ($manual -or -not $lastU -or ((Get-Date) - $lastU).TotalHours -ge 24) {
            $online = $true
            try { $null = Invoke-WebRequest -UseBasicParsing -Method Head -Uri 'https://www.catalog.update.microsoft.com/' -TimeoutSec 15 } catch { $online = $false }
            if ($online) {
                $ups = @(); try { $ups = @(Get-DriverUpdates) } catch { }
                $key = @($ups | ForEach-Object Id) -join '|'
                $st = Get-State
                $isNew = $key -and $key -ne $st.UpdKey
                $st.LastUpd = (Get-Date).ToString('o'); $st.UpdKey = $key; Save-State $st
                if ($ups.Count -and ($isNew -or $manual)) {
                    $updLine = $(if ($ups.Count -eq 1) { '1 atualização de driver oficial disponível.' } else { "$($ups.Count) atualizações de driver oficiais disponíveis." })
                }
                $au = $null; try { $au = Get-AppUpdate $UpdateRepo $AppVersion } catch { }
                $st = Get-State
                if ($au -and ($manual -or $st.AppKey -ne $au.Version)) { $updLine = ("HollowDrivers $($au.Version) disponível. " + $updLine).Trim() }
                $st.AppKey = $(if ($au) { $au.Version } else { '' }); Save-State $st
            }
        }
        $issues = @(Get-WatchIssues)
        if ($issues.Count) {
            $ni.Icon = $icoBad
            $ni.Text = $(if ($issues.Count -eq 1) { 'HollowDrivers — 1 alerta' } else { 'HollowDrivers — {0} alertas' -f $issues.Count })
        } else { $ni.Icon = $icoOk; $ni.Text = 'HollowDrivers — tudo certo' }
        $key = $issues -join '|'
        if ($issues.Count -and ($manual -or $key -ne $script:LastIssues)) {
            $txt = (@($issues) + @($updLine | Where-Object { $_ })) -join "`n"
            $ni.ShowBalloonTip(20000, 'HollowDrivers — atenção', $txt.Substring(0, [Math]::Min(250, $txt.Length)), 'Warning')
        } elseif ($updLine) {
            $ni.ShowBalloonTip(15000, 'HollowDrivers', "$updLine Clique para abrir e atualizar.", 'Info')
        } elseif ($manual) {
            $ni.ShowBalloonTip(8000, 'HollowDrivers', 'Tudo certo com seus drivers.', 'Info')
        }
        $script:LastIssues = $key
    }

    $menu = New-Object Windows.Forms.ContextMenuStrip
    [void]$menu.Items.Add('Abrir HollowDrivers', $null, { Start-Launcher '' })
    [void]$menu.Items.Add('Verificar agora', $null, { Invoke-WatchCheck $true })
    [void]$menu.Items.Add('-')
    [void]$menu.Items.Add('Fechar vigia (volta ao reiniciar o PC)', $null, { $ni.Visible = $false; [Windows.Forms.Application]::Exit() })
    $ni.ContextMenuStrip = $menu
    $ni.add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Start-Launcher '' } })
    $ni.add_BalloonTipClicked({ Start-Launcher '' })

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 3600000
    $timer.add_Tick({ Invoke-WatchCheck $false })
    $timer.Start()
    Invoke-WatchCheck $false
    [Windows.Forms.Application]::Run()
    $ni.Dispose(); $mtx.ReleaseMutex()
    return
}

if ($SelfTest) {
    $g = Get-GpuInfo; $g | Format-List
    Get-SystemInfo | Format-List
    Get-Health | Format-List
    Get-InstallHistory $g.VenDev | Select-Object -First 5 | Format-Table -AutoSize
    Get-CrashList 90 | Group-Object Tipo | Select-Object Count, Name | Format-Table -AutoSize
    'Pacote do driver: ' + (Get-DriverPackage $g.Inf $g.Version | Out-String).Trim()
    "Vigia ligado: $(Test-WatchEnabled)"
    $s = Get-DriverScan
    'Drivers: {0} | problema: {1} | antigos: {2}' -f $s.Count, @($s | Where-Object { $_.Status -notin 'OK', 'Antigo' }).Count, @($s | Where-Object { $_.Status -eq 'Antigo' }).Count
    return
}

# ================================================================ interface (WPF)
# Uma janela por usuário/sessão, inclusive ao executar o .ps1 diretamente.
# Eventos são criados antes do mutex para preservar cliques durante a inicialização.
$instanceUser = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$instanceName = 'Local\HollowDrivers.UI.' + $instanceUser
$activateEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, ($instanceName + '.Activate'))
$rescueEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, ($instanceName + '.Rescue'))
$uiMutex = New-Object Threading.Mutex($false, $instanceName)
$ownsUiMutex = $false
try {
    try { $ownsUiMutex = $uiMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsUiMutex = $true }
    if (-not $ownsUiMutex) {
        # Transfere a permissão de foco recebida pelo clique para a janela existente.
        if (-not ('DG.InstanceFocus' -as [type])) {
            Add-Type -Namespace DG -Name InstanceFocus -MemberDefinition '[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int processId);'
        }
        $currentSession = (Get-Process -Id $PID).SessionId
        Get-Process -Name powershell -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $currentSession -and $_.MainWindowTitle -eq 'HollowDrivers' } |
            ForEach-Object { [void][DG.InstanceFocus]::AllowSetForegroundWindow($_.Id) }
        if ($Rescue) { [void]$rescueEvent.Set() }
        [void]$activateEvent.Set()
        return
    }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
$dwmOk = $false
# carrega pela memória: LoadFrom travaria o .exe e impediria a atualização automática de substituí-lo
if (Test-Path $Exe) { try { [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Exe)); $dwmOk = [bool]('DG.Dwm' -as [type]) } catch { } }
if (-not $dwmOk) { Add-Type -Namespace DG -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);' }

# A janela roda no PowerShell: define a identidade neste processo, antes de criar a UI,
# para a barra de tarefas usar o ícone da janela em vez do agrupamento do PowerShell.
if (-not ('DG.ShellIdentity' -as [type])) {
    Add-Type -Namespace DG -Name ShellIdentity -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)] public static extern void SetCurrentProcessExplicitAppUserModelID(string appId);'
}
[DG.ShellIdentity]::SetCurrentProcessExplicitAppUserModelID('HollowDrivers.Desktop')

$Hex = @{ bad = '#F87171'; warn = '#FBBF24'; ok = '#34D399'; info = '#8B93A1'; ask = '#FF6A55' }
# (a cor 'ask' segue o tema; é ajustada depois que o tema é carregado)
$Glyph = @{ bad = [string][char]0xE7BA; warn = [string][char]0xE946; ok = [string][char]0xE73E; info = [string][char]0xE946; ask = [string][char]0xE946 }

function Get-Plural([int]$n, [string]$one, [string]$many) { if ($n -eq 1) { "1 $one" } else { "$n $many" } }

# ---- temas de cores (a base continua escura; muda a cor de destaque e o brilho)
$Themes = [ordered]@{
    vermelho = @{ Nome = 'Vermelho'; A1 = '#FF5A45'; A2 = '#D4145A'; Glow = '#FF3B30'; Bg = '#2A1418'; Icon = '#FF6A55' }
    azul     = @{ Nome = 'Azul';     A1 = '#3B82F6'; A2 = '#4F46E5'; Glow = '#3B82F6'; Bg = '#111A2E'; Icon = '#60A5FA' }
    verde    = @{ Nome = 'Verde';    A1 = '#22C55E'; A2 = '#0D9488'; Glow = '#10B981'; Bg = '#0E2219'; Icon = '#4ADE80' }
    roxo     = @{ Nome = 'Roxo';     A1 = '#A855F7'; A2 = '#DB2777'; Glow = '#A855F7'; Bg = '#1E1230'; Icon = '#C084FC' }
    laranja  = @{ Nome = 'Laranja';  A1 = '#F59E0B'; A2 = '#EA580C'; Glow = '#F59E0B'; Bg = '#2A1D0C'; Icon = '#FBBF24' }
    ciano    = @{ Nome = 'Ciano';    A1 = '#06B6D4'; A2 = '#2563EB'; Glow = '#06B6D4'; Bg = '#0B1F26'; Icon = '#22D3EE' }
}
$SettingsFile = Join-Path $DataDir 'settings.json'
function Get-Settings {
    $h = @{ Theme = 'vermelho' }
    if (Test-Path $SettingsFile) { try { (Get-Content $SettingsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } } catch { } }
    $h
}
function Save-Settings($h) { $h | ConvertTo-Json | Set-Content $SettingsFile -Encoding UTF8 }
$ThemeKey = (Get-Settings).Theme
if (-not $Themes.Contains($ThemeKey)) { $ThemeKey = 'vermelho' }
$Theme = $Themes[$ThemeKey]
function Use-Theme([string]$x) {
    $x.Replace('__A1__', $Theme.A1).Replace('__A2__', $Theme.A2).Replace('__GLOW__', $Theme.Glow).Replace('__BGR__', $Theme.Bg).
      Replace('__ICON__', $Theme.Icon).Replace('__HALO__', '#1A' + $Theme.A1.Substring(1))
}

$ResXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <SolidColorBrush x:Key="Bg" Color="#0F1115"/>
  <SolidColorBrush x:Key="Surface" Color="#171A21"/>
  <SolidColorBrush x:Key="Surface2" Color="#1F232C"/>
  <SolidColorBrush x:Key="Stroke" Color="#2A2F3A"/>
  <SolidColorBrush x:Key="Text" Color="#E8EAED"/>
  <SolidColorBrush x:Key="Dim" Color="#8B93A1"/>
  <LinearGradientBrush x:Key="Accent" StartPoint="0,0" EndPoint="1,1">
    <GradientStop Color="__A1__" Offset="0"/>
    <GradientStop Color="__A2__" Offset="1"/>
  </LinearGradientBrush>
  <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
  <FontFamily x:Key="Display">Segoe UI Variable Display, Segoe UI</FontFamily>

  <Style x:Key="Pill" TargetType="Button">
    <Setter Property="Foreground" Value="{StaticResource Text}"/>
    <Setter Property="Background" Value="{StaticResource Surface2}"/>
    <Setter Property="BorderBrush" Value="{StaticResource Stroke}"/>
    <Setter Property="Padding" Value="16,8"/>
    <Setter Property="Margin" Value="0,0,8,8"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="B" CornerRadius="18" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#565E6E"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.75"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="PillAccent" TargetType="Button" BasedOn="{StaticResource Pill}">
    <Setter Property="Background" Value="{StaticResource Accent}"/>
    <Setter Property="BorderBrush" Value="Transparent"/>
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
  </Style>
  <Style x:Key="PillBad" TargetType="Button" BasedOn="{StaticResource Pill}">
    <Setter Property="Background" Value="#3A1D22"/>
    <Setter Property="BorderBrush" Value="#7A2E36"/>
    <Setter Property="Foreground" Value="#FCA5A5"/>
  </Style>
  <Style x:Key="Ghost" TargetType="Button">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border Background="Transparent" Padding="6,4"><ContentPresenter/></Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{StaticResource Text}"/></Trigger>
    </Style.Triggers>
  </Style>
  <Style x:Key="MenuBtn" TargetType="Button">
    <Setter Property="Foreground" Value="{StaticResource Text}"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="MinWidth" Value="340"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="B" CornerRadius="8" Background="Transparent" Padding="12,9">
            <ContentPresenter HorizontalAlignment="Left"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#2A2F3A"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="GroupLbl" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontSize" Value="10.5"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Margin" Value="3,0,0,7"/>
  </Style>
  <Style x:Key="SectionTitle" TargetType="TextBlock">
    <Setter Property="FontSize" Value="23"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontFamily" Value="{StaticResource Display}"/>
  </Style>
  <Style x:Key="SectionSub" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Margin" Value="0,5,0,0"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>
  <Style x:Key="Nav" TargetType="ToggleButton">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontSize" Value="13.5"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Margin" Value="0,0,0,4"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToggleButton">
          <Border x:Name="B" CornerRadius="10" Background="Transparent" Padding="12,11">
            <Grid>
              <Rectangle x:Name="Bar" Width="3" RadiusX="2" RadiusY="2" HorizontalAlignment="Left" Margin="-7,3,0,3" Fill="{StaticResource Accent}" Visibility="Collapsed"/>
              <StackPanel Orientation="Horizontal">
                <TextBlock FontFamily="{StaticResource Icons}" Text="{TemplateBinding Tag}" FontSize="15" VerticalAlignment="Center" Margin="0,0,12,0"/>
                <ContentPresenter VerticalAlignment="Center"/>
              </StackPanel>
            </Grid>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#1A1E26"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="B" Property="Background" Value="{StaticResource Surface2}"/>
              <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
              <Setter Property="Foreground" Value="{StaticResource Text}"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="NavBtn" TargetType="Button">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontSize" Value="13.5"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="B" CornerRadius="10" Background="Transparent" Padding="12,11">
            <StackPanel Orientation="Horizontal">
              <TextBlock FontFamily="{StaticResource Icons}" Text="{TemplateBinding Tag}" FontSize="14" VerticalAlignment="Center" Margin="0,0,12,0"/>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="B" Property="Background" Value="#1A1E26"/>
              <Setter Property="Foreground" Value="{StaticResource Text}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="Chip" TargetType="ToggleButton">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Margin" Value="0,0,8,0"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToggleButton">
          <Border x:Name="B" CornerRadius="14" Background="{StaticResource Surface2}" BorderBrush="{StaticResource Stroke}" BorderThickness="1" Padding="13,6">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#565E6E"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="B" Property="Background" Value="{StaticResource Accent}"/>
              <Setter TargetName="B" Property="BorderBrush" Value="Transparent"/>
              <Setter Property="Foreground" Value="White"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="TextBox">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Foreground" Value="{StaticResource Text}"/>
    <Setter Property="CaretBrush" Value="{StaticResource Text}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
  </Style>

  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="Box" Width="18" Height="18" CornerRadius="5" Background="{StaticResource Surface2}" BorderBrush="{StaticResource Stroke}" BorderThickness="1">
              <TextBlock x:Name="Tick" FontFamily="{StaticResource Icons}" Text="&#xE73E;" FontSize="11" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
            </Border>
            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
              <Setter TargetName="Box" Property="BorderBrush" Value="Transparent"/>
              <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="SlimThumb" TargetType="Thumb">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#3A404C"/></ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="8"/>
    <Setter Property="MinWidth" Value="8"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.Thumb><Thumb Style="{StaticResource SlimThumb}" Margin="0,2"/></Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="Orientation" Value="Horizontal">
        <Setter Property="Width" Value="Auto"/>
        <Setter Property="MinWidth" Value="0"/>
        <Setter Property="Height" Value="8"/>
        <Setter Property="MinHeight" Value="8"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="ScrollBar">
              <Track x:Name="PART_Track" IsDirectionReversed="False">
                <Track.Thumb><Thumb Style="{StaticResource SlimThumb}" Margin="2,0"/></Track.Thumb>
              </Track>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Trigger>
    </Style.Triggers>
  </Style>

  <Style TargetType="DataGrid">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Foreground" Value="{StaticResource Text}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="RowBackground" Value="Transparent"/>
    <Setter Property="AlternatingRowBackground" Value="#13161C"/>
    <Setter Property="GridLinesVisibility" Value="None"/>
    <Setter Property="HeadersVisibility" Value="Column"/>
    <Setter Property="SelectionMode" Value="Single"/>
    <Setter Property="SelectionUnit" Value="FullRow"/>
    <Setter Property="CanUserAddRows" Value="False"/>
    <Setter Property="CanUserDeleteRows" Value="False"/>
    <Setter Property="CanUserResizeRows" Value="False"/>
    <Setter Property="IsReadOnly" Value="True"/>
    <Setter Property="RowHeight" Value="34"/>
    <Setter Property="FontSize" Value="13"/>
  </Style>
  <Style TargetType="DataGridColumnHeader">
    <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="DataGridColumnHeader">
          <Border Background="Transparent" BorderBrush="{StaticResource Stroke}" BorderThickness="0,0,0,1" Padding="12,10">
            <StackPanel Orientation="Horizontal">
              <ContentPresenter VerticalAlignment="Center"/>
              <TextBlock x:Name="Arrow" FontFamily="{StaticResource Icons}" FontSize="9" Margin="6,1,0,0" VerticalAlignment="Center" Visibility="Collapsed"/>
            </StackPanel>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="SortDirection" Value="Ascending">
              <Setter TargetName="Arrow" Property="Text" Value="&#xE70E;"/>
              <Setter TargetName="Arrow" Property="Visibility" Value="Visible"/>
            </Trigger>
            <Trigger Property="SortDirection" Value="Descending">
              <Setter TargetName="Arrow" Property="Text" Value="&#xE70D;"/>
              <Setter TargetName="Arrow" Property="Visibility" Value="Visible"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="DataGridRow">
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1C2029"/></Trigger>
      <Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#262B36"/></Trigger>
    </Style.Triggers>
  </Style>
  <!-- dica com o texto inteiro quando a coluna corta (aparece depois de 2 segundos) -->
  <Style TargetType="ToolTip">
    <Setter Property="Foreground" Value="{StaticResource Text}"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="MaxWidth" Value="520"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToolTip">
          <Border Background="#20242E" BorderBrush="{StaticResource Stroke}" BorderThickness="1" CornerRadius="8" Padding="11,8">
            <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
            <ContentPresenter TextBlock.Foreground="{StaticResource Text}"/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="DataGridCell">
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="ToolTip" Value="{Binding RelativeSource={RelativeSource Self}, Path=Content.Text}"/>
    <Setter Property="ToolTipService.InitialShowDelay" Value="2000"/>
    <Setter Property="ToolTipService.ShowDuration" Value="30000"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="DataGridCell">
          <Border Background="Transparent" Padding="12,0"><ContentPresenter VerticalAlignment="Center"/></Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@

. (Join-Path $Here 'Views.ps1')

$app = [Windows.Application]::Current
if (-not $app) { $app = New-Object Windows.Application }
$app.ShutdownMode = 'OnMainWindowClose'
$app.Resources = [Windows.Markup.XamlReader]::Parse((Use-Theme $ResXaml))

$BrushConv = New-Object Windows.Media.BrushConverter
function Get-Brush([string]$hex) { $BrushConv.ConvertFromString($hex) }

function Set-DarkTitle($w) {
    $h = (New-Object Windows.Interop.WindowInteropHelper($w)).Handle
    $v = 1; [void][DG.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
    $c = 0x0015110F; [void][DG.Dwm]::DwmSetWindowAttribute($h, 35, [ref]$c, 4)
}

$Hex.ask = $Theme.Icon
$script:Win = [Windows.Markup.XamlReader]::Parse((Use-Theme $MainXaml))
$Win = $script:Win
$LogoFile = Join-Path $Here 'HollowDrivers-logo.png'
if (-not (Test-Path $LogoFile)) { $LogoFile = Join-Path $Here 'assets\HollowDrivers-logo.png' }
if (Test-Path $LogoFile) {
    $brandImage = New-Object Windows.Media.Imaging.BitmapImage
    $brandImage.BeginInit()
    $brandImage.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $brandImage.UriSource = [Uri]$LogoFile
    $brandImage.EndInit()
    $brandImage.Freeze()
    foreach ($brandName in 'BrandLogo1', 'BrandLogo2', 'BrandLogo3', 'BrandLogo4') {
        $brandControl = $Win.FindName($brandName)
        if ($brandControl) { $brandControl.Source = $brandImage }
    }
}
foreach ($n in 'HomeView', 'AdvView', 'BtnAdvanced', 'BtnHomeScan', 'BtnHomeConfig', 'FooterText', 'BigBtn', 'Spinner', 'SpinRot', 'BigIcon', 'BigLabel', 'VerdictBadge',
    'VerdictIcon', 'VerdictText', 'VerdictSub', 'Findings', 'BtnBack', 'GpuText', 'HealthText', 'BtnScan', 'BtnUpd', 'BtnGood',
    'HomeLogoText', 'HomeNavHome', 'HomeNavVideo', 'HomeNavSystem', 'HomeNavClean', 'HomeNavGuard', 'HomeNavWin', 'BtnAdvConfig', 'BtnRestore', 'BtnPoint', 'BtnAll', 'BtnHist', 'BtnEnable', 'BtnCrash', 'BtnWu', 'BtnSites', 'BtnCsv', 'BtnWatch', 'BtnDb', 'SitesPopup',
    'SitesList', 'SearchBox', 'ChkMs', 'DriverGrid', 'StatusText', 'EmptyText', 'GuardText',
    'NavDrivers', 'NavVideo', 'NavSystem', 'NavClean', 'NavGuard', 'NavWin', 'ConfigCol', 'ConfigRailBox', 'ConfigLogoText', 'BtnRailConfig', 'BtnConfigHome', 'ConfigNavDrivers', 'ConfigNavVideo', 'ConfigNavSystem', 'ConfigNavClean', 'ConfigNavGuard', 'ConfigNavWin', 'ConfigNavSettings', 'PanClean', 'CleanDrive', 'CleanSummary', 'CleanGrid', 'CleanStatus', 'BtnCleanScan', 'BtnCleanRun', 'BtnCleanWindows', 'BtnCleanSense', 'PanWin', 'ConfigView', 'BtnConfigClose', 'WuText', 'SrText', 'BtnWuHold', 'BtnWuKeep', 'BtnWuDrv', 'BtnSrPoint', 'BtnSrOpen', 'StorageText', 'BtnCleanup', 'BtnStorageSense', 'AdvCol', 'AdvLogoText', 'HomeRail', 'HomeRailBox', 'AdvRailBox', 'BtnRailHome', 'BtnRailAdv', 'ConfigThemes', 'ConfigUpd', 'BtnAppCheck', 'BtnAppInstall', 'SysText',
    'KeyCards', 'KeyCoverage', 'KeyResumo', 'BtnKeyAll', 'KeyGrid', 'BtnRescue', 'PanDrivers', 'PanVideo', 'PanSystem', 'PanGuard',
    'ChipAll', 'ChipBad', 'ChipOld', 'ChipVideo', 'ChipNet', 'ChipAudio') {
    Set-Variable -Name $n -Value $Win.FindName($n) -Scope Script
}
$Win.add_SourceInitialized({ Set-DarkTitle $Win })
if (Test-Path $IconFile) { try { $Win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$IconFile) } catch { } }
$FooterText.Text = "HollowDrivers $AppVersion  •  nada é instalado sem você confirmar  •  só avisos e sites oficiais"

# ---------------------------------------------------------------- diálogos

. (Join-Path $Here 'CloneAssistant.ps1')
$Win.FindName('BtnClone').add_Click({ Show-CloneAssistant })
$Win.FindName('BtnHistory').add_Click({ Show-OperationHistory })
$Win.FindName('BtnDiagnostics').add_Click({ Export-OperationDiagnostics })

function Show-Dialog([string]$head, [string]$body, [string]$kind = 'info', [switch]$YesNo, [string]$YesText = 'OK', [string]$NoText = 'Cancelar') {
    $d = [Windows.Markup.XamlReader]::Parse($DialogXaml)
    $col = $Hex[$kind]
    $d.FindName('Head').Text = $head
    $d.FindName('Body').Text = $body
    $ico = $d.FindName('Ico'); $ico.Text = $Glyph[$kind]; $ico.Foreground = Get-Brush $col
    $d.FindName('Badge').Background = Get-Brush ('#26' + $col.Substring(1))
    $yes = $d.FindName('Yes'); $yes.Content = $YesText
    $yes.add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
    if ($YesNo) {
        $no = $d.FindName('No'); $no.Content = $NoText; $no.Visibility = 'Visible'
        $no.add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $false })
    } else { $yes.IsCancel = $true }
    $d.add_MouseLeftButtonDown({ param($s, $e) try { $s.DragMove() } catch { } })
    if ($script:Win.IsLoaded) { $d.Owner = $script:Win } else { $d.WindowStartupLocation = 'CenterScreen' }
    [bool]$d.ShowDialog()
}

function Show-TableWindow([string]$title, $rows, [string]$note) {
    $rows = @($rows)
    $w = [Windows.Markup.XamlReader]::Parse($TableXaml)
    $w.Title = $title; $w.FindName('Head').Text = $title; $w.FindName('Note').Text = $note
    $t = New-Object Data.DataTable
    $names = @($rows[0].PSObject.Properties.Name)
    foreach ($n in $names) { if ($n -eq 'Destaque') { [void]$t.Columns.Add($n, [bool]) } else { [void]$t.Columns.Add($n) } }
    foreach ($r in $rows) {
        $row = $t.NewRow()
        foreach ($n in $names) { $row[$n] = $(if ($n -eq 'Destaque') { [bool]$r.$n } else { "$($r.$n)" }) }
        $t.Rows.Add($row)
    }
    $g = $w.FindName('G')
    $g.add_AutoGeneratingColumn({ param($s, $e)
        if ($e.PropertyName -eq 'Destaque') { $e.Cancel = $true }
        elseif ($e.PropertyName -in 'Detalhe', 'Titulo', 'Tipo', 'Estado') { $e.Column.Width = New-Object Windows.Controls.DataGridLength(1, 'Star') }
    })
    $g.ItemsSource = $t.DefaultView
    $w.FindName('Close').add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).Close() })
    $w.add_SourceInitialized({ param($s, $e) Set-DarkTitle $s })
    $w.Owner = $script:Win
    [void]$w.ShowDialog()
}

# ---------------------------------------------------------------- tarefas em segundo plano (a tela não trava)

. (Join-Path $Here 'Operations.ps1')

$LogicText = $Logic.ToString()
$ScanCode = @'
$gpu = Get-GpuInfo
[pscustomobject]@{ Rows = @(Get-DriverScan); Gpu = $gpu; History = @(if ($gpu) { Get-InstallHistory $gpu.VenDev }); Health = Get-Health; SysInfo = Get-SystemInfo; Keys = @(Get-KeyDrivers) }
'@
$WuCode = @'
$se = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
$r = $se.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
foreach ($u in $r.Updates) {
    [pscustomobject]@{
        Titulo = $u.Title; Fabricante = $u.DriverManufacturer; Modelo = $u.DriverModel; Classe = $u.DriverClass
        Data = $(if ($u.DriverVerDate) { ([datetime]$u.DriverVerDate).ToString('dd/MM/yyyy') } else { '' })
    }
}
'@

# ---------------------------------------------------------------- estado + tabela

$script:Problems = 0; $script:Old = 0; $script:LastScan = $null; $script:History = @(); $script:NeedReboot = @()
$script:Keys = @(); $script:KeyChanges = @(); $script:KeySel = $null
$script:Gpu = $null; $script:Health = $null; $script:SysInfo = $null; $script:Scanning = $false
$script:BackupBusy = $false; $script:BackupVersion = $null; $script:AfterRestore = $null

$dt = New-Object Data.DataTable
foreach ($col in @(
        @('Ordem', [int]), @('Status', [string]), @('Cor', [string]), @('Categoria', [string]), @('Dispositivo', [string]),
        @('Fabricante', [string]), @('Versao', [string]), @('Data', [datetime]), @('Idade', [double]),
        @('INF', [string]), @('Microsoft', [bool]))) {
    [void]$dt.Columns.Add($col[0], $col[1])
}
$dt.DefaultView.Sort = 'Ordem ASC, Categoria ASC, Dispositivo ASC'

# lista completa da seção "Meus drivers" (os cartões ficam acima dela)
$kt = New-Object Data.DataTable
foreach ($col in @('Ordem', 'Estado', 'Cor', 'Categoria', 'Nome', 'Fabricante', 'Versao', 'Backup', 'Id')) { [void]$kt.Columns.Add($col) }
$kt.Columns['Ordem'].DataType = [int]
$kt.DefaultView.Sort = 'Ordem ASC, Categoria ASC, Nome ASC'

$DriverGrid.ItemsSource = $dt.DefaultView

function Add-Line($tb, [string]$text, [string]$hex = '#E8EAED', [double]$size = 13.5, [bool]$bold = $false) {
    if ($tb.Inlines.Count) { $tb.Inlines.Add((New-Object Windows.Documents.LineBreak)) }
    $r = New-Object Windows.Documents.Run($text)
    $r.Foreground = Get-Brush $hex; $r.FontSize = $size
    if ($bold) { $r.FontWeight = [Windows.FontWeights]::SemiBold }
    $tb.Inlines.Add($r)
}

function Set-Status([string]$extra) {
    $t = '{0} exibidos  •  {1} com problema  •  {2} (4+ anos)' -f $dt.DefaultView.Count, $script:Problems, (Get-Plural $script:Old 'antigo' 'antigos')
    if ($script:LastScan) { $t += '  •  escaneado às {0:HH:mm}' -f $script:LastScan }
    if ($extra) { $t += "  •  $extra" }
    $StatusText.Text = $t
}

$script:Chip = 'all'
$ChipNames = 'ChipAll', 'ChipBad', 'ChipOld', 'ChipVideo', 'ChipNet', 'ChipAudio'

function Set-Chip($btn) {
    foreach ($n in $ChipNames) {
        $c = Get-Variable $n -Scope Script -ValueOnly
        $c.IsChecked = ($c -eq $btn)
    }
    $script:Chip = "$($btn.Tag)"
    Update-Filter
}

# contagem em cada filtro rápido, respeitando a opção "mostrar drivers da Microsoft"
function Update-ChipCounts {
    $rows = @($dt.Rows | Where-Object { $ChkMs.IsChecked -or -not $_['Microsoft'] })
    $n = @{
        ChipAll = $rows.Count
        ChipBad = @($rows | Where-Object { $_['Ordem'] -eq 0 }).Count
        ChipOld = @($rows | Where-Object { $_['Ordem'] -eq 1 }).Count
        ChipVideo = @($rows | Where-Object { $_['Categoria'] -eq 'Vídeo' }).Count
        ChipNet = @($rows | Where-Object { $_['Categoria'] -eq 'Rede' }).Count
        ChipAudio = @($rows | Where-Object { $_['Categoria'] -eq 'Áudio' }).Count
    }
    $lbl = @{ ChipAll = 'Todos'; ChipBad = 'Com problema'; ChipOld = 'Antigos'; ChipVideo = 'Vídeo'; ChipNet = 'Rede'; ChipAudio = 'Áudio' }
    foreach ($k in $ChipNames) {
        $c = Get-Variable $k -Scope Script -ValueOnly
        $c.Content = '{0}  {1}' -f $lbl[$k], $n[$k]
        $c.Opacity = $(if ($n[$k] -eq 0 -and -not $c.IsChecked) { 0.45 } else { 1 })
    }
}

function Update-Filter {
    $parts = @()
    if (-not $ChkMs.IsChecked) { $parts += 'Microsoft = false' }
    switch ($script:Chip) {
        'bad' { $parts += 'Ordem = 0' }
        'old' { $parts += 'Ordem = 1' }
        'all' { }
        default { $parts += "Categoria = '$($script:Chip)'" }
    }
    $q = ($SearchBox.Text -replace "[\[\]\*%']", '').Trim()
    if ($q) { $parts += "(Dispositivo LIKE '*$q*' OR Fabricante LIKE '*$q*' OR Categoria LIKE '*$q*')" }
    $dt.DefaultView.RowFilter = ($parts -join ' AND ')
    Update-ChipCounts
    if ($dt.DefaultView.Count -eq 0) {
        $EmptyText.Text = $(if ($q) { "Nenhum driver com `"$q`".`nTente outro nome ou limpe a busca." }
            elseif ($script:Chip -eq 'bad') { "Nenhum driver com problema.`nEstá tudo funcionando." }
            elseif ($script:Chip -eq 'old') { "Nenhum driver antigo (4+ anos)." }
            elseif ($script:LastScan) { "Nenhum driver nesta categoria.`nMarque `"mostrar drivers da Microsoft`" para ver os genéricos." }
            else { 'Clique em Escanear para listar os drivers.' })
        $EmptyText.Visibility = 'Visible'
    } else { $EmptyText.Visibility = 'Collapsed' }
    Set-Status
}

function Update-WatchButton {
    if (Test-WatchEnabled) { $BtnWatch.Content = 'Vigia automático: ligado'; $BtnWatch.Foreground = Get-Brush $Hex.ok }
    else { $BtnWatch.Content = 'Vigia automático: desligado'; $BtnWatch.Foreground = Get-Brush $Hex.info }
}

# ---------------------------------------------------------------- fabricante: links e instruções certas para este PC

function Get-OfficialLinks {
    $links = [ordered]@{}
    $v = if ($script:Gpu) { $script:Gpu.Vendor } else { '' }
    $si = $script:SysInfo
    $amd = 'https://www.amd.com/en/support/download/drivers.html'
    $intel = 'https://www.intel.com.br/content/www/br/pt/support/detect.html'
    switch ($v) {
        'AMD' {
            $label = if ($si -and $si.CpuVendor -eq 'AMD') { 'AMD — vídeo e chipset (baixe o Full Install)' } else { 'AMD — driver de vídeo (baixe o Full Install)' }
            $links[$label] = $amd
        }
        'NVIDIA' { $links['NVIDIA — driver de vídeo'] = 'https://www.nvidia.com/pt-br/drivers/' }
        'Intel' { $links['Intel — vídeo e chipset (assistente oficial)'] = $intel }
    }
    if ($si) {
        if ($si.CpuVendor -eq 'AMD' -and $v -ne 'AMD') { $links['AMD — chipset do processador'] = $amd }
        if ($si.CpuVendor -eq 'Intel' -and $v -ne 'Intel') { $links['Intel — chipset (assistente oficial)'] = $intel }
        # notebook: suporte do fabricante do notebook (modelo completo); desktop: fabricante da placa-mãe
        if ($si.IsLaptop) { $m = $si.Maker; $model = $si.Model; $what = 'drivers do notebook' }
        else { $m = $si.BoardMaker; $model = $si.BoardModel; $what = 'BIOS, rede e áudio' }
        if ($m -and $m -notmatch 'To Be Filled|Default string|System manufacturer') {
            $short = switch -regex ($m) {
                'ASUS' { 'ASUS'; break } 'Micro-Star|MSI' { 'MSI'; break } 'Gigabyte' { 'Gigabyte'; break } 'ASRock' { 'ASRock'; break }
                'Dell' { 'Dell'; break } 'Lenovo' { 'Lenovo'; break } 'HP|Hewlett' { 'HP'; break } 'Acer' { 'Acer'; break }
                'Samsung' { 'Samsung'; break } 'Positivo' { 'Positivo'; break } 'Avell' { 'Avell'; break } 'VAIO|Sony' { 'VAIO'; break }
                default { $m }
            }
            $url = switch ($short) {
                'ASUS' { 'https://www.asus.com/support/download-center/' } 'MSI' { 'https://www.msi.com/support/download' }
                'Gigabyte' { 'https://www.gigabyte.com/Support' } 'ASRock' { 'https://www.asrock.com/support/index.asp' }
                'Dell' { 'https://www.dell.com/support/home' } 'Lenovo' { 'https://pcsupport.lenovo.com' }
                'HP' { 'https://support.hp.com/drivers' } 'Acer' { 'https://www.acer.com/support' }
                default { 'https://www.google.com/search?q=' + [uri]::EscapeDataString("$m $model drivers suporte oficial") }
            }
            $links["$short $model — $what"] = $url
        }
    }
    $links['Windows Update'] = 'ms-settings:windowsupdate'
    $links['Gerenciador de Dispositivos'] = 'devmgmt.msc'
    $links
}

function Update-Sites {
    $SitesList.Children.Clear()
    $links = Get-OfficialLinks
    foreach ($k in $links.Keys) {
        $b = New-Object Windows.Controls.Button
        $b.Content = $k; $b.Tag = $links[$k]; $b.Style = $app.Resources['MenuBtn']
        $b.add_Click({ param($s, $e) $SitesPopup.IsOpen = $false; Start-Process $s.Tag })
        [void]$SitesList.Children.Add($b)
    }
}

function Get-FixSteps {
    switch ($script:Gpu.Vendor) {
        'AMD' { "1.  Baixe no site da AMD o instalador COMPLETO (Full Install) — não o de poucos MB.`n2.  Instale e reinicie o PC." }
        'NVIDIA' { "1.  Baixe o driver Game Ready do seu modelo no site da NVIDIA.`n2.  Instale e reinicie o PC." }
        'Intel' { "1.  Abra o assistente oficial de drivers da Intel.`n2.  Instale o driver de vídeo sugerido e reinicie o PC." }
        default { "1.  Baixe o driver de vídeo no site do fabricante da sua placa.`n2.  Instale e reinicie o PC." }
    }
}

# ---------------------------------------------------------------- cartões do modo avançado

function Update-Cards {
    $g = $script:Gpu; $b = Get-Baseline; $hl = $script:Health
    $bk = if ($b) { Get-Backup $b.Version } else { $null }
    $GpuText.Inlines.Clear()
    Add-Line $GpuText 'PLACA DE VÍDEO' $Hex.info 11 $true
    if (-not $g) {
        Add-Line $GpuText 'Nenhuma placa de vídeo PCI encontrada.' $Hex.bad 15 $true
    } else {
        Add-Line $GpuText $g.Name '#E8EAED' 19 $true
        Add-Line $GpuText ('Driver {0}   •   {1}' -f $g.Version, $g.Inf) '#C9CED6'
        if ($g.Code -eq 0) { Add-Line $GpuText '●  Funcionando — aceleração 3D ativa' $Hex.ok }
        else { Add-Line $GpuText ('●  {0} — jogos não vão abrir' -f (Get-ProblemText $g.Code)) $Hex.bad 13.5 $true }
        if ($g.Code -eq 22) { Add-Line $GpuText '●  Não é falta de driver: a placa está desligada no Windows. Use "Reativar placa".' $Hex.warn 12.5 }
        if (-not $b) { Add-Line $GpuText '●  Sem backup: faça uma cópia enquanto está funcionando' $Hex.warn }
        elseif ($b.Version -eq $g.Version) { Add-Line $GpuText ('●  Igual ao driver salvo em {0}' -f $b.Marcado) $Hex.ok }
        else { Add-Line $GpuText ('●  DRIVER TROCADO — o salvo era {0}' -f $b.Version) $Hex.bad 13.5 $true }
        if ($script:BackupBusy) { Add-Line $GpuText '●  Backup: copiando o driver...' $Hex.info }
        elseif ($bk) { Add-Line $GpuText ('●  Backup: {0}  ({1:N0} MB, {2})' -f $bk.Version, $bk.SizeMB, $bk.Date) $Hex.ok }
        elseif ($b) { Add-Line $GpuText '●  Backup: nenhum' $Hex.warn }
        if ($script:History.Count) {
            $h = $script:History[0]
            Add-Line $GpuText ('Última instalação: {0:dd/MM/yyyy HH:mm} — {1}' -f $h.Quando, $h.Origem) $(if ($h.Origem -like 'Driver Booster*') { $Hex.bad } else { $Hex.info }) 12.5
        }
    }
    $HealthText.Inlines.Clear()
    Add-Line $HealthText 'SAÚDE DO SISTEMA  •  30 DIAS' $Hex.info 11 $true
    if ($hl.Crashes) {
        Add-Line $HealthText (Get-Plural $hl.Crashes 'desligamento inesperado' 'desligamentos inesperados') $Hex.bad 19 $true
        Add-Line $HealthText ('Último em {0:dd/MM HH:mm}' -f $hl.LastCrash) '#C9CED6'
        if (-not $hl.Tdr) { Add-Line $HealthText 'Sem erro de driver → suspeite da fonte/energia' $Hex.info 12.5 }
    } else { Add-Line $HealthText 'Nenhuma queda' $Hex.ok 19 $true }
    Add-Line $HealthText ('Drivers com problema: {0}   •   {1}' -f $script:Problems, (Get-Plural $script:Old 'antigo' 'antigos')) $(if ($script:Problems) { $Hex.bad } else { '#C9CED6' })
    $ab = Get-AllBackupInfo
    if ($ab) { Add-Line $HealthText ('●  Backup dos drivers: {0} ({1} drivers)' -f $ab.Date, $ab.Count) $Hex.ok }
    else { Add-Line $HealthText '●  Backup dos drivers: nenhum' $Hex.warn }
    if ($hl.DriverBooster.Count) { Add-Line $HealthText '●  Driver Booster instalado' $Hex.bad 13.5 $true }
    else { Add-Line $HealthText '●  Driver Booster não instalado' $Hex.ok }
    $BtnDb.Visibility = $(if ($hl.DriverBooster.Count) { 'Visible' } else { 'Collapsed' })

    Update-KeyCards
    Update-SysCard

    $GuardText.Inlines.Clear()
    Add-Line $GuardText 'VIGIA AUTOMÁTICO' $Hex.info 11 $true
    if (Test-WatchEnabled) { Add-Line $GuardText 'Ligado' $Hex.ok 19 $true }
    else { Add-Line $GuardText 'Desligado' $Hex.warn 19 $true }
    Add-Line $GuardText 'Um escudo fica perto do relógio: verde quando está tudo certo, vermelho quando há alerta. O HollowDrivers confere ao ligar o PC e a cada hora.' '#C9CED6' 13
    Add-Line $GuardText '●  avisa se o driver de vídeo for trocado' $Hex.info 12.5
    Add-Line $GuardText '●  avisa se a placa de vídeo der erro' $Hex.info 12.5
    Add-Line $GuardText '●  avisa se o PC cair desde a última verificação' $Hex.info 12.5
    Add-Line $GuardText '●  avisa se o Driver Booster voltar' $Hex.info 12.5
    Add-Line $GuardText '●  procura versões novas de driver uma vez por dia' $Hex.info 12.5
    Add-Line $GuardText 'Não instala nada sozinho e não deixa o PC lento.' '#C9CED6' 12.5
    if (Test-RescueTask) { Add-Line $GuardText '●  Socorro automático: ligado (restaura o vídeo sozinho ao ligar o PC)' $Hex.ok 13 }
    else { Add-Line $GuardText '●  Socorro automático: desligado (a restauração pede sua confirmação)' $Hex.info 13 }
    $ult = Get-ChildItem $DataDir -Filter 'socorro-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($ult) {
        $txt = Get-Content $ult.FullName -Raw
        $res = if ($txt -match 'INSTALAR=0') { 'driver restaurado' } elseif ($txt -match 'ERRO=(.+)') { 'falhou: ' + $matches[1] } else { 'tentativa registrada' }
        Add-Line $GuardText ('Último socorro: {0:dd/MM/yyyy HH:mm} — {1}' -f $ult.LastWriteTime, $res) $Hex.warn 12.5
    }
    if ($hl.DriverBooster.Count) { Add-Line $GuardText ('⚠  Driver Booster instalado em {0}' -f $hl.DriverBooster[0].Path) $Hex.bad 13 $true }
    $BtnRestore.IsEnabled = [bool]$bk -and -not $script:BackupBusy
    $BtnGood.IsEnabled = -not $script:BackupBusy
    $BtnEnable.Visibility = $(if ($g -and $g.Code -eq 22 -and $g.Pnp) { 'Visible' } else { 'Collapsed' })
}

# ---------------------------------------------------------------- seção "Meus drivers"

$CatIcon = @{ 'Vídeo' = [char]0xE7F4; 'Rede' = [char]0xE839; 'Áudio' = [char]0xE767; 'Chipset' = [char]0xE964; 'Armazenamento' = [char]0xEDA2; 'Bluetooth' = [char]0xE702 }

# texto que pode ser cortado: mostra o conteúdo inteiro ao deixar o mouse parado 2 segundos
function Set-Dica($elemento, [string]$texto) {
    $elemento.ToolTip = $texto
    [Windows.Controls.ToolTipService]::SetInitialShowDelay($elemento, 2000)
    [Windows.Controls.ToolTipService]::SetShowDuration($elemento, 30000)
}

function New-KeyCard($k, $estado, $cor, $bk) {
    $card = New-Object Windows.Controls.Border
    $card.Width = 324; $card.Margin = '0,0,10,10'; $card.Padding = '16,14'; $card.CornerRadius = 16
    $card.Background = Get-Brush '#171A21'; $card.BorderBrush = Get-Brush $(if ($estado -eq 'TROCADO') { $cor } else { '#2A2F3A' }); $card.BorderThickness = $(if ($estado -eq 'TROCADO') { 2 } else { 1 })
    $sp = New-Object Windows.Controls.StackPanel

    # linha de cima: categoria + situação
    $top = New-Object Windows.Controls.DockPanel
    $sit = New-Object Windows.Controls.TextBlock
    $sit.Text = $(if ($estado -eq 'Como sempre esteve') { 'Sem alterações' } else { $estado }); $sit.Foreground = Get-Brush $cor; $sit.FontSize = 11.5; $sit.FontWeight = [Windows.FontWeights]::SemiBold
    [Windows.Controls.DockPanel]::SetDock($sit, 'Right'); [void]$top.Children.Add($sit)
    $cat = New-Object Windows.Controls.TextBlock
    $cat.FontSize = 11.5; $cat.Foreground = Get-Brush $Hex.info; $cat.FontWeight = [Windows.FontWeights]::SemiBold
    $ic = New-Object Windows.Documents.Run ("$($CatIcon[$k.Categoria])  ")
    $ic.FontFamily = $app.Resources['Icons']
    $cat.Inlines.Add($ic); $cat.Inlines.Add((New-Object Windows.Documents.Run $k.Categoria.ToUpper()))
    [void]$top.Children.Add($cat)
    [void]$sp.Children.Add($top)

    $nome = New-Object Windows.Controls.TextBlock
    $nome.Text = $k.Nome; $nome.FontSize = 14.5; $nome.FontWeight = [Windows.FontWeights]::SemiBold
    $nome.TextWrapping = 'Wrap'; $nome.Margin = '0,8,0,0'; $nome.Height = 40; $nome.TextTrimming = 'CharacterEllipsis'
    Set-Dica $nome $k.Nome
    [void]$sp.Children.Add($nome)

    $det = New-Object Windows.Controls.TextBlock
    $det.FontSize = 12.5; $det.Foreground = Get-Brush '#C9CED6'; $det.Margin = '0,2,0,0'; $det.TextTrimming = 'CharacterEllipsis'
    $det.Text = '{0}  •  {1}{2}{3}' -f $k.Fabricante, $k.Versao, $(if ($k.Data) { ' de {0:MM/yyyy}' -f $k.Data } else { '' }),
        $(if ($k.Qtd -gt 1) { "  •  $($k.Qtd) dispositivos" } else { '' })
    Set-Dica $det ("{0}`nVersão {1}{2}`nArquivo: {3}{4}" -f $k.Nome, $k.Versao,
        $(if ($k.Data) { ' de {0:dd/MM/yyyy}' -f $k.Data } else { '' }), $k.Inf,
        $(if ($k.Qtd -gt 1) { "`n$($k.Qtd) dispositivos usam este mesmo driver" } else { '' }))
    [void]$sp.Children.Add($det)

    $cop = New-Object Windows.Controls.TextBlock
    $cop.FontSize = 12.5; $cop.Margin = '0,6,0,0'
    if ($bk) {
        $cop.Text = '● Cópia salva: {0:N0} MB, {1}' -f $bk.SizeMB, $bk.Date; $cop.Foreground = Get-Brush $Hex.ok
        Set-Dica $cop ("Cópia guardada em {0}`nVersão {1}  •  {2:N0} MB  •  feita em {3}" -f $bk.Path, $bk.Version, $bk.SizeMB, $bk.Date)
    } else {
        $cop.Text = '● Sem cópia salva'; $cop.Foreground = Get-Brush $Hex.warn
        Set-Dica $cop 'Sem cópia guardada: se este driver for trocado e der problema, não há como voltar com um clique.'
    }
    [void]$sp.Children.Add($cop)

    $acoes = New-Object Windows.Controls.WrapPanel
    $acoes.Margin = '0,12,0,0'
    foreach ($a in @(
            @{ T = $(if ($bk) { 'Refazer cópia' } else { 'Fazer backup' }); S = $(if ($bk) { 'Pill' } else { 'PillAccent' }); F = 'backup'; E = $true },
            @{ T = 'Restaurar'; S = 'Pill'; F = 'restore'; E = [bool]$bk },
            @{ T = 'Origem'; S = 'Pill'; F = 'hist'; E = $true })) {
        $b = New-Object Windows.Controls.Button
        $b.Content = $a.T; $b.Style = $app.Resources[$a.S]; $b.Tag = ('{0}|{1}' -f $a.F, $k.Id)
        $b.FontSize = 12; $b.Padding = '12,6'; $b.Margin = '0,0,6,0'; $b.IsEnabled = $a.E
        $b.add_Click({ param($s, $e)
            $acao, $id = "$($s.Tag)" -split '\|', 2
            switch ($acao) { 'backup' { Act-KeyBackup $id } 'restore' { Act-KeyRestore $id } 'hist' { Act-KeyHist $id } }
        })
        [void]$acoes.Children.Add($b)
    }
    [void]$sp.Children.Add($acoes)
    $card.Child = $sp
    $card
}

function Update-KeyCards {
    $base = Get-KeyBaselines
    $KeyCards.Children.Clear()
    $semCopia = 0; $trocados = 0
    $ordenado = @($script:Keys | Sort-Object @{ e = { switch ($_.Categoria) { 'Vídeo' { 0 } 'Chipset' { 1 } 'Rede' { 2 } 'Áudio' { 3 } default { 4 } } } }, Nome)
    $kt.BeginLoadData(); $kt.Clear()
    foreach ($k in $ordenado) {
        $b = $base[$k.Id]
        if (-not $b) { $ord = 1; $est = 'Nunca visto'; $cor = $Hex.warn }
        elseif ($b.Versao -ne $k.Versao) { $ord = 0; $est = 'TROCADO'; $cor = $Hex.bad; $trocados++ }
        else { $ord = 2; $est = 'Como sempre esteve'; $cor = $Hex.ok }
        $bk = if ($k.Categoria -eq 'Vídeo') { Get-Backup (Get-Baseline).Version } else { Get-DeviceBackup $k.Id }
        if (-not $bk) { $semCopia++ }
        # o vídeo já tem o cartão grande lá em cima: não repete aqui (continua na lista completa)
        if ($k.Categoria -ne 'Vídeo') { [void]$KeyCards.Children.Add((New-KeyCard $k $est $cor $bk)) }
        [void]$kt.Rows.Add($ord, $est, $cor, $k.Categoria, $(if ($k.Qtd -gt 1) { '{0}  ({1} dispositivos)' -f $k.Nome, $k.Qtd } else { $k.Nome }), $k.Fabricante, $k.Versao,
            $(if ($bk) { '{0:N0} MB' -f $bk.SizeMB } else { '—' }), $k.Id)
    }
    $kt.EndLoadData()
    if (-not $KeyGrid.ItemsSource) { $KeyGrid.ItemsSource = $kt.DefaultView }
    $KeyCoverage.Text = '{0} de {1} com cópia salva' -f ($script:Keys.Count - $semCopia), $script:Keys.Count
    $KeyResumo.Text = 'Cópias individuais por driver' + $(if ($trocados) { "  •  $trocados alterado(s)" } else { '  •  nenhuma alteração detectada' })
    $BtnKeyAll.IsEnabled = ($semCopia -gt 0)
    $BtnKeyAll.Content = $(if ($semCopia -gt 0) { 'Fazer backup dos {0} restantes' -f $semCopia } else { 'Todos com cópia salva' })
}

# cartão com processador, placa-mãe, BIOS, chipset e memória
function Update-SysCard {
    $si = $script:SysInfo
    $SysText.Inlines.Clear()
    Add-Line $SysText 'ESTE COMPUTADOR' $Hex.info 11 $true
    if (-not $si) { return }
    Add-Line $SysText $si.Cpu '#E8EAED' 15 $true
    Add-Line $SysText ('{0} núcleos / {1} threads   •   {2} GB de RAM a {3} MHz ({4} pente(s))' -f $si.Cores, $si.Threads, $si.RamGB, $si.RamSpeed, $si.RamSlots) '#C9CED6' 12.5
    $nome = if ($si.IsLaptop -and $si.Model) { '{0} {1}' -f $si.Maker, $si.Model } else { '{0} {1}' -f $si.BoardMaker, $si.BoardModel }
    Add-Line $SysText $nome.Trim() '#C9CED6'
    $anos = { param($d) if ($d) { [math]::Round(((Get-Date) - $d).TotalDays / 365.25, 1) } else { $null } }
    $ab = & $anos $si.BiosDate
    if ($si.BiosVer) {
        $txt = 'BIOS {0}{1}' -f $si.BiosVer, $(if ($si.BiosDate) { ' de {0:MM/yyyy}' -f $si.BiosDate } else { '' })
        # idade não prova que exista versão nova: a placa pode já estar na última. Só informa.
        if ($ab -and $ab -ge 2) { Add-Line $SysText ('●  ' + $txt + " — {0} anos; vale conferir no site do fabricante (pode já ser a última)" -f $ab) $Hex.warn }
        else { Add-Line $SysText ('●  ' + $txt) $Hex.ok }
    }
    $ac = & $anos $si.ChipsetDate
    if ($si.ChipsetVer) {
        $txt = 'Chipset {0} {1}{2}' -f $si.ChipsetMaker, $si.ChipsetVer, $(if ($si.ChipsetDate) { ' de {0:MM/yyyy}' -f $si.ChipsetDate } else { '' })
        if ($ac -and $ac -ge 2) { Add-Line $SysText ('●  ' + $txt + ' — {0} anos; o botão "Atualizar drivers" confere se há versão nova' -f $ac) $Hex.warn }
        else { Add-Line $SysText ('●  ' + $txt) $Hex.ok }
    } else { Add-Line $SysText '●  Driver de chipset não encontrado' $Hex.warn }
}

function Get-KeySel([string]$id) { @($script:Keys | Where-Object { $_.Id -eq $id })[0] }

# o usuário não precisa salvar referência: a primeira análise já registra o "normal" do PC,
# e o backup de um driver atualiza a referência dele.
function Set-KeyNormal($somente) {
    $base = Get-KeyBaselines
    $agora = (Get-Date).ToString('dd/MM/yyyy HH:mm')
    foreach ($k in $script:Keys) {
        if ($somente -and $somente -ne $k.Id) { continue }
        $base[$k.Id] = [pscustomobject]@{ Id = $k.Id; Nome = $k.Nome; Categoria = $k.Categoria; Versao = $k.Versao; Inf = $k.Inf; Marcado = $agora }
    }
    @($base.Values) | ConvertTo-Json -Depth 4 | Set-Content $KeyFile -Encoding UTF8
    $script:KeyChanges = @(Get-KeyChanges $script:Keys)
}

# mostra o que mudou e pergunta se a versão nova pode virar o novo normal
function Act-KeyChanges {
    $ch = @($script:KeyChanges)
    if (-not $ch.Count) { return }
    $rows = @($ch | ForEach-Object { [pscustomobject]@{ Categoria = $_.Categoria; Dispositivo = $_.Nome; Antes = $_.Antes; Agora = $_.Agora } })
    Show-TableWindow 'Drivers principais que mudaram' $rows 'Se algo parou de funcionar depois dessas trocas, restaure o backup em "Meus drivers".'
    if (Show-Dialog 'Está tudo funcionando?' ("Marcar as versões atuais como o normal deste PC?`n`nSe sim, o HollowDrivers para de avisar sobre essas trocas e passa a vigiar a partir delas.`nSe algo está ruim, escolha Não e restaure o backup.") 'ask' -YesNo -YesText 'Está tudo bem' -NoText 'Ainda não') {
        Set-KeyNormal $null
        Update-KeyCards; Update-Cards; Update-Home
    }
}

function Act-KeyBackup([string]$id) {
    $k = Get-KeySel $id
    if (-not $k) { return }
    if ($k.Categoria -eq 'Vídeo') { Act-MarkGood; return }
    $pkg = Get-DriverPackage $k.Inf $k.Versao
    if (-not $pkg) { [void](Show-Dialog 'Backup não disponível' 'Não encontrei o pacote desse driver dentro do Windows.' 'warn'); return }
    $mb = [math]::Round(((Get-ChildItem $pkg.Folder -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 1)
    if (-not (Show-Dialog 'Backup do driver' ("Guardar uma cópia do driver de {0}?`n`n{1}`nVersão {2}  •  cerca de {3} MB`n`nCom a cópia salva, dá para voltar para esta versão com um clique." -f $k.Categoria.ToLower(), $k.Nome, $k.Versao, $mb) 'ask' -YesNo -YesText 'Fazer backup')) { return }
    $dst = Join-Path $BackupDir ('dev-{0}-{1}' -f ($k.Inf -replace '\W', ''), $k.Versao)
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $script:KeyBkId = $k.Id
    $KeyResumo.Text = 'Copiando o driver de {0}...' -f $k.Categoria.ToLower()
    $code = Expand-Tpl $BackupTpl @{ '__SRC__' = $pkg.Folder; '__DST__' = $dst; '__VER__' = $k.Versao; '__NAME__' = $k.Nome; '__INF__' = $pkg.Inf
        '__VENDOR__' = $k.Fabricante; '__DEVID__' = $k.Id; '__CLASSGUID__' = ($k.ClassGuid -replace '[{}]', ''); '__CAT__' = $k.Categoria }
    Start-Bg $code {
        param($out, $err)

        $rc = if ($null -ne $out -and $out.Count) { [int]"$($out[$out.Count - 1])" } else { 99 }
        if ($err -or $rc -ge 8) { [void](Show-Dialog 'Backup falhou' "Não foi possível copiar o driver (código $rc).`n$err" 'bad') }
        else { Set-KeyNormal $script:KeyBkId }
        Update-KeyCards; Update-Cards; Update-Home
    }
}

# copia de uma vez os drivers que ainda não têm cópia
function Act-KeyAll {
    $base = Get-KeyBaselines
    $faltam = @($script:Keys | Where-Object {
        $bk = if ($_.Categoria -eq 'Vídeo') { Get-Backup (Get-Baseline).Version } else { Get-DeviceBackup $_.Id }
        -not $bk
    })
    if (-not $faltam.Count) { return }
    $tam = @{}
    foreach ($k in $faltam) {
        $p = Get-DriverPackage $k.Inf $k.Versao
        $tam[$k.Id] = $(if ($p) { [math]::Round(((Get-ChildItem $p.Folder -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB) } else { 0 })
    }
    $video = @($faltam | Where-Object { $_.Categoria -eq 'Vídeo' })
    $semVideo = [int](($faltam | Where-Object { $_.Categoria -ne 'Vídeo' } | ForEach-Object { $tam[$_.Id] } | Measure-Object -Sum).Sum)
    $comVideo = [int](($faltam | ForEach-Object { $tam[$_.Id] } | Measure-Object -Sum).Sum)
    $lista = (@($faltam | ForEach-Object { '•   {0}: {1} ({2} MB)' -f $_.Categoria, $_.Nome, $tam[$_.Id] }) -join "`n")
    $incluirVideo = $true
    if ($video.Count) {
        $incluirVideo = Show-Dialog 'Incluir o driver de vídeo?' ("O driver de vídeo sozinho ocupa {0} MB; os outros somam {1} MB.`n`nIncluir o vídeo na cópia?" -f ($comVideo - $semVideo), $semVideo) 'ask' -YesNo -YesText 'Incluir' -NoText 'Sem o vídeo'
    }
    if (-not $incluirVideo) { $faltam = @($faltam | Where-Object { $_.Categoria -ne 'Vídeo' }); $lista = (@($faltam | ForEach-Object { '•   {0}: {1} ({2} MB)' -f $_.Categoria, $_.Nome, $tam[$_.Id] }) -join "`n") }
    if (-not $faltam.Count) { return }
    $total = [int](($faltam | ForEach-Object { $tam[$_.Id] } | Measure-Object -Sum).Sum)
    if (-not (Show-Dialog 'Fazer backup de todos' ("Guardar uma cópia de {0} ({1} MB no total)?`n`n{2}`n`nCom as cópias salvas, dá para voltar qualquer um deles com um clique." -f (Get-Plural $faltam.Count 'driver' 'drivers'), $total, $lista) 'ask' -YesNo -YesText 'Fazer backup')) { return }

    $itens = @($faltam | ForEach-Object {
        $p = Get-DriverPackage $_.Inf $_.Versao
        if (-not $p) { return }
        $dst = if ($_.Categoria -eq 'Vídeo') { Join-Path $BackupDir $_.Versao } else { Join-Path $BackupDir ('dev-{0}-{1}' -f ($_.Inf -replace '\W', ''), $_.Versao) }
        [pscustomobject]@{ Src = $p.Folder; Dst = $dst; Inf = $p.Inf; Ver = $_.Versao; Nome = $_.Nome; Vendor = $_.Fabricante; Id = $_.Id; ClassGuid = ($_.ClassGuid -replace '[{}]', ''); Cat = $_.Categoria }
    })
    if (-not $itens.Count) { [void](Show-Dialog 'Backup não disponível' 'Não encontrei os pacotes desses drivers dentro do Windows.' 'warn'); return }
    $BtnKeyAll.IsEnabled = $false; $BtnKeyAll.Content = 'Copiando...'
    $script:KeyAllVideo = @($itens | Where-Object { $_.Cat -eq 'Vídeo' })[0]
    Start-Bg (Expand-Tpl $KeyAllTpl @{ '__JSON__' = (ConvertTo-Json -InputObject @($itens) -Compress -Depth 4) }) {
        param($out, $err)
        $BtnKeyAll.IsEnabled = $true
        $r = if ($out -and $out.Count) { $out[$out.Count - 1] } else { $null }
        if ($err -or -not $r) { [void](Show-Dialog 'Backup falhou' "Não foi possível copiar.`n$err" 'bad') }
        else {
            if ($script:KeyAllVideo -and $script:Gpu) { Save-Baseline $script:Gpu }
            Set-KeyNormal $null
            [void](Show-Dialog 'Cópias guardadas' ("{0} de {1} drivers copiados.`n`nAgora dá para restaurar qualquer um deles pelo próprio cartão." -f $r.Ok, $r.Total) $(if ($r.Ok -eq $r.Total) { 'ok' } else { 'warn' }))
        }
        Update-Cards; Update-Home
    }
}

# Guarda o driver atual antes de instalar outro, mesmo que não tenha sido o app quem o instalou.
# Assim sempre existe para onde voltar.
function Get-DeviceForHw([string]$hw) {
    if (-not $hw) { return $null }
    $k = @($script:Keys | Where-Object { $_.VenDev -eq $hw })[0]
    if ($k) { return $k }
    $d = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -like "*$hw*" -and $_.DriverVersion -and "$($_.DriverProviderName)" -notmatch '^Microsoft' })[0]
    if (-not $d) { return $null }
    [pscustomobject]@{ Id = $d.DeviceID; Nome = $d.DeviceName; Categoria = 'Outros'; Versao = $d.DriverVersion
        Inf = "$($d.InfName)"; Fabricante = "$($d.DriverProviderName)"; ClassGuid = "$($d.ClassGuid)" }
}

function New-PreBackupItems($devs) {
    $itens = @()
    foreach ($d in @($devs | Where-Object { $_ -and $_.Inf })) {
        $dst = if ($d.Categoria -eq 'Vídeo') { Join-Path $BackupDir $d.Versao } else { Join-Path $BackupDir ('dev-{0}-{1}' -f ($d.Inf -replace '\W', ''), $d.Versao) }
        $meta = Join-Path $dst 'HollowDrivers-backup.json'
        if (Test-Path $meta) {
            $saved = $null
            try { $saved = Get-Content $meta -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
            $infPath = if ($saved -and "$($saved.Inf)" -match '^[\w\-\.]+\.inf$') { Join-Path $dst $saved.Inf } else { '' }
            if (-not $saved -or "$($saved.Version)" -ne "$($d.Versao)" -or
                ($saved.DeviceId -and $saved.DeviceId -ne $d.Id) -or
                -not (Test-Path $infPath) -or
                -not @(Get-ChildItem $dst -Recurse -Filter '*.cat' -File -ErrorAction SilentlyContinue).Count) {
                throw "A copia salva de $($d.Nome) esta incompleta. Faca um novo backup antes de continuar."
            }
            continue
        }
        $pkg = Get-DriverPackage $d.Inf $d.Versao
        if (-not $pkg) { throw "Nao foi possivel localizar o pacote atual de $($d.Nome) para fazer backup." }
        $itens += [pscustomobject]@{ Src = $pkg.Folder; Dst = $dst; Inf = $pkg.Inf; Ver = $d.Versao; Nome = $d.Nome
            Vendor = $d.Fabricante; Id = $d.Id; ClassGuid = ($d.ClassGuid -replace '[{}]', ''); Cat = $d.Categoria }
    }
    @($itens)
}

function Stop-PreBackup([string]$reason) {
    $BtnUpd.IsEnabled = $true; $BtnUpd.Content = 'Atualizar drivers'
    $BtnRestore.IsEnabled = $true
    if ($script:UpdState -eq 'installing') { $script:UpdState = 'done' }
    [void](Show-Dialog 'Backup necessario' $reason 'bad')
    Update-Home; Update-Cards
}

# Copia o que estiver faltando e continua apenas depois de conferir o resultado.
function Start-PreBackup($devs, [scriptblock]$depois) {
    try { $itens = @(New-PreBackupItems $devs) }
    catch { Stop-PreBackup $_.Exception.Message; return }
    if (-not $itens.Count) { & $depois; return }
    $script:PreDepois = $depois
    $script:PreCount = $itens.Count
    $script:Prog.Text = 'Guardando copia dos drivers atuais...'
    Start-Bg (Expand-Tpl $KeyAllTpl @{ '__JSON__' = (ConvertTo-Json -InputObject @($itens) -Compress -Depth 4) }) {
        param($out, $err)
        Update-Cards
        $result = if ($out -and $out.Count) { $out[$out.Count - 1] } else { $null }
        if ($err -or -not $result -or $result.Ok -ne $script:PreCount) {
            Stop-PreBackup ('A copia dos drivers atuais nao foi concluida. Nenhum driver foi alterado. ' + $err)
            return
        }
        & $script:PreDepois
    }
}
function Act-KeyRestore([string]$id) {
    $k = Get-KeySel $id
    if (-not $k) { return }
    if ($k.Categoria -eq 'Vídeo') { Act-Restore; return }
    $bk = Get-DeviceBackup $k.Id
    if (-not $bk) { [void](Show-Dialog 'Sem backup' 'Esse driver ainda não tem cópia salva. Use "Backup do selecionado" enquanto ele está funcionando bem.' 'warn'); return }
    if ("$($bk.Inf)" -notmatch '^[\w\-\.]+\.inf$') { [void](Show-Dialog 'Backup inválido' 'O arquivo de controle do backup foi alterado. Faça o backup de novo.' 'bad'); return }
    $msg = "Voltar o driver de {0} para a versão {1} (backup de {2})?`n`n1.   Ponto de restauração do Windows`n2.   Remover o driver atual ({3})`n3.   Instalar o backup`n`nO Windows vai pedir permissão de administrador.{4}" -f
        $k.Categoria.ToLower(), $bk.Version, $bk.Date, $k.Versao, $(if ($k.Categoria -eq 'Rede') { "`n`nA internet pode cair por alguns segundos." } else { '' })
    if (-not (Show-Dialog 'Restaurar driver' $msg 'ask' -YesNo -YesText 'Restaurar')) { return }
    $script:RestoreArgs = @{ '__VENDOR__' = [regex]::Escape("$($bk.Vendor)"); '__SRC__' = $bk.Path; '__INFNAME__' = $bk.Inf
        '__VER__' = $bk.Version; '__CLASSGUID__' = "$($bk.ClassGuid)"; '__DEVID__' = $k.Id; '__CURRENTINF__' = $k.Inf }
    Start-PreBackup @($k) { Start-KeyRestoreNow }
}

function Start-KeyRestoreNow {
    Invoke-Elevated $RestoreTpl $script:RestoreArgs 'restaurar' {
        param($log, $err)
        if ($err) { [void](Show-Dialog 'Restauração cancelada' "O Windows não deu permissão de administrador, então nada foi alterado.`n`n$err" 'warn'); return }
        if ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Erro na restauração' $matches[1] 'bad') }
        else { [void](Show-Dialog 'Pronto' "O driver foi reinstalado.`n`nReinicie o PC para concluir." 'ok') }
        Start-Scan
    }
}

function Act-KeyHist([string]$id) {
    $k = Get-KeySel $id
    if (-not $k) { return }
    if (-not $k.VenDev) { [void](Show-Dialog 'Sem histórico' 'Não consegui identificar esse dispositivo nos registros do Windows.' 'info'); return }
    $script:HistName = $k.Nome
    Start-Bg ($LogicText + "`nGet-InstallHistory '$($k.VenDev)'") {
        param($out, $err)

        $rows = @($out | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{ Quando = $_.Quando.ToString('dd/MM/yyyy HH:mm'); Origem = $_.Origem; Detalhe = $_.Detalhe; Destaque = ($_.Origem -like 'Driver Booster*') }
        })
        if (-not $rows.Count) { [void](Show-Dialog 'Sem histórico' 'Nenhuma instalação desse dispositivo nos registros guardados pelo Windows.' 'info'); return }
        Show-TableWindow ("Quem instalou driver em: $($script:HistName)") $rows 'Fonte: registros de instalação do Windows. Em vermelho: trocas feitas pelo Driver Booster.'
    }
}

# ---------------------------------------------------------------- tela inicial

function Set-Verdict([string]$kind, [string]$text, [string]$sub) {
    $col = $Hex[$kind]
    $VerdictText.Text = $text; $VerdictSub.Text = $sub
    $VerdictIcon.Text = $Glyph[$kind]; $VerdictIcon.Foreground = Get-Brush $col
    $VerdictBadge.Background = Get-Brush ('#26' + $col.Substring(1))
}

$SpinAnim = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, (New-Object Windows.Duration([TimeSpan]::FromSeconds(1))))
$SpinAnim.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever

function Set-BigBusy([bool]$busy) {
    if ($busy) {
        $BigLabel.Text = 'ANALISANDO'; $BigLabel.FontSize = 19; $BigIcon.Visibility = 'Collapsed'
        $Spinner.Opacity = 1; $SpinRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $SpinAnim)
        $BigBtn.IsHitTestVisible = $false
    } else {
        $SpinRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null); $Spinner.Opacity = 0
        $BigLabel.Text = 'ANALISAR'; $BigLabel.FontSize = 24; $BigIcon.Visibility = 'Visible'
        if ($script:LastScan) { $BigIcon.Text = [string][char]0xE72C }
        $BigBtn.IsHitTestVisible = $true
    }
}

function Add-Finding([string]$text, [string]$desc, [string]$kind, [string]$btnText, [scriptblock]$action) {
    $col = $Hex[$kind]
    $card = New-Object Windows.Controls.Border
    $card.Background = Get-Brush '#171A21'; $card.BorderBrush = Get-Brush '#2A2F3A'; $card.BorderThickness = 1
    $card.CornerRadius = 14; $card.Padding = '16,14'; $card.Margin = '0,0,0,10'
    $grid = New-Object Windows.Controls.Grid
    foreach ($w in 'Auto', '*', 'Auto') {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = (New-Object Windows.GridLengthConverter).ConvertFromString($w)
        $grid.ColumnDefinitions.Add($cd)
    }
    $badge = New-Object Windows.Controls.Border
    $badge.Width = 36; $badge.Height = 36; $badge.CornerRadius = 18; $badge.Background = Get-Brush ('#26' + $col.Substring(1))
    $badge.VerticalAlignment = 'Top'
    $gl = New-Object Windows.Controls.TextBlock
    $gl.Text = $Glyph[$kind]; $gl.FontFamily = $app.Resources['Icons']; $gl.FontSize = 15; $gl.Foreground = Get-Brush $col
    $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
    $badge.Child = $gl
    $tb = New-Object Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'; $tb.VerticalAlignment = 'Center'; $tb.Margin = '14,0,14,0'
    $t1 = New-Object Windows.Documents.Run($text); $t1.FontSize = 14; $t1.FontWeight = [Windows.FontWeights]::SemiBold
    $tb.Inlines.Add($t1)
    if ($desc) {
        $tb.Inlines.Add((New-Object Windows.Documents.LineBreak))
        $t2 = New-Object Windows.Documents.Run($desc); $t2.FontSize = 12.5; $t2.Foreground = Get-Brush '#9AA2AF'
        $tb.Inlines.Add($t2); $tb.LineHeight = 20
        $script:LastDescRun = $t2
    }
    [Windows.Controls.Grid]::SetColumn($tb, 1)
    [void]$grid.Children.Add($badge); [void]$grid.Children.Add($tb)
    if ($btnText) {
        $b = New-Object Windows.Controls.Button
        $b.Content = $btnText; $b.Margin = '0'; $b.VerticalAlignment = 'Center'
        $b.Style = $app.Resources[$(if ($kind -eq 'bad') { 'PillAccent' } else { 'Pill' })]
        $b.add_Click($action)
        [Windows.Controls.Grid]::SetColumn($b, 2); [void]$grid.Children.Add($b)
    }
    $card.Child = $grid

    $i = $Findings.Children.Count
    $card.Opacity = 0
    $tt = New-Object Windows.Media.TranslateTransform(0, 12); $card.RenderTransform = $tt
    [void]$Findings.Children.Add($card)
    $dur = New-Object Windows.Duration([TimeSpan]::FromMilliseconds(320))
    $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
    $a1 = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, $dur); $a1.BeginTime = [TimeSpan]::FromMilliseconds(90 * $i)
    $a2 = New-Object Windows.Media.Animation.DoubleAnimation(12, 0, $dur); $a2.BeginTime = $a1.BeginTime; $a2.EasingFunction = $ease
    $card.BeginAnimation([Windows.UIElement]::OpacityProperty, $a1)
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a2)
}

function Update-Home {
    if (-not $script:LastScan) { return }
    $Findings.Children.Clear()
    $g = $script:Gpu; $b = Get-Baseline; $hl = $script:Health
    $bk = if ($b) { Get-Backup $b.Version } else { $null }
    $bad = 0; $tips = 0


    if ($g -and $g.Code -ne 0) {
        $bad++
        if ($bk) {
            Add-Finding 'O driver da placa de vídeo está quebrado' ("A tela funciona, mas jogos e aceleração 3D não. Você tem um backup do driver que funcionava ({0}) — um clique reinstala ele." -f $bk.Version) 'bad' 'Restaurar driver' { Act-Restore }
        } else {
            Add-Finding 'O driver da placa de vídeo está quebrado' 'O Windows passou a usar um modo de vídeo básico: a tela funciona, mas jogos e aceleração 3D não. Reinstale o driver oficial.' 'bad' 'Como resolver' {
                [void](Show-Dialog 'Como resolver' ((Get-FixSteps) + "`n`nVou abrir o site oficial agora.") 'info' -YesText 'Abrir site')
                Start-Process @((Get-OfficialLinks).Values)[0]
            }
        }
    }
    if ($g -and $g.Code -eq 0 -and $b -and $b.Version -ne $g.Version) {
        $origin = if ($script:History.Count) { $script:History[0].Origem } else { '' }
        if ($origin -like 'Instalador oficial*') {
            $tips++
            Add-Finding 'O driver de vídeo foi atualizado' ("Nova versão {0} instalada pelo {1}. Se o vídeo e os jogos estão funcionando bem, salve esta versão como a nova referência." -f $g.Version, $origin.ToLower()) 'warn' 'Salvar nova versão' { Act-MarkGood }
        } else {
            $bad++
            $who = if ($origin) { " (por: $origin)" } else { '' }
            if ($bk) {
                Add-Finding "O driver de vídeo foi trocado sem você saber$who" ("Se o vídeo ou os jogos começaram a falhar, essa troca é a causa mais provável. Você pode voltar para o driver salvo ({0}) com um clique." -f $bk.Version) 'bad' 'Restaurar driver' { Act-Restore }
            } else {
                Add-Finding "O driver de vídeo foi trocado sem você saber$who" 'Se o vídeo ou os jogos começaram a falhar, essa troca é a causa mais provável. Veja quem trocou e reinstale o driver oficial.' 'bad' 'Ver quem trocou' { Act-History }
            }
        }
    }
    if (@($script:KeyChanges).Count) {
        $bad++
        $n = @($script:KeyChanges)
        $quais = (@($n | Select-Object -First 3 | ForEach-Object { '{0} ({1})' -f $_.Categoria.ToLower(), $_.Nome }) -join ', ')
        Add-Finding ((Get-Plural $n.Count 'driver principal foi trocado' 'drivers principais foram trocados')) "Mudaram de versão desde a última vez: $quais. Se algo parou de funcionar, foi provavelmente isso." 'bad' 'Ver quais' { Act-KeyChanges }
    }
    if ($hl.DriverBooster.Count) {
        $bad++
        Add-Finding 'O Driver Booster está instalado' 'Ele instala drivers de fontes próprias por cima dos oficiais, sem pedir. Isso pode deixar a placa de vídeo instável ou impedir jogos de abrir.' 'bad' 'Remover' { Act-RemoveDb }
    }
    if ($hl.Crashes) {
        $bad++
        $why = if (-not $hl.Tdr) { 'Nenhuma dessas quedas teve erro de driver. Isso costuma ser a fonte de energia não aguentando a placa de vídeo em jogos pesados, e não o driver.' }
               else { 'O Windows registrou falhas do driver de vídeo junto com as quedas. Veja os detalhes para saber quando aconteceram.' }
        Add-Finding ('O PC desligou sozinho {0} no último mês' -f (Get-Plural $hl.Crashes 'vez' 'vezes')) $why 'bad' 'Ver quedas' { Act-Crashes }
    }
    if ($script:NeedReboot.Count) {
        $bad++
        $quais = ($script:NeedReboot | Select-Object -First 3 -Expand Dispositivo) -join ', '
        Add-Finding ((Get-Plural $script:NeedReboot.Count 'driver está esperando você reiniciar' 'drivers estão esperando você reiniciar')) `
            ("$quais só vai funcionar depois de reiniciar o PC. Atualizar o driver de novo não tira esse aviso.`n`nImportante: use Iniciar → Reiniciar. Desligar e ligar não resolve, porque o Windows 11 não desliga de verdade (Inicialização Rápida).") `
            'warn' 'Reiniciar agora' { Act-Reboot }
    }
    if ($script:Problems) {
        $bad++
        Add-Finding ((Get-Plural $script:Problems 'dispositivo com problema' 'dispositivos com problema') + ' no driver') 'Algum componente do PC está sem driver ou com erro e pode não funcionar direito. Veja qual no modo avançado.' 'bad' 'Ver' { Show-View $true }
    }
    $script:ProgRun = $null
    switch ($script:UpdState) {
        'checking' {
            Add-Finding 'Procurando atualizações de driver...' $script:Prog.Text 'info' $null $null
            $script:ProgRun = $script:LastDescRun
        }
        'installing' {
            Add-Finding 'Atualizando drivers...' $script:Prog.Text 'info' $null $null
            $script:ProgRun = $script:LastDescRun
        }
        'error' {
            Add-Finding 'Não foi possível buscar atualizações' 'Sem internet ou o catálogo da Microsoft não respondeu. Tente de novo mais tarde.' 'info' 'Tentar de novo' { Start-UpdateCheck }
        }
        'done' {
            if ($script:Updates.Count) {
                $tips++
                $names = (@($script:Updates | Select-Object -First 3 | ForEach-Object Dispositivo) -join ', ')
                if ($script:Updates.Count -gt 3) { $names += '...' }
                Add-Finding ((Get-Plural $script:Updates.Count 'driver tem versão nova' 'drivers têm versão nova') + ' oficial') "Versões mais novas certificadas pela Microsoft: $names. Antes de instalar é criado um ponto de restauração." 'warn' 'Atualizar' { Show-UpdatesWindow }
            }
        }
    }
    if ($script:BackupBusy) {
        Add-Finding 'Fazendo backup do driver de vídeo...' 'Copiando o driver atual para você poder restaurar com um clique no futuro. Pode continuar usando o PC.' 'info' $null $null
    } elseif ($g -and $g.Code -eq 0 -and -not $b) {
        $tips++
        Add-Finding 'Faça backup do seu driver de vídeo' 'Seu vídeo está funcionando agora. Guardando uma cópia deste driver, se algum programa ou o Windows trocar ele, é só um clique para voltar.' 'warn' 'Fazer backup' { Act-MarkGood }
    } elseif ($g -and $g.Code -eq 0 -and $b -and $b.Version -eq $g.Version -and -not $bk) {
        $tips++
        Add-Finding 'Faça o backup do seu driver de vídeo' 'Seu driver está salvo como referência, mas ainda sem cópia de segurança. Com o backup, dá para restaurar com um clique se algo trocar o driver.' 'warn' 'Fazer backup' { Start-Backup $script:Gpu }
    }
    if ($script:AllBusy) {
        Add-Finding 'Salvando todos os drivers...' 'Copiando os drivers do fabricante para a pasta escolhida. Pode levar alguns minutos — pode continuar usando o PC.' 'info' $null $null
    } elseif (-not (Get-AllBackupInfo)) {
        $tips++
        $dev = if ($script:SysInfo -and $script:SysInfo.IsLaptop) { 'Notebooks dependem' } else { 'Seu PC depende' }
        Add-Finding 'Guarde todos os drivers num pendrive' "$dev de drivers do fabricante (chipset, Wi-Fi, áudio, touchpad, teclas especiais) que o Windows nem sempre instala sozinho depois de formatar. Salve todos agora e reinstale com dois cliques quando precisar." 'warn' 'Fazer backup' { Act-AllBackup }
    }
    if (-not (Test-WatchEnabled)) {
        $tips++
        Add-Finding 'A proteção automática está desligada' 'Quando ligada, um escudo fica perto do relógio: o HollowDrivers confere seu PC em silêncio e só avisa se o driver de vídeo for trocado, a placa der erro, o PC cair ou o Driver Booster voltar. Não instala nada e não deixa o PC lento.' 'warn' 'Ligar' { Act-Watch }
    }

    $sub = 'Última análise às {0:HH:mm}' -f $script:LastScan
    if ($script:UpdState -eq 'done' -and -not $script:Updates.Count) { $sub += '  •  drivers em dia' }
    if ($bad) { Set-Verdict 'bad' (Get-Plural $bad 'problema encontrado' 'problemas encontrados') $sub }
    elseif ($tips) { Set-Verdict 'ok' 'Tudo certo' ('{0}  •  {1} para ficar mais protegido' -f $sub, (Get-Plural $tips 'sugestão' 'sugestões')) }
    else { Set-Verdict 'ok' 'Tudo certo — seu PC está protegido' $sub }
}

# barra lateral: mostra uma seção por vez
$script:Section = 'drivers'
$Sections = @{ drivers = 'NavDrivers,PanDrivers'; video = 'NavVideo,PanVideo'; sistema = 'NavSystem,PanSystem'; limpeza = 'NavClean,PanClean'; protecao = 'NavGuard,PanGuard'; windows = 'NavWin,PanWin' }
function Show-Section([string]$key) {
    if (-not $Sections.ContainsKey($key)) { $key = 'drivers' }
    $script:Section = $key
    foreach ($k in $Sections.Keys) {
        $nav, $pan = $Sections[$k] -split ','
        (Get-Variable $nav -Scope Script -ValueOnly).IsChecked = ($k -eq $key)
        (Get-Variable $pan -Scope Script -ValueOnly).Visibility = $(if ($k -eq $key) { 'Visible' } else { 'Collapsed' })
    }
}

$script:RailOpen = $true
$RailItems = 'BtnHomeScan', 'BtnHomeConfig', 'BtnAdvanced', 'BtnRailHome', 'HomeNavHome', 'HomeNavVideo', 'HomeNavSystem', 'HomeNavClean', 'HomeNavGuard', 'HomeNavWin', 'BtnRailAdv', 'BtnBack', 'NavDrivers', 'NavVideo', 'NavSystem', 'NavClean', 'NavGuard', 'NavWin', 'BtnAdvConfig', 'BtnRailConfig', 'BtnConfigHome', 'ConfigNavDrivers', 'ConfigNavVideo', 'ConfigNavSystem', 'ConfigNavClean', 'ConfigNavGuard', 'ConfigNavWin', 'ConfigNavSettings'
$RailText = @{}
function Set-Rail([bool]$open) {
    $script:RailOpen = $open
    if (-not $RailText.Count) { foreach ($n in $RailItems) { $RailText[$n] = (Get-Variable $n -Scope Script -ValueOnly).Content } }
    foreach ($n in $RailItems) {
        $b = Get-Variable $n -Scope Script -ValueOnly
        $b.Content = $(if ($open) { $RailText[$n] } else { '' })
        $b.ToolTip = $(if ($open) { $null } else { $RailText[$n] })
    }
    $HomeRail.Width = $(if ($open) { 228 } else { 64 })
    $AdvCol.Width = $(if ($open) { 228 } else { 64 })
    $ConfigCol.Width = $(if ($open) { 228 } else { 64 })
    $HomeRailBox.Margin = $(if ($open) { '14,18,14,14' } else { '6,18,6,14' })
    $AdvRailBox.Margin = $(if ($open) { '14,18,14,14' } else { '6,18,6,14' })
    $ConfigRailBox.Margin = $(if ($open) { '14,18,14,14' } else { '6,18,6,14' })
    $AdvLogoText.Visibility = $(if ($open) { 'Visible' } else { 'Collapsed' })
    $HomeLogoText.Visibility = $AdvLogoText.Visibility
    $ConfigLogoText.Visibility = $AdvLogoText.Visibility
    $BtnRailHome.ToolTip = $BtnRailAdv.ToolTip = $(if ($open) { $null } else { 'Expandir menu' })
    $BtnRailConfig.ToolTip = $BtnRailHome.ToolTip
}

function Show-Config([bool]$on) {
    $ConfigView.Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' })

}

function Show-View([bool]$adv) {
    Show-Config $false
    if (-not $adv) { Show-Section 'drivers' }
    $AdvView.Visibility = $(if ($adv) { 'Visible' } else { 'Collapsed' })
    $HomeView.Visibility = $(if ($adv) { 'Collapsed' } else { 'Visible' })
    if ($adv -and -not $script:LastScan -and -not $script:Scanning) { Start-Scan }
}

# ---------------------------------------------------------------- ações

function Apply-Scan($r) {
    $rows = @($r.Rows)
    $script:Gpu = $r.Gpu; $script:History = @($r.History); $script:Health = $r.Health; $script:SysInfo = $r.SysInfo
    $script:Keys = @($r.Keys)
    if ($script:Keys.Count -and -not (Get-KeyBaselines).Count) { Set-KeyNormal $null }   # primeira análise = normal do PC
    $script:KeyChanges = @(Get-KeyChanges $script:Keys)
    $script:Problems = @($rows | Where-Object { $_.Status -notin 'OK', 'Antigo' }).Count
    $script:Old = @($rows | Where-Object { $_.Status -eq 'Antigo' }).Count
    $script:NeedReboot = @($rows | Where-Object { $_.Status -like '*código 14*' })
    $dt.BeginLoadData(); $dt.Clear()
    foreach ($x in $rows) {
        if ($x.Status -eq 'OK') { $ord = 2; $cor = $Hex.ok } elseif ($x.Status -eq 'Antigo') { $ord = 1; $cor = $Hex.warn } else { $ord = 0; $cor = $Hex.bad }
        [void]$dt.Rows.Add($ord, $x.Status, $cor, $x.Categoria, $x.Dispositivo, $x.Fabricante, $x.Versao,
            $(if ($x.Data) { $x.Data } else { [DBNull]::Value }),
            $(if ($null -ne $x.Idade) { $x.Idade } else { [DBNull]::Value }),
            $x.INF, $x.Microsoft)
    }
    $dt.EndLoadData()
    $script:LastScan = Get-Date
    Update-Cards; Update-Filter; Update-Home; Update-Sites
    if ($script:WdDepois) { $script:WdDepois = $false; Start-VideoWatchdog 60 }
    if ($script:AfterUpdate) { Show-UpdateResult $rows }
    elseif ($script:UpdState -in 'idle', 'error') { Start-UpdateCheck }
    if ($script:AfterRestore) {
        $want = $script:AfterRestore; $script:AfterRestore = $null
        $g = $script:Gpu
        if ($g -and $g.Code -eq 0 -and $g.Version -eq $want) {
            [void](Show-Dialog 'Driver restaurado' ("A placa de vídeo voltou para o driver $want e está funcionando.`n`nReinicie o PC para finalizar.") 'ok')
        } else {
            $now = if ($g) { "$($g.Version) — $(Get-ProblemText $g.Code)" } else { 'placa não encontrada' }
            [void](Show-Dialog 'Reinicie o PC' ("A restauração terminou, mas a placa ainda mostra: $now.`n`nIsso é normal logo após trocar driver. Reinicie o PC e analise de novo.") 'warn')
        }
    }
}

function Start-Scan {
    if ($script:Scanning) { return }
    $script:Scanning = $true
    Set-BigBusy $true; $BtnScan.IsEnabled = $false
    Set-Verdict 'info' 'Analisando seu PC...' 'Verificando drivers, placa de vídeo e quedas'
    $Findings.Children.Clear()
    $StatusText.Text = 'Escaneando...'
    Start-Bg ($LogicText + "`n" + $ScanCode) {
        param($out, $err)
        $script:Scanning = $false; Set-BigBusy $false; $BtnScan.IsEnabled = $true
        if ($err -or -not $out -or -not $out.Count) {
            Set-Verdict 'info' 'Pronto para verificar' 'Clique no botão para analisar seu PC'
            [void](Show-Dialog 'Erro ao analisar' "$err" 'bad')
            return
        }
        Apply-Scan $out[0]
    }
}

function Start-Backup($g) {
    if (-not $g -or $script:BackupBusy) { return }
    $pkg = Get-DriverPackage $g.Inf $g.Version
    if (-not $pkg) {
        [void](Show-Dialog 'Backup não disponível' 'Não encontrei o pacote do driver de vídeo dentro do Windows. O driver foi salvo como referência (você continua sendo avisado se ele for trocado), mas sem cópia de segurança.' 'warn')
        return
    }
    $dst = Join-Path $BackupDir $g.Version
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $script:BackupBusy = $true; $script:BackupVersion = $g.Version
    Update-Cards; Update-Home
    $code = Expand-Tpl $BackupTpl @{ '__SRC__' = $pkg.Folder; '__DST__' = $dst; '__VER__' = $g.Version; '__NAME__' = $g.Name; '__INF__' = $pkg.Inf
        '__VENDOR__' = $g.Vendor; '__DEVID__' = ''; '__CLASSGUID__' = '4d36e968-e325-11ce-bfc1-08002be10318'; '__CAT__' = 'Vídeo' }
    Start-Bg $code {
        param($out, $err)
        $script:BackupBusy = $false
        $v = $script:BackupVersion
        $rc = if ($null -ne $out -and $out.Count) { [int]"$($out[$out.Count - 1])" } else { 99 }
        if ($err -or $rc -ge 8 -or -not (Get-Backup $v)) {
            [void](Show-Dialog 'Backup falhou' ("Não foi possível copiar o driver (código $rc).`n$err") 'bad')
        } else {
            Write-OperationEvent 'backup-video' 'concluido' ('Versao ' + $v + '; copias anteriores preservadas')
        }
        Update-Cards; Update-Home
    }
}

function Act-MarkGood {
    $g = $script:Gpu
    if (-not $g) { return }
    if ($g.Code -ne 0) { [void](Show-Dialog 'Agora não' 'A placa de vídeo está com erro. Salve o driver só quando o vídeo estiver funcionando.' 'warn'); return }
    $msg = "Guardar uma cópia do driver de vídeo $($g.Version)?`n`n•   Com a cópia salva, dá para voltar para esta versão com um clique`n•   Ocupa cerca de 1 GB por versão; mantém os backups anteriores`n`nA cópia é feita em segundo plano; pode continuar usando o PC."
    if (-not (Show-Dialog 'Fazer backup do vídeo' $msg 'ask' -YesNo -YesText 'Fazer backup')) { return }
    Save-Baseline $g
    Start-Backup $g
    if ($script:Keys.Count) { Set-KeyNormal (@($script:Keys | Where-Object { $_.Categoria -eq 'Vídeo' })[0]).Id }
    Update-Cards; Update-Home
}

# Depois de qualquer mexida no driver de vídeo, confere por 1 minuto se a placa voltou.
# Se não voltar, restaura a cópia salva sozinho. É a rede de segurança contra ficar sem vídeo.
$WdTimer = New-Object Windows.Threading.DispatcherTimer
$WdTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:WdLeft = 0
$WdTimer.add_Tick({
    $script:WdLeft--
    $g = Get-GpuInfo
    if ($g -and $g.Code -eq 0 -and $script:WdLeft -lt 55) {   # voltou sozinho antes do fim
        $WdTimer.Stop()
        Set-Verdict 'ok' 'Vídeo funcionando' 'A placa respondeu normalmente. Nada mais a fazer.'
        $Findings.Children.Clear(); Start-Scan
        return
    }
    if ($script:WdLeft -gt 0) {
        $VerdictSub.Text = 'Se a placa não voltar em {0}s, eu restauro o driver salvo. NÃO desligue o PC.' -f $script:WdLeft
        return
    }
    $WdTimer.Stop()
    if ($g -and $g.Code -ne 0) {
        Set-Verdict 'bad' 'Restaurando o driver de vídeo...' 'A placa não voltou. Restaurando a cópia salva. Não desligue o PC.'
        Act-Restore -Auto
    } else {
        Set-Verdict 'ok' 'Vídeo funcionando' 'A placa respondeu normalmente.'
        Start-Scan
    }
})

function Start-VideoWatchdog([int]$segundos = 60) {
    $b = Get-Baseline
    if (-not $b -or -not (Get-Backup $b.Version)) { return }   # sem cópia não há como socorrer
    $script:WdLeft = $segundos
    Set-Verdict 'info' 'Conferindo se o vídeo voltou' ('Se a placa não voltar em {0}s, eu restauro o driver salvo. NÃO desligue o PC.' -f $segundos)
    $Findings.Children.Clear()
    Add-Finding 'Rede de segurança ligada' 'Se a tela ficar sem aceleração ou o jogo não abrir, o HollowDrivers reinstala sozinho o driver que estava funcionando. Você pode cancelar se estiver tudo bem.' 'info' 'Cancelar' {
        $WdTimer.Stop(); Set-Verdict 'ok' 'Tudo certo' 'Rede de segurança cancelada.'; Start-Scan
    }
    $WdTimer.Start()
}

function Act-Restore {
    param([switch]$Auto)
    $b = Get-Baseline
    $bk = if ($b) { Get-Backup $b.Version } else { $null }
    if (-not $bk) { [void](Show-Dialog 'Sem backup' 'Ainda não há backup do driver de vídeo. Quando o vídeo estiver funcionando bem, use "Fazer backup".' 'warn'); return }
    $g = $script:Gpu
    $now = if ($g) { $g.Version } else { 'desconhecido' }
    $msg = "Isso vai:`n`n1.   Guardar uma cópia do driver atual, se ainda não houver`n2.   Criar um ponto de restauração do Windows`n3.   Remover o driver de vídeo atual ($now)`n4.   Instalar o driver salvo ($($bk.Version), backup de $($bk.Date))`n`nA tela vai piscar ou apagar por alguns segundos. SE A TELA APAGAR, NÃO DESLIGUE O PC: em 1 minuto eu volto o driver anterior sozinho.`n`nO Windows vai pedir permissão de administrador."
    if (-not $Auto -and -not (Show-Dialog 'Restaurar driver de vídeo' $msg 'ask' -YesNo -YesText 'Restaurar')) { return }
    $vendorRx = switch ($bk.Vendor) {
        'AMD' { 'Advanced Micro Devices|\bAMD\b|ATI Technologies' }
        'NVIDIA' { 'NVIDIA' }
        'Intel' { '\bIntel\b' }
        default { [regex]::Escape("$($bk.Vendor)") }
    }
    $script:RestoreWant = $bk.Version
    $BtnRestore.IsEnabled = $false
    Set-Verdict 'info' 'Restaurando o driver de vídeo...' 'A tela pode piscar. Não desligue o PC.'
    $Findings.Children.Clear()
    # se o vídeo atual está funcionando e ainda não tem cópia, guarda antes de trocar
    $atual = @($script:Keys | Where-Object { $_.Categoria -eq 'Vídeo' })
    if ($g -and $g.Code -ne 0) { $atual = @() }
    if ("$($bk.Inf)" -notmatch '^[\w\-\.]+\.inf$') { [void](Show-Dialog 'Backup inválido' 'O arquivo de controle do backup foi alterado. Faça o backup do driver de vídeo de novo.' 'bad'); return }
    $script:VideoRestoreArgs = @{ '__VENDOR__' = $vendorRx; '__SRC__' = $bk.Path; '__INFNAME__' = $bk.Inf; '__VER__' = $bk.Version
        '__CLASSGUID__' = '4d36e968-e325-11ce-bfc1-08002be10318'; '__DEVID__' = $g.Pnp; '__CURRENTINF__' = $g.Inf }
    Start-PreBackup $atual { Start-VideoRestoreNow }
}

function Start-VideoRestoreNow {
    Invoke-Elevated $RestoreTpl $script:VideoRestoreArgs 'restaurar' {
        param($log, $err)
        if ($err) {
            [void](Show-Dialog 'Restauração cancelada' "O Windows não deu permissão de administrador, então nada foi alterado.`n`n$err" 'warn')
            Update-Home; Update-Cards
            return
        }
        if ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Erro na restauração' $matches[1] 'bad') }
        $script:AfterRestore = $script:RestoreWant
        $script:WdDepois = $true
        Start-Scan
    }
}

function Act-Point {
    if (-not (Show-Dialog 'Ponto de restauração' "Criar um ponto de restauração do Windows agora?`n`nSe algo der errado depois (driver, programa, atualização), dá para voltar o sistema para este momento. O Windows vai pedir permissão de administrador." 'ask' -YesNo -YesText 'Criar')) { return }
    $BtnPoint.IsEnabled = $false; $BtnPoint.Content = 'Criando ponto...'
    Invoke-Elevated $PointTpl @{} 'ponto' {
        param($log, $err)
        $BtnPoint.IsEnabled = $true; $BtnPoint.Content = 'Criar ponto de restauração'
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador.' 'warn'); return }
        if ($log -match 'PONTO=ok') { [void](Show-Dialog 'Ponto criado' 'Ponto de restauração criado com sucesso.' 'ok') }
        elseif ($log -match 'PONTO=aviso: (.+)') { [void](Show-Dialog 'Já existe um ponto recente' ("O Windows só cria um ponto de restauração a cada 24 horas e já existe um recente — você está protegido.`n`n" + $matches[1].Trim()) 'info') }
        elseif ($log -match 'PONTO=falhou: (.+)') { [void](Show-Dialog 'Não foi possível criar' ("A Proteção do Sistema pode estar desligada no disco C:.`nAtive em: Painel de Controle → Sistema → Proteção do Sistema.`n`nDetalhe: " + $matches[1].Trim()) 'warn') }
        else { [void](Show-Dialog 'Sem resposta' 'Não foi possível confirmar o resultado.' 'warn') }
    }
}

# ---------------------------------------------------------------- backup de TODOS os drivers (para depois de formatar)

$AllInfoFile = Join-Path $DataDir 'drivers-backup.json'
function Get-AllBackupInfo { if (Test-Path $AllInfoFile) { try { Get-Content $AllInfoFile -Raw | ConvertFrom-Json } catch { $null } } }

$AllTpl = @'
$pk = @(Get-OemPackages)
if (-not __VIDEO__) { $pk = @($pk | Where-Object { $_.Class -ne 'DISPLAY' }) }
$ok = 0; $fail = @()
foreach ($p in $pk) {
    $cat = if ($CatMap.ContainsKey($p.Class)) { $CatMap[$p.Class] } else { 'Outros' }
    $d = Join-Path (Join-Path '__DST__' ($cat -replace '[\\/:*?"<>|]', '-')) (([IO.Path]::GetFileNameWithoutExtension($p.Inf)) + ' ' + $p.Version)
    robocopy $p.Folder $d /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -lt 8) { $ok++ } else { $fail += $p.Inf }
}
[pscustomobject]@{
    Ok = $ok; Total = $pk.Count; Fail = @($fail)
    Cats = @($pk | Group-Object { if ($CatMap.ContainsKey($_.Class)) { $CatMap[$_.Class] } else { 'Outros' } } |
        Sort-Object Count -Descending | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count })
}
'@

$AllBat = @(
    '@echo off'
    'title HollowDrivers - Reinstalar drivers'
    'net session >nul 2>&1'
    'if errorlevel 1 ('
    '  powershell -NoProfile -Command "Start-Process -FilePath ''%~f0'' -Verb RunAs"'
    '  exit /b'
    ')'
    'echo.'
    'echo  Reinstalando os drivers salvos pelo HollowDrivers.'
    'echo  (chipset, rede, Wi-Fi, audio, touchpad, teclas especiais, Bluetooth, camera...)'
    'echo.'
    'echo  Pode levar alguns minutos e a tela pode piscar. Nao desligue o PC.'
    'echo.'
    'pnputil /add-driver "%~dp0*.inf" /subdirs /install'
    'echo.'
    'echo  Pronto. REINICIE o PC para terminar.'
    'echo  Depois, confira no Windows Update se falta algo.'
    'echo.'
    'pause'
) -join "`r`n"

function Act-AllBackup {
    $si = $script:SysInfo
    $what = if ($si -and $si.IsLaptop) { 'do seu notebook' } else { 'do seu PC' }
    $msg = "Vou salvar todos os drivers de fabricante $what — chipset, rede, Wi-Fi, áudio, touchpad, teclas especiais, Bluetooth, câmera, leitor de cartão e as extensões do fabricante.`n`nDepois de formatar, é só dar dois cliques no instalador que fica junto e o Windows volta com tudo funcionando.`n`nNa próxima tela escolha onde salvar — de preferência um PENDRIVE ou uma pasta da nuvem. Se salvar só neste PC, a cópia some ao formatar."
    if (-not (Show-Dialog 'Backup de todos os drivers' $msg 'ask' -YesNo -YesText 'Continuar')) { return }

    $video = $false
    $g = $script:Gpu
    if ($g) {
        $vp = Get-DriverPackage $g.Inf $g.Version
        $vmb = if ($vp) { [math]::Round(((Get-ChildItem $vp.Folder -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB) } else { 0 }
        $vmsg = "Incluir também o driver de vídeo ($($g.Name))?`n`nEle ocupa cerca de $vmb MB. Se não incluir, depois de formatar você baixa ele no site oficial (normalmente a versão mais nova é melhor)."
        $video = Show-Dialog 'Driver de vídeo' $vmsg 'ask' -YesNo -YesText "Incluir (+$vmb MB)" -NoText 'Sem vídeo'
    }

    $usb = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue | Select-Object -First 1
    $fb = New-Object Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Onde salvar o backup dos drivers? (de preferência um pendrive)'
    $fb.ShowNewFolderButton = $true
    $fb.SelectedPath = $(if ($usb) { $usb.DeviceID + '\' } else { [Environment]::GetFolderPath('Desktop') })
    if ($fb.ShowDialog() -ne 'OK') { return }

    $label = if ($si -and $si.Model -and $si.Model -notmatch 'To Be Filled|System Product') { $si.Model } else { $env:COMPUTERNAME }
    $label = ($label -replace '[\\/:*?"<>|]', '').Trim()
    $dst = Join-Path $fb.SelectedPath ('HollowDrivers - Drivers ({0}) {1:yyyy-MM-dd}' -f $label, (Get-Date))
    try { New-Item -ItemType Directory -Force -Path $dst -ErrorAction Stop | Out-Null }
    catch { [void](Show-Dialog 'Não foi possível salvar' "Não consegui criar a pasta em:`n$dst`n`n$($_.Exception.Message)" 'bad'); return }

    $script:AllDst = $dst; $script:AllVideo = $video
    $BtnAll.IsEnabled = $false; $BtnAll.Content = 'Copiando drivers... (alguns minutos)'
    $script:AllBusy = $true; Update-Home
    $code = $LogicText + "`n" + (Expand-Tpl $AllTpl @{ '__DST__' = $dst; '__VIDEO__' = $(if ($video) { '$true' } else { '$false' }) })
    Start-Bg $code {
        param($out, $err)
        $script:AllBusy = $false
        $BtnAll.IsEnabled = $true; $BtnAll.Content = 'Backup de todos os drivers'
        $dst = $script:AllDst
        $r = if ($out -and $out.Count) { $out[$out.Count - 1] } else { $null }
        if ($err -or -not $r -or -not $r.Ok) {
            [void](Show-Dialog 'Backup falhou' "Não foi possível copiar os drivers.`n$err" 'bad'); Update-Home; return
        }
        [IO.File]::WriteAllText((Join-Path $dst 'REINSTALAR-DRIVERS.bat'), $AllBat, [Text.Encoding]::ASCII)
        $mb = [math]::Round(((Get-ChildItem $dst -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
        [pscustomobject]@{ Date = (Get-Date).ToString('dd/MM/yyyy'); Path = $dst; Count = $r.Ok; Video = [bool]$script:AllVideo; SizeMB = $mb } |
            ConvertTo-Json | Set-Content $AllInfoFile -Encoding UTF8
        $drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $dst.Substring(0, 2)) -ErrorAction SilentlyContinue
        $warn = if ($drive -and $drive.DriveType -ne 2 -and $dst -notmatch 'OneDrive|Google Drive|Dropbox') { "`n`nAtenção: você salvou neste PC. Copie a pasta para um pendrive ou para a nuvem, senão ela some ao formatar." } else { '' }
        $failTxt = if (@($r.Fail).Count) { "`n`nNão copiados: " + (@($r.Fail) -join ', ') } else { '' }
        $cats = (@($r.Cats) | Select-Object -First 8) -join ', '
        [void](Show-Dialog 'Backup concluído' ("$($r.Ok) de $($r.Total) drivers salvos ($mb MB):`n$cats`n`nPasta:`n$dst`n`nDepois de formatar: abra a pasta e dê dois cliques em REINSTALAR-DRIVERS.bat, depois reinicie.$failTxt$warn") 'ok')
        Update-Cards; Update-Home
    }
}

# ---------------------------------------------------------------- atualização de drivers (Catálogo do Microsoft Update)

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

# ---------------------------------------------------------------- atualização do próprio HollowDrivers

$script:AppUpd = $null
function Start-AppUpdateCheck([bool]$manual) {
    if ($manual) { $BtnAppCheck.IsEnabled = $false; $BtnAppCheck.Content = 'Procurando...' }
    Start-Bg ($LogicText + "`nGet-AppUpdate '$UpdateRepo' '$AppVersion'") {
        param($out, $err)
        $BtnAppCheck.IsEnabled = $true; $BtnAppCheck.Content = 'Procurar atualização'
        $script:AppUpd = if ($out -and $out.Count) { $out[$out.Count - 1] } else { $null }
        $script:AppChecked = $true
        if ($script:AppUpd) { $FooterText.Text = "HollowDrivers $AppVersion  •  versão $($script:AppUpd.Version) disponível em Configurações" }
        Update-ConfigCard
    }
}

# Baixa a versão nova e confere a assinatura RSA com a chave pública embutida no app.
$AppDlTpl = @'
$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
Invoke-WebRequest -UseBasicParsing -Uri '__URL__' -OutFile '__OUT__' -TimeoutSec 300
$raw = (Invoke-WebRequest -UseBasicParsing -Uri '__SIGURL__' -TimeoutSec 60).Content
if ($raw -is [byte[]]) { $raw = [Text.Encoding]::ASCII.GetString($raw) }   # o GitHub entrega como binário
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
$rsa.PersistKeyInCsp = $false
$rsa.FromXmlString('__PUB__')
$ok = $false
try { $ok = $rsa.VerifyData([IO.File]::ReadAllBytes('__OUT__'), 'SHA256', [Convert]::FromBase64String($raw.Trim())) } catch { }
if (-not $ok) { [IO.File]::Delete('__OUT__'); throw 'a versão baixada NÃO tem a assinatura oficial do HollowDrivers e foi descartada' }
'ok'
'@

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

$CleanLogic = {
    function Get-CleanRoots {
        @(
            [pscustomobject]@{ Id = 'temp'; Root = $env:TEMP; Days = 7; Recursive = $true; Pattern = '*' },
            [pscustomobject]@{ Id = 'updates'; Root = (Join-Path $env:LOCALAPPDATA 'HollowDrivers\updates'); Days = 7; Recursive = $true; Pattern = '*' },
            [pscustomobject]@{ Id = 'logs'; Root = (Join-Path $env:LOCALAPPDATA 'HollowDrivers'); Days = 30; Recursive = $false; Pattern = '*.log' }
        )
    }
    function Get-CleanCandidates($roots) {
        $now = [datetime]::UtcNow
        foreach ($r in $roots) {
            if (-not $r.Root -or -not [IO.Directory]::Exists($r.Root)) { continue }
            try {
                $root = [IO.Path]::GetFullPath($r.Root).TrimEnd('\')
                if (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                $pending = New-Object 'System.Collections.Generic.Stack[string]'
                $pending.Push($root)
                while ($pending.Count) {
                    $dir = $pending.Pop()
                    try { $children = [IO.Directory]::EnumerateFileSystemEntries($dir) }
                    catch { continue }
                    foreach ($path in $children) {
                        try {
                            $attr = [IO.File]::GetAttributes($path)
                            if (($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                            if (($attr -band [IO.FileAttributes]::Directory) -ne 0) {
                                if ($r.Recursive) { $pending.Push($path) }
                                continue
                            }
                            $file = New-Object IO.FileInfo $path
                            if ($r.Pattern -ne '*' -and $file.Name -notlike $r.Pattern) { continue }
                            if ($file.LastWriteTimeUtc -ge $now.AddDays(-[int]$r.Days)) { continue }
                            [pscustomobject]@{ Category = $r.Id; Path = $file.FullName; Size = [int64]$file.Length; Ticks = $file.LastWriteTimeUtc.Ticks }
                        } catch { continue }
                    }
                }
            } catch { continue }
        }
    }
    function Invoke-CleanCandidates($candidates, $roots) {
        $removed = 0; $bytes = [int64]0; $skipped = 0
        $now = [datetime]::UtcNow
        foreach ($candidate in $candidates) {
            try {
                $r = @($roots | Where-Object { $_.Id -eq $candidate.Category })[0]
                if (-not $r -or -not $r.Root -or -not [IO.Directory]::Exists($r.Root)) { throw 'root' }
                $root = [IO.Path]::GetFullPath($r.Root).TrimEnd('\')
                $path = [IO.Path]::GetFullPath([string]$candidate.Path)
                if (-not $path.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'path' }
                if (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'root link' }
                $parent = [IO.Path]::GetDirectoryName($path)
                if (-not $r.Recursive -and -not $parent.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'depth' }
                while (-not $parent.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
                    if (([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'link' }
                    $parent = [IO.Path]::GetDirectoryName($parent)
                    if (-not $parent -or -not $parent.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'path' }
                }
                $file = New-Object IO.FileInfo $path
                if (-not $file.Exists -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'file' }
                if ($r.Pattern -ne '*' -and $file.Name -notlike $r.Pattern) { throw 'pattern' }
                if ($file.Length -ne [int64]$candidate.Size -or $file.LastWriteTimeUtc.Ticks -ne [int64]$candidate.Ticks) { throw 'changed' }
                if ($file.LastWriteTimeUtc -ge $now.AddDays(-[int]$r.Days)) { throw 'new' }
                $size = $file.Length
                $file.Delete()
                $removed++; $bytes += $size
            } catch { $skipped++ }
        }
        [pscustomobject]@{ Removed = $removed; Bytes = $bytes; Skipped = $skipped }
    }
}
function Format-CleanSize([long]$size) {
    if ($size -ge 1GB) { return ('{0:N2} GB' -f ($size / 1GB)) }
    if ($size -ge 1MB) { return ('{0:N1} MB' -f ($size / 1MB)) }
    return ('{0:N0} KB' -f [math]::Ceiling($size / 1KB))
}
$script:CleanFiles = @()
$script:CleanBusy = $false
function Update-CleanDrive {
    try {
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($env:SystemRoot))
        $CleanDrive.Text = ('{0:N1} GB livres em {1}' -f ($drive.AvailableFreeSpace / 1GB), $drive.Name.TrimEnd('\'))
    } catch { $CleanDrive.Text = 'Espaço livre indisponível' }
}
function Start-CleanScan {
    if ($script:CleanBusy) { return }
    $script:CleanBusy = $true
    $BtnCleanScan.IsEnabled = $false; $BtnCleanRun.IsEnabled = $false
    $CleanStatus.Text = 'Analisando arquivos antigos...'
    Start-Bg ($CleanLogic.ToString() + [Environment]::NewLine + '@(Get-CleanCandidates (Get-CleanRoots))') {
        param($out, $err)
        $script:CleanBusy = $false; $BtnCleanScan.IsEnabled = $true
        if ($err) { $CleanStatus.Text = 'Não foi possível concluir a análise: ' + $err; return }
        $script:CleanFiles = @($out | Where-Object { $_ -and $_.Path })
        $table = New-Object Data.DataTable
        [void]$table.Columns.Add('Select', [bool])
        [void]$table.Columns.Add('Id', [string])
        [void]$table.Columns.Add('Category', [string])
        [void]$table.Columns.Add('Count', [int])
        [void]$table.Columns.Add('Size', [string])
        [void]$table.Columns.Add('Description', [string])
        foreach ($c in @(
            @{ Id = 'temp'; Name = 'Temporários'; Desc = 'Arquivos temporários do usuário, com mais de 7 dias' },
            @{ Id = 'updates'; Name = 'Downloads de atualização'; Desc = 'Downloads antigos do HollowDrivers, com mais de 7 dias' },
            @{ Id = 'logs'; Name = 'Logs antigos'; Desc = 'Logs do HollowDrivers, com mais de 30 dias' }
        )) {
            $files = @($script:CleanFiles | Where-Object { $_.Category -eq $c.Id })
            $sum = [long]0; foreach ($f in $files) { $sum += [long]$f.Size }
            $row = $table.NewRow()
            $row.Select = $false; $row.Id = $c.Id; $row.Category = $c.Name
            $row.Count = $files.Count; $row.Size = Format-CleanSize $sum; $row.Description = $c.Desc
            $table.Rows.Add($row)
        }
        $CleanGrid.ItemsSource = $table.DefaultView
        $total = [long]0; foreach ($f in $script:CleanFiles) { $total += [long]$f.Size }
        $CleanSummary.Text = ('{0} arquivos antigos encontrados • até {1} recuperáveis' -f $script:CleanFiles.Count, (Format-CleanSize $total))
        $CleanStatus.Text = 'Selecione as categorias e confirme a limpeza. Arquivos em uso são ignorados.'
        if ($script:CleanResultMessage) { $CleanStatus.Text = $script:CleanResultMessage; $script:CleanResultMessage = '' }
        $BtnCleanRun.IsEnabled = ($script:CleanFiles.Count -gt 0)
        Update-CleanDrive
    }
}
function Start-CleanRun {
    if ($script:CleanBusy) { return }
    [void]$CleanGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell, $true)
    [void]$CleanGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true)
    $ids = @($CleanGrid.ItemsSource | Where-Object { $_.Row.Select -and $_.Row.Count -gt 0 } | ForEach-Object { $_.Row.Id })
    if (-not $ids.Count) { [void](Show-Dialog 'Escolha uma categoria' 'Marque pelo menos uma categoria com arquivos encontrados.' 'info'); return }
    $selected = @($script:CleanFiles | Where-Object { $ids -contains $_.Category })
    $bytes = [long]0; foreach ($f in $selected) { $bytes += [long]$f.Size }
    $message = ('{0} arquivos • até {1}' -f $selected.Count, (Format-CleanSize $bytes)) + [Environment]::NewLine + [Environment]::NewLine + 'Os arquivos selecionados serão excluídos. Deseja continuar?'
    if (-not (Show-Dialog 'Confirmar limpeza' $message 'ask' -YesNo -YesText 'Limpar')) { return }
    $script:CleanBusy = $true
    $BtnCleanRun.IsEnabled = $false; $BtnCleanScan.IsEnabled = $false
    $CleanStatus.Text = 'Limpando arquivos selecionados...'
    Start-Bg ($CleanLogic.ToString() + [Environment]::NewLine + 'Invoke-CleanCandidates $CleanSelection (Get-CleanRoots)') {
        param($out, $err)
        $script:CleanBusy = $false; $BtnCleanScan.IsEnabled = $true
        if ($err) { $CleanStatus.Text = 'Falha na limpeza: ' + $err; return }
        $result = @($out)[-1]
        $script:CleanResultMessage = ('{0} arquivos removidos • {1} liberados • {2} ignorados' -f $result.Removed, (Format-CleanSize ([long]$result.Bytes)), $result.Skipped)
        Start-CleanScan
    } @{ CleanSelection = $selected }
}
function Update-StorageInfo {
    try {
        $root = [IO.Path]::GetPathRoot($env:SystemRoot)
        $drive = New-Object IO.DriveInfo $root
        if (-not $drive.IsReady) { throw 'unavailable' }
        $StorageText.Text = '{0:N1} GB livres de {1:N1} GB em {2}' -f ($drive.AvailableFreeSpace / 1GB), ($drive.TotalSize / 1GB), $drive.Name.TrimEnd('\')
    } catch {
        $StorageText.Text = 'Espaço livre indisponível'
    }
}

function Open-StorageSettings([string]$page) {
    try { Start-Process -FilePath $page -ErrorAction Stop }
    catch { [void](Show-Dialog 'Não foi possível abrir' 'Abra Configurações do Windows > Sistema > Armazenamento.' 'warn') }
}
function Act-SrOpen {
    if (-not (Show-Dialog 'Restaurar o Windows' "Vou abrir a Restauração do Sistema do Windows.`n`nLá você escolhe um dos pontos salvos e o PC reinicia para voltar àquele momento. Drivers, programas e configurações voltam; seus arquivos pessoais ficam como estão." 'ask' -YesNo -YesText 'Abrir')) { return }
    try { Start-Process 'rstrui.exe' } catch { [void](Show-Dialog 'Não foi possível abrir' $_.Exception.Message 'bad') }
}

function Update-ConfigCard {
    $ConfigUpd.Inlines.Clear()
    Add-Line $ConfigUpd ("Versão instalada: {0}" -f $AppVersion) '#E8EAED' 15 $true
    if ($script:AppUpd) {
        Add-Line $ConfigUpd ('Versão {0} disponível ({1} MB)' -f $script:AppUpd.Version, $script:AppUpd.SizeMB) $Hex.warn 13.5 $true
        if ($script:AppUpd.Notes) { Add-Line $ConfigUpd $script:AppUpd.Notes '#C9CED6' 12.5 }
        $BtnAppInstall.Visibility = 'Visible'
    } else {
        Add-Line $ConfigUpd $(if ($script:AppChecked) { 'Nenhuma versão nova por enquanto.' } else { 'Clique em "Procurar atualização" para verificar agora.' }) $(if ($script:AppChecked) { $Hex.ok } else { $Hex.info }) 13
        $BtnAppInstall.Visibility = 'Collapsed'
    }
    Add-Line $ConfigUpd 'O app também verifica sozinho ao abrir e uma vez por dia.' $Hex.info 12.5
}

function Act-AppUpdate {
    if ($script:Tasks.Count -or $script:BackupBusy -or $script:ElevBusy) { $FooterText.Text='Aguarde as operações antes de atualizar.'; return }
    $u = $script:AppUpd
    if (-not $u) { return }
    $msg = "Atualizar o HollowDrivers de $AppVersion para $($u.Version)?`n`nFeche também o monitor na bandeja antes de continuar. O app vai fechar, atualizar e abrir novamente. Seu backup e suas configurações são mantidos."
    if ($u.Notes) { $msg += "`n`nNovidades:`n" + $u.Notes }
    if (-not (Show-Dialog 'Atualizar HollowDrivers' $msg 'ask' -YesNo -YesText 'Atualizar')) { return }
    $script:AppSetup = Join-Path $env:TEMP "HollowDrivers-Setup-$($u.Version).exe"
    $FooterText.Text = "Baixando HollowDrivers $($u.Version)..."
    $code = Expand-Tpl $AppDlTpl @{ '__URL__' = $u.Url; '__SIGURL__' = $u.SigUrl; '__OUT__' = $script:AppSetup; '__PUB__' = $UpdatePubKey }
    Start-Bg $code {
        param($out, $err)
        if ($err -or -not $out -or "$($out[$out.Count - 1])" -ne 'ok') {
            $FooterText.Text = "HollowDrivers $AppVersion"
            [void](Show-Dialog 'Atualização falhou' "Não foi possível baixar a versão nova. Nada foi alterado.`n`n$err" 'bad')
            return
        }
        if ($script:Tasks.Count -or $script:BackupBusy -or $script:ElevBusy) { $FooterText.Text='Download pronto. Aguarde as operações e tente atualizar novamente.'; return }
        Start-Process $script:AppSetup -ArgumentList '/silent'
        $app.Shutdown()
    }
}

# ---------------------------------------------------------------- temas de cores


function Add-ThemeCards($panel) {
    foreach ($k in $Themes.Keys) {
        $t = $Themes[$k]
        $card = New-Object Windows.Controls.Border
        $card.Width = 136; $card.Margin = '0,0,12,12'; $card.Padding = '10,14'; $card.CornerRadius = 12; $card.Cursor = 'Hand'
        $card.Background = Get-Brush '#1F232C'; $card.BorderThickness = 2; $card.Tag = $k
        $card.BorderBrush = Get-Brush $(if ($k -eq $ThemeKey) { $t.A1 } else { '#2A2F3A' })
        $sp = New-Object Windows.Controls.StackPanel
        $el = New-Object Windows.Shapes.Ellipse
        $el.Width = 48; $el.Height = 48; $el.Margin = '0,0,0,8'
        $el.Fill = New-Object Windows.Media.LinearGradientBrush(([Windows.Media.ColorConverter]::ConvertFromString($t.A1)), ([Windows.Media.ColorConverter]::ConvertFromString($t.A2)), 45)
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = $(if ($k -eq $ThemeKey) { "$($t.Nome)  ✓" } else { $t.Nome }); $tb.HorizontalAlignment = 'Center'; $tb.FontSize = 13
        [void]$sp.Children.Add($el); [void]$sp.Children.Add($tb)
        $card.Child = $sp
        # MouseLeftButtonDown + Handled: senão o "arrastar janela" engole o clique
        $card.add_MouseLeftButtonDown({ param($s, $e)
            $e.Handled = $true
            if ($s.Tag -eq $ThemeKey) { return }
            $st = Get-Settings; $st.Theme = $s.Tag; Save-Settings $st
            Start-Launcher ''
            $app.Shutdown()
        })
        [void]$panel.Children.Add($card)
    }
}

function Act-EnableGpu {
    $g = $script:Gpu
    if (-not $g -or -not $g.Pnp) { return }
    $msg = "A placa está DESABILITADA no Windows (código 22) — o driver está instalado, só o dispositivo está desligado.`n`n" +
        "O HollowDrivers vai ligar o dispositivo de novo. A tela pode piscar por um instante.`n`n" +
        "O Windows vai pedir permissão de administrador."
    if (-not (Show-Dialog 'Reativar a placa de vídeo?' $msg 'ask' -YesNo -YesText 'Reativar')) { return }
    $BtnEnable.IsEnabled = $false
    Invoke-Elevated $EnableTpl @{ '__PNP__' = $g.Pnp } 'reativar' {
        param($log, $err)
        $BtnEnable.IsEnabled = $true
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador, então nada mudou.' 'warn'); return }
        if ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Não foi possível' $matches[1] 'bad'); return }
        $depois = if ($log -match 'DEPOIS=([^\r\n]+)') { $matches[1].Trim() } else { '' }
        if ($depois -match 'OK/CM_PROB_NONE') {
            [void](Show-Dialog 'Placa reativada' 'A placa de vídeo voltou a funcionar. Analise de novo para confirmar.' 'ok')
        } else {
            $extra = if ($log -match 'PNPUTIL=([^\r\n]+)') { "`n`n" + $matches[1].Trim() } else { '' }
            [void](Show-Dialog 'Ainda desabilitada' ("O Windows aceitou o comando, mas a placa continua desligada ($depois).`n`nIsso costuma exigir reinício: reinicie o PC e analise de novo." + $extra) 'warn')
        }
        Start-Scan
    }
}

function Act-Reboot {
    $quais = ($script:NeedReboot | Select-Object -First 4 -Expand Dispositivo) -join "`n•   "
    if (-not (Show-Dialog 'Reiniciar o PC agora?' ("Estes drivers só entram em funcionamento depois do reinício:`n`n•   $quais`n`nSalve o que estiver aberto antes de continuar.") 'ask' -YesNo -YesText 'Reiniciar')) { return }
    try { Restart-Computer -Force -ErrorAction Stop } catch { [void](Show-Dialog 'Não foi possível' $_.Exception.Message 'bad') }
}

function Act-History {
    $rows = @($script:History | ForEach-Object {
        [pscustomobject]@{ Quando = $_.Quando.ToString('dd/MM/yyyy HH:mm'); Origem = $_.Origem; Detalhe = $_.Detalhe; Destaque = ($_.Origem -like 'Driver Booster*') }
    })
    if (-not $rows.Count) { [void](Show-Dialog 'Histórico' 'Nenhuma instalação de driver de vídeo encontrada nos registros do Windows.' 'info'); return }
    Show-TableWindow 'Quem instalou driver na placa de vídeo' $rows 'Fonte: registros de instalação do Windows. Em vermelho: trocas feitas pelo Driver Booster.'
}

function Act-Crashes {
    $list = @(Get-CrashList 90)
    if (-not $list.Count) { [void](Show-Dialog 'Quedas do PC' 'Nenhuma queda inesperada nos últimos 90 dias.' 'ok'); return }
    $sudden = @($list | Where-Object { $_.Tipo -like 'Desligou de repente*' }).Count
    $madrugada = @($list | Where-Object { $_.Quando.Hour -lt 6 }).Count
    $sozinho = @($list | Where-Object { $_.Sozinho }).Count
    $rows = $list | ForEach-Object {
        [pscustomobject]@{
            Quando = $_.Quando.ToString('dd/MM/yyyy HH:mm (ddd)'); Tipo = $_.Tipo; Estado = $_.Estado
            'Ficou desligado' = $_.Desligado
            Destaque = ($_.Tipo -like 'Desligou de repente*')
        }
    }
    $note = '{0} em 90 dias  •  {1} sem erro registrado  •  {2} de madrugada  •  {3} voltaram sozinhas' -f (Get-Plural $list.Count 'queda' 'quedas'), $sudden, $madrugada, $sozinho
    if ($sozinho -eq 0 -and $sudden -ge [Math]::Ceiling($list.Count / 2)) {
        $note += "`nO PC ficou horas desligado depois de cada queda e não voltou sozinho: isso combina tanto com falta de luz quanto com problema na fonte. Veja no seu roteador se ele reiniciou nos mesmos horários — se sim, foi a rede elétrica."
    } elseif ($sozinho) {
        $note += "`nAs que voltaram na hora não são falta de luz (nesse caso o PC ficaria desligado): são travamento ou falha do próprio PC."
    }
    Show-TableWindow 'Quedas do PC — últimos 90 dias' $rows $note
}

function Act-Wu {
    $BtnWu.IsEnabled = $false; $BtnWu.Content = 'Consultando Windows Update...'
    Start-Bg $WuCode {
        param($out, $err)
        $BtnWu.IsEnabled = $true; $BtnWu.Content = 'Windows Update'
        $res = @($out | Where-Object { $_ })
        if ($err -and -not $res.Count) { [void](Show-Dialog 'Windows Update' "Não foi possível consultar o Windows Update.`n`n$err" 'warn') }
        elseif (-not $res.Count) { [void](Show-Dialog 'Windows Update' "Nenhuma atualização de driver oferecida pelo Windows Update.`n`nSe você bloqueou drivers pelo Windows Update (recomendado para placas de vídeo), isso é o esperado." 'ok') }
        else { Show-TableWindow 'Atualizações de driver no Windows Update' $res 'Somente leitura — nada foi instalado. Para vídeo, prefira sempre o instalador oficial do fabricante.' }
    }
}

function Act-Csv {
    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) ('HollowDrivers-{0:yyyyMMdd-HHmm}.csv' -f (Get-Date))
    $dt.DefaultView.ToTable() |
        Select-Object Status, Categoria, Dispositivo, Fabricante, @{ n = 'Versão'; e = { $_.Versao } },
            @{ n = 'Data'; e = { if ($_.Data -is [datetime]) { $_.Data.ToString('dd/MM/yyyy') } } }, @{ n = 'Idade (anos)'; e = { $_.Idade } }, INF |
        Export-Csv $path -NoTypeInformation -Delimiter ';' -Encoding UTF8
    Set-Status 'relatório salvo na Área de Trabalho'
}

$TaskTpl = @'
try {
    if ('__ON__' -eq '1') {
        $a = New-ScheduledTaskAction -Execute '__RUN__' -Argument '__ARGS__'
        $t = @(New-ScheduledTaskTrigger -AtLogOn -User '__USER__')
        if ('__DAILY__' -eq '1') { $t += New-ScheduledTaskTrigger -Daily -At '12:00' }
        $p = New-ScheduledTaskPrincipal -UserId '__USER__' -RunLevel Highest -LogonType Interactive
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName '__TASK__' -Description 'HollowDrivers' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
        W 'TAREFA=criada'
    } else {
        Unregister-ScheduledTask -TaskName '__TASK__' -Confirm:$false -ErrorAction Stop
        W 'TAREFA=removida'
    }
} catch { W ('ERRO=' + $_.Exception.Message) }
finally { Save-Log }
'@

function Act-Rescue {
    if (Test-RescueTask) {
        if (-not (Show-Dialog 'Socorro automático' 'Desligar o socorro automático? O HollowDrivers vai voltar a pedir sua confirmação para restaurar o vídeo.' 'ask' -YesNo -YesText 'Desligar')) { return }
        $ligar = $false
    } else {
        $msg = "Criar uma tarefa do Windows que, ao ligar o PC, restaura o driver de vídeo salvo SE a placa estiver com erro?`n`n" +
            "•   Roda só no logon, e só faz isso: reinstalar uma cópia sua já conferida`n" +
            "•   Uma tentativa por inicialização, com registro do que fez`n" +
            "•   Não instala driver novo nem mexe em mais nada`n`n" +
            "É o que permite voltar o vídeo SEM pedir permissão na hora do aperto. Para criar a tarefa, o Windows vai pedir permissão de administrador agora."
        if (-not (Show-Dialog 'Ligar socorro automático?' $msg 'ask' -YesNo -YesText 'Ligar')) { return }
        $ligar = $true
    }
    $run = if (Test-Path $Exe) { $Exe } else { 'powershell.exe' }
    $args = if (Test-Path $Exe) { '-AutoRescue' } else { '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AutoRescue' -f $ScriptPath }
    $BtnRescue.IsEnabled = $false
    Invoke-Elevated $TaskTpl @{ '__ON__' = $(if ($ligar) { '1' } else { '0' }); '__TASK__' = $RescueTask; '__DAILY__' = '0'
        '__RUN__' = $run; '__ARGS__' = $args; '__USER__' = "$env:USERDOMAIN\$env:USERNAME" } 'tarefa' {
        param($log, $err)
        $BtnRescue.IsEnabled = $true
        if ($err) { [void](Show-Dialog 'Cancelado' 'O Windows não deu permissão de administrador, então nada mudou.' 'warn') }
        elseif ($log -match 'ERRO=(.+)') { [void](Show-Dialog 'Não foi possível' $matches[1] 'bad') }
        elseif ($log -match 'TAREFA=criada') { [void](Show-Dialog 'Socorro automático ligado' "Se a placa de vídeo quebrar, o HollowDrivers restaura o driver salvo sozinho ao ligar o PC, sem pedir nada.`n`nVocê pode desligar isso quando quiser." 'ok') }
        else { [void](Show-Dialog 'Socorro automático desligado' 'A tarefa foi removida.' 'ok') }
        Update-RescueButton; Update-Cards
    }
}

function Update-RescueButton {
    if (Test-RescueTask) { $BtnRescue.Content = 'Socorro automático: ligado'; $BtnRescue.Foreground = Get-Brush $Hex.ok }
    else { $BtnRescue.Content = 'Socorro automático: desligado'; $BtnRescue.Foreground = Get-Brush $Hex.info }
}

function Act-Watch {
    if (Test-WatchEnabled) {
        if (Show-Dialog 'Proteção automática' 'Desligar a proteção automática? O escudo perto do relógio vai sumir.' 'ask' -YesNo -YesText 'Desligar') {
            Set-WatchEnabled $false; Stop-Tray
        }
    } else {
        $msg = "Um escudo fica perto do relógio (verde = tudo certo, vermelho = atenção). O HollowDrivers confere seu PC ao ligar e a cada hora, e só avisa se:`n`n•   o driver de vídeo foi trocado`n•   a placa de vídeo está com erro`n•   o PC caiu desde a última vez`n•   o Driver Booster voltou`n`nNão instala nada. Dá para desligar quando quiser."
        if (Show-Dialog 'Ligar proteção automática?' $msg 'ask' -YesNo -YesText 'Ligar') {
            Set-WatchEnabled $true
            $st = Get-State; $st.LastCheck = (Get-Date).ToString('o'); Save-State $st
            Start-Launcher '-Watch'
        }
    }
    Update-WatchButton; Update-Home
}

function Act-RemoveDb {
    $db = @($script:Health.DriverBooster)[0]
    if (-not $db) { return }
    $exe = $null; $arg = ''
    if ($db.Uninstall -match '^"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $arg = $matches[2] }
    elseif ($db.Uninstall) { $exe = $db.Uninstall }
    if (-not $exe -or -not (Test-Path $exe)) {
        $u = if ($db.Path) { Get-ChildItem $db.Path -Filter 'unins*.exe' -Recurse -Depth 1 -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($u) { $exe = $u.FullName; $arg = '' } else { $exe = $null }
    }
    if (-not $exe) { [void](Show-Dialog 'Desinstalador não encontrado' 'Remova pelo Windows: Configurações → Apps → Driver Booster.' 'warn'); return }
    $BtnDb.IsEnabled = $false
    $code = if ($arg) { "Start-Process '{0}' -ArgumentList '{1}' -Wait" -f $exe.Replace("'", "''"), $arg.Replace("'", "''") } else { "Start-Process '{0}' -Wait" -f $exe.Replace("'", "''") }
    Start-Bg $code { param($o, $e) $BtnDb.IsEnabled = $true; Start-Scan }
}

# ---------------------------------------------------------------- eventos

$BigBtn.add_Click({ Start-Scan })
$BtnAdvanced.add_Click({ Show-View $true; Show-Section 'drivers' })
$BtnHomeScan.add_Click({ Start-Scan })
$HomeNavHome.add_Click({ $HomeNavHome.IsChecked = $true })
$BtnHomeConfig.add_Click({ Show-Config $true })
$HomeNavVideo.add_Click({ Show-View $true; Show-Section 'video' })
$HomeNavSystem.add_Click({ Show-View $true; Show-Section 'sistema'; Update-StorageInfo })
$HomeNavClean.add_Click({ Show-View $true; Show-Section 'limpeza'; Update-CleanDrive; if (-not $CleanGrid.ItemsSource) { Start-CleanScan } })
$HomeNavGuard.add_Click({ Show-View $true; Show-Section 'protecao' })
$HomeNavWin.add_Click({ Show-View $true; Show-Section 'windows'; Start-WuCheck })
$BtnAdvConfig.add_Click({ Show-Config $true })

$BtnBack.add_Click({ Show-View $false })
$BtnScan.add_Click({ Start-Scan })
$BtnGood.add_Click({ Act-MarkGood })
$BtnUpd.add_Click({ Act-Updates })
$BtnRestore.add_Click({ Act-Restore })
$BtnPoint.add_Click({ Act-Point })
$BtnAll.add_Click({ Act-AllBackup })
$BtnHist.add_Click({ Act-History })
$BtnEnable.add_Click({ Act-EnableGpu })
$BtnCrash.add_Click({ Act-Crashes })
$BtnWu.add_Click({ Act-Wu })
$BtnSites.add_Click({ $SitesPopup.IsOpen = -not $SitesPopup.IsOpen })
$BtnCsv.add_Click({ Act-Csv })
$BtnWatch.add_Click({ Act-Watch })
$BtnRescue.add_Click({ Act-Rescue })
$BtnDb.add_Click({ Act-RemoveDb })
$SearchBox.add_TextChanged({ Update-Filter })
$ChkMs.add_Checked({ Update-Filter })
$ChkMs.add_Unchecked({ Update-Filter })
foreach ($n in $ChipNames) { (Get-Variable $n -Scope Script -ValueOnly).add_Click({ param($s, $e) Set-Chip $s }) }
$NavDrivers.add_Click({ Show-Section 'drivers' })
$NavVideo.add_Click({ Show-Section 'video' })
$NavSystem.add_Click({ Show-Section 'sistema'; Update-StorageInfo })
$NavClean.add_Click({ Show-Section 'limpeza'; Update-CleanDrive; if (-not $CleanGrid.ItemsSource) { Start-CleanScan } })
$NavGuard.add_Click({ Show-Section 'protecao' })
$NavWin.add_Click({ Show-Section 'windows'; Start-WuCheck })

$BtnConfigClose.add_Click({ Show-Config $false })
$BtnRailConfig.add_Click({ Set-Rail (-not $script:RailOpen) })
$BtnConfigHome.add_Click({ Show-View $false })
$ConfigNavSettings.add_Click({ $ConfigNavSettings.IsChecked = $true })
$ConfigNavDrivers.add_Click({ Show-View $true; Show-Section 'drivers' })
$ConfigNavVideo.add_Click({ Show-View $true; Show-Section 'video' })
$ConfigNavSystem.add_Click({ Show-View $true; Show-Section 'sistema'; Update-StorageInfo })
$ConfigNavClean.add_Click({ Show-View $true; Show-Section 'limpeza'; Update-CleanDrive; if (-not $CleanGrid.ItemsSource) { Start-CleanScan } })
$ConfigNavGuard.add_Click({ Show-View $true; Show-Section 'protecao' })
$ConfigNavWin.add_Click({ Show-View $true; Show-Section 'windows'; Start-WuCheck })
$BtnWuHold.add_Click({ Act-WuHold })
$BtnWuKeep.add_Click({ Act-WuKeep })
$BtnWuDrv.add_Click({ Act-WuDrv })
$BtnSrPoint.add_Click({ Act-SrPoint })
$BtnSrOpen.add_Click({ Act-SrOpen })
$BtnCleanup.add_Click({ Show-Section 'limpeza'; Update-CleanDrive; if (-not $CleanGrid.ItemsSource) { Start-CleanScan } })
$BtnCleanScan.add_Click({ Start-CleanScan })
$BtnCleanRun.add_Click({ Start-CleanRun })
$BtnCleanWindows.add_Click({
    $page = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'ms-settings:storagerecommendations' } else { 'ms-settings:storagesense' }
    Open-StorageSettings $page
})
$BtnCleanSense.add_Click({ Open-StorageSettings 'ms-settings:storagepolicies' })
$BtnStorageSense.add_Click({ Open-StorageSettings 'ms-settings:storagepolicies' })
$BtnRailHome.add_Click({ Set-Rail (-not $script:RailOpen) })
$BtnRailAdv.add_Click({ Set-Rail (-not $script:RailOpen) })
$BtnAppCheck.add_Click({ Start-AppUpdateCheck $true })
$BtnAppInstall.add_Click({ Act-AppUpdate })

$BtnKeyAll.add_Click({ Act-KeyAll })

# atalhos: F5 escaneia, Ctrl+F busca, Esc volta ao início
$Win.add_KeyDown({ param($s, $e)
    if ($e.Key -eq 'F5') { Start-Scan; $e.Handled = $true; return }
    if ($e.Key -eq 'Escape' -and $ConfigView.Visibility -eq 'Visible') { Show-Config $false; $e.Handled = $true; return }
    if ($e.Key -eq 'Escape' -and $AdvView.Visibility -eq 'Visible') { Show-View $false; $e.Handled = $true; return }
    if ($e.Key -eq 'F' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
        Show-View $true; Show-Section 'drivers'; [void]$SearchBox.Focus(); $SearchBox.SelectAll(); $e.Handled = $true
    }
})

if (Test-WatchEnabled) { Set-WatchEnabled $true }
Set-Rail $true
Add-ThemeCards $ConfigThemes
Update-StorageInfo
Update-ConfigCard
Update-WuCard
Update-WatchButton
Update-RescueButton
Update-Sites
function Show-RescueRequest {
    if (-not $WdTimer.IsEnabled) {
        $g = Get-GpuInfo
        $b = Get-Baseline
        if ($g -and $g.Code -ne 0 -and $b -and (Get-Backup $b.Version)) {
            $Win.WindowState = 'Normal'; [void]$Win.Activate()
            Set-Verdict 'bad' 'Seu vídeo está quebrado' 'Vou restaurar o driver que estava funcionando. NÃO desligue o PC.'
            $script:WdLeft = 30
            $Findings.Children.Clear()
            Add-Finding 'Socorro automático' ("A placa de vídeo está com erro ({0}) e existe uma cópia do driver {1}. Vou reinstalar essa cópia em alguns segundos; o Windows vai pedir permissão de administrador." -f (Get-ProblemText $g.Code), $b.Version) 'bad' 'Cancelar' {
                $WdTimer.Stop(); Set-Verdict 'info' 'Socorro cancelado' 'Use o botão Restaurar quando quiser.'
            }
            $WdTimer.Start()
        }
    }
}
$Win.add_Loaded({
    Start-AppUpdateCheck $false
    if ($Rescue) { Show-RescueRequest }
})
$BtnRestore.IsEnabled = [bool](Get-Backup (Get-Baseline).Version)

$instanceTimer = New-Object Windows.Threading.DispatcherTimer
$instanceTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$instanceTimer.add_Tick({
    if ($activateEvent.WaitOne(0)) {
        if ($Win.WindowState -eq 'Minimized') { $Win.WindowState = 'Normal' }
        [void]$Win.Activate()
    }
    if ($rescueEvent.WaitOne(0)) { Show-RescueRequest }
})
$instanceTimer.Start()
$Win.add_Closing({ param($sender,$args)
    if($script:Tasks.Count -or $script:ElevBusy -or $script:BackupBusy){
        $args.Cancel=$true
        $FooterText.Text='Aguarde a operação em andamento terminar antes de fechar.'
    }
})
[void]$app.Run($Win)
} finally {
    if ($instanceTimer) { $instanceTimer.Stop() }
    if ($ownsUiMutex) { $uiMutex.ReleaseMutex() }
    $uiMutex.Dispose()
    $activateEvent.Dispose()
    $rescueEvent.Dispose()
}

} finally { $sessionLease.Dispose() }
