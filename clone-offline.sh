#!/usr/bin/env bash
# HollowDrivers: run only in Clonezilla Live. Never execute this template directly.
set -euo pipefail
export LC_ALL=C
fail() { printf '\nBLOQUEADO: %s\n' "$*" >&2; exit 1; }
normalize() { tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'; }
[[ $EUID -eq 0 ]] || fail 'Use sudo bash CLONAR.sh no Clonezilla Live.'
[[ -e /etc/ocs/ocs-live.conf ]] || fail 'Inicie pelo Clonezilla Live.'
for tool in lsblk blockdev base64 ocs-onthefly; do command -v "$tool" >/dev/null || fail "Componente ausente: $tool"; done
source_serial=$(printf '%s' '__SOURCE_SERIAL__' | base64 -d | normalize)
target_serial=$(printf '%s' '__TARGET_SERIAL__' | base64 -d | normalize)
source_size=__SOURCE_SIZE__
target_size=__TARGET_SIZE__
sector=__SECTOR__
[[ -n $source_serial && -n $target_serial && $source_serial != "$target_serial" ]] || fail 'Seriais invalidos.'
resolve_disk() {
    local expected=$1 found='' matches=0 dev kind serial
    while read -r dev kind; do
        [[ $kind == disk ]] || continue
        serial=$(lsblk -dn -o SERIAL "$dev" | normalize)
        if [[ $serial == "$expected" ]]; then found=$dev; matches=$((matches+1)); fi
    done < <(lsblk -dnpo NAME,TYPE)
    [[ $matches -eq 1 ]] || fail "Serial ausente ou ambiguo: $expected. Nao escolha pelo numero do disco."
    printf '%s' "$found"
}
source_disk=$(resolve_disk "$source_serial")
target_disk=$(resolve_disk "$target_serial")
[[ $source_disk != "$target_disk" ]] || fail 'Origem igual ao destino.'
check_disks() {
    [[ $(resolve_disk "$source_serial") == "$source_disk" && $(resolve_disk "$target_serial") == "$target_disk" ]] || fail 'Os discos mudaram.'
    [[ $(blockdev --getsize64 "$source_disk") == "$source_size" ]] || fail 'Tamanho da origem mudou.'
    [[ $(blockdev --getsize64 "$target_disk") == "$target_size" ]] || fail 'Tamanho do destino mudou.'
    (( target_size >= source_size )) || fail 'Destino menor que origem.'
    local disk mounts fs
    for disk in "$source_disk" "$target_disk"; do
        [[ $(blockdev --getss "$disk") == "$sector" ]] || fail 'Setor incompativel.'
        mounts=$(lsblk -nrpo MOUNTPOINTS "$disk")
        [[ -z ${mounts//[[:space:]]/} ]] || fail "Disco em uso: $disk. Desmonte-o antes de continuar."
        fs=$(lsblk -nrpo FSTYPE "$disk")
        if printf '%s\n' "$fs" | grep -Eiq 'bitlocker|crypto|LVM|raid'; then
            fail 'Criptografia, RAID ou LVM detectado. Este fluxo nao suporta esse layout.'
        fi
    done
    [[ $(blockdev --getro "$target_disk") == 0 ]] || fail 'Destino protegido contra escrita.'
}
check_disks
printf '\nORIGEM (preservar):\n'
lsblk -dnbo NAME,SIZE,MODEL,SERIAL "$source_disk"
printf '\nDESTINO (APAGAR TODAS AS PARTICOES):\n'
lsblk -dnbo NAME,SIZE,MODEL,SERIAL "$target_disk"
printf '\nWindows, programas e arquivos de OUTROS discos nao entram.\n'
printf 'Para continuar digite exatamente: APAGAR %s\n> ' "$target_serial"
read -r answer
[[ $answer == "APAGAR $target_serial" ]] || fail 'Cancelado. Nenhuma clonagem iniciada.'
check_disks
# No batch mode, no force/ignore-size, no removal of NTFS dirty flags.
# Clonezilla retains its own destructive-operation confirmations.
if ocs-onthefly -f "$source_disk" -d "$target_disk" -sfsck -p true; then
    printf '\nMotor concluiu sem erro. BOOT AINDA NAO TESTADO.\nDesligue, desconecte a origem e teste o destino na conexao interna.\n'
else
    fail 'O motor informou falha. Nao confie no destino como backup. Preserve a origem e consulte o log do Clonezilla.'
fi
