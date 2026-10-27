#!/usr/bin/env bash
# GCRV installer - installe depuis GitHub ou depuis une copie locale
# Depot officiel du projet : https://github.com/ILYASSETOM55/GC
set -euo pipefail

REPO_URL="https://github.com/ILYASSETOM55/GC.git"
RAW_BASE="https://raw.githubusercontent.com/ILYASSETOM55/GC/main"
INSTALL_DIR="/opt/gcrv"
TMP_DIR=""

[ "$(id -u)" -eq 0 ] || { echo "Lance ce script en root (sudo bash install.sh)"; exit 1; }

cleanup() { [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

log() { echo "[GCRV] $*"; }

# Si install.sh est lance depuis le depot, on utilise les fichiers locaux.
SRC="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SRC/gcrv" ] && [ -d "$SRC/lib" ] && [ -d "$SRC/templates" ]; then
  log "Sources locales detectees : $SRC"
else
  # Installation distante : telecharge le depot GitHub complet.
  TMP_DIR="$(mktemp -d)"
  SRC="$TMP_DIR/gcrv"
  mkdir -p "$SRC"

  log "Telechargement du projet depuis GitHub..."
  if command -v git >/dev/null 2>&1; then
    if git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo" >/dev/null 2>&1; then
      SRC="$TMP_DIR/repo"
    fi
  fi

  # Fallback sans git : archive ZIP GitHub.
  if [ ! -f "$SRC/gcrv" ] || [ ! -d "$SRC/lib" ]; then
    rm -rf "$SRC"
    mkdir -p "$SRC"
    ARCHIVE="$TMP_DIR/gcrv.zip"
    curl -fL --retry 3 --connect-timeout 15 "https://github.com/ILYASSETOM55/GC/archive/refs/heads/main.zip" -o "$ARCHIVE"
    command -v unzip >/dev/null 2>&1 || apt-get update -y && apt-get install -y unzip
    unzip -q "$ARCHIVE" -d "$TMP_DIR/unpacked"
    ROOT="$(find "$TMP_DIR/unpacked" -maxdepth 1 -type d -name 'GC-*' | head -n 1)"
    [ -n "$ROOT" ] || { echo "[ERREUR] Archive GitHub invalide."; exit 1; }
    SRC="$ROOT"
  fi
fi

for required in gcrv lib/common.sh lib/gcloud.sh lib/services.sh lib/users.sh templates/Dockerfile; do
  [ -e "$SRC/$required" ] || { echo "[ERREUR] Fichier manquant dans le dépôt : $required"; exit 1; }
done

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl python3 cron unzip >/dev/null 2>&1 || true

mkdir -p "$INSTALL_DIR"

# Sauvegarde des données locales avant mise à jour.
if [ -d "$INSTALL_DIR" ]; then
  mkdir -p /root/gcrv-backup
  cp -a "$INSTALL_DIR"/. /root/gcrv-backup/ 2>/dev/null || true
fi

# Remplace uniquement les fichiers du programme. Les données utilisateur sont dans ~/.gcrv.
rm -rf "$INSTALL_DIR/lib" "$INSTALL_DIR/templates" "$INSTALL_DIR/bot"
cp -f "$SRC/gcrv" "$INSTALL_DIR/gcrv"
cp -a "$SRC/lib" "$SRC/templates" "$INSTALL_DIR/"
[ -d "$SRC/bot" ] && cp -a "$SRC/bot" "$INSTALL_DIR/"
[ -f "$SRC/README.md" ] && cp -f "$SRC/README.md" "$INSTALL_DIR/README.md"
chmod +x "$INSTALL_DIR/gcrv"
[ -f "$INSTALL_DIR/bot/bot.py" ] && chmod +x "$INSTALL_DIR/bot/bot.py"
ln -sfn "$INSTALL_DIR/gcrv" /usr/local/bin/gcrv

# Petit fichier d'information pour les mises a jour.
cat > "$INSTALL_DIR/update.sh" <<'UPDATE'
#!/usr/bin/env bash
set -euo pipefail
REPO_URL="https://github.com/ILYASSETOM55/GC.git"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if command -v git >/dev/null 2>&1; then
  git clone --depth 1 "$REPO_URL" "$TMP/repo" >/dev/null 2>&1 || true
fi
if [ ! -f "$TMP/repo/install.sh" ]; then
  echo "[ERREUR] Impossible de telecharger le depot GitHub."; exit 1
fi
bash "$TMP/repo/install.sh"
UPDATE
chmod +x "$INSTALL_DIR/update.sh"

log "GCRV installe/mis a jour dans $INSTALL_DIR"
echo "Commande : gcrv"
echo "Mise a jour : sudo bash $INSTALL_DIR/update.sh"
echo "Depot : $REPO_URL"

auto_bot="N"
read -rp "Installer le bot Telegram ? (o/N) " auto_bot || true
if [[ "$auto_bot" =~ ^[oOyY]$ ]] && [ -d "$INSTALL_DIR/bot" ]; then
  read -rp "Token du bot : " tok
  read -rp "Ton ID Telegram (admin) : " adm
  printf 'BOT_TOKEN=%s\nADMIN_ID=%s\nGCRV_BIN=/usr/local/bin/gcrv\n' "$tok" "$adm" > "$INSTALL_DIR/bot/.env"
  chmod 600 "$INSTALL_DIR/bot/.env"
  cp "$INSTALL_DIR/bot/gcrv-bot.service" /etc/systemd/system/gcrv-bot.service
  systemctl daemon-reload
  systemctl enable --now gcrv-bot
  echo "[OK] Bot demarre (systemctl status gcrv-bot)"
fi
