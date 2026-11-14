# ============================================
# Função: Write-JsonResult
# ============================================
function Write-JsonResult {
    param(
        [Parameter(Mandatory=$true)] [string] $Phase,
        [Parameter(Mandatory=$true)] [bool] $Sucesso,
        [Parameter(Mandatory=$true)] [TimeSpan] $Tempo,
        [Parameter(Mandatory=$false)] [object] $Mensagem
    )

    $mensagemSegura = ""
    if ($Mensagem -is [System.Array]) {
        $mensagemSegura = ($Mensagem | ForEach-Object { $_ | Out-String }) -join "`n"
    } elseif ($Mensagem) {
        $mensagemSegura = ($Mensagem | Out-String).Trim()
    }

    $jsonObject = [PSCustomObject]@{
        Phase    = $Phase
        Status   = if ($Sucesso) { "OK" } else { "ALERTA" }
        TempoSeg = [math]::Round($Tempo.TotalSeconds, 2)
        Mensagem = $mensagemSegura
    }

    # Log opcional
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log ("[JSON] {0} -> {1}" -f $Phase, $mensagemSegura)
    }

    return $jsonObject
}

# Inicializa array global de resultados
if (-not $global:Results) { $global:Results = @() }
