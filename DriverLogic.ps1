$Logic = {
    $CatMap = @{
        DISPLAY = 'Vídeo'; NET = 'Rede'; MEDIA = 'Áudio'; AUDIOENDPOINT = 'Áudio'; SYSTEM = 'Sistema / Chipset'
        USB = 'USB'; HDC = 'Armazenamento'; SCSIADAPTER = 'Armazenamento'; BLUETOOTH = 'Bluetooth'
        HIDCLASS = 'Entrada'; MOUSE = 'Entrada'; KEYBOARD = 'Entrada'; MONITOR = 'Monitor'
        PRINTER = 'Impressora'; CAMERA = 'Câmera'; IMAGE = 'Câmera'; SECURITYDEVICES = 'Segurança'
        SOFTWARECOMPONENT = 'Componente de software'; EXTENSION = 'Extensões do fabricante'; FIRMWARE = 'Firmware'
        BIOMETRIC = 'Biometria'; SMARTCARDREADER = 'Leitor de cartão'; SDHOST = 'Leitor de cartão'; SENSOR = 'Sensores'
        BATTERY = 'Bateria / energia'; PORTS = 'Portas'; PROCESSOR = 'Processador'
    }
    $ProblemText = @{
        1 = 'Mal configurado (código 1)'; 10 = 'Não iniciou (código 10)'; 14 = 'Precisa reiniciar (código 14)'
        22 = 'DESABILITADO (código 22)'
        28 = 'SEM DRIVER (código 28)'; 31 = 'Falha ao carregar (código 31)'; 43 = 'FALHOU (código 43)'
    }
    function Get-ProblemText([int]$code) {
        if ($code -eq 0) { return 'OK' }
        if ($ProblemText.ContainsKey($code)) { return $ProblemText[$code] }
        "Erro (código $code)"
    }

    function Get-WuState {
        $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $au = "$pol\AU"
        $get = { param($p, $n) try { (Get-ItemProperty -Path $p -Name $n -ErrorAction Stop).$n } catch { $null } }
        $ate = $null
        $exp = & $get $ux 'PauseUpdatesExpiryTime'
        if ($exp) { try { $ate = ([datetime]$exp).ToLocalTime() } catch { } }
        $pontos = $null; $ultimo = $null
        try {
            $rp = @(Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction Stop)
            $pontos = $rp.Count
            if ($pontos) { $ultimo = ($rp | Sort-Object CreationTime -Descending | Select-Object -First 1).CreationTime }
        } catch { }
        [pscustomobject]@{
            PausadoAte = $ate
            Pausado    = [bool]($ate -and $ate -gt (Get-Date))
            SemAuto    = ((& $get $au 'NoAutoUpdate') -eq 1)
            SemDriver  = ((& $get $pol 'ExcludeWUDriversInQualityUpdate') -eq 1)
            SrLigada   = -not ((& $get 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'DisableSR') -eq 1)
            Pontos     = $pontos
            UltimoPonto = $(if ($ultimo) { try { [Management.ManagementDateTimeConverter]::ToDateTime($ultimo) } catch { $null } } else { $null })
        }
    }

    function Get-DriverScan {
        $problems = @{}
        Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -ne 45 } |
            ForEach-Object { $problems[$_.PNPDeviceID] = $_ }
        $now = Get-Date
        $seen = @{}
        $list = @(foreach ($d in Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) {
            if (-not $d.DeviceName -or -not $d.DriverVersion) { continue }
            $seen[$d.DeviceID] = $true
            $cls = "$($d.DeviceClass)".ToUpper()
            $age = if ($d.DriverDate) { [math]::Round(($now - $d.DriverDate).TotalDays / 365.25, 1) } else { $null }
            if ($problems.ContainsKey($d.DeviceID)) { $status = Get-ProblemText $problems[$d.DeviceID].ConfigManagerErrorCode }
            elseif ($null -ne $age -and $age -ge 4 -and "$($d.DriverProviderName)" -notmatch '^Microsoft') { $status = 'Antigo' }
            else { $status = 'OK' }
            [pscustomobject]@{
                Status      = $status
                Categoria   = $(if ($CatMap.ContainsKey($cls)) { $CatMap[$cls] } else { 'Outros' })
                Dispositivo = $d.DeviceName
                Fabricante  = "$($d.DriverProviderName)"
                Versao      = $d.DriverVersion
                Data        = $d.DriverDate
                Idade       = $age
                INF         = "$($d.InfName)"
                Microsoft   = ("$($d.DriverProviderName)" -match '^Microsoft')
            }
        })
        foreach ($p in $problems.Values) {
            if ($seen.ContainsKey($p.PNPDeviceID)) { continue }
            $list += [pscustomobject]@{
                Status      = Get-ProblemText $p.ConfigManagerErrorCode
                Categoria   = 'Sem driver'
                Dispositivo = $(if ($p.Name) { $p.Name } else { $p.PNPDeviceID })
                Fabricante  = "$($p.Manufacturer)"; Versao = ''; Data = $null; Idade = $null; INF = ''; Microsoft = $false
            }
        }
        $list
    }

    # Notebook com duas placas: prefere a dedicada (NVIDIA, depois AMD) em vez da integrada.
    function Get-GpuInfo {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -like 'PCI\*' } |
            Sort-Object @{ e = { if ($_.PNPDeviceID -match 'VEN_10DE') { 0 } elseif ($_.PNPDeviceID -match 'VEN_1002') { 1 } else { 2 } } },
                        @{ e = { [int64]$_.AdapterRAM }; Descending = $true } |
            Select-Object -First 1
        if (-not $vc) { return $null }
        $venDev = if ($vc.PNPDeviceID -match '(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})') { $matches[1] } else { '' }
        $vendor = switch -regex ($venDev) {
            '^VEN_1002' { 'AMD'; break }
            '^VEN_10DE' { 'NVIDIA'; break }
            '^VEN_8086' { 'Intel'; break }
            default { "$($vc.AdapterCompatibility)" }
        }
        [pscustomobject]@{
            Name = $vc.Name; Version = $vc.DriverVersion; Inf = $vc.InfFilename
            Code = [int]$vc.ConfigManagerErrorCode; VenDev = $venDev; Vendor = $vendor; Pnp = "$($vc.PNPDeviceID)"
        }
    }

    # drivers principais: os que fazem o PC funcionar (vídeo, rede, áudio, chipset, armazenamento, bluetooth)
    $KeyClasses = @{ DISPLAY = 'Vídeo'; NET = 'Rede'; MEDIA = 'Áudio'; SYSTEM = 'Chipset'; HDC = 'Armazenamento'; SCSIADAPTER = 'Armazenamento'; BLUETOOTH = 'Bluetooth' }
    function Get-KeyDrivers {
        # dispositivos diferentes que usam o MESMO driver (ex.: duas pontes AMD PCI) viram uma entrada só
        $porDriver = @{}
        foreach ($k in Get-KeyDriversRaw) {
            $key = '{0}|{1}|{2}' -f $k.Inf, $k.Versao, $k.Nome
            if ($porDriver.ContainsKey($key)) { $porDriver[$key].Qtd++ ; continue }
            $k | Add-Member -NotePropertyName Qtd -NotePropertyValue 1 -Force
            $porDriver[$key] = $k
        }
        @($porDriver.Values)
    }

    function Get-KeyDriversRaw {
        $seen = @{}
        foreach ($d in Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) {
            $cls = "$($d.DeviceClass)".ToUpper()
            if (-not $KeyClasses.ContainsKey($cls) -or -not $d.DriverVersion) { continue }
            if ($d.DeviceID -notmatch '^(PCI|USB)\\' -or "$($d.DriverProviderName)" -match '^Microsoft') { continue }
            if ($seen.ContainsKey($d.DeviceID)) { continue }
            $seen[$d.DeviceID] = $true
            [pscustomobject]@{
                Id = $d.DeviceID; Nome = $d.DeviceName; Categoria = $KeyClasses[$cls]; Classe = $cls
                ClassGuid = "$($d.ClassGuid)"; Versao = $d.DriverVersion; Data = $d.DriverDate
                Inf = "$($d.InfName)"; Fabricante = "$($d.DriverProviderName)"
                VenDev = $(if ($d.DeviceID -match '((VEN_|VID_)[0-9A-F]{4}&(DEV_|PID_)[0-9A-F]{4})') { $matches[1] } else { '' })
            }
        }
    }

    function Get-SystemInfo {
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
        $ram = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        # driver de chipset: o mais recente da classe Sistema feito pelo fabricante do processador
        $chip = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Where-Object { "$($_.DeviceClass)".ToUpper() -eq 'SYSTEM' -and "$($_.DriverProviderName)" -notmatch '^Microsoft' -and $_.DriverDate } |
            Sort-Object DriverDate -Descending | Select-Object -First 1
        $cv = if ("$($cpu.Manufacturer)" -match 'AMD') { 'AMD' } elseif ("$($cpu.Manufacturer)" -match 'Intel') { 'Intel' } else { "$($cpu.Manufacturer)" }
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $enc = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
        $laptop = [bool](@($enc.ChassisTypes) | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }) -or
                  [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            BoardMaker = "$($bb.Manufacturer)".Trim(); BoardModel = "$($bb.Product)".Trim()
            Maker = "$($cs.Manufacturer)".Trim(); Model = "$($cs.Model)".Trim(); IsLaptop = $laptop
            Cpu = "$($cpu.Name)".Trim(); CpuVendor = $cv; Cores = [int]$cpu.NumberOfCores; Threads = [int]$cpu.NumberOfLogicalProcessors
            BiosVer = "$($bios.SMBIOSBIOSVersion)".Trim(); BiosDate = $bios.ReleaseDate
            ChipsetName = "$($chip.DeviceName)"; ChipsetVer = "$($chip.DriverVersion)"; ChipsetDate = $chip.DriverDate; ChipsetMaker = "$($chip.DriverProviderName)"
            RamGB = [math]::Round((($ram | Measure-Object Capacity -Sum).Sum) / 1GB); RamSpeed = [int]($ram | Select-Object -First 1).ConfiguredClockSpeed; RamSlots = $ram.Count
        }
    }

    # Acha a pasta do pacote do driver dentro do DriverStore do Windows (leitura, sem admin).
    function Get-DriverPackage([string]$oemInf, [string]$version) {
        $inf = Join-Path $env:windir "INF\$oemInf"
        if (-not $oemInf -or -not (Test-Path $inf)) { return $null }
        $repo = Join-Path $env:windir 'System32\DriverStore\FileRepository'
        $cat = Select-String -Path $inf -Pattern '^\s*CatalogFile\S*\s*=\s*(\S+)' | Select-Object -First 1
        if ($cat) {
            $base = [IO.Path]::GetFileNameWithoutExtension($cat.Matches[0].Groups[1].Value)
            foreach ($d in Get-ChildItem $repo -Directory -Filter "$base.inf_*" -ErrorAction SilentlyContinue) {
                $f = Get-ChildItem $d.FullName -Filter '*.inf' -File | Select-Object -First 1
                if ($f -and (Select-String -Path $f.FullName -Pattern ('DriverVer\s*=.*' + [regex]::Escape($version)) -Quiet)) {
                    return [pscustomobject]@{ Folder = $d.FullName; Inf = $f.Name }
                }
            }
        }
        $len = (Get-Item $inf).Length; $hash = (Get-FileHash $inf).Hash
        foreach ($d in Get-ChildItem $repo -Directory -ErrorAction SilentlyContinue) {
            foreach ($f in Get-ChildItem $d.FullName -Filter '*.inf' -File -ErrorAction SilentlyContinue) {
                if ($f.Length -eq $len -and (Get-FileHash $f.FullName).Hash -eq $hash) { return [pscustomobject]@{ Folder = $d.FullName; Inf = $f.Name } }
            }
        }
        $null
    }

    # Todos os pacotes de driver de terceiros instalados (inclui extensões do fabricante), só a versão mais nova de cada.
    function Get-OemPackages {
        $byName = @{}
        foreach ($f in Get-ChildItem (Join-Path $env:windir 'INF') -Filter 'oem*.inf' -File -ErrorAction SilentlyContinue) {
            $ver = Select-String -Path $f.FullName -Pattern '^\s*DriverVer\s*=\s*[^,]*,\s*([\d\.]+)' | Select-Object -First 1
            if (-not $ver) { continue }
            $v = $ver.Matches[0].Groups[1].Value
            $cls = Select-String -Path $f.FullName -Pattern '^\s*Class\s*=\s*(\w+)' | Select-Object -First 1
            $pkg = Get-DriverPackage $f.Name $v
            if (-not $pkg) { continue }
            $vv = try { [version]$v } catch { [version]'0.0' }
            $key = $pkg.Inf.ToLower()
            if (-not $byName.ContainsKey($key) -or $byName[$key].V -lt $vv) {
                $byName[$key] = [pscustomobject]@{
                    Oem = $f.Name; Inf = $pkg.Inf; Folder = $pkg.Folder; Version = $v; V = $vv
                    Class = $(if ($cls) { $cls.Matches[0].Groups[1].Value.ToUpper() } else { 'OUTROS' })
                }
            }
        }
        @($byName.Values)
    }

    # ---- versão nova do próprio HollowDrivers (GitHub Releases)
    function Get-AppUpdate([string]$repo, [string]$current) {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'HollowDrivers' } -TimeoutSec 20
        $v = $null; try { $v = [version](("$($r.tag_name)") -replace '^[vV]', '') } catch { }
        if (-not $v -or $v -le [version]$current) { return }
        $exe = @($r.assets | Where-Object { $_.name -eq 'HollowDrivers-Setup.exe' })[0]
        $sig = @($r.assets | Where-Object { $_.name -eq 'HollowDrivers-Setup.exe.sig' })[0]
        if (-not $exe -or -not $sig) { return }   # versão sem assinatura não é oferecida
        # os links precisam ser exatamente os do GitHub deste repositório
        $ok = '^https://github\.com/' + [regex]::Escape($repo) + '/releases/download/v[\d\.]+/HollowDrivers-Setup\.exe(\.sig)?$'
        if ($exe.browser_download_url -notmatch $ok -or $sig.browser_download_url -notmatch $ok) { return }
        [pscustomobject]@{ Version = "$v"; Url = $exe.browser_download_url; SigUrl = $sig.browser_download_url; Notes = "$($r.body)".Trim(); SizeMB = [math]::Round($exe.size / 1MB, 1) }
    }

    # ---- atualizações pelo Catálogo oficial do Microsoft Update (drivers certificados pela Microsoft)
    function Get-CatalogHwId([string]$id) {
        if ($id -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})') { return $matches[1] }
        if ($id -match '^((USB|HID)\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') { return $matches[1] }
        if ($id -match '^(HID\\VEN_[A-Z0-9]+&DEV_[0-9A-F]{4})') { return $matches[1] }
        if ($id -match '^(ACPI\\[A-Z0-9]{4,8})\\') { return $matches[1] }
        $null
    }

    function Search-Catalog([string]$q) {
        $r = Invoke-WebRequest -UseBasicParsing -Uri ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($q)) -TimeoutSec 60
        foreach ($m in [regex]::Matches($r.Content, '<tr id="([0-9a-f\-]{36})_R\d+"[\s\S]*?</tr>')) {
            $c = @([regex]::Matches($m.Value, '<td[^>]*>([\s\S]*?)</td>') | ForEach-Object { ($_.Groups[1].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim() })
            if ($c.Count -lt 7) { continue }
            [pscustomobject]@{ Id = $m.Groups[1].Value; Title = $c[1]; Products = $c[2]; Class = $c[3]; Date = $c[4]; Version = $c[5]; Size = ([regex]::Match($c[6], '[\d\.,]+ [KMG]B')).Value }
        }
    }

    # Para cada dispositivo com driver de fabricante (ou sem driver), procura versão MAIS NOVA no catálogo.
    # Vídeo e firmware ficam de fora de propósito.
    function Get-DriverUpdates {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
        $os = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
        $cands = @{}
        foreach ($d in Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) {
            if (-not $d.DeviceID -or "$($d.DeviceClass)".ToUpper() -in 'DISPLAY', 'FIRMWARE') { continue }
            if ("$($d.DriverProviderName)" -match '^Microsoft' -or -not $d.DriverVersion) { continue }
            $hw = Get-CatalogHwId $d.DeviceID
            if (-not $hw -or $cands.ContainsKey($hw)) { continue }
            $cands[$hw] = [pscustomobject]@{ Hw = $hw; Name = $d.DeviceName; Class = "$($d.DeviceClass)".ToUpper(); Version = $d.DriverVersion; Date = $d.DriverDate }
        }
        foreach ($p in Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode = 28' -ErrorAction SilentlyContinue) {
            $hw = Get-CatalogHwId $p.PNPDeviceID
            if (-not $hw -or $cands.ContainsKey($hw)) { continue }
            $cands[$hw] = [pscustomobject]@{ Hw = $hw; Name = $(if ($p.Name) { $p.Name } else { $hw }); Class = "$($p.PNPClass)".ToUpper(); Version = ''; Date = $null }
        }
        $i = 0; $n = $cands.Count
        foreach ($c in $cands.Values) {
            $i++
            if ($Prog) { $Prog.Text = "Verificando $i de ${n}: $($c.Name)" }
            $rows = @()
            try { $rows = @(Search-Catalog $c.Hw) } catch { continue }
            $cur = $null; try { $cur = [version]$c.Version } catch { }
            $best = $null; $bestV = $null
            foreach ($r in $rows) {
                if ($r.Products -notmatch [regex]::Escape($os) -or $r.Class -match 'Firmware') { continue }
                $v = $null; try { $v = [version]$r.Version } catch { }
                if (-not $v -or ($cur -and $v -le $cur)) { continue }
                $pub = $null; try { $pub = [datetime]::ParseExact($r.Date, 'M/d/yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { }
                if ($c.Date -and $pub -and $pub -le $c.Date) { continue }
                if (-not $bestV -or $v -gt $bestV) { $best = $r; $bestV = $v }
            }
            if ($best) {
                [pscustomobject]@{
                    Id = $best.Id; Dispositivo = $c.Name; Classe = $c.Class
                    Atual = $(if ($c.Version) { $c.Version } else { 'sem driver' })
                    Nova = $best.Version; Data = $best.Date; Tamanho = $best.Size; Titulo = $best.Title; Hw = $c.Hw
                }
            }
        }
    }

    function Find-DriverBooster {
        $found = @()
        foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                          'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall') {
            foreach ($k in Get-ChildItem $root -ErrorAction SilentlyContinue) {
                $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if ("$($p.DisplayName)" -match 'Driver Booster') {
                    $found += [pscustomobject]@{ Path = "$($p.InstallLocation)".TrimEnd('\'); Uninstall = "$($p.UninstallString)" }
                }
            }
        }
        foreach ($d in 'C:\Program Files\Driver Booster', 'C:\Program Files (x86)\IObit\Driver Booster') {
            if ((Test-Path $d) -and -not ($found | Where-Object { $_.Path -eq $d })) { $found += [pscustomobject]@{ Path = $d; Uninstall = '' } }
        }
        @($found)
    }

    function Get-SourceName([string]$cmd, [string]$header) {
        if ($cmd -match 'Driver ?Booster|DpInst') { return 'Driver Booster ⚠' }
        if ($cmd -match 'AMDSoftwareInstaller|AtiSetup|AMDInstallManager') { return 'Instalador oficial AMD' }
        if ($cmd -match 'nvidia') { return 'Instalador oficial NVIDIA' }
        if ($cmd -match '\\Intel\\|igxpin|Installer\.exe.*Intel') { return 'Instalador oficial Intel' }
        if ($header -match 'Hardware initiated') { return 'Windows (detecção automática)' }
        if ($cmd -match 'pnputil') { return 'pnputil (manual / HollowDrivers)' }
        if ($cmd -match 'svchost|wuauclt|TiWorker|MoUsoCoreWorker|drvinst') { return 'Windows / Windows Update' }
        if ($cmd) {
            $exe = if ($cmd -match '^"([^"]+)"') { $matches[1] } else { ($cmd -split '\s+')[0] }
            return [IO.Path]::GetFileName($exe)
        }
        'Desconhecido'
    }

    # Lê o log de instalação do Windows e devolve quem instalou driver na placa de vídeo.
    function Get-InstallHistory([string]$venDev) {
        if (-not $venDev) { return @() }
        $files = Get-ChildItem (Join-Path $env:windir 'INF') -Filter 'setupapi.dev*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime
        $found = New-Object Collections.Generic.List[object]
        foreach ($f in $files) {
            try { $sr = New-Object IO.StreamReader([IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')) } catch { continue }
            $cur = $null
            while ($null -ne ($line = $sr.ReadLine())) {
                if ($line.StartsWith('>>>  [')) {
                    if ($cur -and $cur.Match -and $cur.Start) { $found.Add($cur) }
                    $h = $line.Substring(6).TrimEnd(']')
                    $cur = if ($h -like 'Device Install*') { [pscustomobject]@{ Header = $h; Start = $null; Cmd = ''; Match = ($h -like "*$venDev*") } } else { $null }
                    continue
                }
                if (-not $cur) { continue }
                if (-not $cur.Start -and $line -match 'Section start (\d{4}/\d\d/\d\d \d\d:\d\d:\d\d)') {
                    $cur.Start = [datetime]::ParseExact($matches[1], 'yyyy/MM/dd HH:mm:ss', $null)
                    continue
                }
                if (-not $cur.Cmd -and $line -match '^\s+cmd:\s+(.+)$') {
                    $cur.Cmd = $matches[1]
                    if ($cur.Cmd -like "*$venDev*" -or $cur.Cmd -match 'AMDSoftwareInstaller|AtiSetup|AMDInstallManager') { $cur.Match = $true }
                }
            }
            if ($cur -and $cur.Match -and $cur.Start) { $found.Add($cur) }
            $sr.Close()
        }
        $seen = @{}
        $found | Sort-Object Start -Descending | ForEach-Object {
            $src = Get-SourceName $_.Cmd $_.Header
            $key = $_.Start.ToString('yyyyMMddHHmm') + $src
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [pscustomobject]@{ Quando = $_.Start; Origem = $src; Detalhe = $_.Header }
            }
        }
    }

    function Get-Health {
        $since = (Get-Date).AddDays(-30)
        $kp = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue)
        $tdr = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101; StartTime = $since } -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Crashes       = $kp.Count
            LastCrash     = $(if ($kp.Count) { $kp[0].TimeCreated } else { $null })
            Tdr           = $tdr.Count
            DriverBooster = @(Find-DriverBooster)
        }
    }

    # A hora que o Windows REGISTRA a queda é a do boot seguinte. A hora real vem da mensagem do evento 6008.
    function Get-CrashList([int]$days = 90) {
        $since = (Get-Date).AddDays(-$days)
        $log = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Id = 41, 42, 107, 1, 6008 } -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'Kernel-Power|Power-Troubleshooter|EventLog' })
        $sh = @($log | Where-Object { $_.Id -eq 6008 })
        $sleeps = @($log | Where-Object { $_.Id -eq 42 })
        $wakes = @($log | Where-Object { $_.Id -in 107, 1 })
        foreach ($e in @($log | Where-Object { $_.Id -eq 41 })) {
            $h = @{}
            ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $h[$_.Name] = $_.'#text' }
            $bc = [int64]("0$($h['BugcheckCode'])"); $btn = [int64]("0$($h['PowerButtonTimestamp'])"); $sl = [int]("0$($h['SleepInProgress'])")
            $tipo = if ($bc -ne 0) { 'Tela azul (0x{0:X})' -f $bc }
                elseif ($btn -ne 0) { 'Você segurou o botão de ligar' }
                elseif ($sl -ne 0) { 'Travou ao desligar/suspender' }
                else { 'Desligou de repente (sem erro)' }
            # hora real: números da mensagem do 6008 do mesmo boot, na ordem h m s dia mes ano
            $real = $e.TimeCreated
            $m = @($sh | Where-Object { [math]::Abs(($_.TimeCreated - $e.TimeCreated).TotalMinutes) -le 5 }) | Select-Object -First 1
            if ($m) {
                $n = @([regex]::Matches($m.Message, '\d+') | ForEach-Object { [int]$_.Value })
                if ($n.Count -ge 6) { try { $real = Get-Date -Year $n[5] -Month $n[4] -Day $n[3] -Hour $n[0] -Minute $n[1] -Second $n[2] } catch { } }
            }
            $off = ($e.TimeCreated - $real).TotalMinutes
            if ($off -lt 0) { $off = 0 }
            $s = @($sleeps | Where-Object { $_.TimeCreated -le $real }) | Select-Object -Last 1
            $w = @($wakes | Where-Object { $_.TimeCreated -le $real }) | Select-Object -Last 1
            [pscustomobject]@{
                Quando = $real
                Tipo = $tipo
                Estado = $(if ($s -and (-not $w -or $s.TimeCreated -gt $w.TimeCreated)) { 'Suspenso (dormindo)' } else { 'Ligado, em uso' })
                Desligado = $(if ($off -lt 2) { 'voltou na hora' } elseif ($off -lt 60) { '{0:N0} min' -f $off } else { '{0:N1} h' -f ($off / 60) })
                Sozinho = ($off -lt 2)
            }
        }
    }
}
