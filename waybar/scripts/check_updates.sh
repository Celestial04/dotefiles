#!/usr/bin/env bash
# renvoie un petit texte (ex: nb de maj) que Waybar affichera
# adapte pour ton distro : pacman -Qqu / apt list --upgradable etc.
if command -v checkupdates >/dev/null 2>&1; then
  n=$(checkupdates | wc -l)
  echo "$n updates"
else
  echo "0 updates"
fi
