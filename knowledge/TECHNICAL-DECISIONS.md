# Decisões técnicas

## OpenCode no BigLinux/Arch

- O módulo `scripts/07-opencode.sh` usa `opencode-bin` e
  `opencode-desktop-bin` via AUR quando um helper (`yay` ou `paru`) está
  disponível. Essa é a integração preferencial para Arch/BigLinux, pois
  mantém o CLI e o Desktop atualizáveis pelo gerenciador nativo.
- O Desktop **não** usa AppImage: o fallback AppImage foi removido do módulo
  por preferência do usuário ("não gosto de AppImage"). O Desktop só é
  instalado pelo pacote AUR `opencode-desktop-bin` (reempacota o `.deb`
  oficial e roda no `electron44` do sistema); sem helper AUR, o módulo aborta
  com erro explícito em vez de instalar um AppImage solto.
- O único fallback restante é o do **CLI**: quando a instalação AUR não
  consegue elevar privilégios, o módulo usa o instalador oficial no perfil do
  usuário (`~/.opencode`), evitando exigir senha ou alterar pacotes do sistema
  em sessões sem TTY.
- **Pitfalls medidos (08/10/2026)**: o pacote AUR `opencode-desktop-bin` não
  tem `electron44` nos repos oficiais (param no `electron43`) e resolve via
  `electron44-bin` (AUR, `provides=electron44`). Um symlink quebrado em
  `~/.local/bin/opencode-desktop` **sombreia** o binário real
  `/usr/bin/opencode-desktop` (o `~/.local/bin` vem antes no PATH). O
  AppImageLauncher **consome/move** um AppImage quando ele é executado. Na GPU
  híbrida (Intel HD 4000 + GT 740M/Bumblebee) o app sobe no render
  Intel/software; avisos `NV-GLX missing` e `Ivy Bridge Vulkan incompleto` são
  benignos, e os wrappers de render do BigLinux (`SoftwareRender`,
  `NvidiaRender`, `IntegratedRender`) seguem disponíveis nas ações do
  `.desktop`.

## Cursor IDE no BigLinux/Arch

- **Integração via AUR (`cursor-bin`)**: O pacote oficial mantido pela comunidade AUR (`cursor-bin`) foi adotado por desacoplar o runtime Electron do pacote `.deb` original da Cursor e reutilizar o pacote binário `electron42` do repositório `extra` do Arch/BigLinux. Isso reduz o tempo de instalação a zero compilação, economiza espaço e unifica as atualizações ao gerenciador do sistema (`yay` / `pacman`).
- **Compartilhamento de Dotfiles (`settings.json`)**: O Cursor mantém total compatibilidade estrutural com as configurações do VS Code em `~/.config/Cursor/User/settings.json`. Em vez de duplicar arquivos, o módulo `scripts/05-dotfiles-sync.sh` cria symlink direto para `configs/vscode/settings.json`, mantendo fontes (`JetBrains Mono`, `Fira Code`), ligaturas tipográficas, auto-formatação e tema sincronizados.
- **Resiliência em Scripts de Diagnóstico (`check-environment.sh`)**: Em ambientes com `set -euo pipefail`, comandos de inspeção de versão (`eval "$version_cmd" | head -n 1`) que retornam saída com código não-zero (ou binários quebrados) abortam o diagnóstico. O padrão adotado e consolidado é envolver o eval de versão em subshell tolerante a falhas: `ver=$( (eval "$version_cmd" 2>&1 || true) | head -n 1 )`.

## Atalhos do KDE Plasma (Visão Geral / KGlobalAccel)

- **Decisão (10/10/2026)**: manter o **padrão do KDE** — a **Visão Geral** (efeito KWin
  "Overview", o equivalente ao "Activities" do GNOME) fica em **`Super+W`**, e a **`Super`
  sozinha** abre o **Lançador de Aplicativos** (`Meta` + `Alt+F1`). **Não** perseguir a
  "`Super` sozinha" ("modifier-only") para a Visão Geral nesta máquina.
- **Medição**: no **KDE Plasma 6.7.4 em sessão X11** (BigLinux), a `Super` sozinha **não** dispara
  a Visão Geral. Registrar o atalho via KGlobalAccel **funciona** (o daemon passa a listar `Meta`
  como atalho de `Overview`), mas o "tap" do modificador **não é honrado** — a seta do mouse some
  e nada acontece. Persistiu mesmo após reiniciar o `plasma-kglobalaccel.service`. O ícone/widget
  do painel ("Visão Geral das Atividades") funciona normalmente.
- **Alterar atalhos por CLI (referência)**: o caminho oficial é o DBus `org.kde.kglobalaccel`
  (o daemon regrava o `~/.config/kglobalshortcutsrc`). Usar **`gdbus`**, **não** `qdbus6`
  (o `qdbus6` falha com `Invalid number of parameters` em métodos que recebem `QStringList`):
  ```bash
  # actionId = [componente, ação, componente_amigável, ação_amigável]
  gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
    --method org.kde.KGlobalAccel.setForeignShortcut \
    "['kwin','Overview','kwin','Alternar para visão geral']" "[268435543]"
  ```
  Códigos de `QKeySequence`: `Meta` = `16777250`, `Meta+W` = `268435543`, `Alt+F1` = `150994992`.
- **Pitfall medido**: `setForeignShortcut` **falha em silêncio** quando a tecla ainda pertence a
  outra ação. Atribuir um modificador a uma nova ação exige **primeiro removê-lo** da ação antiga
  (ex.: tirar `Meta` da Visão Geral antes de devolvê-lo ao Lançador); senão a mudança não aplica.
- **Backup obrigatório** de `~/.config/kglobalshortcutsrc` antes de qualquer alteração.
- No **Plasma ≥ 6.1** atalhos de "modificador sozinho" vivem no `kglobalshortcutsrc`; a antiga
  seção `[ModifierOnlyShortcuts]` do `kwinrc` foi abandonada (ignorada).

