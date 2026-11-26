#!/bin/sh
# ==============================================================================
# Calix CLI Bridge Tool: Управление мостом из командной строки
# ==============================================================================

ACTION=$1
VLAN=$2
PORT=$3

usage() {
    echo "Использование:"
    echo "  $0 bridge <VLAN_ID> <LAN_PORT (1-4)>  - Перевести VLAN в мост на указанный порт"
    echo "  $0 route <VLAN_ID>                     - Вернуть VLAN в режим роутера (Layer 3 Routed)"
    echo "  $0 status                              - Проверить текущее состояние"
    echo ""
    echo "Пример (пробросить VLAN 40 Казахтелекома на LAN2):"
    echo "  $0 bridge 40 2"
    exit 1
}

[ -z "$ACTION" ] && usage

if [ "$ACTION" = "status" ]; then
    echo "=== WAN & Bridge Status ==="
    grep -E '^(dev_wan1_|wan1_enable|wan1_if_name|brwan1_enable|brwan1_vid|brwan1_portmask|brwan1_name)' /etc/wwwctrl/metafile.dat
    echo ""
    echo "=== VoIP SIP Status (pon1.4090) ==="
    ifconfig pon1.4090 2>/dev/null | grep -E '(inet addr|RX packets)' || echo "VoIP не активен"
    echo ""
    echo "=== OMCI Protection ==="
    omcicli -c "env batchtab_wanif_feature" 2>/dev/null || grep -o '<batchtab_wanif_feature>.*</batchtab_wanif_feature>' /etc/omci/omcienv.xml 2>/dev/null
    exit 0
fi

if [ "$ACTION" = "bridge" ]; then
    [ -z "$VLAN" ] || [ -z "$PORT" ] && usage

    # Вычисляем битовую маску порта: Port 1 = 0x1, Port 2 = 0x2, Port 3 = 0x4, Port 4 = 0x8
    SHIFT=$((PORT - 1))
    PORTMASK=$(printf "0x%x" $((1 << SHIFT)))

    echo "[*] Настройка моста: VLAN $VLAN -> LAN$PORT (mask $PORTMASK)..."

    META_TMP=/tmp/bridge_apply.$$
    cat > $META_TMP << EOF
dev_wan1_interface=brwan1.${VLAN}
wan1_enable=0
wan1_if_name=
brwan1_enable=1
brwan1_name=bridge_lan${PORT}_${VLAN}
brwan1_vid=${VLAN}
brwan1_pbit=0
brwan1_portmask=${PORTMASK}
brwan1_wifimask=0
brwan1_igmp_enable=0
EOF

    # Применяем через нативный диспетчер конфигурации Calix
    /etc/init.d/cmd_dispatcher.sh diff $META_TMP >/dev/null 2>&1
    rm -f $META_TMP

    # Снимаем аппаратную изоляцию портов
    diag port set port 0-3 isolation-set 0 2>/dev/null || true
    diag port set port 0-3 state enable 2>/dev/null || true
    diag port set port 0-3 link-up enable 2>/dev/null || true

    sync; sync
    echo "[+] Мост успешно активирован! Трафик VLAN $VLAN выходит на LAN$PORT."
    exit 0
fi

if [ "$ACTION" = "route" ]; then
    [ -z "$VLAN" ] && VLAN=40
    echo "[*] Возврат в режим роутера (Routed IPoE)..."

    META_TMP=/tmp/route_apply.$$
    cat > $META_TMP << EOF
dev_wan1_interface=pon2.${VLAN}
wan1_enable=1
wan1_if_name=ipoe_veip1-${VLAN}
brwan1_enable=0
brwan1_name=
brwan1_vid=0
brwan1_portmask=0
system_default_route_interface=dev_wan1_interface
EOF

    /etc/init.d/cmd_dispatcher.sh diff $META_TMP >/dev/null 2>&1
    rm -f $META_TMP

    sync; sync
    echo "[+] Возврат в режим роутера завершен."
    exit 0
fi

usage
