$script:Tasks = New-Object Collections.ArrayList
$BgTimer = New-Object Windows.Threading.DispatcherTimer
$BgTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:Prog = [hashtable]::Synchronized(@{ Text = '' })
$script:ProgRun = $null
$BgTimer.add_Tick({
    if ($script:ProgRun -and $script:Prog.Text -and $script:ProgRun.Text -ne $script:Prog.Text) { $script:ProgRun.Text = $script:Prog.Text }
    foreach ($t in @($script:Tasks)) {
        if (-not $t.Handle.IsCompleted) { continue }
        $script:Tasks.Remove($t)
        $out = $null; $err = $null
        try { $out = $t.Ps.EndInvoke($t.Handle) }
        catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        if (-not $err -and $t.Ps.Streams.Error.Count) { $err=($t.Ps.Streams.Error | Out-String) }
        $t.Ps.Dispose(); $t.Rs.Dispose()
        try { & $t.Done $out $err $t.Context }
        catch { Write-OperationEvent 'callback' 'falhou' $_.Exception.Message }
    }
    if (-not $script:Tasks.Count) { $BgTimer.Stop() }
})
function Start-Bg([string]$code, [scriptblock]$onDone, [hashtable]$vars = @{}, [hashtable]$context = @{}) {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('Prog', $script:Prog)
    foreach ($key in $vars.Keys) { $rs.SessionStateProxy.SetVariable($key, $vars[$key]) }
    $ps = [PowerShell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript($code)
    [void]$script:Tasks.Add(@{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Done = $onDone; Context=$context })
    $BgTimer.Start()
}

# Roda um script como administrador (o Windows pede confirmação) e devolve o log.
# O script vai inteiro na linha de comando (-EncodedCommand): não existe arquivo .ps1 que um programa
# malicioso pudesse trocar entre o app pedir a permissão e você clicar "Sim" no UAC.
function Invoke-Elevated([string]$tpl, [hashtable]$map, [string]$name, [scriptblock]$onDone) {
    if ($script:ElevBusy) { & $onDone '' 'Aguarde a operação administrativa em andamento.'; return }
    $log = Join-Path $DataDir ('{0}-{1}.log' -f $name, [guid]::NewGuid().ToString('N'))
    $code = (Expand-Tpl $ElevLib @{ '__LOG__' = $log }) + "`n" + (Expand-Tpl $tpl $map)
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    if ($enc.Length -gt 30000) { & $onDone '' 'comando grande demais para a linha de comando do Windows'; return }
    $context=@{ Log=$log; Done=$onDone; Name=$name; Id=[guid]::NewGuid().ToString('N') }
    Write-OperationEvent $name 'iniciado' '' $context.Id
    $script:ElevBusy=$true
    $Win.IsEnabled=$false
    try {
    Start-Bg ("Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -EncodedCommand {0}'" -f $enc) {
        param($out, $err, $job)
        $text = ''
        try {
            if (Test-Path -LiteralPath $job.Log) { $text = Get-Content -LiteralPath $job.Log -Raw }
            if(-not $err -and -not $text){$err='A operação não produziu um resultado verificável.'}
            $status=if($err -or $text -match '(?im)ERRO=|falhou|failed'){ 'falhou' }else{ 'finalizado; ver detalhes' }
            Write-OperationEvent $job.Name $status $(if($err){$err}else{$text}) $job.Id
            & $job.Done $text $err
        } finally { $script:ElevBusy=$false; $Win.IsEnabled=$true }
    } @{} $context
    } catch { $script:ElevBusy=$false; $Win.IsEnabled=$true; & $onDone '' $_.Exception.Message }
}

