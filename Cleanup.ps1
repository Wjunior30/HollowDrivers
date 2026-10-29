# Limpeza de arquivos antigos (temporários, downloads e logs do app) e espaço livre.

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
