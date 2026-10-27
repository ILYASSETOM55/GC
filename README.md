# GCRV : serveurs V2Ray sur Google Cloud Run, gérés depuis un VPS

Déploie des services **Xray (VLESS + WebSocket + TLS)** sur Cloud Run et génère les liens `vless://`
(même schéma que ton lien : IP Google en front, SNI googleapis, host `*.run.app`).

## Contenu
- `gcrv` : commande principale (menu + sous-commandes)
- `lib/` : modules (gcloud, services, utilisateurs, outils communs)
- `templates/Dockerfile` : image Xray déployée
- `bot/` : bot Telegram admin (optionnel) + service systemd
- `install.sh` : installation dans `/opt/gcrv` + commande `gcrv`

## Installation depuis GitHub (Ubuntu/Debian, root)
Le dépôt officiel est : https://github.com/ILYASSETOM55/GC

Installation directe :
    sudo apt-get update -y
    sudo apt-get install -y curl git unzip
    git clone https://github.com/ILYASSETOM55/GC.git
    cd GC
    sudo bash install.sh
    gcrv

Le même `install.sh` peut aussi être exécuté depuis une copie locale du projet.
Il détecte automatiquement les fichiers locaux. Lorsqu'il est lancé depuis une autre machine, il peut télécharger le dépôt GitHub complet.

Mise à jour après installation :
    sudo bash /opt/gcrv/update.sh

Dans le menu : 1) installer gcloud, 2) connexion Google + ID du projet (facturation activée), 3) créer un service.

## Commandes
    gcrv service-create <nom> [region] [path] [memoire] [min_instances]
    gcrv service-list
    gcrv service-delete <nom>
    gcrv user-add <service> <utilisateur> [jours]   # 0 = illimité
    gcrv user-del <service> <utilisateur>
    gcrv user-list <service>
    gcrv link <service> <utilisateur>
    gcrv expire-check

Chaque service a plusieurs utilisateurs (un UUID chacun, avec date d'expiration optionnelle).
Ajouter ou supprimer un utilisateur redéploie le service (2-4 min) : la config est dans l'image.
Menu 11 : cron horaire qui supprime les comptes expirés.

## Bot Telegram
`install.sh` propose de l'installer (token BotFather + ton ID). Seul l'admin est écouté.
Commandes : /services /create /delservice /adduser /deluser /users /link /expire

## Limites à connaître
- **Pas de quota en Go ni de limite d'IP par compte** : le trafic passe par Google, pas par le VPS,
  donc on ne peut pas le mesurer par utilisateur. Les moyens de contrôle disponibles sont
  l'expiration, le nombre max d'utilisateurs par service et le plafond d'instances Cloud Run (menu 10).
- Les connexions Cloud Run sont coupées après 60 min : le client se reconnecte.
- `min_instances=1` est facturé en continu ; `0` ajoute un délai au premier réveil.
- Si le déploiement échoue au démarrage, vérifier l'image `teddysun/xray` dans `templates/Dockerfile`.
- Journal du dernier déploiement : `~/.gcrv/deploy.log`.
