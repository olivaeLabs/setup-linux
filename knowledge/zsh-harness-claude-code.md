# zsh previsível dentro do Claude Code (22/10/2026)

**Problema:** o Claude Code executa cada comando num `zsh` e quatro regras do zsh que o bash não tem quebravam comandos de agente: (1) `$var` não separa em palavras (`go test $pkgs` virava um argumento só); (2) `ls` é alias do `eza --icons`; (3) `==` expande como caminho de comando; (4) glob sem resultado dá erro `no matches found`.

**Solução (opção A do dono):** bloco no FIM de `configs/zsh/.zshrc`, ativo só quando `CLAUDECODE=1` (o Claude Code exporta): `unalias -a`, `setopt sh_word_split`, `unsetopt nomatch`, `unsetopt equals`. O terminal pessoal NÃO muda (mantém aliases, plugins, starship, fzf, zoxide).

**Verificação (22/10):** com `CLAUDECODE=1`, `$pk="a b c"` ⇒ 3 palavras, `alias ls` ⇒ nenhum, glob vazio e `==` literais; sem `CLAUDECODE` ⇒ 1 palavra e `ls='eza --icons'`.

**Vale só para sessões NOVAS** do Claude Code (o harness grava um snapshot do shell ao abrir a sessão).

**Propagar para outra máquina (ex.: notebook):** o `~/.zshrc` é symlink para este arquivo; basta `git -C ~/Projetos/setup-linux pull`. Se o `~/.zshrc` ainda não for symlink: `bash ~/Projetos/setup-linux/scripts/05-dotfiles-sync.sh`. Regra do workspace: edição só no ambiente de origem; o outro só faz `git pull`.

**Alternativa descartada (por ora):** trocar o shell de login para bash com `ble.sh`, starship, fzf, zoxide, eza e bat (paridade ~95 %, mas um componente a mais e perda do completador do zsh). Fica como plano B.
