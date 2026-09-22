# SECURITY-TODO — higiene pendente

Stack: **shell**
Referência aplicada: `browser-harness-go` (CI + CodeQL + Dependabot + SECURITY.md + govulncheck).
Inventário e checklist completo: `tasks/WORKSPACE-SECURITY-HYGIENE/README.md`.

- [ ] `shellcheck` nos scripts (CI ou pre-commit)
- [ ] CI mínima: `bash -n` + `shellcheck`
- [ ] `SECURITY.md` mínimo
- [ ] (Aplicado em 2026-09-22: `check-environment.sh` e `00-system-init.sh` já checam/instalam ferramentas de higiene)
