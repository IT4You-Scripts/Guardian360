function Show-GuardianEndUI {
    [CmdletBinding()]
    param(
        [string]$LogoPath = 'C:\Guardian\Assets\Images\logotipo.png',
        [string]$Title = 'Guardian 360 - Manutenção Automatizada'
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore

    # Janela principal
    $window = New-Object Windows.Window
    $window.Title = $Title
    $window.Width = 1200
    $window.Height = 900
    $window.WindowStartupLocation = 'CenterScreen'
    $window.Background = 'Black'
    $window.Topmost = $true

    # Força a abertura no monitor principal
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.WindowStartupLocation = 'Manual'
    $window.Left = $workArea.Left + (($workArea.Width  - $window.Width)  / 2)
    $window.Top  = $workArea.Top  + (($workArea.Height - $window.Height) / 2)

    # Grid principal
    $grid = New-Object Windows.Controls.Grid

    # Definição das linhas (logo + texto)
    $rowLogo = New-Object Windows.Controls.RowDefinition
    $rowLogo.Height = '2*'

    $rowText = New-Object Windows.Controls.RowDefinition
    $rowText.Height = '8*'

    $grid.RowDefinitions.Add($rowLogo)
    $grid.RowDefinitions.Add($rowText)

    $window.Content = $grid

    # Logotipo
    if (Test-Path $LogoPath) {
        $img = New-Object Windows.Controls.Image
        $img.Source = New-Object Windows.Media.Imaging.BitmapImage([Uri]$LogoPath)
        $img.Stretch = 'Uniform'
        $img.HorizontalAlignment = 'Left'
        $img.VerticalAlignment = 'Center'
        $img.Margin = '20,20,20,20'
        [Windows.Controls.Grid]::SetRow($img, 0)
        $grid.Children.Add($img)
    }

    # Texto explicativo
    $textBlock = New-Object Windows.Controls.TextBlock
    $textBlock.FontSize = 16
    $textBlock.TextAlignment = 'Left'
    $textBlock.TextWrapping = 'Wrap'
    $textBlock.Foreground = 'White'
    $textBlock.Margin = '20,20,20,10'

    # Conteúdo
    $textBlock.Inlines.Add("A Manutenção Preventiva Automatizada foi finalizada com ")
    $inlineSucesso = New-Object Windows.Documents.Run("Sucesso")
    $inlineSucesso.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inlineSucesso)
    $textBlock.Inlines.Add("!`n`n")

    $textBlock.Inlines.Add("Agradecemos imensamente sua paciência e compreensão durante o processo, que durou ")

    $inlineTempo = New-Object Windows.Documents.Run("$global:tempoFormatado")
    $inlineTempo.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inlineTempo)

    $textBlock.Inlines.Add(" e exigiu que você aguardasse sem poder utilizar seu computador.`n`n")

    $textBlock.Inlines.Add("Entendemos que esse tempo de espera pode ter causado algum inconveniente, mas gostaríamos de ressaltar a importância dessa manutenção para garantir o bom funcionamento e a longevidade do seu equipamento.`n`n")

    $textBlock.Inlines.Add("Durante a manutenção preventiva, foram realizadas diversas tarefas importantes, tais como:`n`n")
    $textBlock.Inlines.Add("    - Inventário de Hardware e Software`n")
    $textBlock.Inlines.Add("    - Integridade do sistema`n")
    $textBlock.Inlines.Add("    - Otimizações estruturais`n")
    $textBlock.Inlines.Add("    - Limpeza de arquivos temporários`n")
    $textBlock.Inlines.Add("    - Atualizações controladas`n")
    $textBlock.Inlines.Add("    - Pós-atualização / Componentes`n")
    $textBlock.Inlines.Add("    - Otimização de Armazenamento`n")
    $textBlock.Inlines.Add("    - Segurança (Varredura contra malwares)`n")
    $textBlock.Inlines.Add("    - Gestão (Centralização de logs no Servidor de Arquivos)`n`n")

    $textBlock.Inlines.Add("Em caso de dúvidas, estamos à disposição pelos canais oficiais:`n`n")
    $textBlock.Inlines.Add("Telefone/WhatsApp: ")
    $inlineTel = New-Object Windows.Documents.Run("(11) 9.7191-1500")
    $inlineTel.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inlineTel)
    $textBlock.Inlines.Add("`n`n")

    $textBlock.Inlines.Add("E-mail: ")
    $inlineEmail = New-Object Windows.Documents.Run("suporte@it4you.com.br")
    $inlineEmail.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inlineEmail)
    $textBlock.Inlines.Add("`n`n")

    $textBlock.Inlines.Add("Atenciosamente, ")
    $inlineEquipe = New-Object Windows.Documents.Run("Equipe IT4You")
    $inlineEquipe.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inlineEquipe)

    [Windows.Controls.Grid]::SetRow($textBlock, 1)
    $grid.Children.Add($textBlock)

    # ---- FECHAMENTO AUTOMÁTICO (ÚNICA ADIÇÃO) ----
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(5)
    $timer.Add_Tick({
        $timer.Stop()
        $window.Close()
    })
    $timer.Start()

    # Exibe mantendo Dispatcher ativo
    $window.ShowDialog() | Out-Null
}
