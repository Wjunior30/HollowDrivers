function Write-OperationEvent([string]$operation, [string]$status, [string]$detail, [string]$id = '') {
    try {
        $entry = [ordered]@{ Date=(Get-Date).ToString('o'); Id=$id; Operation=$operation; Status=$status; Detail=$detail }
        $line=($entry | ConvertTo-Json -Compress)+[Environment]::NewLine
        $path=Join-Path $DataDir 'history.jsonl'
        $guard=New-Object Threading.Mutex($false, ('Local\HollowDrivers.History.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
        $owned=$false
        try {
            try{$owned=$guard.WaitOne(2000)}catch [Threading.AbandonedMutexException]{$owned=$true}
            if($owned){[IO.File]::AppendAllText($path,$line,(New-Object Text.UTF8Encoding $false))}
        } finally {if($owned){$guard.ReleaseMutex()};$guard.Dispose()}
    } catch { Write-Warning ('Falha ao registrar historico: '+$_.Exception.Message) }
}
function Show-OperationHistory {
    $rows=@(Get-Content (Join-Path $DataDir 'history.jsonl') -Encoding UTF8 -Tail 200 -ErrorAction SilentlyContinue | ForEach-Object {try{$_|ConvertFrom-Json}catch{}})
    if(-not $rows.Count){[void](Show-Dialog 'Histórico' 'Nenhuma operação registrada nesta versão.' 'info');return}
    Show-TableWindow 'Histórico de operações' ($rows | Sort-Object Date -Descending) 'Resultados externos de clonagem são declarações do usuário, não verificações automáticas.'
}
function Export-OperationDiagnostics {
    $picker=New-Object Microsoft.Win32.SaveFileDialog
    $picker.Filter='Diagnóstico (*.zip)|*.zip';$picker.FileName='HollowDrivers-diagnostico.zip'
    if(-not $picker.ShowDialog($Win)){return}
    try {
        $files=@(Get-ChildItem $DataDir -File -Filter '*.log' | Select-Object -ExpandProperty FullName)
        $history=Join-Path $DataDir 'history.jsonl';if(Test-Path $history){$files+=$history}
        if(-not $files.Count){throw 'Nenhum histórico ou log disponível.'}
        Compress-Archive -LiteralPath $files -DestinationPath $picker.FileName -Force
        [void](Show-Dialog 'Diagnóstico salvo' 'O arquivo contém logs locais, que podem incluir nomes de dispositivos e caminhos. Revise antes de compartilhar.' 'info')
    }catch{[void](Show-Dialog 'Não foi possível exportar' $_.Exception.Message 'warn')}
}
