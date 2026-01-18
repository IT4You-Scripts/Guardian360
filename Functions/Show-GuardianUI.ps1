
function Show-GuardianUI {
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

    # Definição das linhas
    #$rowLogo      = New-Object Windows.Controls.RowDefinition; $rowLogo.Height = '2*'
    $rowLogo      = New-Object Windows.Controls.RowDefinition; $rowLogo.Height = 'Auto'
    $rowText      = New-Object Windows.Controls.RowDefinition; $rowText.Height = '4.5*'
    $rowPhase     = New-Object Windows.Controls.RowDefinition; $rowPhase.Height = '0.7*'
    $rowStep      = New-Object Windows.Controls.RowDefinition; $rowStep.Height = '0.5*'
    $rowProgress  = New-Object Windows.Controls.RowDefinition; $rowProgress.Height = '1*'
    $rowCliente   = New-Object Windows.Controls.RowDefinition; $rowCliente.Height = '0.5*'
 
    $grid.RowDefinitions.Add($rowLogo) | Out-Null
    $grid.RowDefinitions.Add($rowText) | Out-Null
    $grid.RowDefinitions.Add($rowPhase) | Out-Null
    $grid.RowDefinitions.Add($rowStep) | Out-Null
    $grid.RowDefinitions.Add($rowProgress) | Out-Null
    $grid.RowDefinitions.Add($rowCliente) | Out-Null

    $window.Content = $grid

    # Logotipo
    if (Test-Path $LogoPath) {
        $img = New-Object Windows.Controls.Image
        $img.Source = New-Object Windows.Media.Imaging.BitmapImage([Uri]$LogoPath)
        $img.Width = '1150'
        $img.Stretch = 'Uniform'
        $img.HorizontalAlignment = 'Left'
        $img.VerticalAlignment = 'Center'
        $img.Margin = '20,20,10,20'
        [Windows.Controls.Grid]::SetRow($img, 0)
        $grid.Children.Add($img)
    }

    # Texto explicativo com destaques
    $textBlock = New-Object Windows.Controls.TextBlock
    $textBlock.FontSize = 16
    $textBlock.TextAlignment = 'Left'
    $textBlock.TextWrapping = 'Wrap'
    $textBlock.Foreground = 'White'
    $textBlock.Margin = '20,0,20,0'

    # Conteúdo inicial
    $textBlock.Inlines.Add("Prezado(a) usuário(a),`n`n")
    $textBlock.Inlines.Add("Estamos dando início à Manutenção Preventiva Automatizada em seu computador. Este procedimento é realizado de forma totalmente autônoma, diretamente no seu computador, ")
    $inline1 = New-Object Windows.Documents.Run("sem qualquer acesso remoto por parte de nossa equipe técnica")
    $inline1.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inline1)
    $textBlock.Inlines.Add(".`n`n")
    $textBlock.Inlines.Add("A execução segue rigorosamente o calendário de vistorias previamente agendado e comunicado por e-mail à sua empresa, garantindo segurança, transparência e eficiência. Para aprimorar ainda mais este processo, utilizamos recursos avançados de Inteligência Artificial, que permitem analisar o estado do sistema com maior precisão, identificar possíveis inconsistências e aplicar soluções automatizadas, adaptadas às necessidades específicas do seu equipamento.`n`n")
    $textBlock.Inlines.Add("Durante a execução, solicitamos que evite utilizar o computador, a fim de assegurar a integridade da manutenção e prevenir interferências.`n`n")
    $textBlock.Inlines.Add("Em caso de dúvidas, estamos à disposição pelos canais oficiais:`n`n")
    $textBlock.Inlines.Add("Telefone/WhatsApp: ")
    $inline2 = New-Object Windows.Documents.Run("(11) 9.7191-1500")
    $inline2.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inline2)
    $textBlock.Inlines.Add("`n`n")
    $textBlock.Inlines.Add("E-mail: ")
    $inline3 = New-Object Windows.Documents.Run("suporte@it4you.com.br")
    $inline3.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inline3)
    $textBlock.Inlines.Add("`n`n")
    $textBlock.Inlines.Add("Atenciosamente, ")
    $inline4 = New-Object Windows.Documents.Run("Equipe IT4You")
    $inline4.Foreground = '#90EE90'
    $textBlock.Inlines.Add($inline4)

    [Windows.Controls.Grid]::SetRow($textBlock, 1)
    $grid.Children.Add($textBlock)

    
    # Texto dinâmico (fase)
    $phaseText = New-Object Windows.Controls.TextBlock
    $phaseText.Text = "Fase atual: Inicializando..."
    $phaseText.FontSize = 14
    $phaseText.Foreground = 'Gray'
    $phaseText.TextAlignment = 'Left'
    $phaseText.Margin = '20,0,20,5'
    [Windows.Controls.Grid]::SetRow($phaseText, 2)
    $grid.Children.Add($phaseText)

    # Barra de progresso
    $progressBar = New-Object Windows.Controls.ProgressBar
    $progressBar.Height = 10
    $progressBar.Margin = '40'
    $progressBar.Minimum = 0
    $progressBar.Maximum = 9
    $progressBar.Value = 0
    $progressBar.Background = '#333333'
    $progressBar.Foreground = '#32CD32'
    [Windows.Controls.Grid]::SetRow($progressBar, 4)
    $grid.Children.Add($progressBar)

    # Texto discreto com nome do cliente
    $clienteText = New-Object Windows.Controls.TextBlock
    $clienteText.Text = "Cliente: $Cliente"
    $clienteText.FontSize = 12
    $clienteText.Foreground = 'Gray'
    $clienteText.HorizontalAlignment = 'Right'
    $clienteText.Margin = '0,5,45,5'
    [Windows.Controls.Grid]::SetRow($clienteText, 5)
    $grid.Children.Add($clienteText)

    # Guarda referências globais para atualização dinâmica
    $global:GuardianUIWindow = $window
    $global:GuardianPhaseText = $phaseText
    $global:GuardianProgressBar = $progressBar
    $global:GuardianTextBlock = $textBlock

    # Exibe sem bloquear
    $window.Show() | Out-Null
}
