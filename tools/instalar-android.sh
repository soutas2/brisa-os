#!/usr/bin/env bash
# Instala o Bliss OS (Android 13 + Google Play, versao para Surface) no Surface Go 2,
# a partir do Fedora/Brisa OS ja instalado.
#
# O que faz:
#   1. Encolhe o Fedora ao minimo (fica escondido, so para emergencias).
#   2. Cria uma particao ext4 "ANDROID" com o resto do disco.
#   3. Descarrega o Bliss OS (2,4 GB), verifica o SHA-256 e copia-o para la.
#   4. O Surface passa a arrancar direto para o Android, sem menu.
#
# Pode ser corrido varias vezes: retoma onde ficou.
#
# Uso:  sudo bash instalar-android.sh

set -euo pipefail

ISO_NAME="Bliss-Surface-v16.9.7-x86_64-OFFICIAL-gapps-20241012.iso"
ISO_URL="https://sourceforge.net/projects/blissos-x86/files/Official/BlissOS16/Gapps/Surface/${ISO_NAME}/download"
ISO_SHA256="38bbc3dc40b2e735dd395df2302d7c762a2f91030cef1f12bc1ccb1abfa43ce1"
LABEL="ANDROID"
MIN_ANDROID_GIB=12
MNT=/var/mnt/android
ISOMNT=/var/mnt/blissiso

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31mERRO: %s\033[0m\n\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Corre com sudo:  sudo bash $0"

cleanup() {
    mountpoint -q "$ISOMNT" && umount "$ISOMNT" || true
    mountpoint -q "$MNT" && umount "$MNT" || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Disco e particao do Fedora
# ---------------------------------------------------------------------------
say "A analisar o disco..."
ROOTMNT=/sysroot
mountpoint -q "$ROOTMNT" || ROOTMNT=/
ROOTSRC=$(findmnt -no SOURCE "$ROOTMNT"); ROOTSRC=${ROOTSRC%%[*}
ROOTFS=$(findmnt -no FSTYPE "$ROOTMNT")
case "$ROOTSRC" in
    /dev/mapper/*|/dev/dm-*) die "O disco esta encriptado (LUKS). Este script nao suporta esse caso." ;;
esac
[ "$ROOTFS" = btrfs ] || die "Esperava btrfs na raiz do Fedora, encontrei '$ROOTFS'."

PART=$(basename "$ROOTSRC")
DISKNAME=$(lsblk -no PKNAME "$ROOTSRC" | head -1)
DISK=/dev/$DISKNAME
PNUM=$(cat "/sys/class/block/$PART/partition")
PSTART=$(cat "/sys/class/block/$PART/start")   # em setores de 512 bytes
PSIZE=$(cat "/sys/class/block/$PART/size")
SS=$(blockdev --getss "$DISK")                  # tamanho de setor do disco
info "Disco: $DISK  ($(lsblk -dno SIZE "$DISK"))"
info "Fedora: $ROOTSRC  ($(lsblk -no SIZE "$ROOTSRC"))"

# Particoes que comecam depois da do Fedora
after_parts() {
    local p
    for p in /sys/class/block/"$DISKNAME"*; do
        [ -f "$p/partition" ] || continue
        if [ "$(cat "$p/start")" -gt "$PSTART" ]; then basename "$p"; fi
    done
    return 0
}

ANDEV=$(blkid -L "$LABEL" 2>/dev/null || true)

if [ -z "$ANDEV" ]; then
    EXTRA=$(after_parts | head -1)
    if [ -n "$EXTRA" ]; then
        # Particao criada numa corrida anterior, ainda sem sistema de ficheiros
        FST=$(blkid -o value -s TYPE "/dev/$EXTRA" 2>/dev/null || true)
        [ -z "$FST" ] || die "Ja existe outra particao (/dev/$EXTRA, $FST) depois do Fedora. Nao lhe vou mexer."
        ANDEV=/dev/$EXTRA
        info "A usar a particao criada antes: $ANDEV"
    else
        # -------------------------------------------------------------------
        # Encolher o Fedora
        # -------------------------------------------------------------------
        say "A limpar versoes antigas do sistema para libertar espaco..."
        rpm-ostree cleanup -r -m >/dev/null 2>&1 || true
        sync

        USED=$(df -B1 --output=used "$ROOTMNT" | tail -1 | tr -d ' ')
        KEEP=$(( USED / 1073741824 + 4 ))
        [ "$KEEP" -lt 10 ] && KEEP=10
        PART_GIB=$(( PSIZE * 512 / 1073741824 ))
        ANDROID_GIB=$(( PART_GIB - KEEP - 1 ))
        info "Fedora usa $(( USED / 1073741824 )) GB -> fica com $KEEP GB"
        info "Android fica com cerca de $ANDROID_GIB GB"
        [ "$ANDROID_GIB" -ge "$MIN_ANDROID_GIB" ] || die "Nao ha espaco suficiente para o Android (preciso de ${MIN_ANDROID_GIB} GB)."

        # No Fedora atomico o /sysroot esta montado so de leitura; o resize
        # precisa de um ponto de montagem com escrita do mesmo btrfs.
        RWMNT=/var/mnt/fedora-btrfs
        mkdir -p "$RWMNT"
        mountpoint -q "$RWMNT" || mount -o rw,subvolid=5 "$ROOTSRC" "$RWMNT" 2>/dev/null || true
        T="$RWMNT"; mountpoint -q "$T" || T=/var

        # O btrfs espalha blocos pelo disco todo; primeiro junta-os no inicio
        # (balance), depois encolhe aos poucos (4 GB de cada vez).
        say "A arrumar o disco do Fedora (pode demorar 5 a 20 minutos)..."
        btrfs balance start -dusage=0 -musage=0 "$T" >/dev/null 2>&1 || true
        btrfs balance start -dusage=50 -musage=50 "$T" >/dev/null 2>&1 || true

        say "A encolher o Fedora para $KEEP GB..."
        SIZE=$(( $(btrfs filesystem show --raw "$T" | awk '/devid/{print $4; exit}') / 1073741824 ))
        [ "$SIZE" -gt 0 ] || die "Nao consegui ler o tamanho do btrfs."
        while [ "$SIZE" -gt "$KEEP" ]; do
            NEXT=$(( SIZE - 4 )); [ "$NEXT" -lt "$KEEP" ] && NEXT=$KEEP
            if btrfs filesystem resize "${NEXT}g" "$T" >/dev/null 2>&1; then
                SIZE=$NEXT
            else
                btrfs balance start -dusage=90 -musage=90 "$T" >/dev/null 2>&1 || true
                if btrfs filesystem resize "${NEXT}g" "$T" >/dev/null 2>&1; then SIZE=$NEXT; else break; fi
            fi
            info "Fedora agora com $SIZE GB"
        done
        umount "$RWMNT" 2>/dev/null || true
        KEEP=$SIZE
        ANDROID_GIB=$(( PART_GIB - KEEP - 1 ))
        [ "$ANDROID_GIB" -ge "$MIN_ANDROID_GIB" ] || die "So consegui encolher o Fedora para $KEEP GB - nao chega para o Android."
        info "Fedora fica com $KEEP GB, Android com cerca de $ANDROID_GIB GB"

        # Particao do Fedora fica com KEEP+1 GiB (margem de seguranca)
        NEWSIZE_512=$(( (KEEP + 1) * 2097152 ))
        START_SS=$(( PSTART * 512 / SS ))
        NEWSIZE_SS=$(( NEWSIZE_512 * 512 / SS ))
        NSTART_SS=$(( START_SS + NEWSIZE_SS ))

        say "A alterar a tabela de particoes..."
        sfdisk -d "$DISK" > /var/tmp/particoes-antes-android.txt
        info "Copia da tabela antiga: /var/tmp/particoes-antes-android.txt"
        echo "${START_SS},${NEWSIZE_SS}" | sfdisk --no-reread --no-tell-kernel -q -N "$PNUM" "$DISK"
        echo "${NSTART_SS},,L" | sfdisk --no-reread --no-tell-kernel -q --append "$DISK"

        partx -u "$DISK" >/dev/null 2>&1 || true
        partx -a "$DISK" >/dev/null 2>&1 || true
        udevadm settle || true
        sleep 2

        EXTRA=$(after_parts | head -1)
        if [ -z "$EXTRA" ]; then
            printf '\n\033[1;33mParticao criada, mas o sistema so a ve depois de reiniciar.\033[0m\n'
            printf 'Reinicia (escolhe o Fedora) e corre o MESMO comando outra vez.\n\n'
            exit 0
        fi
        ANDEV=/dev/$EXTRA
    fi

    say "A formatar $ANDEV como ext4 ($LABEL)..."
    mkfs.ext4 -F -q -L "$LABEL" -O ^orphan_file "$ANDEV" 2>/dev/null || mkfs.ext4 -F -q -L "$LABEL" "$ANDEV"
    udevadm settle || true
fi
info "Particao do Android: $ANDEV"

# ---------------------------------------------------------------------------
# Descarregar e copiar o Bliss OS
# ---------------------------------------------------------------------------
mkdir -p "$MNT" "$ISOMNT"
mountpoint -q "$MNT" || mount "$ANDEV" "$MNT"

if [ ! -f "$MNT/blissos/kernel" ] || [ ! -f "$MNT/blissos/.instalado" ]; then
    ISO="$MNT/$ISO_NAME"
    if [ ! -f "$ISO" ] || ! echo "$ISO_SHA256  $ISO" | sha256sum -c --status; then
        say "A descarregar o Bliss OS (2,4 GB)..."
        curl -fL --retry 5 --retry-delay 5 -C - -o "$ISO" "$ISO_URL" || \
            curl -fL --retry 5 --retry-delay 5 -o "$ISO" "$ISO_URL"
        say "A verificar o ficheiro (SHA-256)..."
        echo "$ISO_SHA256  $ISO" | sha256sum -c --status || { rm -f "$ISO"; die "O ficheiro descarregado esta corrompido. Corre outra vez."; }
    fi
    info "Ficheiro verificado."

    say "A copiar o Android para a particao..."
    mount -o loop,ro "$ISO" "$ISOMNT"
    mkdir -p "$MNT/blissos/data"
    shopt -s nullglob
    FILES=("$ISOMNT"/kernel "$ISOMNT"/initrd.img "$ISOMNT"/ramdisk*.img "$ISOMNT"/system.*)
    shopt -u nullglob
    [ -f "$ISOMNT/kernel" ] && [ -f "$ISOMNT/initrd.img" ] || die "O ISO nao tem kernel/initrd.img."
    ls "$ISOMNT"/system.* >/dev/null 2>&1 || die "O ISO nao tem system.*"
    cp -v "${FILES[@]}" "$MNT/blissos/"
    umount "$ISOMNT"
    sync
    touch "$MNT/blissos/.instalado"
    rm -f "$ISO"
fi
info "Ficheiros do Android: $(ls "$MNT/blissos" | tr '\n' ' ')"
umount "$MNT"

# ---------------------------------------------------------------------------
# Menu de arranque
# ---------------------------------------------------------------------------
say "A adicionar o Android ao menu de arranque..."
BOOT_RO=0
if findmnt -no OPTIONS /boot | grep -qw ro; then
    BOOT_RO=1
    mount -o remount,rw /boot
fi

GRUBDIR=/boot/grub2
[ -f "$GRUBDIR/grub.cfg" ] || die "Nao encontrei $GRUBDIR/grub.cfg"
if grep -q 'custom.cfg' "$GRUBDIR/grub.cfg"; then
    TARGET="$GRUBDIR/custom.cfg"
elif grep -q 'user.cfg' "$GRUBDIR/grub.cfg"; then
    TARGET="$GRUBDIR/user.cfg"
else
    die "O grub.cfg nao carrega custom.cfg nem user.cfg."
fi

# Remove entradas antigas deste script e acrescenta as novas
if [ -f "$TARGET" ]; then
    sed -i '/^### BRISA-ANDROID BEGIN/,/^### BRISA-ANDROID END/d' "$TARGET"
fi
cat >> "$TARGET" <<'EOF'
### BRISA-ANDROID BEGIN
# Arranque direto para o Android: menu escondido (Esc num teclado mostra-o).
set default=brisa-android
set timeout_style=hidden
set timeout=1
menuentry "Android (Bliss OS)" --id brisa-android --class android {
    insmod part_gpt
    insmod ext2
    search --no-floppy --set=root --label ANDROID
    linux /blissos/kernel HWC=drm_minigbm_celadon GRALLOC=minigbm FFMPEG_CODEC=1 FFMPEG_PREFER_C2=1 quiet root=/dev/ram0 SRC=/blissos
    initrd /blissos/initrd.img
}
menuentry "Android (modo seguro de graficos)" --id brisa-android-safe --class android {
    insmod part_gpt
    insmod ext2
    search --no-floppy --set=root --label ANDROID
    linux /blissos/kernel FFMPEG_CODEC=1 FFMPEG_PREFER_C2=1 quiet root=/dev/ram0 SRC=/blissos
    initrd /blissos/initrd.img
}
### BRISA-ANDROID END
EOF
info "Entradas escritas em $TARGET"

grub2-editenv "$GRUBDIR/grubenv" set saved_entry=brisa-android
grub2-editenv "$GRUBDIR/grubenv" unset menu_auto_hide || true
grub2-editenv "$GRUBDIR/grubenv" unset next_entry || true
info "Android definido como arranque por omissao."
grep -q 'saved_entry' "$GRUBDIR/grub.cfg" || info "AVISO: o grub.cfg pode ignorar saved_entry - escolhe 'Android' no menu."

[ "$BOOT_RO" -eq 1 ] && mount -o remount,ro /boot || true

printf '\n\033[1;32mANDROID INSTALADO!\033[0m\n\n'
printf 'Reinicia com:  systemctl reboot\n'
printf 'O Surface arranca direto para o Android (sem menu).\n'
printf 'O primeiro arranque demora 2 a 5 minutos.\n\n'
