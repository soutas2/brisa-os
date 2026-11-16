# Prepara o Surface para instalar o Fedora SEM arrancar de USB.
# 1. Separa 3.5 GB do disco interno numa particao FAT32 "FEDORA"
# 2. Copia para la o instalador que esta na pen
# 3. Poe o instalador em primeiro lugar no menu de arranque do Surface
#
# Corre como administrador (o INSTALAR.cmd trata disso).

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Brisa OS - preparar instalacao'

function Passo($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Fim($t, $ok) {
    if ($ok) { Write-Host "`n$t" -ForegroundColor Green } else { Write-Host "`nERRO: $t" -ForegroundColor Red }
    Read-Host "`nCarrega Enter para fechar"
    exit ([int](-not $ok))
}

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Fim 'Tem de correr como administrador. Usa o INSTALAR.cmd.' $false }

    # --- Encontrar a pen (origem) e o disco interno -----------------------------
    Passo 'A procurar a pen com o instalador...'
    $pen = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'FEDORA' -and $_.DriveType -eq 'Removable' } | Select-Object -First 1
    if (-not $pen) { Fim 'Nao encontrei a pen "FEDORA". Liga a pen e tenta outra vez.' $false }
    $src = "$($pen.DriveLetter):\"
    if (-not (Test-Path "$src\images\install.img")) { Fim "A pen $src nao tem o instalador completo." $false }
    Write-Host "   Pen encontrada: $src"

    $cPart = Get-Partition -DriveLetter C
    $diskNum = $cPart.DiskNumber
    Write-Host "   Disco interno: #$diskNum"

    # --- Particao FEDORA no disco interno (reutiliza se ja existir) --------------
    $dstVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'FEDORA' -and $_.DriveType -eq 'Fixed' } | Select-Object -First 1
    if ($dstVol) {
        Passo 'A particao FEDORA ja existe no disco interno - vou reutiliza-la.'
        $dstPart = Get-Partition -Volume $dstVol
    } else {
        # BitLocker: suspender para o Windows nao pedir a chave de recuperacao
        try {
            $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
            if ($bl.ProtectionStatus -eq 'On') {
                Passo 'A suspender o BitLocker (evita pedidos da chave de recuperacao)...'
                Suspend-BitLocker -MountPoint 'C:' -RebootCount 0 | Out-Null
            }
        } catch { Write-Host '   (BitLocker nao disponivel - a continuar)' }

        # O instalador ocupa ~2.9 GB; 3.5 GB chegam.
        $need = 3.5GB
        $sup = Get-PartitionSupportedSize -DriveLetter C
        $max = $cPart.Size - $sup.SizeMin
        Write-Host ("   O Windows deixa reduzir o C: em {0:N1} GB" -f ($max / 1GB))

        if ($max -lt $need) {
            # Ficheiros que o Windows nao consegue mover: hibernacao e pontos de restauro
            Passo 'Pouco espaco movivel - a desligar a hibernacao e a apagar pontos de restauro...'
            powercfg /h off | Out-Null
            vssadmin delete shadows /for=C: /all /quiet | Out-Null
            Start-Sleep -Seconds 3
            $sup = Get-PartitionSupportedSize -DriveLetter C
            $max = $cPart.Size - $sup.SizeMin
            Write-Host ("   Agora o Windows deixa reduzir o C: em {0:N1} GB" -f ($max / 1GB))
        }
        if ($max -lt $need) {
            Fim ("So consigo libertar {0:N1} GB do C: (preciso de 3.5 GB). Reinicia o Surface e corre isto outra vez; se continuar, diz ao Claude este numero." -f ($max / 1GB)) $false
        }

        Passo 'A libertar 3.5 GB do disco C: (pode demorar 1-3 minutos)...'
        Resize-Partition -DriveLetter C -Size ($cPart.Size - $need)

        Passo 'A criar a particao FEDORA...'
        $dstPart = New-Partition -DiskNumber $diskNum -UseMaximumSize -AssignDriveLetter
        Start-Sleep -Seconds 2
        Format-Volume -Partition $dstPart -FileSystem FAT32 -NewFileSystemLabel 'FEDORA' -Confirm:$false | Out-Null
        $dstPart = Get-Partition -DiskNumber $diskNum -PartitionNumber $dstPart.PartitionNumber
    }

    if (-not $dstPart.DriveLetter -or $dstPart.DriveLetter -eq [char]0) {
        $dstPart | Add-PartitionAccessPath -AssignDriveLetter
        $dstPart = Get-Partition -DiskNumber $dstPart.DiskNumber -PartitionNumber $dstPart.PartitionNumber
    }
    $dl = $dstPart.DriveLetter
    $dst = "$($dl):\"
    Write-Host "   Particao FEDORA: $dst"

    # --- Copiar o instalador -----------------------------------------------------
    Passo 'A copiar o instalador para o disco interno (cerca de 3 GB, 3-8 minutos)...'
    robocopy $src $dst /E /R:2 /W:2 /NFL /NDL /NP /XD 'System Volume Information' '$RECYCLE.BIN' '.Spotlight-V100' '.fseventsd' '.Trashes' /XF '._*' | Out-Host
    if ($LASTEXITCODE -ge 8) { Fim "A copia falhou (codigo $LASTEXITCODE)." $false }

    $srcSize = (Get-Item "$src\images\install.img").Length
    $dstSize = (Get-Item "$dst\images\install.img").Length
    if ($srcSize -ne $dstSize) { Fim 'O ficheiro install.img ficou incompleto.' $false }
    if (-not (Test-Path "$dst\EFI\BOOT\grubx64.efi")) { Fim 'Falta o EFI\BOOT\grubx64.efi.' $false }
    Write-Host '   Copia verificada.'

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
  1. TIRA A PEN do Surface (importante).
  2. Reinicia o Surface.
  3. Deve aparecer o menu do Fedora -> escolhe "Install Fedora 45".

Na instalacao: em "Destino da instalacao" escolhe o disco e "Recuperar espaco"
-> "Apagar tudo". A particao FEDORA (o instalador) fica protegida automaticamente.
"@ $true
} catch {
    Fim $_.Exception.Message $false
}
