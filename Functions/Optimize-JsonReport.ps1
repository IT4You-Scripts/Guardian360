<# ====================================================================
   OPTIZE-JSONREPORT (versão revisada)
   - Fases opcionais
   - Nenhum exit
   - Nenhuma fase criada artificialmente
   - Nenhuma nota calculada
   - Nenhum SaudeGeral adicionado
   - Apenas trata fases realmente existentes
==================================================================== #>

param(
    [string]$Pasta = "."
)

Write-Host "`n🔍 Procurando arquivo ORIGINAL..." -ForegroundColor Cyan

# --------------------------------------------------------------------
# 1) Localizar arquivo ORIGINAL — caminho fixo C:\Guardian\Json
# --------------------------------------------------------------------

$baseJsonDir = "C:\Guardian\Json"

$year        = Get-Date -Format 'yyyy'
$monthNumber = Get-Date -Format 'MM'
$monthName   = (Get-Culture).DateTimeFormat.GetMonthName([int]$monthNumber)
$monthFolder = ("{0}. {1}" -f $monthNumber, (Get-Culture).TextInfo.ToTitleCase($monthName.ToLower()))

$jsonDir = Join-Path (Join-Path $baseJsonDir $year) $monthFolder

if (-not (Test-Path $jsonDir)) {
    Write-Host "❌ Pasta de inventários não encontrada: $jsonDir" -ForegroundColor Red
    return
}

Write-Host "📁 Procurando arquivo ORIGINAL em: $jsonDir" -ForegroundColor Cyan

$arquivo = Get-ChildItem -Path $jsonDir -Filter *.json |
    Where-Object {
        $_.Name -match "^[A-Za-z0-9\-]+_\d{8}_\d{4}\.json$" -and
        $_.Name -notmatch "EXTREME" -and
        $_.Name -notmatch "TRATADO"
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $arquivo) {
    Write-Host "❌ Nenhum arquivo ORIGINAL encontrado." -ForegroundColor Red
    return
}

Write-Host "✔ Arquivo original identificado: $($arquivo.FullName)" -ForegroundColor Green

# --------------------------------------------------------------------
# 2) Carregar JSON com segurança
# --------------------------------------------------------------------

try {
    $jsonRaw = Get-Content $arquivo.FullName -Raw | ConvertFrom-Json
} catch {
    Write-Host "❌ Erro ao carregar JSON." -ForegroundColor Red
    return
}

$jsonFases = @()

# Função auxiliar para adicionar fases somente se existirem
function Add-Fase($faseOriginal, $mensagemTratada) {
    if ($faseOriginal) {
        $jsonFases += [PSCustomObject]@{
            Phase    = $faseOriginal.Phase
            Status   = $faseOriginal.Status
            TempoSeg = $faseOriginal.TempoSeg
            Mensagem = $mensagemTratada
        }
    }
}

# --------------------------------------------------------------------
# 3) FASE 1 — Inventário de Hardware, Rede, Armazenamento e Softwares
# --------------------------------------------------------------------

$fase1 = $jsonRaw.Fases | Where-Object { $_.Phase -match "Invent" }

if ($fase1) {

    # Divide mensagem em linhas
    $msg = $fase1.Mensagem -split "`r`n"

    # --- Encontrar início da lista de softwares ---
    $indexSoftware = $null
    for ($i = 0; $i -lt $msg.Count; $i++) {
        $linha = $msg[$i].Trim()
        if ($linha -match "Softwares" -or $linha -match "Instalados") {
            $indexSoftware = $i
            break
        }
    }

    # --- Se não tiver softwares, cria lista vazia ---
    $softwareList = @()
    if ($indexSoftware) {
        $softwareLines = $msg[($indexSoftware + 1)..($msg.Count - 1)]
        $softwareList = $softwareLines |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" }
    }

    # --- Hardware bruto (antes de Armazenamento/Partições) ---
    $hardwareLines = if ($indexSoftware) {
        $msg[0..($indexSoftware - 1)]
    } else {
        $msg
    }

    # --- Encontrar blocos Armazenamento + Partições ---
    $idxArmazenamento = ($hardwareLines | Select-String "^\s*Armazenamento\s*:").LineNumber
    $idxParticoes     = ($hardwareLines | Select-String "^\s*Partições\s*:").LineNumber

    $armazenamentosRaw = @()
    $particoesRaw = @()

    # --- Armazenamentos ---
    if ($idxArmazenamento) {
        $start = $idxArmazenamento - 1
        if ($hardwareLines[$start] -match "Armazenamento\s*:\s*(.*)$") {
            if ($matches[1].Trim() -ne "") { $armazenamentosRaw += $matches[1].Trim() }
        }
        for ($j = $start + 1; $j -lt $hardwareLines.Count; $j++) {
            $linha = $hardwareLines[$j].Trim()
            if ($linha -match "^[A-Za-z].*:\s*$") { break }
            if ($linha -ne "") { $armazenamentosRaw += $linha }
        }
    }

    # --- Partições ---
    if ($idxParticoes) {
        $start = $idxParticoes - 1
        if ($hardwareLines[$start] -match "Partições\s*:\s*(.*)$") {
            if ($matches[1].Trim() -ne "") { $particoesRaw += $matches[1].Trim() }
        }
    }

    # --- Hardware limpo ---
    $hardwareObj = @{}
    foreach ($line in $hardwareLines) {
        $linha = $line.Trim()
        if ($linha -eq "") { continue }
        if ($linha -match "^(Armazenamento|Partições)") { continue }
        if ($linha -match "->") { continue }
        if ($linha -match "^[A-Z]:") { continue }
        if ($linha -match "GB" -or $linha -match "% livres") { continue }
        if ($linha -match "^(.*?):\s*(.*)$") {
            $hardwareObj[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    # --- Converter Armazenamentos ---
    $armazenamentos = foreach ($a in $armazenamentosRaw) {
        if ($a -match "^(.*?)\s*-&gt;\s*Status:\s*(.*)$") {
            [PSCustomObject]@{
                Nome   = $matches[1].Trim()
                Status = $matches[2].Trim()
            }
        }
    }

    # --- Converter Partições ---
    $particoes = foreach ($p in $particoesRaw) {
        if ($p -match "^([A-Z]):.*?([\d\.]+)\s*GB.*?([\d\.]+)%") {

            $letra     = $matches[1]
            $tamanho   = [double]$matches[2]
            $pctLivre  = [double]$matches[3]

            $livreGB = [Math]::Round(($tamanho * $pctLivre) / 100, 2)
            $usadoGB = [Math]::Round(($tamanho - $livreGB), 2)
            $pctUsado = [Math]::Round((($tamanho - $livreGB) / $tamanho) * 100, 2)

            [PSCustomObject]@{
                Letra     = $letra
                TamanhoGB = $tamanho
                LivreGB   = $livreGB
                UsadoGB   = $usadoGB
                UsadoPct  = $pctUsado
            }
        }
    }

    # --- REDE (fallback simples) ---
    $rede = $null
    if ($hardwareObj.ContainsKey("Endereço IP") -or $hardwareObj.ContainsKey("Endereço MAC")) {
        $rede = [PSCustomObject]@{
            EnderecoIP  = $hardwareObj["Endereço IP"]
            EnderecoMAC = $hardwareObj["Endereço MAC"]
        }
    }

    # Remover IP e MAC do hardware
    $hardwareObj.Remove("Endereço IP")
    $hardwareObj.Remove("Endereço MAC")

    # --- Adicionar Fase 1 tratada ---
    Add-Fase $fase1 ([PSCustomObject]@{
        Hardware       = $hardwareObj
        Rede           = $rede
        Armazenamentos = $armazenamentos
        Particoes      = $particoes
        Softwares      = $softwareList
    })
}

# ============================================================
# 4) FASE 2 — Verificação do Registro / SFC / DISM
# ============================================================

$fase2 = $jsonRaw.Fases | Where-Object { $_.Phase -match "Registro" }

if ($fase2) {

    $linhasF2 = $fase2.Mensagem -split "`r`n"
    $tecnico = @{}

    foreach ($l in $linhasF2) {
        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($v -match "^(True|False)$") { $v = [bool]$v }
            elseif ($v -match "^\d+$")     { $v = [int]$v }

            $tecnico[$k] = $v
        }
    }

    Add-Fase $fase2 ([PSCustomObject]@{
        IntegridadeArquivos      = $tecnico["MensagemTecnica"]
        SfcExitCode              = $tecnico["SfcExitCode"]
        DismExitCode             = $tecnico["DismExitCode"]
        ComponentCleanupExitCode = $tecnico["ComponentCleanupExitCode"]
        PendingRebootBefore      = $tecnico["PendingRebootBefore"]
        PendingRebootAfter       = $tecnico["PendingRebootAfter"]
        DetalhesTecnicos         = $tecnico
    })
}

# ============================================================
# FASE — Limpeza de lixeiras
# ============================================================

$faseLixo = $jsonRaw.Fases | Where-Object { $_.Phase -match "lixeiras" }

if ($faseLixo) {

    $entries = $faseLixo.Mensagem -split "\|"
    $detalhes = @()

    foreach ($e in $entries) {
        if ($e -match "Drive=(.*?),\s*Success=(.*?),\s*ItemsDeleted=(.*?),\s*Errors=(.*)$") {
            $detalhes += [PSCustomObject]@{
                Unidade        = $matches[1].Trim()
                Sucesso        = [bool]$matches[2]
                ItensDeletados = [int]$matches[3]
                Erros          = if ($matches[4].Trim() -ne "") { $matches[4].Trim() } else { $null }
            }
        }
    }

    Add-Fase $faseLixo ([PSCustomObject]@{
        DetalhesPorUnidade = $detalhes
    })
}

# ============================================================
# FASE — Atualização do Windows
# ============================================================

$faseUpdateWin = $jsonRaw.Fases | Where-Object { $_.Phase -match "Atualização do Windows" }

if ($faseUpdateWin) {
    $linhas = $faseUpdateWin.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {
        if ($l -match "ExitCode\s*=\s*(\d+)") {
            $exitCode = [int]$matches[1]
        }
        if ($l -match "^(.*?):\s*(.*)$") {
            $tecnico[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    Add-Fase $faseUpdateWin ([PSCustomObject]@{
        CodigoSaida      = $exitCode
        DetalhesTecnicos = $tecnico
    })
}

# ============================================================
# FASE — Microsoft Store
# ============================================================

$faseStore = $jsonRaw.Fases | Where-Object { $_.Phase -match "Loja da Microsoft" }

if ($faseStore) {

    $linhas = $faseStore.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {

        if ($l -match "ExitCode\s*=\s*([-]?\d+)") {
            $exitCode = [int]$matches[1]
        }

        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($v -match "^\-?\d+$") { $v = [int]$v }

            $tecnico[$k] = $v
        }
    }

    Add-Fase $faseStore ([PSCustomObject]@{
        CodigoSaida      = $exitCode
        DetalhesTecnicos = $tecnico
    })
}

# ============================================================
# FASE — Winget
# ============================================================

$faseWinget = $jsonRaw.Fases | Where-Object { $_.Phase -match "Winget" }

if ($faseWinget) {

    $linhas = $faseWinget.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {

        if ($l -match "ExitCode\s*=\s*([-]?\d+)") {
            $exitCode = [int]$matches[1]
        }

        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($v -match "^\-?\d+$") { $v = [int]$v }
            $tecnico[$k] = $v
        }
    }

    Add-Fase $faseWinget ([PSCustomObject]@{
        CodigoSaida      = $exitCode
        DetalhesTecnicos = $tecnico
    })
}

# ============================================================
# FASE — DISM Cleanup
# ============================================================

$faseDismClean = $jsonRaw.Fases | Where-Object { $_.Phase -match "componentes do Windows" }

if ($faseDismClean) {

    $linhas = $faseDismClean.Mensagem -split "`r`n"
    $versaoFerramenta = $null
    $versaoImagem = $null
    $sucesso = $false

    foreach ($l in $linhas) {
        if ($l -match "Vers[aã]o:\s*(.*)$") {
            $versaoFerramenta = $matches[1].Trim()
        }
        if ($l -match "Vers[aã]o da Imagem:\s*(.*)$") {
            $versaoImagem = $matches[1].Trim()
        }
        if ($l -match "conclu[ií]da|êxito|sucesso") {
            $sucesso = $true
        }
    }

    Add-Fase $faseDismClean ([PSCustomObject]@{
        VersaoFerramentaDISM = $versaoFerramenta
        VersaoImagemWindows  = $versaoImagem
        Sucesso              = $sucesso
    })
}

# ============================================================
# FASE — Windows Defender
# ============================================================

$faseDefender = $jsonRaw.Fases | Where-Object { $_.Phase -match "Windows Defender" }

if ($faseDefender) {

    $linhas = $faseDefender.Mensagem -split "`r`n"
    $tecnico = @{}
    $exitCode = $null

    foreach ($l in $linhas) {

        if ($l -match "ExitCode\s*=\s*([-]?\d+)") {
            $exitCode = [int]$matches[1]
        }

        if ($l -match "^(.*?):\s*(.*)$") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($v -match "^\-?\d+$") { $v = [int]$v }
            $tecnico[$k] = $v
        }
    }

    Add-Fase $faseDefender ([PSCustomObject]@{
        CodigoSaida      = $exitCode
        DetalhesTecnicos = $tecnico
    })
}

# ============================================================
# 5) MONTAGEM FINAL DO JSON TRATADO
# ============================================================

$jsonFinal = [PSCustomObject]@{
    Cliente        = $jsonRaw.Cliente
    NomeComputador = $jsonRaw.NomeComputador
    DataExecucao   = $jsonRaw.DataExecucao
    Fases          = $jsonFases  # APENAS as fases realmente existentes
}

# ============================================================
# 6) EXPORTAÇÃO — criando o arquivo _TRATADO.json
# ============================================================

$nomeOut = Join-Path $arquivo.DirectoryName (($arquivo.BaseName) + "_TRATADO.json")

try {
    $jsonFinal | ConvertTo-Json -Depth 20 |
        Out-File $nomeOut -Encoding UTF8

    Write-Host "`n🔥 GUARDIAN 360 finalizado com sucesso!"
    Write-Host "📦 JSON TRATADO gerado em: $nomeOut" -ForegroundColor Yellow
} catch {
    Write-Host "❌ Falha ao gravar o arquivo TRATADO." -ForegroundColor Red
}

# ============================================================
# 7) Funções auxiliares gerais (se no futuro precisar adicionar mais)
# ============================================================

function Safe-Trim {
    param([string]$text)
    if ($null -eq $text) { return "" }
    return $text.Trim()
}

function Safe-Split {
    param(
        [string]$text,
        [string]$separator = "`r`n"
    )
    if ($null -eq $text) { return @() }
    return $text -split $separator
}

function Safe-ExtractKeyValue {
    param([string]$line)

    if ($line -match "^(.*?):\s*(.*)$") {
        $key = $matches[1].Trim()
        $val = $matches[2].Trim()

        if ($val -match "^(True|False)$") { $val = [bool]$val }
        elseif ($val -match "^\-?\d+$")   { $val = [int]$val }

        return @{ Key = $key; Value = $val }
    }

    return $null
}

# ============================================================
# 8) Mensagem final do script carregado
# ============================================================

Write-Host "🔥 Guardian 360 Operacional." -ForegroundColor Green

