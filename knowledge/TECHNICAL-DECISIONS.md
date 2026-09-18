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
