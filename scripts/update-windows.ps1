<#
.SYNOPSIS
    update-windows.ps1 — Atualizador do Windows (equivalente ao update-all.sh no WSL).

.DESCRIPTION
    Apresenta o PLANO de atualizacoes (winget, Microsoft Store, Windows Update informativo,
    reinicio pendente e WSL) e pede confirmacao do operador antes de aplicar qualquer alteracao.
    Gera log detalhado por passo em arquivo UTF-8, isola falhas parciais e protege contra
    encerramento acidental de sessoes WSL ativas.

    Compativel com Windows PowerShell 5.1 e PowerShell 7+.

.PARAMETER Yes
    Aplica as atualizacoes sem solicitar confirmacao interativa.

.PARAMETER DryRun
    Modo simulacao: apenas lista o plano e sai (exit 0). Prevalece sobre -Yes.

.PARAMETER SkipWsl
    Pula a verificacao e atualizacao do WSL (wsl --update).

.PARAMETER SkipStore
    Pula a atualizacao dos pacotes da Microsoft Store (winget --source msstore).

.PARAMETER SkipWinget
    Pula a atualizacao de pacotes gerais do winget (winget upgrade --all).

.PARAMETER ForceWsl
    Permite wsl --update mesmo quando detectada execucao de dentro do WSL.

.PARAMETER LogDir
    Diretorio onde os logs sao gravados (padrao: %LOCALAPPDATA%\update-windows\).

.PARAMETER Help
    Exibe instrucoes de uso e parametros disponiveis.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==============================================================================
# Funcoes Utilitarias e Nativas
# ==============================================================================

$script:CurrentLogFile = $null

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $output = @()
    $exitCode = 0
    try {
        $output = & $FilePath @ArgumentList 2>&1
        if ($null -ne $LASTEXITCODE) {
            $exitCode = [int]$LASTEXITCODE
        } else {
            $exitCode = 0
        }
    } catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        StdOut   = ($output -join [Environment]::NewLine)
        StdErr   = ""
    }
}

function Get-NativeExitCode {
    param($Result)
    if ($null -eq $Result) { return 0 }
    if ($Result -is [int]) { return $Result }
    if ($Result.PSObject.Properties['ExitCode']) { return [int]$Result.ExitCode }
    return 0
}

function Get-NativeOutput {
    param($Result)
    if ($null -eq $Result) { return "" }
    if ($Result.PSObject.Properties['StdOut']) { return [string]$Result.StdOut }
    if ($Result -is [string]) { return $Result }
    return ""
}

function Write-LogMessage {
    param(
        [string]$Message,
        [string]$FilePath = $script:CurrentLogFile,
        [switch]$NoConsole
    )

    if (-not $NoConsole) {
        Write-Host $Message
    }

    if (-not [string]::IsNullOrEmpty($FilePath)) {
        try {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $logLine = "[$timestamp] $Message"
            [System.IO.File]::AppendAllText($FilePath, "$logLine`r`n", [System.Text.Encoding]::UTF8)
        } catch {
            # Falha de gravacao de log nao deve interromper o script principal
        }
    }
}

function Test-CommandAvailable {
    param([string]$Name)
    try {
        $cmd = Get-Command -Name $Name -ErrorAction Stop
        return ($null -ne $cmd)
    } catch {
        return $false
    }
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-PendingWindowsUpdates {
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        # Consulta somente atualizacoes nao instaladas e nao ocultas
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")
        $titles = @()
        if ($null -ne $searchResult -and $null -ne $searchResult.Updates) {
            foreach ($update in $searchResult.Updates) {
                if ($null -ne $update -and $null -ne $update.Title) {
                    $titles += [string]$update.Title
                }
            }
        }
        return @{
            Success = $true
            Updates = $titles
            Message = ""
        }
    } catch {
        return @{
            Success = $false
            Updates = @()
            Message = $_.Exception.Message
        }
    }
}

function Test-PendingReboot {
    $reasons = @()
    try {
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
            $reasons += "WindowsUpdate RebootRequired"
        }
    } catch {}

    try {
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
            $reasons += "Component Based Servicing RebootPending"
        }
    } catch {}

    try {
        $sm = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($null -ne $sm -and $sm.PendingFileRenameOperations) {
            $reasons += "PendingFileRenameOperations"
        }
    } catch {}

    return @{
        RebootPending = ($reasons.Count -gt 0)
        Reasons       = $reasons
    }
}

function Test-IsInteractive {
    try {
        if (-not [Environment]::UserInteractive) {
            return $false
        }
        if ([Console]::IsInputRedirected) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

function Read-UserConfirmation {
    param([string]$Prompt = "Aplicar? [s/N]")
    if (-not (Test-IsInteractive)) {
        return $null
    }
    Write-Host -NoNewline "$Prompt "
    return (Read-Host)
}

function Test-AffirmativeResponse {
    param([string]$Response)
    if ([string]::IsNullOrWhiteSpace($Response)) {
        return $false
    }
    $trimmed = $Response.Trim().ToLowerInvariant()
    return ($trimmed -eq 's' -or $trimmed -eq 'sim' -or $trimmed -eq 'y' -or $trimmed -eq 'yes')
}

# ==============================================================================
# Funcao Principal (Main)
# ==============================================================================

function Main {
    param(
        [switch]$Yes,
        [switch]$DryRun,
        [switch]$SkipWsl,
        [switch]$SkipStore,
        [switch]$SkipWinget,
        [switch]$ForceWsl,
        [string]$LogDir = "",
        [switch]$Help
    )

    # Inicializacao explicita de variaveis locais (compatibilidade Set-StrictMode Latest)
    $parsedYes = $Yes.IsPresent
    $parsedDryRun = $DryRun.IsPresent
    $parsedSkipWsl = $SkipWsl.IsPresent
    $parsedSkipStore = $SkipStore.IsPresent
    $parsedSkipWinget = $SkipWinget.IsPresent
    $parsedForceWsl = $ForceWsl.IsPresent
    $parsedLogDir = $LogDir
    $parsedHelp = $Help.IsPresent

    # Analise de argumentos remanescentes ou passados via array
    $rawTokens = @()
    if ($args.Count -gt 0) {
        foreach ($item in $args) {
            if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
                foreach ($sub in $item) {
                    $rawTokens += [string]$sub
                }
            } else {
                $rawTokens += [string]$item
            }
        }
    }

    $i = 0
    while ($i -lt $rawTokens.Count) {
        $token = $rawTokens[$i]
        switch -Regex ($token) {
            '^(-y|--yes|-Yes)$' {
                $parsedYes = $true
            }
            '^(-n|--dry-run|-DryRun)$' {
                $parsedDryRun = $true
            }
            '^(--skip-wsl|-SkipWsl)$' {
                $parsedSkipWsl = $true
            }
            '^(--skip-store|-SkipStore)$' {
                $parsedSkipStore = $true
            }
            '^(--skip-winget|-SkipWinget)$' {
                $parsedSkipWinget = $true
            }
            '^(--force-wsl|-ForceWsl)$' {
                $parsedForceWsl = $true
            }
            '^(--log-dir|-LogDir)$' {
                $i++
                if ($i -ge $rawTokens.Count) {
                    [Console]::Error.WriteLine("update-windows: opcao '$token' requer um argumento de diretorio.")
                    return 2
                }
                $parsedLogDir = $rawTokens[$i]
            }
            '^(-h|--help|-Help|-\?)$' {
                $parsedHelp = $true
            }
            default {
                [Console]::Error.WriteLine("update-windows: opcao desconhecida: $token (use -Help)")
                return 2
            }
        }
        $i++
    }

    if ($parsedHelp) {
        Write-Host "Uso: update-windows.ps1 [-Yes] [-DryRun] [-SkipWsl] [-SkipStore] [-SkipWinget] [-ForceWsl] [-LogDir <caminho>] [-Help]"
        Write-Host ""
        Write-Host "Parametros:"
        Write-Host "  -Yes         Executa sem pedir confirmacao interativa."
        Write-Host "  -DryRun      Mostra o plano de atualizacao sem executar alteracoes (vence -Yes)."
        Write-Host "  -SkipWsl     Pula a atualizacao do WSL (wsl --update)."
        Write-Host "  -SkipStore   Pula a atualizacao de pacotes da Microsoft Store (msstore)."
        Write-Host "  -SkipWinget  Pula a atualizacao de pacotes gerais do winget."
        Write-Host "  -ForceWsl    Permite wsl --update mesmo quando executado dentro do WSL."
        Write-Host "  -LogDir      Diretorio para gravacao dos logs (padrao: %LOCALAPPDATA%\update-windows\)."
        Write-Host "  -Help        Exibe esta mensagem de ajuda."
        return 0
    }

    # Configuracao do diretorio e arquivo de log
    if ([string]::IsNullOrEmpty($parsedLogDir)) {
        if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
            $parsedLogDir = Join-Path $env:LOCALAPPDATA "update-windows"
        } else {
            $parsedLogDir = Join-Path $HOME "update-windows"
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $parsedLogDir)) {
            $null = New-Item -ItemType Directory -Path $parsedLogDir -Force
        }
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $script:CurrentLogFile = Join-Path $parsedLogDir "update-windows-$timestamp.log"
    } catch {
        $script:CurrentLogFile = $null
    }

    Write-LogMessage "== update-windows iniciado =="
    Write-LogMessage "Parametros: DryRun=$parsedDryRun, Yes=$parsedYes, SkipWsl=$parsedSkipWsl, SkipStore=$parsedSkipStore, SkipWinget=$parsedSkipWinget, ForceWsl=$parsedForceWsl, LogDir='$parsedLogDir'"

    # ------------------------------------------------------------------
    # 1. Pre-checagens
    # ------------------------------------------------------------------
    if (-not (Test-CommandAvailable -Name 'winget')) {
        $msg = "update-windows: 'winget' nao encontrado no PATH. Instale o Instalador de Aplicativos (App Installer) da Microsoft Store ou adicione winget ao PATH."
        [Console]::Error.WriteLine($msg)
        Write-LogMessage $msg
        return 3
    }

    $isAdmin = Test-IsAdmin
    if (-not $isAdmin) {
        $warnAdmin = "[aviso] Executando sem privilegios de Administrador. Algumas atualizacoes do winget podem solicitar elevacao UAC."
        Write-LogMessage $warnAdmin
    }

    # ------------------------------------------------------------------
    # 2. PLANO (somente leitura)
    # ------------------------------------------------------------------
    $planMode = if ($parsedDryRun) { "dry-run" } else { "interativo" }
    Write-Host ""
    Write-Host "== update-windows ==  plano  ($planMode)"
    Write-LogMessage "== PLANO ($planMode) ==" -NoConsole

    # 2.1 winget
    if ($parsedSkipWinget) {
        Write-Host "  1) winget (pacotes) : (pulado por -SkipWinget)"
        Write-LogMessage "1) winget (pacotes) : pulado por -SkipWinget" -NoConsole
    } else {
        Write-Host "  1) winget (pacotes) : verificando atualizacoes disponiveis (winget upgrade --include-unknown)..."
        Write-LogMessage "1) winget (pacotes) : winget upgrade --include-unknown" -NoConsole
        try {
            $wingetCheck = Invoke-Native -FilePath 'winget' -ArgumentList @('upgrade', '--include-unknown')
            $out = Get-NativeOutput $wingetCheck
            if (-not [string]::IsNullOrEmpty($out)) {
                Write-Host $out
                Write-LogMessage $out -NoConsole
            }
        } catch {
            Write-Host "     [aviso] Falha ao consultar winget: $($_.Exception.Message)"
            Write-LogMessage "[aviso] Falha ao consultar winget: $($_.Exception.Message)" -NoConsole
        }
    }

    # 2.2 Windows Update (COM Microsoft.Update.Session) + Reboot Pending
    Write-Host "  2) Windows Update   : verificando atualizacoes pendentes (COM Microsoft.Update.Session)..."
    Write-LogMessage "2) Windows Update (COM Microsoft.Update.Session)" -NoConsole
    $wuInfo = Get-PendingWindowsUpdates
    if ($wuInfo.Success) {
        $updates = $wuInfo.Updates
        if ($updates.Count -gt 0) {
            Write-Host "     $($updates.Count) atualizacao(oes) pendente(s) no Windows Update:"
            Write-LogMessage "$($updates.Count) atualizacao(oes) pendente(s) no Windows Update:" -NoConsole
            foreach ($u in $updates) {
                Write-Host "     - $u"
                Write-LogMessage "     - $u" -NoConsole
            }
            Write-Host "     (Windows Update e informativo; utilize as Configuracoes do Windows para instalar)"
        } else {
            Write-Host "     Nenhuma atualizacao pendente no Windows Update."
            Write-LogMessage "Nenhuma atualizacao pendente no Windows Update." -NoConsole
        }
    } else {
        Write-Host "     [aviso] Falha ao consultar Windows Update via COM: $($wuInfo.Message)"
        Write-LogMessage "[aviso] Falha ao consultar Windows Update via COM: $($wuInfo.Message)" -NoConsole
    }

    $rebootInfo = Test-PendingReboot
    if ($rebootInfo.RebootPending) {
        $reasons = ($rebootInfo.Reasons -join ', ')
        Write-Host "     [aviso] Reinicio pendente detectado: $reasons"
        Write-LogMessage "[aviso] Reinicio pendente detectado: $reasons" -NoConsole
    } else {
        Write-Host "     Reinicio pendente: Nao"
        Write-LogMessage "Reinicio pendente: Nao" -NoConsole
    }

    # 2.3 WSL
    if ($parsedSkipWsl) {
        Write-Host "  3) WSL              : (pulado por -SkipWsl)"
        Write-LogMessage "3) WSL : pulado por -SkipWsl" -NoConsole
    } else {
        Write-Host "  3) WSL              : verificando versao (wsl --version)..."
        Write-LogMessage "3) WSL : wsl --version" -NoConsole
        try {
            $wslCheck = Invoke-Native -FilePath 'wsl' -ArgumentList @('--version')
            $wslOut = Get-NativeOutput $wslCheck
            if (-not [string]::IsNullOrEmpty($wslOut)) {
                Write-Host $wslOut
                Write-LogMessage $wslOut -NoConsole
            }
        } catch {
            Write-Host "     [aviso] Falha ao verificar versao do WSL: $($_.Exception.Message)"
            Write-LogMessage "[aviso] Falha ao verificar versao do WSL: $($_.Exception.Message)" -NoConsole
        }
    }

    # Regra de ouro: -DryRun vence -Yes (se vierem juntos, e dry-run)
    if ($parsedDryRun) {
        Write-Host ""
        Write-Host "(dry-run: nada foi executado)"
        Write-LogMessage "(dry-run: nada foi executado)" -NoConsole
        return 0
    }

    # ------------------------------------------------------------------
    # 3. Confirmacao
    # ------------------------------------------------------------------
    if (-not $parsedYes) {
        if (-not (Test-IsInteractive)) {
            $msgFailClosed = "update-windows: sessao nao interativa e parametro -Yes nao fornecido. Cancelando por seguranca."
            [Console]::Error.WriteLine($msgFailClosed)
            Write-LogMessage $msgFailClosed
            return 4
        }

        $resp = Read-UserConfirmation -Prompt "Aplicar? [s/N]"
        if (-not (Test-AffirmativeResponse -Response $resp)) {
            Write-Host "abortado pelo operador"
            Write-LogMessage "abortado pelo operador"
            return 4
        }
    } else {
        Write-LogMessage "Confirmacao ignorada devido ao parametro -Yes." -NoConsole
    }

    # ------------------------------------------------------------------
    # 4. Aplicar
    # ------------------------------------------------------------------
    $stepResults = [System.Collections.Generic.List[object]]::new()
    $totalErrors = 0

    # 4.1 winget geral
    Write-Host ""
    Write-Host "=== 1) winget (geral) ==="
    Write-LogMessage "=== 1) winget (geral) ===" -NoConsole
    if ($parsedSkipWinget) {
        Write-Host "  pulado (-SkipWinget)"
        Write-LogMessage "1) winget (geral): pulado (-SkipWinget)" -NoConsole
        $stepResults.Add([PSCustomObject]@{ Name = "winget (geral)"; Status = "pulado" })
    } else {
        $stepStart = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-LogMessage "Inicio do passo winget (geral): $stepStart" -NoConsole
        $cmdArgs = @('upgrade', '--all', '--include-unknown', '--accept-package-agreements', '--accept-source-agreements', '--silent')
        Write-LogMessage "Comando: winget $($cmdArgs -join ' ')" -NoConsole
        $stepFailed = $false
        $code = 0
        try {
            $res = Invoke-Native -FilePath 'winget' -ArgumentList $cmdArgs
            $code = Get-NativeExitCode $res
            $out = Get-NativeOutput $res
            if (-not [string]::IsNullOrEmpty($out)) {
                Write-Host $out
                Write-LogMessage $out -NoConsole
            }
            if ($code -ne 0) {
                $stepFailed = $true
                Write-Host "  FALHOU: winget upgrade (exit code $code)"
                Write-LogMessage "FALHOU: winget upgrade (exit code $code)" -NoConsole
            } else {
                Write-Host "  ok"
                Write-LogMessage "ok: winget upgrade" -NoConsole
            }
        } catch {
            $stepFailed = $true
            $code = 1
            Write-Host "  FALHOU: $($_.Exception.Message)"
            Write-LogMessage "FALHOU: $($_.Exception.Message)" -NoConsole
        }
        $stepEnd = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-LogMessage "Fim do passo winget (geral): $stepEnd (exit code $code)" -NoConsole
        if ($stepFailed) {
            $totalErrors++
            $stepResults.Add([PSCustomObject]@{ Name = "winget (geral)"; Status = "FALHOU" })
        } else {
            $stepResults.Add([PSCustomObject]@{ Name = "winget (geral)"; Status = "ok" })
        }
    }

    # 4.2 winget Microsoft Store
    Write-Host ""
    Write-Host "=== 2) winget (Store) ==="
    Write-LogMessage "=== 2) winget (Store) ===" -NoConsole
    if ($parsedSkipStore) {
        Write-Host "  pulado (-SkipStore)"
        Write-LogMessage "2) winget (Store): pulado (-SkipStore)" -NoConsole
        $stepResults.Add([PSCustomObject]@{ Name = "winget (Store)"; Status = "pulado" })
    } else {
        $stepStart = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-LogMessage "Inicio do passo winget (Store): $stepStart" -NoConsole
        $cmdArgs = @('upgrade', '--source', 'msstore', '--all', '--accept-package-agreements', '--accept-source-agreements')
        Write-LogMessage "Comando: winget $($cmdArgs -join ' ')" -NoConsole
        $stepFailed = $false
        $code = 0
        try {
            $res = Invoke-Native -FilePath 'winget' -ArgumentList $cmdArgs
            $code = Get-NativeExitCode $res
            $out = Get-NativeOutput $res
            if (-not [string]::IsNullOrEmpty($out)) {
                Write-Host $out
                Write-LogMessage $out -NoConsole
            }
            if ($code -ne 0) {
                $stepFailed = $true
                Write-Host "  FALHOU: winget msstore upgrade (exit code $code)"
                Write-LogMessage "FALHOU: winget msstore upgrade (exit code $code)" -NoConsole
            } else {
                Write-Host "  ok"
                Write-LogMessage "ok: winget msstore upgrade" -NoConsole
            }
        } catch {
            $stepFailed = $true
            $code = 1
            Write-Host "  FALHOU: $($_.Exception.Message)"
            Write-LogMessage "FALHOU: $($_.Exception.Message)" -NoConsole
        }
        $stepEnd = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-LogMessage "Fim do passo winget (Store): $stepEnd (exit code $code)" -NoConsole
        if ($stepFailed) {
            $totalErrors++
            $stepResults.Add([PSCustomObject]@{ Name = "winget (Store)"; Status = "FALHOU" })
        } else {
            $stepResults.Add([PSCustomObject]@{ Name = "winget (Store)"; Status = "ok" })
        }
    }

    # 4.3 WSL
    Write-Host ""
    Write-Host "=== 3) WSL ==="
    Write-LogMessage "=== 3) WSL ===" -NoConsole
    if ($parsedSkipWsl) {
        Write-Host "  pulado (-SkipWsl)"
        Write-LogMessage "3) WSL: pulado (-SkipWsl)" -NoConsole
        $stepResults.Add([PSCustomObject]@{ Name = "wsl"; Status = "pulado" })
    } else {
        $inWsl = (-not [string]::IsNullOrEmpty($env:WSL_DISTRO_NAME))
        if ($inWsl -and (-not $parsedForceWsl)) {
            $wslNotice = "[aviso] Execucao detectada dentro do WSL (WSL_DISTRO_NAME='$($env:WSL_DISTRO_NAME)'). 'wsl --update' derrubaria a sessao atual. Passo pulado por seguranca (use -ForceWsl para forcar)."
            Write-Host "  $wslNotice"
            Write-LogMessage $wslNotice
            $stepResults.Add([PSCustomObject]@{ Name = "wsl"; Status = "pulado (WSL ativo)" })
        } else {
            $stepStart = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Write-LogMessage "Inicio do passo WSL: $stepStart" -NoConsole
            $cmdArgs = @('--update')
            Write-LogMessage "Comando: wsl $($cmdArgs -join ' ')" -NoConsole
            $stepFailed = $false
            $code = 0
            try {
                $res = Invoke-Native -FilePath 'wsl' -ArgumentList $cmdArgs
                $code = Get-NativeExitCode $res
                $out = Get-NativeOutput $res
                if (-not [string]::IsNullOrEmpty($out)) {
                    Write-Host $out
                    Write-LogMessage $out -NoConsole
                }
                if ($code -ne 0) {
                    $stepFailed = $true
                    Write-Host "  FALHOU: wsl --update (exit code $code)"
                    Write-LogMessage "FALHOU: wsl --update (exit code $code)" -NoConsole
                } else {
                    Write-Host "  ok"
                    Write-LogMessage "ok: wsl --update" -NoConsole
                }
            } catch {
                $stepFailed = $true
                $code = 1
                Write-Host "  FALHOU: $($_.Exception.Message)"
                Write-LogMessage "FALHOU: $($_.Exception.Message)" -NoConsole
            }
            $stepEnd = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Write-LogMessage "Fim do passo WSL: $stepEnd (exit code $code)" -NoConsole
            if ($stepFailed) {
                $totalErrors++
                $stepResults.Add([PSCustomObject]@{ Name = "wsl"; Status = "FALHOU" })
            } else {
                $stepResults.Add([PSCustomObject]@{ Name = "wsl"; Status = "ok" })
            }
        }
    }

    # ------------------------------------------------------------------
    # Resumo Final
    # ------------------------------------------------------------------
    Write-Host ""
    Write-Host "== update-windows: resumo =="
    Write-LogMessage "" -NoConsole
    Write-LogMessage "== update-windows: resumo ==" -NoConsole
    foreach ($res in $stepResults) {
        $line = ("  {0,-20} : {1}" -f $res.Name, $res.Status)
        Write-Host $line
        Write-LogMessage $line -NoConsole
    }
    Write-Host "erros: $totalErrors"
    Write-LogMessage "erros: $totalErrors" -NoConsole
    if ($totalErrors -gt 0) {
        Write-Host "veja as linhas FALHOU acima e no log: $parsedLogDir"
        Write-LogMessage "veja as linhas FALHOU acima e no log: $parsedLogDir" -NoConsole
        return 1
    }
    return 0
}

# ==============================================================================
# Ponto de Entrada (so executa Main se chamado diretamente, nao em dot-source)
# ==============================================================================

if ($MyInvocation.InvocationName -ne '.') {
    exit (Main @args)
}
