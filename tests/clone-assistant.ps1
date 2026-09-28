$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'CloneAssistant.ps1')
foreach ($file in 'CloneAssistant.ps1','HollowDrivers.ps1') {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
}
function Disk($number, $serial, $size, $system) {
    [pscustomobject]@{ Number=$number; Serial=$serial; Size=[long]$size; System=$system; Offline=$false; ReadOnly=$false; Bus='SATA'; Style='GPT'; Sector=512; Model='Test disk'; Letters=''; Label="Test disk $number" }
}
$src = Disk 0 'SOURCE-123' 1000000000 $true
$dst = Disk 1 'TARGET-456' 2000000000 $false
function ExpectBlocked($source, $target, $all, $label) {
    if (-not (Get-CloneBlockReason $source $target $all)) { throw "Expected rejection: $label" }
}
if (Get-CloneBlockReason $src $dst @($src,$dst)) { throw 'Valid pair rejected' }
ExpectBlocked $src $src @($src,$dst) 'same disk'
$dst.Size=500000000; ExpectBlocked $src $dst @($src,$dst) 'smaller'; $dst.Size=2000000000
$dst.ReadOnly=$true; ExpectBlocked $src $dst @($src,$dst) 'read only'; $dst.ReadOnly=$false
$dst.Offline=$true; ExpectBlocked $src $dst @($src,$dst) 'offline'; $dst.Offline=$false
$dst.System=$true; ExpectBlocked $src $dst @($src,$dst) 'system'; $dst.System=$false
$dst.Sector=4096; ExpectBlocked $src $dst @($src,$dst) 'sector'; $dst.Sector=512
$dst.Bus='Spaces'; ExpectBlocked $src $dst @($src,$dst) 'storage spaces'; $dst.Bus='SATA'
$dst.Serial=''; ExpectBlocked $src $dst @($src,$dst) 'missing serial'; $dst.Serial='SOURCE-123'
ExpectBlocked $src $dst @($src,$dst) 'duplicate serial'; $dst.Serial='TARGET-456'
$other=Disk 2 'BOOT-789' 1000000000 $true
ExpectBlocked $src $dst @($src,$dst,$other) 'split boot'
$output=Join-Path $root ('dist\clone-test-' + [guid]::NewGuid().ToString('N'))
[void](New-CloneKit $src $dst @($src,$dst) $output)
$shell=[IO.File]::ReadAllText((Join-Path $output 'CLONAR.sh'))
if ($shell -match '__SOURCE_|__TARGET_|__SECTOR__' -or $shell.Contains("`r")) { throw 'Incomplete or CRLF shell export' }
if ($shell -notmatch 'ocs-onthefly -f "\$source_disk" -d "\$target_disk" -sfsck -p true') { throw 'Wrong clone command' }
$plan=Get-Content (Join-Path $output 'discos.json') -Raw | ConvertFrom-Json
if ($plan.Source.Serial -ne $src.Serial -or $plan.Target.Serial -ne $dst.Serial) { throw 'Wrong exported identities' }
# Compile the actual dialog and render with a synthetic disk inventory, without disk I/O.
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$module=[IO.File]::ReadAllText((Join-Path $root 'CloneAssistant.ps1'))
$xaml=[regex]::Match($module,'(?s)\$xaml = @''\r?\n(.*?)\r?\n''@').Groups[1].Value
$dialog=[Windows.Markup.XamlReader]::Parse($xaml)
$dialog.FindName('Source').Text='Disco 2 - Windows - 2 TB'
$dialog.FindName('Eligibility').Text='Destino menor que o disco de origem. Use um disco com capacidade igual ou maior.'
$dialog.FindName('Target').ItemsSource=@($dst)
$dialog.FindName('Target').SelectedIndex=0
$visual=$dialog.Content
$visual.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#12151B')
$visual.Measure((New-Object Windows.Size(820,690)))
$visual.Arrange((New-Object Windows.Rect(0,0,820,690)))
$visual.UpdateLayout()
$bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(820,690,96,96,[Windows.Media.PixelFormats]::Pbgra32)
$bitmap.Render($visual)
$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
$stream=[IO.File]::Create((Join-Path $root 'dist\clone-preview.png'))
try { $encoder.Save($stream) } finally { $stream.Dispose(); $dialog.Close() }
$assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $root 'dist\HollowDrivers-Setup.exe')))
foreach ($name in 'CloneAssistant.ps1','clone-offline.sh') {
    $stream=$assembly.GetManifestResourceStream($name)
    if (-not $stream -or $stream.Length -eq 0) { throw "Missing package resource: $name" }
    $stream.Dispose()
}
'OK: target validation, kit generation, dialog rendering, syntax and installer resources.'
