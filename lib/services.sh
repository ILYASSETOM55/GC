#!/usr/bin/env bash
# Gestion des services Cloud Run

svc_line()  { grep -m1 "^$1|" "$SERVICES_DB"; }
svc_field() { svc_line "$1" | cut -d'|' -f"$2"; }   # 2=region 3=path 4=host 5=mem 6=minst
svc_exists(){ [ -n "$(svc_line "$1")" ]; }
svc_set_host() {
  awk -F'|' -v OFS='|' -v n="$1" -v h="$2" '$1==n{$4=h}1' "$SERVICES_DB" > "$SERVICES_DB.tmp" \
    && mv "$SERVICES_DB.tmp" "$SERVICES_DB"
}

# Genere le dossier de build (config.json depuis users.db + Dockerfile)
render_build() {
  local svc="$1" path dir clients="" sep="" s user uuid exp
  path=$(svc_field "$svc" 3)
  dir=$(mktemp -d)
  while IFS='|' read -r s user uuid exp; do
    [ "$s" = "$svc" ] || continue
    clients+="${sep}{\"id\":\"$uuid\",\"email\":\"$user@$svc\"}"
    sep=","
  done < "$USERS_DB"
  cat > "$dir/config.json" <<EOT
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 8080,
    "protocol": "vless",
    "settings": {"clients": [$clients], "decryption": "none"},
    "streamSettings": {"network": "ws", "wsSettings": {"path": "$path"}}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOT
  cp "$GCRV_ROOT/templates/Dockerfile" "$dir/Dockerfile"
  echo "$dir"
}

# (Re)deploie un service avec la liste d'utilisateurs actuelle
deploy_service() {
  local svc="$1" region mem minst dir host
  region=$(svc_field "$svc" 2); mem=$(svc_field "$svc" 5); minst=$(svc_field "$svc" 6)
  dir=$(render_build "$svc")
  echo "Deploiement de '$svc' sur Cloud Run (2-4 min)..."
  if gcloud run deploy "$svc" --source "$dir" --region "$region" \
      --port 8080 --allow-unauthenticated --timeout 3600 \
      --memory "$mem" --cpu 1 --min-instances "$minst" --max-instances "$MAX_INSTANCES" \
      --execution-environment gen2 --quiet > "$GCRV_HOME/deploy.log" 2>&1; then
    host=$(gcloud run services describe "$svc" --region "$region" --format='value(status.url)' | sed 's#https://##')
    svc_set_host "$svc" "$host"
    rm -rf "$dir"
    return 0
  fi
  err "Deploiement echoue. Fin du journal :"
  tail -n 15 "$GCRV_HOME/deploy.log" >&2
  rm -rf "$dir"
  return 1
}

# svc_create <nom> [region] [path] [memoire] [min_instances]
svc_create() {
  local name="$1" region="${2:-$DEFAULT_REGION}" path="${3:-/vless_$1}" mem="${4:-512Mi}" minst="${5:-0}"
  valid_name "$name" || { err "Nom invalide (minuscules, chiffres, tirets, commence par une lettre)"; return 1; }
  svc_exists "$name" && { err "Le service '$name' existe deja"; return 1; }
  [[ "$path" == /* ]] || path="/$path"
  [[ "$minst" =~ ^[0-9]+$ ]] || { err "min_instances invalide"; return 1; }
  require_gcloud || return 1

  local uuid; uuid=$(new_uuid)
  echo "$name|$region|$path||$mem|$minst" >> "$SERVICES_DB"
  echo "$name|default|$uuid|never" >> "$USERS_DB"
  if deploy_service "$name"; then
    ok "Service '$name' cree : $(svc_field "$name" 4)"
    echo
    make_link "$name-default" "$uuid" "$path" "$(svc_field "$name" 4)"
  else
    grep -v "^$name|" "$SERVICES_DB" > "$SERVICES_DB.tmp"; mv "$SERVICES_DB.tmp" "$SERVICES_DB"
    grep -v "^$name|" "$USERS_DB" > "$USERS_DB.tmp"; mv "$USERS_DB.tmp" "$USERS_DB"
    return 1
  fi
}

svc_delete() {
  local name="$1" region
  svc_exists "$name" || { err "Service '$name' introuvable"; return 1; }
  require_gcloud || return 1
  region=$(svc_field "$name" 2)
  if gcloud run services delete "$name" --region "$region" --quiet; then
    grep -v "^$name|" "$SERVICES_DB" > "$SERVICES_DB.tmp"; mv "$SERVICES_DB.tmp" "$SERVICES_DB"
    grep -v "^$name|" "$USERS_DB" > "$USERS_DB.tmp"; mv "$USERS_DB.tmp" "$USERS_DB"
    ok "Service '$name' supprime"
  else
    err "Suppression echouee"; return 1
  fi
}

svc_list() {
  [ -s "$SERVICES_DB" ] || { echo "Aucun service."; return 0; }
  local n r p h m mi cnt
  while IFS='|' read -r n r p h m mi; do
    cnt=$(grep -c "^$n|" "$USERS_DB")
    echo "- $n | $r | $p | $h | $cnt utilisateur(s)"
  done < "$SERVICES_DB"
}
