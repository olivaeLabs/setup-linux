# update-windows.ps1

Atualizador do sistema Windows e equivalente nativo do script `update-all.sh` (comando `update` no ambiente WSL/Linux).

Apresenta o **PLANO** completo de atualizações em modo somente leitura e solicita confirmação explícita do operador antes de realizar qualquer alteração no sistema.

---

## O que faz

1. **Pré-checagens**:
   - Valida a presença do `winget` no PATH (se ausente, encerra com código `3`).
   - Verifica privilégios de Administrador (emite aviso de conveniência caso não elevado; winget pode solicitar elevação via UAC).
2. **Apresentação do PLANO (somente leitura)**:
   - Lista pacotes com atualização disponível via `winget upgrade --include-unknown`.
   - Consulta atualizações pendentes do Windows Update via COM `Microsoft.Update.Session` (`IsInstalled=0 and IsHidden=0`, somente títulos). **Nunca instala atualizações do Windows Update** (puramente informativo).
   - Verifica flags de reinício pendente no registro (`RebootRequired`, `PendingFileRenameOperations`).
   - Exibe a versão instalada do WSL (`wsl --version`).
3. **Confirmação**:
   - Pergunta `Aplicar? [s/N]` (padrão **NÃO**; respostas afirmativas aceitas: `s`, `sim`, `y`, `yes`).
   - Em ambiente não interativo sem a flag `-Yes`, cancela a execução imediatamente (**fail-closed**, código `4`).
4. **Aplicação com isolamento por passos**:
   - `winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements --silent`.
   - Microsoft Store: `winget upgrade --source msstore --all --accept-package-agreements --accept-source-agreements`.
   - Subsistema Linux: `wsl --update` (com trava de segurança: se executado dentro de uma sessão WSL ativa, o passo é pulado automaticamente para não derrubar a própria sessão, a menos que `-ForceWsl` seja informado).
5. **Log seguro**:
   - Grava cada etapa com horário de início, término e código de saída em arquivo UTF-8 (`update-windows-AAAAMMDD-HHMMSS.log`).
   - **Sem vazamento de segredos**: não registra variáveis de ambiente ou credenciais no log.

---

## Parâmetros

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `-Yes` | Switch | Executa as atualizações sem solicitar confirmação interativa. |
| `-DryRun` | Switch | Modo simulação: exibe o plano detalhado e finaliza sem aplicar nada (exit 0). **Prevalece sobre `-Yes`**. |
| `-SkipWsl` | Switch | Pula a verificação e atualização do WSL (`wsl --update`). |
| `-SkipStore` | Switch | Pula a atualização de pacotes da Microsoft Store (`winget --source msstore`). |
| `-SkipWinget` | Switch | Pula a atualização geral de pacotes do winget. |
| `-ForceWsl` | Switch | Força a execução de `wsl --update` mesmo se detectada execução de dentro de uma sessão WSL ativa. |
| `-LogDir` | String | Diretório onde os arquivos de log serão gravados (padrão: `%LOCALAPPDATA%\update-windows\`). |
| `-Help` | Switch | Exibe a mensagem de ajuda com os parâmetros suportados. |

---

## Códigos de Saída (Exit Codes)

- **`0`**: Sucesso total de todos os passos executados, ou execução finalizada em modo `-DryRun`.
- **`1`**: Falha em um ou mais passos de atualização (o resumo final lista o status de cada passo e erros).
- **`2`**: Argumento inválido ou opção desconhecida informada na linha de comando.
- **`3`**: Executável `winget` não encontrado no PATH do sistema.
- **`4`**: Cancelado pelo operador na confirmação, ou execução em terminal não interativo sem `-Yes`.

---

## Configuração do Atalho no Perfil do PowerShell (`$PROFILE`)

Para utilizar o comando `update-windows` diretamente em qualquer janela do PowerShell, adicione a função abaixo ao seu perfil de usuário (o repositório não altera seu perfil automaticamente):

1. Abra o arquivo de perfil no seu editor preferido:
   ```powershell
   notepad $PROFILE
   ```
2. Adicione a seguinte definição:
   ```powershell
   function update-windows {
       & "$HOME\Projetos\setup-linux\scripts\update-windows.ps1" @args
   }
   ```
   *(Ajuste o caminho caso seu clone do repositório esteja em outro diretório).*

3. Salve o arquivo e recarregue o perfil no terminal ativo:
   ```powershell
   . $PROFILE
   ```

---

## Execução dos Testes

- **Suíte Autônoma (sem Pester)**:
  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\update-windows.selftest.ps1
  ```
- **Suíte Pester**:
  ```powershell
  Invoke-Pester -Path scripts\update-windows.Tests.ps1
  ```
