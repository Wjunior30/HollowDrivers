param([switch]$Smaller)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'CloneAssistant.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$src=[pscustomobject]@{ Number=0; Serial='SRC-1'; Size=[long]2000000000000; System=$true; Offline=$false; ReadOnly=$false; Bus='NVMe'; Style='GPT'; Sector=512; Label='Windows - 2 TB'; Model='Source' }
$dst=[pscustomobject]@{ Number=1; Serial='DST-2'; Size=[long]2001000000000; System=$false; Offline=$false; ReadOnly=$false; Bus='SATA'; Style='GPT'; Sector=512; Label='Destino - 2 TB'; Model='Target' }
$script:fixture=[pscustomobject]@{ Source=$src; Disks=@($src,$dst); UsedWindows=[long]191000000000 }
$dst.Size=1000000000000
$result=Get-SimpleCloneAssessment $fixture $dst
if(-not $result.Allowed -or -not $result.Migration){throw 'Smaller disk migration missing'}
$dst.Size=100000000000
if((Get-SimpleCloneAssessment $fixture $dst).Message -notmatch 'Espaço insuficiente'){throw 'Insufficient space not explained'}
$dst.Size=2001000000000
$guide=Join-Path $root 'dist\simple-clone-guide.html'
$dst.Label='<script>alert(1)</script>'
Save-SimpleCloneGuide $fixture $dst $guide
$html=[IO.File]::ReadAllText($guide)
if($html.Contains('<script>alert(1)</script>') -or -not $html.Contains('&lt;script&gt;')){throw 'Unescaped device label'}
if($html -match 'sudo bash|CLONAR.sh|lsblk'){throw 'Guide requires shell commands'}
$dst.Label='Destino - 2 TB'
if($Smaller){$dst.Size=1000000000000}
$readyControl=if($Smaller){'MigrationReady'}else{'UsbReady'}
# Exercise actual dialog events with a fake inventory. No disk operations or external tools.
function Get-CloneInventory { $script:fixture }
$script:Win=$null
$application=New-Object Windows.Application
$application.ShutdownMode='OnExplicitShutdown'
$script:failure=$null
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(200)
$timer.add_Tick({
    $timer.Stop()
    $w=@($application.Windows | Where-Object Title -eq 'Preparar segundo disco — HollowDrivers')[0]
    try {
        if(-not $w){throw 'Dialog missing'}
        if(-not $w.FindName('Next').IsEnabled){throw 'Valid destination blocked'}
        foreach($step in 1..3){
            if($w.Tag.Step -ne $step){throw 'Navigation failed'}
            $visual=$w.Content
            $visual.Measure((New-Object Windows.Size(784,650)))
            $visual.Arrange((New-Object Windows.Rect(0,0,784,650))); $visual.UpdateLayout()
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(784,650,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($visual)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream=[IO.File]::Create((Join-Path $root "dist\simple-clone-step$step.png"))
            try{$encoder.Save($stream)}finally{$stream.Dispose()}
            if($step -eq 2){
                if($w.FindName('Next').IsEnabled){throw 'USB preparation acknowledgment bypassed'}
                $w.FindName($readyControl).IsChecked=$true
                if(-not $w.FindName('Next').IsEnabled){throw 'USB acknowledgment did not enable next'}
            }
            if($step -lt 3){$w.FindName('Next').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
        }
        $w.FindName('Back').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if($w.Tag.Step -ne 2){throw 'Back failed'}
    }catch{$script:failure=$_}finally{if($w){$w.Close()}}
})
$timer.Start()
Show-CloneAssistant
$application.Shutdown()
if($failure){throw $failure}
$assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $root 'dist\HollowDrivers-Setup.exe')))
$stream=$assembly.GetManifestResourceStream('SimpleClone.ps1')
if(-not $stream){throw 'Installer missing new wizard'}
$stream.Dispose()
'OK: three-step navigation, preparation acknowledgment, smaller disks, HTML escaping, command-free guide and installer.'
