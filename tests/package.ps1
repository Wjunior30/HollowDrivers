$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $root 'dist\HollowDrivers-Setup.exe')))
foreach($name in 'HollowDrivers.ps1','CloneAssistant.ps1','SimpleClone.ps1','DriverLogic.ps1','Views.ps1','Operations.ps1','History.ps1','clone-offline.sh'){
 $stream=$assembly.GetManifestResourceStream($name)
 if(-not $stream){throw "Missing resource: $name"}
 $memory=New-Object IO.MemoryStream
 try{$stream.CopyTo($memory);$packed=[Convert]::ToBase64String($memory.ToArray())}finally{$stream.Dispose();$memory.Dispose()}
 if($packed -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $name)))){throw "Stale resource: $name"}
}
foreach($file in Get-ChildItem $root -Filter '*.ps1'){
 $errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$errors)
 if($errors){throw ($errors|Out-String)}
}
Add-Type -AssemblyName PresentationFramework
$source=[IO.File]::ReadAllText((Join-Path $root 'HollowDrivers.ps1'))
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$assignment=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$ResXaml'},$true)
Invoke-Expression $assignment.Extent.Text
# Theme placeholders are replaced with valid colors solely for layout parsing.
$ResXaml=[regex]::Replace($ResXaml,'__[A-Z0-9_]+__','#FF9900')
$app=New-Object Windows.Application
$app.Resources=[Windows.Markup.XamlReader]::Parse($ResXaml)
. (Join-Path $root 'Views.ps1')
foreach($xaml in $MainXaml,$DialogXaml,$TableXaml){$window=[Windows.Markup.XamlReader]::Parse([regex]::Replace($xaml,'__[A-Z0-9_]+__','#FF9900'));$window.Close()}
$app.Shutdown()
'OK: all packaged modules match sources, PowerShell syntax and primary WPF views.'
