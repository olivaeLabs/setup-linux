# Decisões técnicas

## OpenCode no BigLinux/Arch

- O módulo `scripts/07-opencode.sh` usa `opencode-bin` e
  `opencode-desktop-bin` via AUR quando um helper (`yay` ou `paru`) está
  disponível. Essa é a integração preferencial para Arch/BigLinux, pois
  mantém o CLI e o Desktop atualizáveis pelo gerenciador nativo.
- Quando a instalação AUR não consegue elevar privilégios, o módulo usa o
  instalador oficial do CLI no perfil do usuário e o AppImage oficial do
  Desktop. O AppImage é baixado da release atual, validado pelo SHA-256
  publicado pela API do GitHub e registrado como aplicativo `.desktop` local.
- Os fallbacks são deliberadamente instalados em `~/.opencode` e
  `~/.local`, evitando exigir senha ou alterar pacotes do sistema em sessões
  sem TTY. O caminho AUR continua sendo escolhido automaticamente em uma
  execução normal com privilégios disponíveis.

## Cursor IDE no BigLinux/Arch

- **Integração via AUR (`cursor-bin`)**: O pacote oficial mantido pela comunidade AUR (`cursor-bin`) foi adotado por desacoplar o runtime Electron do pacote `.deb` original da Cursor e reutilizar o pacote binário `electron42` do repositório `extra` do Arch/BigLinux. Isso reduz o tempo de instalação a zero compilação, economiza espaço e unifica as atualizações ao gerenciador do sistema (`yay` / `pacman`).
- **Compartilhamento de Dotfiles (`settings.json`)**: O Cursor mantém total compatibilidade estrutural com as configurações do VS Code em `~/.config/Cursor/User/settings.json`. Em vez de duplicar arquivos, o módulo `scripts/05-dotfiles-sync.sh` cria symlink direto para `configs/vscode/settings.json`, mantendo fontes (`JetBrains Mono`, `Fira Code`), ligaturas tipográficas, auto-formatação e tema sincronizados.
- **Resiliência em Scripts de Diagnóstico (`check-environment.sh`)**: Em ambientes com `set -euo pipefail`, comandos de inspeção de versão (`eval "$version_cmd" | head -n 1`) que retornam saída com código não-zero (ou binários quebrados) abortam o diagnóstico. O padrão adotado e consolidado é envolver o eval de versão em subshell tolerante a falhas: `ver=$( (eval "$version_cmd" 2>&1 || true) | head -n 1 )`.

