#!/usr/bin/env bash
# Installation et connexion gcloud

install_gcloud() {
  if command -v gcloud >/dev/null 2>&1; then ok "gcloud deja installe"; return 0; fi
  echo "Installation de gcloud..."
  local SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -y && $SUDO apt-get install -y curl gnupg apt-transport-https ca-certificates
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      | $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
    $SUDO apt-get update -y && $SUDO apt-get install -y google-cloud-cli
  else
    curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
    export PATH="$HOME/google-cloud-sdk/bin:$PATH"
  fi
  command -v gcloud >/dev/null 2>&1 && ok "gcloud installe" || { err "Echec installation gcloud"; return 1; }
}

login_gcloud() {
  command -v gcloud >/dev/null 2>&1 || { err "gcloud absent : lance d'abord l'installation"; return 1; }
  gcloud auth login --no-launch-browser || return 1
  local p; p=$(gcloud config get-value project 2>/dev/null)
  { [ -z "$p" ] || [ "$p" = "(unset)" ]; } && p="mon-projet"
  p=$(ask "ID du projet Google Cloud" "$p")
  gcloud config set project "$p" || return 1
  echo "Activation des APIs (1-2 min)..."
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
  ok "Projet configure : $p"
}

require_gcloud() {
  command -v gcloud >/dev/null 2>&1 || { err "gcloud non installe (gcrv menu > 1)"; return 1; }
  local a; a=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)
  [ -n "$a" ] || { err "Aucun compte Google connecte (gcrv menu > 2)"; return 1; }
}
