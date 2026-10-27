#!/usr/bin/env bash
# Gestion des utilisateurs (UUID) par service

user_line() { grep -m1 "^$1|$2|" "$USERS_DB"; }

# user_add <service> <utilisateur> [jours]   (0 ou vide = sans expiration)
user_add() {
  local svc="$1" user="$2" days="${3:-0}" uuid exp
  svc_exists "$svc" || { err "Service '$svc' introuvable"; return 1; }
  valid_user "$user" || { err "Nom d'utilisateur invalide (lettres, chiffres, _ -)"; return 1; }
  [ -n "$(user_line "$svc" "$user")" ] && { err "L'utilisateur '$user' existe deja sur '$svc'"; return 1; }
  [[ "$days" =~ ^[0-9]+$ ]] || { err "Nombre de jours invalide"; return 1; }
  [ "$(grep -c "^$svc|" "$USERS_DB")" -ge "$MAX_USERS" ] && { err "Limite de $MAX_USERS utilisateurs atteinte"; return 1; }
  require_gcloud || return 1

  uuid=$(new_uuid)
  if [ "$days" -gt 0 ]; then exp=$(date -d "+$days days" +%F); else exp="never"; fi
  echo "$svc|$user|$uuid|$exp" >> "$USERS_DB"
  if deploy_service "$svc"; then
    ok "Utilisateur '$user' ajoute (expiration : $exp)"
    make_link "$svc-$user" "$uuid" "$(svc_field "$svc" 3)" "$(svc_field "$svc" 4)"
  else
    grep -v "^$svc|$user|" "$USERS_DB" > "$USERS_DB.tmp"; mv "$USERS_DB.tmp" "$USERS_DB"
    return 1
  fi
}

user_del() {
  local svc="$1" user="$2"
  svc_exists "$svc" || { err "Service '$svc' introuvable"; return 1; }
  [ -n "$(user_line "$svc" "$user")" ] || { err "Utilisateur '$user' introuvable"; return 1; }
  require_gcloud || return 1
  local backup; backup=$(cat "$USERS_DB")
  grep -v "^$svc|$user|" "$USERS_DB" > "$USERS_DB.tmp"; mv "$USERS_DB.tmp" "$USERS_DB"
  if deploy_service "$svc"; then
    ok "Utilisateur '$user' supprime"
  else
    printf '%s\n' "$backup" > "$USERS_DB"; return 1
  fi
}

user_list() {
  local svc="$1" s u id exp n=0
  svc_exists "$svc" || { err "Service '$svc' introuvable"; return 1; }
  while IFS='|' read -r s u id exp; do
    [ "$s" = "$svc" ] || continue
    echo "- $u | expire : $exp | ${id:0:8}..."; n=$((n+1))
  done < "$USERS_DB"
  [ "$n" -eq 0 ] && echo "Aucun utilisateur."
  return 0
}

user_link() {
  local svc="$1" user="$2" l uuid
  l=$(user_line "$svc" "$user")
  [ -n "$l" ] || { err "Utilisateur introuvable"; return 1; }
  uuid=$(echo "$l" | cut -d'|' -f3)
  make_link "$svc-$user" "$uuid" "$(svc_field "$svc" 3)" "$(svc_field "$svc" 4)"
}

# Supprime les utilisateurs expires et redeploie les services touches
expire_check() {
  local today expired affected svc
  today=$(date +%F)
  expired=$(awk -F'|' -v t="$today" '$4!="never" && $4<t' "$USERS_DB")
  [ -z "$expired" ] && { echo "$(date '+%F %T') rien a expirer"; return 0; }
  affected=$(echo "$expired" | cut -d'|' -f1 | sort -u)
  awk -F'|' -v t="$today" '$4=="never" || $4>=t' "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
  echo "$(date '+%F %T') expires supprimes :"; echo "$expired" | cut -d'|' -f1,2
  require_gcloud || return 1
  for svc in $affected; do svc_exists "$svc" && deploy_service "$svc"; done
}
