#!/usr/bin/env bash
# Fonctions communes GCRV

GCRV_HOME="${GCRV_HOME:-$HOME/.gcrv}"
SERVICES_DB="$GCRV_HOME/services.db"   # nom|region|path|host|memoire|min_instances
USERS_DB="$GCRV_HOME/users.db"         # service|utilisateur|uuid|expiration (YYYY-MM-DD ou never)
CONF="$GCRV_HOME/settings.conf"
mkdir -p "$GCRV_HOME"; touch "$SERVICES_DB" "$USERS_DB"

# Valeurs par defaut (modifiables via le menu Parametres)
FRONT_IP="192.179.18.100"
SNI="crashlyticsreports-pa.googleapis.com"
DEFAULT_REGION="europe-west4"
MAX_USERS=50
MAX_INSTANCES=5
[ -f "$CONF" ] && . "$CONF"

if [ -t 1 ]; then
  G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; C='\033[1;36m'; N='\033[0m'
else
  G=''; R=''; Y=''; C=''; N=''
fi
ok()   { echo -e "${G}[OK]${N} $*"; }
err()  { echo -e "${R}[ERREUR]${N} $*" >&2; }
warn() { echo -e "${Y}[!]${N} $*"; }
ask()  { local v; read -rp "$1 [$2] : " v; echo "${v:-$2}"; }

new_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen; }
valid_name() { [[ "$1" =~ ^[a-z][a-z0-9-]{0,29}$ ]]; }
valid_user() { [[ "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; }

save_conf() {
  cat > "$CONF" <<EOT
FRONT_IP="$FRONT_IP"
SNI="$SNI"
DEFAULT_REGION="$DEFAULT_REGION"
MAX_USERS=$MAX_USERS
MAX_INSTANCES=$MAX_INSTANCES
EOT
}

# make_link <label> <uuid> <path> <host>
make_link() {
  local epath
  epath=$(printf '%s' "$3" | sed 's#/#%2F#g')
  echo "vless://$2@${FRONT_IP}:443?path=${epath}&security=tls&encryption=none&host=$4&type=ws&allowInsecure=1&sni=${SNI}#$1"
}
