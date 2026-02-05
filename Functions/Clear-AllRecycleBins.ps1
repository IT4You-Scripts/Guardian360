function Clear-AllRecycleBins {
    [CmdletBinding()]
    param()

    try {
        # Verificação de privilégios
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Esta função requer execução como Administrador (elevado).'
        }

        Write-Host "Iniciando limpeza das lixeiras de TODOS os usuários em unidades locais..." -ForegroundColor Cyan

        $results = @()

        # Unidades fixas
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" |
                  Where-Object { $_.DeviceID -match '^[A-Z]:$' }

        if (-not $drives) {
            Write-Host "Nenhuma unidade fixa encontrada." -ForegroundColor Yellow
            Write-Log "Nenhuma unidade fixa encontrada para limpeza de lixeira."
            return "Nenhuma unidade fixa encontrada."
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
                    $items = @(Get-ChildItem -LiteralPath $recycleRoot -Force -ErrorAction SilentlyContinue)

                    foreach ($item in $items) {
                        try {
                            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                            $itemsDeleted++
                        } catch {
                            try { attrib -r -s -h -a $item.FullName 2>$null } catch {}
                            try {
                                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                                $itemsDeleted++
                            } catch {
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

                    $postItems = @(Get-ChildItem -LiteralPath $recycleRoot -Force -ErrorAction SilentlyContinue)
                    $success = ($postItems.Count -eq 0 -or $errors.Count -eq 0)
                } else {
                    Write-Host "  → Pasta não encontrada: $recycleRoot" -ForegroundColor DarkYellow
                    $success = $true
                }
            } catch {
                $errors += "Erro ao processar ${recycleRoot}: $($_.Exception.Message)"
                throw
            }

            $results += [pscustomobject]@{
                Drive        = $drive
                Success      = $success
                ItemsDeleted = $itemsDeleted
                Errors       = if ($errors) { $errors -join '; ' } else { '' }
            }
        }

        Write-Host "Limpeza concluída." -ForegroundColor Green
        Write-Log "Limpeza de todas as lixeiras concluída."

        # 🔥 retorna mensagem técnica rica
        $msg = ($results | ForEach-Object {
            "Drive=$($_.Drive), Success=$($_.Success), ItemsDeleted=$($_.ItemsDeleted), Errors=$($_.Errors)"
        }) -join " | "

        return $msg
    }
    catch {
        Write-Host "Falha durante limpeza das lixeiras." -ForegroundColor Red
        Write-Log "Erro em Clear-AllRecycleBins: $_"
        throw $_
    }
}
