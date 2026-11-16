#!/usr/bin/env bash
# Constrói o Brisa OS por cima da imagem base.
set -euxo pipefail

OS_NAME="Brisa OS"

# ---------------------------------------------------------------------------
# 1. Ficheiros do sistema (configurações, scripts, wallpaper)
# ---------------------------------------------------------------------------
cp -a /ctx/system_files/. /
chmod 0755 /usr/bin/brisa /usr/libexec/brisa-first-login

# ---------------------------------------------------------------------------
# 2. Pacotes
# ---------------------------------------------------------------------------
# Essenciais: se algum falhar, o build para.
dnf5 -y install \
    firefox \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-blur-my-shell \
    rsms-inter-fonts \
    jetbrains-mono-fonts-all \
    thermald \
    git

# Extras: instalados se existirem nesta versão do Fedora.
dnf5 -y install --skip-unavailable \
    gnome-shell-extension-appindicator \
    gh \
    zram-generator-defaults

# Remover o que só gasta espaço/RAM num tablet de 4 GB.
for pkg in gnome-tour; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        dnf5 -y remove --no-autoremove "$pkg"
    fi
done

# ---------------------------------------------------------------------------
# 3. Serviços
# ---------------------------------------------------------------------------
# thermald: gere a temperatura dos CPUs Intel Y sem cortes bruscos de velocidade.
systemctl enable thermald.service

# A loja (GNOME Software) não fica sempre aberta em segundo plano (~150-250 MB).
# Continua a abrir normalmente quando tocas no ícone.
SOFTWARE_AUTOSTART=/etc/xdg/autostart/org.gnome.Software.desktop
if [ -f "$SOFTWARE_AUTOSTART" ]; then
    sed -i '/^X-GNOME-Autostart-enabled=/d' "$SOFTWARE_AUTOSTART"
    sed -i '/^\[Desktop Entry\]/a X-GNOME-Autostart-enabled=false' "$SOFTWARE_AUTOSTART"
fi

# ---------------------------------------------------------------------------
# 4. Definições por omissão (visual tipo macOS, touch, poupança de RAM)
# ---------------------------------------------------------------------------
dconf update

# ---------------------------------------------------------------------------
# 5. Identidade do sistema
# ---------------------------------------------------------------------------
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${OS_NAME}\"/" /usr/lib/os-release
sed -i "s/^NAME=.*/NAME=\"${OS_NAME}\"/" /usr/lib/os-release

# ---------------------------------------------------------------------------
# 6. Limpeza
# ---------------------------------------------------------------------------
dnf5 clean all
rm -rf /var/log/dnf5.log* || true
