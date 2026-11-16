#!/usr/bin/env bash
# Lancador: instala o Android (Bliss OS) no Surface.
# Uso no Terminal:  bash ANDROID.sh   (ou arrasta este ficheiro para o Terminal)

HERE="$(cd "$(dirname "$0")" && pwd)"

# Se foi aberto sem terminal (ex.: "Executar como programa"), abre um.
if [ ! -t 0 ]; then
    if command -v ptyxis >/dev/null; then exec ptyxis --new-window -x "bash '$HERE/$(basename "$0")'"; fi
    if command -v gnome-terminal >/dev/null; then exec gnome-terminal -- bash "$HERE/$(basename "$0")"; fi
    if command -v kgx >/dev/null; then exec kgx -e bash "$HERE/$(basename "$0")"; fi
fi

clear
printf '\033[1;36m=== Instalar Android no Surface ===\033[0m\n\n'
printf 'Vai pedir a tua palavra-passe (nao aparece nada enquanto escreves).\n\n'

SCRIPT=/tmp/instalar-android.sh
if [ -f "$HERE/android-script.sh" ]; then
    cp "$HERE/android-script.sh" "$SCRIPT"
elif curl -fsSL https://raw.githubusercontent.com/soutas2/brisa-os/main/tools/instalar-android.sh -o "$SCRIPT" 2>/dev/null; then
    :
else
    printf '\033[1;31mNao encontrei o instalador. Liga o Wi-Fi e tenta outra vez.\033[0m\n'
    read -rp 'Carrega Enter para fechar...'
    exit 1
fi

sudo bash "$SCRIPT"
printf '\n'
read -rp 'Carrega Enter para fechar...'
