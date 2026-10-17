# ==============================================================================
# update-windows.selftest.ps1 — Suite de Autoteste Autonoma (sem Pester, exit 0/1)
# ==============================================================================
#
# Executavel diretamente via:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/update-windows.selftest.ps1
#
# Cobre integralmente a tabela de casos adversariais (CA-D, CA-I1, CA-I, CA-J, CA-A, CA-C)
# e garante saida 0 (todos passaram) ou 1 (ao menos uma falha).
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $here "update-windows.ps1"

# Dot-source do script em teste
. $sut

# ------------------------------------------------------------------------------
# Framework minimo de assercoes
# ------------------------------------------------------------------------------
$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$TestName)
    $script:TotalTests++
    if ($Actual -eq $Expected) {
        $script:PassedTests++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailedTests++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "         Esperado: '$Expected'" -ForegroundColor Yellow
        Write-Host "         Obtido  : '$Actual'" -ForegroundColor Yellow
    }
}

function Assert-True {
    param($Condition, [string]$TestName)
    Assert-Equal ([bool]$Condition) $true $TestName
}

function Assert-False {
    param($Condition, [string]$TestName)
    Assert-Equal ([bool]$Condition) $false $TestName
}

# ------------------------------------------------------------------------------
# Estado e Dubles de Teste (Fakes)
# ------------------------------------------------------------------------------
$script:RecordedCommands = [System.Collections.Generic.List[object]]::new()
$script:FailCommands = [System.Collections.Generic.List[string]]::new()
$script:MockCommandAvailable = $true
$script:MockIsAdmin = $true
$script:MockIsInteractive = $true
$script:MockConfirmation = "s"
$script:MockPendingUpdates = @()
$script:MockPendingReboot = $false

function Reset-TestState {
    $script:RecordedCommands.Clear()
    $script:FailCommands.Clear()
    $script:MockCommandAvailable = $true
    $script:MockIsAdmin = $true
    $script:MockIsInteractive = $true
    $script:MockConfirmation = "s"
    $script:MockPendingUpdates = @()
    $script:MockPendingReboot = $false
    $env:WSL_DISTRO_NAME = $null
}

function global:Invoke-Native {
    param($FilePath, $ArgumentList)
    $cmdObj = [PSCustomObject]@{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
    }
    $script:RecordedCommands.Add($cmdObj)

    if ($script:FailCommands.Contains($FilePath) -or
        ($FilePath -eq 'winget' -and $ArgumentList -contains '--all' -and $script:FailCommands.Contains('winget-all'))) {
        return [PSCustomObject]@{
            ExitCode = 1
            StdOut   = "Erro simulado"
            StdErr   = "Erro simulado no comando nativo"
        }
    }

    return [PSCustomObject]@{
        ExitCode = 0
        StdOut   = "Saida simulada de sucesso"
        StdErr   = ""
    }
}

function global:Test-CommandAvailable {
    param([string]$Name)
    if ($Name -eq 'winget') {
        return $script:MockCommandAvailable
    }
    return $true
}

function global:Test-IsAdmin {
    return $script:MockIsAdmin
}

function global:Test-IsInteractive {
    return $script:MockIsInteractive
}

function global:Read-UserConfirmation {
    param([string]$Prompt = "Aplicar? [s/N]")
    return $script:MockConfirmation
}

function global:Get-PendingWindowsUpdates {
    return @{
        Success = $true
        Updates = $script:MockPendingUpdates
        Message = ""
    }
}

function global:Test-PendingReboot {
    return @{
        RebootPending = $script:MockPendingReboot
        Reasons       = if ($script:MockPendingReboot) { @("MockReboot") } else { @() }
    }
}

# Salva variavel original do WSL para restauracao final
$origWslDistro = $env:WSL_DISTRO_NAME

Write-Host "=== Iniciando Selftest de update-windows.ps1 ===" -ForegroundColor Cyan

try {
    # --------------------------------------------------------------------------
    # 1. CA-I1: Precedencia entre -DryRun e -Yes
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-I1: -DryRun vence -Yes --" -ForegroundColor Yellow
    Reset-TestState
    $code = Main -DryRun -Yes
    Assert-Equal $code 0 "CA-I1: exit code deve ser 0 em dry-run mesmo com -Yes"

    $applyCalls = $script:RecordedCommands | Where-Object {
        ($_.FilePath -eq 'winget' -and $_.ArgumentList -contains '--all') -or
        ($_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update')
    }
    Assert-Equal (@($applyCalls).Count) 0 "CA-I1: nenhum comando de aplicacao (--all / --update) deve ser executado"

    # --------------------------------------------------------------------------
    # 2. CA-D: wsl --update dentro do WSL mata a sessao
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-D: Protecao contra encerramento de sessao WSL --" -ForegroundColor Yellow
    Reset-TestState
    $env:WSL_DISTRO_NAME = "Ubuntu-22.04"
    $code = Main -Yes
    Assert-Equal $code 0 "CA-D: exit code 0 com passo pulado"
    $wslUpdateCalls = $script:RecordedCommands | Where-Object {
        $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
    }
    Assert-Equal (@($wslUpdateCalls).Count) 0 "CA-D: wsl --update NAO deve ser chamado dentro do WSL sem -ForceWsl"

    # Com -ForceWsl
    Reset-TestState
    $env:WSL_DISTRO_NAME = "Ubuntu-22.04"
    $code = Main -Yes -ForceWsl
    Assert-Equal $code 0 "CA-D: exit code 0 com -ForceWsl"
    $wslUpdateCallsForce = $script:RecordedCommands | Where-Object {
        $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
    }
    Assert-Equal (@($wslUpdateCallsForce).Count) 1 "CA-D: wsl --update DEVE ser chamado dentro do WSL quando -ForceWsl e fornecido"

    # Fora do WSL
    Reset-TestState
    $env:WSL_DISTRO_NAME = $null
    $code = Main -Yes
    Assert-Equal $code 0 "CA-D: exit code 0 fora do WSL"
    $wslUpdateCallsNormal = $script:RecordedCommands | Where-Object {
        $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
    }
    Assert-Equal (@($wslUpdateCallsNormal).Count) 1 "CA-D: wsl --update DEVE ser chamado fora do WSL"

    # --------------------------------------------------------------------------
    # 3. CA-I: Terminal nao interativo sem -Yes (Fail-Closed)
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-I: Fail-Closed em terminal nao interativo --" -ForegroundColor Yellow
    Reset-TestState
    $script:MockIsInteractive = $false
    $code = Main
    Assert-Equal $code 4 "CA-I: sem -Yes em terminal nao interativo deve abortar com exit 4"

    $applyCalls = $script:RecordedCommands | Where-Object {
        ($_.FilePath -eq 'winget' -and $_.ArgumentList -contains '--all') -or
        ($_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update')
    }
    Assert-Equal (@($applyCalls).Count) 0 "CA-I: nada aplicado quando terminal nao for interativo"

    # --------------------------------------------------------------------------
    # 4. CA-I: Confirmacao com padrao NAO
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-I: Confirmacao com padrao NAO --" -ForegroundColor Yellow
    # Resposta vazia (Enter)
    Reset-TestState
    $script:MockConfirmation = ""
    $code = Main
    Assert-Equal $code 4 "CA-I: resposta vazia (padrao N) deve cancelar com exit 4"

    # Respostas negativas e lixo
    foreach ($negativeResp in @("n", "N", "nao", "não", "no", "cancelar", "xyz")) {
        Reset-TestState
        $script:MockConfirmation = $negativeResp
        $code = Main
        Assert-Equal $code 4 "CA-I: resposta '$negativeResp' deve cancelar com exit 4"
    }

    # Respostas afirmativas
    foreach ($affirmativeResp in @("s", "S", "sim", "SIM", "y", "Y", "yes", "YES")) {
        Reset-TestState
        $script:MockConfirmation = $affirmativeResp
        $code = Main
        Assert-Equal $code 0 "CA-I: resposta afirmativa '$affirmativeResp' deve aplicar e retornar exit 0"
        $applyCalls = $script:RecordedCommands | Where-Object {
            $_.FilePath -eq 'winget' -and $_.ArgumentList -contains '--all'
        }
        Assert-True (@($applyCalls).Count -gt 0) "CA-I: comandos aplicados para '$affirmativeResp'"
    }

    # --------------------------------------------------------------------------
    # 5. CA-I: Winget ausente no PATH
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-I: Winget ausente no PATH --" -ForegroundColor Yellow
    Reset-TestState
    $script:MockCommandAvailable = $false
    $code = Main -Yes
    Assert-Equal $code 3 "CA-I: winget ausente deve retornar exit 3 com causa clara"
    Assert-Equal ($script:RecordedCommands.Count) 0 "CA-I: nenhum comando executado quando winget ausente"

    # --------------------------------------------------------------------------
    # 6. CA-J: Falha parcial e isolamento por passo
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-J: Falha parcial e continuidade dos passos --" -ForegroundColor Yellow
    Reset-TestState
    $script:FailCommands.Add('winget-all')
    $code = Main -Yes
    Assert-Equal $code 1 "CA-J: falha no passo winget geral deve resultar em exit code final 1"

    $storeCalls = $script:RecordedCommands | Where-Object {
        $_.FilePath -eq 'winget' -and $_.ArgumentList -contains 'msstore'
    }
    Assert-Equal (@($storeCalls).Count) 1 "CA-J: passo Store deve executar mesmo apos falha do winget geral"

    $wslCalls = $script:RecordedCommands | Where-Object {
        $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
    }
    Assert-Equal (@($wslCalls).Count) 1 "CA-J: passo WSL deve executar mesmo apos falha do winget geral"

    # --------------------------------------------------------------------------
    # 7. CA-A: LogDir com espacos e caracteres especiais
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-A: LogDir com espacos e acentos --" -ForegroundColor Yellow
    $testBaseDir = Join-Path $here ".orq-selftest-tmp-a"
    $accentDir = Join-Path $testBaseDir "Meu Log çá"
    try {
        Reset-TestState
        $code = Main -DryRun -LogDir $accentDir
        Assert-Equal $code 0 "CA-A: execucao com sucesso apontando para diretorio com acento/espaco"
        Assert-True (Test-Path -LiteralPath $accentDir) "CA-A: diretorio com espaco e acento criado com sucesso"

        $logs = Get-ChildItem -LiteralPath $accentDir -Filter "update-windows-*.log"
        Assert-True (@($logs).Count -gt 0) "CA-A: arquivo de log gerado dentro da pasta com acento/espaco"
    } finally {
        if (Test-Path -LiteralPath $testBaseDir) {
            Remove-Item -LiteralPath $testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --------------------------------------------------------------------------
    # 8. CA-C: Windows Update nunca instala
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-C: Windows Update somente leitura --" -ForegroundColor Yellow
    $sutContent = Get-Content -LiteralPath $sut -Raw
    $hasInstaller = ($sutContent -match 'CreateUpdateInstaller')
    $hasInstallCall = ($sutContent -match '\.Install\(')
    Assert-False $hasInstaller "CA-C: codigo nunca deve instanciar CreateUpdateInstaller"
    Assert-False $hasInstallCall "CA-C: codigo nunca deve chamar metodo Install() no Windows Update"

    # --------------------------------------------------------------------------
    # 9. CA-J: Sem segredos no log
    # --------------------------------------------------------------------------
    Write-Host "`n-- Caso CA-J: Sem segredos no log --" -ForegroundColor Yellow
    $sentinelSecret = "SECRET_TOKEN_SENTINEL_SELFTEST_12345"
    $env:SENTINEL_TOKEN_VAR = $sentinelSecret
    $testSecretsDir = Join-Path $here ".orq-selftest-tmp-secrets"
    try {
        Reset-TestState
        $code = Main -DryRun -LogDir $testSecretsDir
        Assert-Equal $code 0 "CA-J: execucao com dry-run para teste de segredos"

        $logs = Get-ChildItem -LiteralPath $testSecretsDir -Filter "update-windows-*.log"
        Assert-True (@($logs).Count -gt 0) "CA-J: arquivo de log gerado"
        if (@($logs).Count -gt 0) {
            $logBody = Get-Content -LiteralPath $logs[0].FullName -Raw
            $containsSecret = $logBody.Contains($sentinelSecret)
            Assert-False $containsSecret "CA-J: sentinela de variavel de ambiente NAO deve estar presente no log"
        }
    } finally {
        Remove-Item env:SENTINEL_TOKEN_VAR -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testSecretsDir) {
            Remove-Item -LiteralPath $testSecretsDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --------------------------------------------------------------------------
    # 10. Validacao de argumentos
    # --------------------------------------------------------------------------
    Write-Host "`n-- Validacao de argumentos --" -ForegroundColor Yellow
    Reset-TestState
    $code = Main -OpcaoInvalida
    Assert-Equal $code 2 "Validacao: opcao desconhecida deve retornar exit 2"

    Reset-TestState
    $code = Main -Help
    Assert-Equal $code 0 "Validacao: -Help deve retornar exit 0"

    # --------------------------------------------------------------------------
    # 11. Flags de Skip
    # --------------------------------------------------------------------------
    Write-Host "`n-- Flags de Skip (-SkipWinget, -SkipStore, -SkipWsl) --" -ForegroundColor Yellow
    Reset-TestState
    $code = Main -Yes -SkipWinget -SkipStore -SkipWsl
    Assert-Equal $code 0 "Skip: exit 0 quando tudo pulado"
    $applyCalls = $script:RecordedCommands | Where-Object {
        $_.ArgumentList -contains '--all' -or $_.ArgumentList -contains '--update'
    }
    Assert-Equal (@($applyCalls).Count) 0 "Skip: nenhum comando de aplicacao chamado quando todas as flags de skip sao passadas"

} finally {
    $env:WSL_DISTRO_NAME = $origWslDistro
}

# ------------------------------------------------------------------------------
# Resumo Final do Selftest
# ------------------------------------------------------------------------------
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "== Selftest update-windows.ps1: Fim ==" -ForegroundColor Cyan
Write-Host "Total de testes : $script:TotalTests"
Write-Host "Passaram        : $script:PassedTests" -ForegroundColor Green
Write-Host "Falharam        : $script:FailedTests" -ForegroundColor $(if ($script:FailedTests -gt 0) { "Red" } else { "Green" })
Write-Host "==================================================" -ForegroundColor Cyan

if ($script:FailedTests -gt 0) {
    exit 1
}
exit 0
