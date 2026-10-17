# ==============================================================================
# update-windows.Tests.ps1 — Testes de Unidade e Integracao Pester (W-423)
# ==============================================================================

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $here "update-windows.ps1"

Describe "update-windows.ps1" {
    BeforeAll {
        Set-StrictMode -Version Latest
        . $sut
    }

    BeforeEach {
        $script:RecordedCommands = [System.Collections.Generic.List[object]]::new()
        $script:FailCommands = [System.Collections.Generic.List[string]]::new()
        $script:MockCommandAvailable = $true
        $script:MockIsAdmin = $true
        $script:MockIsInteractive = $true
        $script:MockConfirmation = "s"
        $script:MockPendingUpdates = @()
        $script:MockPendingReboot = $false

        # Salva estado de variaveis de ambiente
        $script:OrigWslDistro = $env:WSL_DISTRO_NAME

        # Sobrescreve funcoes para o teste
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
    }

    AfterEach {
        $env:WSL_DISTRO_NAME = $script:OrigWslDistro
    }

    Context "CA-I1: Precedencia entre -DryRun e -Yes" {
        It "deve executar apenas o plano e nenhum comando de aplicacao quando ambos forem passados (-DryRun vence)" {
            $code = Main -DryRun -Yes
            $code | Should -Be 0

            # Verifica se nenhum comando com --all ou --update foi chamado
            $applyCalls = $script:RecordedCommands | Where-Object {
                ($_.FilePath -eq 'winget' -and $_.ArgumentList -contains '--all') -or
                ($_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update')
            }
            @($applyCalls).Count | Should -Be 0
        }
    }

    Context "CA-D: Protecao do WSL contra derrubada de sessao" {
        It "deve pular wsl --update quando executado dentro do WSL e -ForceWsl nao for fornecido" {
            $env:WSL_DISTRO_NAME = "Ubuntu-22.04"
            $code = Main -Yes
            $code | Should -Be 0

            $wslUpdateCalls = $script:RecordedCommands | Where-Object {
                $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
            }
            @($wslUpdateCalls).Count | Should -Be 0
        }

        It "deve executar wsl --update dentro do WSL quando -ForceWsl for fornecido" {
            $env:WSL_DISTRO_NAME = "Ubuntu-22.04"
            $code = Main -Yes -ForceWsl
            $code | Should -Be 0

            $wslUpdateCalls = $script:RecordedCommands | Where-Object {
                $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
            }
            @($wslUpdateCalls).Count | Should -Be 1
        }

        It "deve executar wsl --update normalmente fora do WSL sem -ForceWsl" {
            $env:WSL_DISTRO_NAME = $null
            $code = Main -Yes
            $code | Should -Be 0

            $wslUpdateCalls = $script:RecordedCommands | Where-Object {
                $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
            }
            @($wslUpdateCalls).Count | Should -Be 1
        }
    }

    Context "CA-I: Terminal nao interativo sem -Yes (Fail-Closed)" {
        It "deve abortar com codigo 4 e nao aplicar nada se nao interativo e sem -Yes" {
            $script:MockIsInteractive = $false
            $code = Main
            $code | Should -Be 4

            $applyCalls = $script:RecordedCommands | Where-Object {
                ($_.FilePath -eq 'winget' -and $_.ArgumentList -contains '--all') -or
                ($_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update')
            }
            @($applyCalls).Count | Should -Be 0
        }
    }

    Context "CA-I: Confirmacao com padrao NAO" {
        It "deve cancelar com exit 4 se a resposta for vazia (enter)" {
            $script:MockConfirmation = ""
            $code = Main
            $code | Should -Be 4

            $applyCalls = $script:RecordedCommands | Where-Object {
                $_.ArgumentList -contains '--all'
            }
            @($applyCalls).Count | Should -Be 0
        }

        It "deve cancelar com exit 4 se a resposta for 'n', 'nao' ou texto desconhecido" {
            foreach ($resp in @("n", "N", "nao", "não", "cancelar", "random")) {
                $script:RecordedCommands.Clear()
                $script:MockConfirmation = $resp
                $code = Main
                $code | Should -Be 4
                $applyCalls = $script:RecordedCommands | Where-Object {
                    $_.ArgumentList -contains '--all'
                }
                @($applyCalls).Count | Should -Be 0
            }
        }

        It "deve aplicar e retornar exit 0 quando a resposta for afirmativa ('s', 'sim', 'y', 'yes')" {
            foreach ($resp in @("s", "S", "sim", "SIM", "y", "Y", "yes", "YES")) {
                $script:RecordedCommands.Clear()
                $script:MockConfirmation = $resp
                $code = Main
                $code | Should -Be 0
                $applyCalls = $script:RecordedCommands | Where-Object {
                    $_.FilePath -eq 'winget' -and $_.ArgumentList -contains '--all'
                }
                @($applyCalls).Count | Should -BeGreaterThan 0
            }
        }
    }

    Context "CA-I: Winget ausente no PATH" {
        It "deve sair com exit 3 e nao aplicar nada se winget nao estiver no PATH" {
            $script:MockCommandAvailable = $false
            $code = Main -Yes
            $code | Should -Be 3

            $script:RecordedCommands.Count | Should -Be 0
        }
    }

    Context "CA-J: Falha parcial e isolamento por passo" {
        It "deve continuar executando passos subsequentes se winget geral falhar e retornar exit 1" {
            $script:FailCommands.Add('winget-all')
            $env:WSL_DISTRO_NAME = $null
            $code = Main -Yes
            $code | Should -Be 1

            # winget geral falhou, mas Store e WSL ainda devem ter sido chamados
            $storeCalls = $script:RecordedCommands | Where-Object {
                $_.FilePath -eq 'winget' -and $_.ArgumentList -contains 'msstore'
            }
            $wslCalls = $script:RecordedCommands | Where-Object {
                $_.FilePath -eq 'wsl' -and $_.ArgumentList -contains '--update'
            }
            @($storeCalls).Count | Should -Be 1
            @($wslCalls).Count | Should -Be 1
        }
    }

    Context "CA-A: LogDir com espacos e caracteres especiais" {
        It "deve criar o arquivo de log no caminho com espacos e acentos" {
            $testDir = Join-Path $PSScriptRoot ".orq-mut-test-log-ca-a"
            $accentDir = Join-Path $testDir "Meu Log çá"
            try {
                $code = Main -DryRun -LogDir $accentDir
                $code | Should -Be 0

                Test-Path -LiteralPath $accentDir | Should -Be $true
                $logs = Get-ChildItem -LiteralPath $accentDir -Filter "update-windows-*.log"
                @($logs).Count | Should -BeGreaterThan 0
            } finally {
                if (Test-Path -LiteralPath $testDir) {
                    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "CA-C: Windows Update nunca instala" {
        It "deve apenas consultar atualizacoes e nunca invocar instalador" {
            $content = Get-Content -LiteralPath $sut -Raw
            # Verifica que o script nunca chama CreateUpdateInstaller ou Install
            $content -match 'CreateUpdateInstaller' | Should -Be $false
            $content -match '\.Install\(' | Should -Be $false
        }
    }

    Context "CA-J: Sem segredos no log" {
        It "nao deve vazar variaveis de ambiente sensiveis no arquivo de log" {
            $secretKey = "SECRET_TOKEN_SENTINEL_VAL_999"
            $env:SECRET_TOKEN_SENTINEL_VAL = $secretKey
            $testDir = Join-Path $PSScriptRoot ".orq-mut-test-log-secrets"
            try {
                $code = Main -DryRun -LogDir $testDir
                $code | Should -Be 0

                $logs = Get-ChildItem -LiteralPath $testDir -Filter "update-windows-*.log"
                @($logs).Count | Should -BeGreaterThan 0
                $logContent = Get-Content -LiteralPath $logs[0].FullName -Raw
                $logContent.Contains($secretKey) | Should -Be $false
            } finally {
                Remove-Item env:SECRET_TOKEN_SENTINEL_VAL -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $testDir) {
                    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Validacao de argumentos" {
        It "deve retornar codigo 2 para argumentos invalidos ou opcoes desconhecidas" {
            $code = Main -Invalido
            $code | Should -Be 2
        }

        It "deve exibir ajuda e retornar 0 para -Help" {
            $code = Main -Help
            $code | Should -Be 0
        }
    }

    Context "Flags de Skip" {
        It "deve respeitar -SkipWinget, -SkipStore e -SkipWsl" {
            $env:WSL_DISTRO_NAME = $null
            $code = Main -Yes -SkipWinget -SkipStore -SkipWsl
            $code | Should -Be 0

            $applyCalls = $script:RecordedCommands | Where-Object {
                $_.ArgumentList -contains '--all' -or $_.ArgumentList -contains '--update'
            }
            @($applyCalls).Count | Should -Be 0
        }
    }
}
