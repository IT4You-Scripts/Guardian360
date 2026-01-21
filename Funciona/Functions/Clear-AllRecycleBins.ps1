# Limpa as lixeiras ($Recycle.Bin) de TODOS os usuários em TODAS as unidades fixas
# Sem prompts. Requer PowerShell em modo Administrador.
function Clear-AllRecycleBins {
    [CmdletBinding()]
    param()

    # Verificação de privilégio elevado
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Esta função requer execução como Administrador (elevado).'
        }
    } catch {
        Write-Error "Falha ao verificar privilégios: $($_.Exception.Message)"
        return
    }

    Write-Host "Iniciando limpeza das lixeiras de TODOS os usuários em unidades locais..." -ForegroundColor Cyan

    $results = @()

    try {
        # Unidades fixas (DriveType=3)
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" |
                  Where-Object { $_.DeviceID -match '^[A-Z]:$' }

        if (-not $drives) {
            Write-Host "Nenhuma unidade fixa encontrada." -ForegroundColor Yellow
            return
        }

        foreach ($d in $drives) {
            $drive = $d.DeviceID
            $recycleRoot = Join-Path $drive '$Recycle.Bin'
            $itemsDeleted = 0
            $errors = @()
            $success = $false

            Write-Host "• Limpando: $recycleRoot" -ForegroundColor Yellow

            try {
                if (Test-Path -LiteralPath $recycleRoot) {
                    # Coleta itens antes para contagem
                    $items = @(Get-ChildItem -LiteralPath $recycleRoot -Force -ErrorAction SilentlyContinue)
                    $preCount = $items.Count

                    foreach ($item in $items) {
                        try {
                            # Tentativa direta
                            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                            $itemsDeleted++
                        } catch {
                            # Remove atributos e tenta novamente
                            try { attrib -r -s -h -a $item.FullName 2>$null } catch {}
                            try {
                                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                                $itemsDeleted++
                            } catch {
                                # Último recurso: .NET
                                try {
                                    if (Test-Path -LiteralPath $item.FullName) {
                                        if ($item.PSIsContainer) {
                                            [System.IO.Directory]::Delete($item.FullName, $true)
                                        } else {
                                            [System.IO.File]::Delete($item.FullName)
                                        }
                                        $itemsDeleted++
                                    }
                                } catch {
                                    $errors += "Falha em '$($item.FullName)': $($_.Exception.Message)"
                                }
                            }
                        }
                    }

                    # Verifica se esvaziou
                    $postItems = @(Get-ChildItem -LiteralPath $recycleRoot -Force -ErrorAction SilentlyContinue)
                    if ($postItems.Count -eq 0) {
                        Write-Host "  → Lixeira de $drive limpa." -ForegroundColor Green
                        $success = $true
                    } else {
                        Write-Warning "  → Itens remanescentes em $drive (alguns podem estar em uso)."
                        $success = ($errors.Count -eq 0)
                    }
                } else {
                    Write-Host "  → Pasta não encontrada: $recycleRoot" -ForegroundColor DarkYellow
                    $success = $true
                }
            } catch {
                $errors += "Erro ao processar ${recycleRoot}: $($_.Exception.Message)"
                Write-Error "Falha em ${recycleRoot}: $($_.Exception.Message)"
            }

            $results += [pscustomobject]@{
                Drive        = $drive
                Success      = $success
                ItemsDeleted = $itemsDeleted
                Errors       = if ($errors) { $errors -join '; ' } else { '' }
            }
        }

        Write-Host "Limpeza concluída." -ForegroundColor Green
    } catch {
        Write-Error "Erro inesperado: $($_.Exception.Message)"
    }

    return $results
}