function Update-ChocoApps {
    [CmdletBinding()]
    param()

    # Logger seguro: usa Write-Log se existir; caso contrário, fica silencioso
    function Invoke-Log {
        param([string]$Message)
        try {
            $logger = Get-Command -Name Write-Log -ErrorAction SilentlyContinue
            if ($logger) { Write-Log $Message }
        } catch {}
    }

    # Preferências originais
    $origErr  = $ErrorActionPreference
    $origProg = $ProgressPreference
    $origInfo = $InformationPreference

    # Execução silenciosa
    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'

    # Bloqueados (case-insensitive)
    $blockedRegex = '(?i)QGIS|TeamViewer|GoodSync|MiniTool'

    try {
        # 1) Verifica Chocolatey
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Invoke-Log "Chocolatey não encontrado; ignorando etapa de atualização."
            return
        }

        # 2) Atualiza índice/localcache (best effort; silencioso)
        try {
            # 'choco outdated' já atualiza metadados, mas este passo ajuda a aquecer cache
            & choco list -lo --no-color --limit-output *> $null
        } catch {
            Invoke-Log ("Aviso: falha ao aquecer cache do Chocolatey: {0}" -f $_.Exception.Message)
        }

        # 3) Coleta lista de pacotes desatualizados (ignorando pinados)
        $outdatedRaw = $null
        try {
            # --limit-output: linhas no formato "id|versaoAtual|versaoNova|pinned"
            # --ignore-pinned: oculta pinados da lista
            $outdatedRaw = (& choco outdated --ignore-pinned --no-color --limit-output) 2>$null
        } catch {
            Invoke-Log ("Aviso: 'choco outdated' falhou: {0}" -f $_.Exception.Message)
            $outdatedRaw = $null
        }

        if (-not $outdatedRaw) {
            Invoke-Log "Chocolatey: nenhuma atualização disponível ou saída ausente."
            return
        }

        # 4) Normaliza candidatos
        # Aceita string única ou array de linhas; filtra linhas válidas "id|cur|new|pinned?"
        $lines = @()
        if ($outdatedRaw -is [array]) { $lines = $outdatedRaw } else { $lines = @($outdatedRaw) }
        $candidates = foreach ($line in $lines) {
            if (-not $line) { continue }
            # Alguns ambientes podem imprimir cabeçalho/ruído; mantenha apenas linhas com '|'
            if ($line -notmatch '\|') { continue }
            $parts = $line -split '\|'
            if ($parts.Count -lt 3) { continue }

            # Estrutura: id | versaoAtual | versaoNova | pinned(optional)
            [pscustomobject]@{
                PackageId     = $parts[0]
                Current       = $parts[1]
                Available     = $parts[2]
                Pinned        = if ($parts.Count -ge 4) { $parts[3] } else { '' }
                PackageName   = $parts[0]  # Em Chocolatey, id == name
                PackageSource = $null      # 'outdated' não retorna fonte; manter null
            }
        }

        if (-not $candidates -or $candidates.Count -eq 0) {
            Invoke-Log "Chocolatey: lista de atualizações vazia após normalização."
            return
        }

        # 5) Filtra bloqueados por id/name
        $toUpdate = $candidates | Where-Object {
            ($_.PackageId   -notmatch $blockedRegex) -and
            ($_.PackageName -notmatch $blockedRegex)
        }
        if (-not $toUpdate -or $toUpdate.Count -eq 0) {
            Invoke-Log "Chocolatey: apenas pacotes bloqueados (QGIS/TeamViewer/GoodSync/MiniTool)."
            return
        }

        # 6) Aplica upgrades por pacote (silencioso)
        foreach ($pkg in $toUpdate) {
            try {
                $chocoArgs = @(
                    'upgrade', $pkg.PackageId,
                    '--yes',                # aceita automaticamente
                    '--no-progress',        # sem barra de progresso
                    '--limit-output',       # saída compacta
                    '--no-color'            # sem cor
                )

                # Fonte: se você usar fontes customizadas e quiser direcionar, adicione aqui
                if ($pkg.PackageSource) {
                    $chocoArgs += @('--source', $pkg.PackageSource)
                }

                # Execução
                & choco @chocoArgs *> $null
                $exit = $LASTEXITCODE

                # Tratamento de códigos de retorno comuns do Chocolatey/MSI
                # 0 = sucesso sem mudanças; 2 = mudanças aplicadas; 3010/1641 = reboot necessário
                $okCodes = @(0, 2, 3010, 1641)
                if ($okCodes -notcontains $exit) {
                    Invoke-Log ("Chocolatey: falha ao atualizar '{0}' código 0x{1:x}" -f $pkg.PackageId, $exit)
                }
            } catch {
                Invoke-Log ("Chocolatey: exceção ao atualizar '{0}' - {1}" -f $pkg.PackageId, $_.Exception.Message)
            }
        }
    } catch {
        Invoke-Log ("Chocolatey: exceção geral em Update-ChocoApps - {0}" -f $_.Exception.Message)
    } finally {
        # Restaura preferências
        $ErrorActionPreference = $origErr
        $ProgressPreference    = $origProg
        $InformationPreference = $origInfo
    }
}