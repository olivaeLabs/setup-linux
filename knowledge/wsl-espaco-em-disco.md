# WSL — espaço em disco (medido em 23/10/2026)

- O `ext4.vhdx` só cresce: apagar dentro do Linux **não** devolve espaço ao C:. É preciso compactar (`fstrim` → `wsl --shutdown` → `Optimize-VHD -Mode Full`, admin).
- **Evitar `wsl --manage --set-sparse true`**: o WSL o declara experimental com risco de corrupção do disco.
- Maiores ganhos medidos: `cargo clean` de projetos Rust (8,8 GB), imagens/volumes Docker órfãos (~8 GB), cópias `*-mut` e `judge-cwd/.orq` em `tasks/` (4,7 GB), `/swapfile` 16 → 6 GB (10 GB; RAM de 32 GB).
- Docker: nunca `volume prune` às cegas; listar volumes e proteger `anubis-mongo-*`, `mongo-ci-*`, `openclaw-state`. `rmi` sem `-f` recusa imagem em uso.
- Windows: pagefile gerenciado pelo sistema (~18 GB) pode cair para 4–8 GB com 48 GB de RAM (admin + reinício). OneDrive aparente ≠ disco usado (Files On-Demand).
- Rotina sugerida (mensal, com OK do dono): `orphan-reaper tmp-clean`, `ci-disk-guard`, `docker image prune`, compactação do vhdx.
- Detalhes: `Projetos/tasks/LIMPEZA-DISCO-2026-10-23/RELATORIO.md`.
