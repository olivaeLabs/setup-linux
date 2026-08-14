#!/usr/bin/env bash
# ==============================================================================
# Script: 06-webapps.sh
# Descrição: Instalação e priorização de WebApps (BigLinux WebApps / PWA)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$ROOT_DIR/configs"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "06 - WebApps e PWAs (Priorizados sobre Apps Desktop)"

WEBAPPS_JSON="$CONFIGS_DIR/webapps/webapps.json"
ICONS_DIR="$CONFIGS_DIR/webapps/icons"
TARGET_APPS_DIR="$HOME/.local/share/applications"
TARGET_CACHE_ICONS="$HOME/.cache/biglinux-webapps/favicons"

mkdir -p "$TARGET_APPS_DIR" "$TARGET_CACHE_ICONS"

# Copia ícones customizados
if [ -d "$ICONS_DIR" ]; then
    log_info "Copiando ícones de WebApps..."
    cp -r "$ICONS_DIR"/* "$TARGET_CACHE_ICONS/" 2>/dev/null || true
fi

if [ -f "$WEBAPPS_JSON" ] && command -v jq &>/dev/null; then
    log_info "Instalando WebApps registrados a partir de configs/webapps/webapps.json..."

    TOTAL_WEBAPPS=$(jq '. | length' "$WEBAPPS_JSON")

    for ((i = 0; i < TOTAL_WEBAPPS; i++)); do
        APP_NAME=$(jq -r ".[$i].app_name" "$WEBAPPS_JSON")
        APP_URL=$(jq -r ".[$i].app_url" "$WEBAPPS_JSON")
        APP_FILE=$(jq -r ".[$i].app_file" "$WEBAPPS_JSON")
        APP_ICON=$(jq -r ".[$i].app_icon" "$WEBAPPS_JSON")
        BROWSER=$(jq -r ".[$i].browser" "$WEBAPPS_JSON")
        PROFILE=$(jq -r ".[$i].app_profile // \"Browser\"" "$WEBAPPS_JSON")

        # Se o nome do arquivo for inválido ou '-', gera um nome amigável
        if [ "$APP_FILE" = "-__-Default.desktop" ] || [ -z "$APP_FILE" ]; then
            CLEAN_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            APP_FILE="webapp-${CLEAN_NAME}.desktop"
        fi

        # Garante fallback de navegador disponível
        if ! command -v "$BROWSER" &>/dev/null; then
            if command -v google-chrome-stable &>/dev/null; then
                BROWSER="google-chrome-stable"
            elif command -v google-chrome &>/dev/null; then
                BROWSER="google-chrome"
            elif command -v brave &>/dev/null; then
                BROWSER="brave"
            elif command -v chromium &>/dev/null; then
                BROWSER="chromium"
            fi
        fi

        DEST_DESKTOP="$TARGET_APPS_DIR/$APP_FILE"

        # Extrai classe/domínio
        DOMAIN=$(echo "$APP_URL" | awk -F[/:] '{print $4}')

        cat << EOF > "$DEST_DESKTOP"
[Desktop Entry]
Version=1.0
Terminal=false
Type=Application
Name=$APP_NAME
Exec=big-webapps-exec filename="$APP_FILE" $BROWSER --class="$DOMAIN" --profile-directory=$PROFILE --app="$APP_URL"
Icon=$APP_ICON
StartupWMClass=$DOMAIN
Categories=Webapps;Network;
StartupNotify=false

Actions=SoftwareRender;NvidiaRender;IntegratedRender;

[Desktop Action SoftwareRender]
Name=Software Render
Exec=SoftwareRender big-webapps-exec filename="$APP_FILE" $BROWSER --class="$DOMAIN" --profile-directory=$PROFILE --app="$APP_URL"

[Desktop Action NvidiaRender]
Name=Nvidia Render
Exec=NvidiaRender big-webapps-exec filename="$APP_FILE" $BROWSER --class="$DOMAIN" --profile-directory=$PROFILE --app="$APP_URL"

[Desktop Action IntegratedRender]
Name=Integrated Render
Exec=IntegratedRender big-webapps-exec filename="$APP_FILE" $BROWSER --class="$DOMAIN" --profile-directory=$PROFILE --app="$APP_URL"
EOF
        chmod +x "$DEST_DESKTOP"
        log_success "WebApp configurado: $APP_NAME ($APP_URL)"
    done
else
    log_warn "Arquivo $WEBAPPS_JSON não encontrado ou jq ausente."
fi

log_success "Etapa 06 (WebApps) concluída com sucesso!"
