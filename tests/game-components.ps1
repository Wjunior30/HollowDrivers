$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'GameComponents.ps1')
$catalog=@(Get-GameCatalog)
if(-not ($catalog.Id -contains 'vc-x86')){throw 'Missing x86 runtime'}
if([Environment]::Is64BitOperatingSystem -and -not ($catalog.Id -contains 'vc-x64')){throw 'Missing x64 runtime'}
foreach($item in $catalog){
    $uri=[uri]$item.Url
    if($uri.Scheme -ne 'https' -or $uri.Host -notin 'aka.ms','download.microsoft.com'){throw 'Unexpected download source'}
    if(-not (Get-GameComponentStatus $item)){throw 'Missing status'}
}
foreach($code in 0,3010,1638){if(-not (Get-GameExitMessage $code)){throw 'Missing success status'}}
if((Get-GameVcAction $null ([version]'14.50.1.0')) -ne '/install'){throw 'Missing runtime not installable'}
if((Get-GameVcAction ([version]'14.49.1.0') ([version]'14.50.1.0')) -ne '/install'){throw 'Older runtime not updated'}
if((Get-GameVcAction ([version]'14.50.1.0') ([version]'14.50.1.0')) -ne '/repair'){throw 'Equal runtime not repaired'}
if((Get-GameVcAction ([version]'14.51.1.0') ([version]'14.50.1.0')) -ne 'keep'){throw 'Newer runtime downgraded'}
foreach($code in 1602,1603,-1){
    $failed=$false;try{Get-GameExitMessage $code}catch{$failed=$true}
    if(-not $failed){throw "Failure treated as success: $code"}
}
function Get-AuthenticodeSignature { [pscustomobject]@{Status=$script:signatureStatus;SignerCertificate=[pscustomobject]@{Subject=$script:signer}} }
$script:signatureStatus='Valid';$script:signer='CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
Assert-GameMicrosoftSignature 'fake'
foreach($case in @(@('NotSigned','O=Microsoft Corporation'),@('Valid','O=Untrusted Corporation'))){
    $script:signatureStatus=$case[0];$script:signer=$case[1]
    $failed=$false;try{Assert-GameMicrosoftSignature 'fake'}catch{$failed=$true}
    if(-not $failed){throw 'Untrusted executable accepted'}
}
# Verify worker fits the actual elevation transport, without launching an installer.
$source=[IO.File]::ReadAllText((Join-Path $root 'HollowDrivers.ps1'))
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$assignment=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$ElevLib'},$true)
Invoke-Expression $assignment.Extent.Text
$worker=$ElevLib+$GameComponentLogic.ToString()+[Environment]::NewLine+$GameInstallWorker.ToString()
if([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker)).Length -gt 29500){throw 'Worker exceeds elevation transport'}
$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseInput($worker,[ref]$null,[ref]$parseErrors)
if($parseErrors){throw ($parseErrors|Out-String)}
Add-Type -AssemblyName PresentationFramework
$app=New-Object Windows.Application
$app.ShutdownMode='OnExplicitShutdown'
$Win=$null
$script:failure=$null
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(150)
$timer.add_Tick({
    $timer.Stop()
    $window=@($app.Windows|Where-Object Title -eq 'Componentes para jogos — HollowDrivers')[0]
    try{
        if(-not $window){throw 'Game window missing'}
        foreach($i in 0..($window.FindName('Components').Items.Count-1)){
            $window.FindName('Components').SelectedIndex=$i
            if(-not $window.FindName('Status').Text){throw 'Selection did not update status'}
        }
        $window.Tag.Busy=$true;$window.Close()
        if(-not $window.IsVisible){throw 'Closed while installer running'}
        $window.Tag.Busy=$false
        $visual=$window.Content
        $visual.Measure((New-Object Windows.Size(704,492)))
        $visual.Arrange((New-Object Windows.Rect(0,0,704,492)));$visual.UpdateLayout()
        $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(704,492,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $root 'dist\game-components-preview.png'))
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }catch{$script:failure=$_}finally{if($window){$window.Tag.Busy=$false;$window.Close()}}
})
$timer.Start()
Show-GameComponents
$app.Shutdown()
if($failure){throw $failure}
'OK: component detection, architecture catalog, official URLs, signature rejection, exit codes, worker size/syntax, real window selection and closing guard. No runtimes installed.'
