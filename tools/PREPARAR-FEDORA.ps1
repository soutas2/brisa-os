# Prepara o Surface para instalar o Fedora quando o firmware nao arranca de USB.
#
# O firmware do Surface nao consegue arrancar da pen, mas o Linux consegue le-la.
# Por isso:
# 1. Cria uma particao pequena (1 GB) "FEDBOOT" no disco interno so com o
#    arranque (GRUB + kernel + initrd).
# 2. O instalador grande (install.img) continua na pen "FEDORA" - o Linux le-a.
# 3. Poe "Fedora Installer" em primeiro lugar no menu de arranque do Surface.
#
# A PEN TEM DE FICAR LIGADA durante a instalacao.

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Brisa OS - preparar instalacao'

function Passo($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Fim($t, $ok) {
    if ($ok) { Write-Host "`n$t" -ForegroundColor Green } else { Write-Host "`nERRO: $t" -ForegroundColor Red }
    Read-Host "`nCarrega Enter para fechar"
    exit ([int](-not $ok))
}

$BootLabel = 'FEDBOOT'
$Need = 1GB

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Fim 'Tem de correr como administrador.' $false }

    # --- Pen (origem) e disco interno --------------------------------------------
    Passo 'A procurar a pen com o instalador...'
    $pen = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'FEDORA' -and $_.DriveType -eq 'Removable' } | Select-Object -First 1
    if (-not $pen) { Fim 'Nao encontrei a pen "FEDORA". Liga a pen e tenta outra vez.' $false }
    $src = "$($pen.DriveLetter):"
    foreach ($f in 'images\install.img', 'images\pxeboot\vmlinuz', 'images\pxeboot\initrd.img', 'EFI\BOOT\grubx64.efi') {
        if (-not (Test-Path "$src\$f")) { Fim "A pen nao tem o ficheiro $f." $false }
    }
    Write-Host "   Pen encontrada: $src\"

    $cPart = Get-Partition -DriveLetter C
    $diskNum = $cPart.DiskNumber
    Write-Host "   Disco interno: #$diskNum"

    # --- Particao FEDBOOT (reutiliza se ja existir) ------------------------------
    $dstVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq $BootLabel -and $_.DriveType -eq 'Fixed' } | Select-Object -First 1
    if ($dstVol) {
        Passo "A particao $BootLabel ja existe - vou reutiliza-la."
        $dstPart = Get-Partition -Volume $dstVol
    } else {
        try {
            $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
            if ($bl.ProtectionStatus -eq 'On') {
                Passo 'A suspender o BitLocker (evita pedidos da chave de recuperacao)...'
                Suspend-BitLocker -MountPoint 'C:' -RebootCount 0 | Out-Null
            }
        } catch { Write-Host '   (BitLocker nao disponivel - a continuar)' }

        $sup = Get-PartitionSupportedSize -DriveLetter C
        $max = $cPart.Size - $sup.SizeMin
        Write-Host ("   O Windows deixa reduzir o C: em {0:N1} GB" -f ($max / 1GB))
        if ($max -lt $Need) {
            Passo 'A desligar a hibernacao e a apagar pontos de restauro...'
            powercfg /h off | Out-Null
            vssadmin delete shadows /for=C: /all /quiet | Out-Null
            Start-Sleep -Seconds 3
            $sup = Get-PartitionSupportedSize -DriveLetter C
            $max = $cPart.Size - $sup.SizeMin
        }
        if ($max -lt $Need) {
            Fim ("So consigo libertar {0:N1} GB do C: (preciso de 1 GB)." -f ($max / 1GB)) $false
        }

        Passo 'A libertar 1 GB do disco C:...'
        Resize-Partition -DriveLetter C -Size ($cPart.Size - $Need)

        Passo "A criar a particao $BootLabel..."
        $dstPart = New-Partition -DiskNumber $diskNum -UseMaximumSize -AssignDriveLetter
        Start-Sleep -Seconds 2
        Format-Volume -Partition $dstPart -FileSystem FAT32 -NewFileSystemLabel $BootLabel -Confirm:$false | Out-Null
        $dstPart = Get-Partition -DiskNumber $diskNum -PartitionNumber $dstPart.PartitionNumber
    }

    if (-not $dstPart.DriveLetter -or $dstPart.DriveLetter -eq [char]0) {
        $dstPart | Add-PartitionAccessPath -AssignDriveLetter
        $dstPart = Get-Partition -DiskNumber $dstPart.DiskNumber -PartitionNumber $dstPart.PartitionNumber
    }
    $dl = $dstPart.DriveLetter
    $dst = "$($dl):"
    Write-Host "   Particao ${BootLabel}: $dst\"

    # --- Copiar so os ficheiros de arranque --------------------------------------
    Passo 'A copiar os ficheiros de arranque (cerca de 300 MB)...'
    foreach ($d in 'EFI', 'boot', 'images\pxeboot') {
        robocopy "$src\$d" "$dst\$d" /E /R:2 /W:2 /NFL /NDL /NP /NJH /NJS /XF '._*' | Out-Null
        if ($LASTEXITCODE -ge 8) { Fim "A copia de $d falhou (codigo $LASTEXITCODE)." $false }
    }
    foreach ($f in 'images\pxeboot\vmlinuz', 'images\pxeboot\initrd.img', 'EFI\BOOT\grubx64.efi') {
        if ((Get-Item "$src\$f").Length -ne (Get-Item "$dst\$f").Length) { Fim "O ficheiro $f ficou incompleto." $false }
    }

    # GRUB procura a particao interna; o instalador (stage2) continua na pen FEDORA
    $cfg = "$dst\EFI\BOOT\grub.cfg"
    $txt = Get-Content $cfg -Raw
    $txt = $txt -replace "-l 'FEDORA'", "-l '$BootLabel'"
    $txt = $txt -replace 'set default="1"', 'set default="0"'
    [IO.File]::WriteAllText($cfg, $txt, [Text.Encoding]::ASCII)
    if ((Get-Content $cfg -Raw) -notmatch "-l '$BootLabel'") { Fim 'Nao consegui ajustar o grub.cfg.' $false }
    Write-Host '   Ficheiros copiados e verificados.'

    # --- Entrada de arranque "Fedora Installer" em primeiro lugar ----------------
    Passo 'A adicionar "Fedora Installer" ao menu de arranque do Surface...'
    $out = (bcdedit /copy '{bootmgr}' /d 'Fedora Installer') -join ' '
    $guid = [regex]::Match($out, '\{[0-9a-fA-F\-]{36}\}').Value
    if (-not $guid) { Fim "Nao consegui criar a entrada de arranque: $out" $false }
    bcdedit /set $guid device "partition=$($dl):" | Out-Null
    bcdedit /set $guid path '\EFI\BOOT\grubx64.efi' | Out-Null
    bcdedit /set '{fwbootmgr}' displayorder $guid /addfirst | Out-Null
    Write-Host "   Entrada criada: $guid"

    Fim @"
TUDO PRONTO!

Agora:
  1. DEIXA A PEN LIGADA (o instalador esta nela).
  2. Reinicia o Surface.
  3. Aparece o menu do Fedora -> "Install Fedora 45" arranca sozinho.

Na instalacao: em "Destino da instalacao" escolhe o disco interno (NAO a pen)
e "Recuperar espaco" -> "Apagar tudo".
"@ $true
} catch {
    Fim $_.Exception.Message $false
}
