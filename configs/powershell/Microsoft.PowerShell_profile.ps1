# ==============================================================================
# Modern PowerShell Developer Profile - Fast, Visual & Intelligent
# Setup Imortal / Windows & WSL Cross-Platform
# ==============================================================================

# 1. Universal UTF-8 Encoding
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 2. PATHs & Tooling Runtimes
$devPaths = @(
    "$HOME\.local\bin",
    "$HOME\go\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
    "$HOME\AppData\Local\agy\bin",
    "$HOME\AppData\Local\JetBrains\Toolbox\scripts",
    "$HOME\AppData\Local\Programs\Microsoft VS Code\bin",
    "C:\Program Files\Microsoft VS Code\bin"
)
foreach ($path in $devPaths) {
    if ((Test-Path $path) -and ($env:Path -notlike "*$path*")) {
        $env:Path = "$path;$env:Path"
    }
}

# 3. Advanced PSReadLine Configuration (Auto-Suggestions & Predictive IntelliSense)
if (Get-Module -ListAvailable PSReadLine) {
    try {
        Import-Module PSReadLine
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
        Set-PSReadLineOption -EditMode Windows -ErrorAction SilentlyContinue
        
        # Colors for Predictive Syntax
        Set-PSReadLineOption -Colors @{
            InlinePrediction = "`e[38;5;242m"
            Command          = "`e[96m"
            Parameter        = "`e[90m"
            String           = "`e[92m"
            Number           = "`e[93m"
        } -ErrorAction SilentlyContinue

        # Keybindings: Up/Down arrow filters typed history, Tab menu completion
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
        
        # F2 Switcher: Alterna dinamicamente entre InlineView (ghost text) e ListView (menu suspenso)
        Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView -ErrorAction SilentlyContinue
    } catch {
        # Fallback silencioso para sessões não-interativas
    }
}

# 4. Terminal-Icons (Ícones contextuais para arquivos e pastas)
if (Get-Module -ListAvailable Terminal-Icons) {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}

# 5. PSFzf (Fuzzy Search com Ctrl+R e Ctrl+T)
if ((Get-Module -ListAvailable PSFzf) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineKeyBindings @{
        "Ctrl+r" = "History"
        "Ctrl+t" = "File"
    } -ErrorAction SilentlyContinue
}

# 6. Zoxide (Navegação Inteligente com 'z')
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# 7. Starship Prompt (Rust)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# 8. Aliases Modernos de Produtividade (CLI Tooling)
# Eza (ls moderno com ícones e status git)
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function List-Files { eza --icons --group-directories-first $args }
    function List-AllFiles { eza -la --icons --git --group-directories-first $args }
    function List-Tree { eza --tree --level=2 --icons --group-directories-first $args }
    Set-Alias -Name ls -Value List-Files -Option AllScope -Force
    Set-Alias -Name ll -Value List-AllFiles -Option AllScope -Force
    Set-Alias -Name lt -Value List-Tree -Option AllScope -Force
}

# Bat (cat moderno com syntax highlighting)
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias -Name cat -Value bat -Option AllScope -Force
}

# Ripgrep
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias -Name grep -Value rg -Option AllScope -Force
}

# 9. Atalhos Git
function git-status-short { git status -sb $args }
function git-log-graph { git log --oneline --graph --decorate -n 15 $args }
function git-diff-all { git diff $args }
function git-commit-msg { git commit -m $args }
function git-commit-amend { git commit --amend $args }
function git-push-origin { git push $args }
function git-pull-rebase { git pull --rebase $args }

Set-Alias -Name gs -Value git-status-short -Option AllScope -Force
Set-Alias -Name gl -Value git-log-graph -Option AllScope -Force
Set-Alias -Name gd -Value git-diff-all -Option AllScope -Force
Set-Alias -Name gc -Value git-commit-msg -Option AllScope -Force
Set-Alias -Name gca -Value git-commit-amend -Option AllScope -Force
Set-Alias -Name gp -Value git-push-origin -Option AllScope -Force
Set-Alias -Name gpl -Value git-pull-rebase -Option AllScope -Force

# Kubernetes
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Set-Alias -Name k -Value kubectl -Option AllScope -Force
}

# 10. Navegação e Integração Ágil com WSL2
function Go-To-WslWorkspace {
    Set-Location "\\wsl.localhost\Arch\home\marcos\Projetos"
}
function Go-To-WinWorkspace {
    Set-Location "C:\Users\marco\Projetos"
}
function Enter-ArchWSL {
    wsl -d Arch
}

Set-Alias -Name proj -Value Go-To-WslWorkspace -Option AllScope -Force
Set-Alias -Name proj-wsl -Value Go-To-WslWorkspace -Option AllScope -Force
Set-Alias -Name proj-win -Value Go-To-WinWorkspace -Option AllScope -Force
Set-Alias -Name arch -Value Enter-ArchWSL -Option AllScope -Force
Set-Alias -Name wsl-arch -Value Enter-ArchWSL -Option AllScope -Force

# 11. Funções Utilitárias
function mkcd ($dir) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Location $dir
}

function touch ($file) {
    if (-not (Test-Path $file)) {
        New-Item -ItemType File -Path $file -Force | Out-Null
    } else {
        (Get-Item $file).LastWriteTime = Get-Date
    }
}

function which ($cmd) {
    Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function reload-profile {
    & $PROFILE
    Write-Host "✔ Perfil do PowerShell recarregado com sucesso!" -ForegroundColor Green
}
