function Update-ChocoApps {
    [CmdletBinding()]
    param([switch]$VerboseOutput)

    function WL($m,$l='INFO'){
        if(Get-Command Write-Log -ErrorAction SilentlyContinue){
            try { Write-Log $m $l } catch { Write-Host $m }
        } else {
            switch ($l) {
                'ERROR' { Write-Host $m -ForegroundColor Red }
                'WARN'  { Write-Host $m -ForegroundColor Yellow }
                default { Write-Host $m }
            }
        }
    }

    # TLS forte
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

    # Admin obrigatório
    $isAdmin = try { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $false }
    if(-not $isAdmin){
        WL 'Update-ChocoApps requer privilégios administrativos.' 'ERROR'
        return [pscustomobject]@{ Sucesso=$false; PacotesAtualizados=@(); PacotesComFalha=@(); Mensagem='Sem privilégios administrativos' }
    }

    # Instala Chocolatey se necessário (bootstrap oficial)
    if(-not (Get-Command choco -ErrorAction SilentlyContinue)){
        WL 'Chocolatey não detectado. Instalando...' 'WARN'
        try{
            Set-ExecutionPolicy Bypass -Scope Process -Force
            $s = Invoke-WebRequest -UseBasicParsing -Uri 'https://community.chocolatey.org/install.ps1' -ErrorAction Stop
            Invoke-Expression $s.Content
            # Atualiza PATH da sessão
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
            if(-not (Get-Command choco -ErrorAction SilentlyContinue)){ throw 'Falha ao localizar choco após instalação.' }
            WL 'Chocolatey instalado com sucesso.'
        } catch {
            WL ("Falha ao instalar Chocolatey: {0}" -f $_.Exception.Message) 'ERROR'
            return [pscustomobject]@{ Sucesso=$false; PacotesAtualizados=@(); PacotesComFalha=@(); Mensagem='Falha instalando Chocolatey' }
        }
    }

    # Evitar prompts e avisos desnecessários
    try { choco feature enable -n allowGlobalConfirmation  | Out-Null } catch {}
    try { choco feature enable -n showNonElevatedWarnings | Out-Null } catch {}

    # Atualiza o próprio Chocolatey primeiro
    WL 'Atualizando o Chocolatey...'
    try { choco upgrade chocolatey -y --no-progress --ignore-pinned | Out-Null } catch { WL ("Aviso ao atualizar Chocolatey: {0}" -f $_.Exception.Message) 'WARN' }

    # Lista de desatualizados (antes) para relatório
    $before = @()
    try{
        $raw = choco outdated --no-color --limit-output 2>$null
        if($raw){
            foreach($l in $raw){
                $p = $l -split '\|'
                if($p.Length -ge 1){ $before += $p[0] }
            }
        }
    } catch {}

    # Atualização absoluta: todos os pacotes (ignorando pinos)
    WL 'Atualizando todos os pacotes Chocolatey instalados (ignorando pinos)...'
    $exit = 0
    try{
        $proc = Start-Process -FilePath 'choco' -ArgumentList 'upgrade all -y --no-progress --ignore-pinned' -Wait -PassThru -WindowStyle Hidden
        $exit = $proc.ExitCode
    } catch {
        $exit = 1
        WL ("Falha no upgrade all: {0}" -f $_.Exception.Message) 'ERROR'
    }

    # Lista de desatualizados (depois) e montagem do relatório
    $after = @()
    try{
        $raw2 = choco outdated --no-color --limit-output 2>$null
        if($raw2){
            foreach($l in $raw2){
                $p = $l -split '\|'
                if($p.Length -ge 1){ $after += $p[0] }
            }
        }
    } catch {}

    $updated = @()
    $failed  = @()

    foreach($pkg in $before){
        if(-not ($after -contains $pkg)){ $updated += $pkg }
    }

    if($exit -ne 0){
        foreach($pkg in $after){
            if(-not ($failed -contains $pkg)){ $failed += $pkg }
        }
    }

    # Limpeza de cache do Chocolatey
    try { choco clean --yes | Out-Null } catch {}

    if($VerboseOutput){
        if($updated.Count){ WL ("Atualizados: {0}" -f ($updated -join ', ')) }
        if($failed.Count){  WL ("Com falha: {0}"   -f ($failed  -join ', ')) 'WARN' }
    }

    $ok = ($exit -eq 0 -and $failed.Count -eq 0)
    return [pscustomobject]@{
        Sucesso            = $ok
        PacotesAtualizados = $updated
        PacotesComFalha    = $failed
    }
}