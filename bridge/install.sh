#!/bin/sh
# ==============================================================================
# Calix GigaCenter (813Gv2 / 812G / etc.) GPON Bridge & Anti-OMCI Installer
# One-liner: curl -ksSL <URL>/install.sh | sh
# ==============================================================================

set -e

C_RESET="\033[0m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[1;36m"

echo "${C_CYAN}"
echo "  ========================================================"
echo "    Calix GPON ONT (813Gv2 / 812G) Bridge & Anti-Reset    "
echo "    Казахтелеком / Rostelecom / Generic GPON Solution     "
echo "  ========================================================"
echo "${C_RESET}"

# 0. Проверка окружения
if [ ! -f /etc/omci/omcienv.xml ] && [ ! -f /etc/wwwctrl/metafile.dat ]; then
    echo "${C_RED}[!] Ошибка: Этот скрипт предназначен только для ONT Calix (Luna SDK).${C_RESET}"
    exit 1
fi

BACKUP_DIR="/flash/calix_backup_orig"
mkdir -p "$BACKUP_DIR"

echo "${C_YELLOW}[*] Создание резервной копии оригинальных файлов...${C_RESET}"
[ ! -f "$BACKUP_DIR/metafile.dat" ] && cp /etc/wwwctrl/metafile.dat "$BACKUP_DIR/" 2>/dev/null || true
[ ! -f "$BACKUP_DIR/omcienv.xml" ] && cp /etc/omci/omcienv.xml "$BACKUP_DIR/" 2>/dev/null || true
[ ! -f "$BACKUP_DIR/support_wan_setting_ipv6.html" ] && cp /opt/httpd/data/pages/support/support_wan_setting_ipv6.html "$BACKUP_DIR/" 2>/dev/null || true
[ ! -f "$BACKUP_DIR/service_wan_vlan_setting.cmd" ] && cp /opt/httpd/data/cgi-bin/service_wan_vlan_setting.cmd "$BACKUP_DIR/" 2>/dev/null || true

# 1. Отключение и блокировка TR-069
echo "${C_YELLOW}[1/5] Блокировка TR-069 (ACS Казахтелеком)...${C_RESET}"
/etc/init.d/cwmp.sh stop 2>/dev/null || true
killall -9 cwmpmain 2>/dev/null || true

if [ -f /etc/wwwctrl/metafile.dat ]; then
    sed -i 's/cwmp_enable=1/cwmp_enable=0/g' /etc/wwwctrl/metafile.dat
    sed -i 's/wan1_service_cwmp=1/wan1_service_cwmp=0/g' /etc/wwwctrl/metafile.dat
fi

if ! grep -q "hdm.telecom.kz" /etc/hosts; then
    echo "127.0.0.1 hdm.telecom.kz" >> /etc/hosts
fi

# 2. Патч OMCI демона (маска 0x0ff3 сохраняет SIP VoIP на pon1.4090, но запрещает удалять мосты)
echo "${C_YELLOW}[2/5] Патчинг OMCI окружения (Anti-Reset + сохранение VoIP)...${C_RESET}"
mkdir -p /etc/omci
cat > /etc/omci/custom_env << 'EOF'
batchtab_wanif_feature 0x0ff3
mib_uni_adminlock_default 0
EOF

sed -i 's/<batchtab_wanif_feature>.*<\/batchtab_wanif_feature>/<batchtab_wanif_feature>0x0ff3<\/batchtab_wanif_feature>/g' /etc/omci/omcienv.xml 2>/dev/null || true
sed -i 's/<mib_uni_adminlock_default>.*<\/mib_uni_adminlock_default>/<mib_uni_adminlock_default>0<\/mib_uni_adminlock_default>/g' /etc/omci/omcienv.xml 2>/dev/null || true

omcicli -c "env batchtab_wanif_feature 0x0ff3" 2>/dev/null || true
omcicli -c "env mib_uni_adminlock_default 0" 2>/dev/null || true

# 3. Разблокировка портов свитча и снятие изоляции
echo "${C_YELLOW}[3/5] Активация портов свитча и снятие изоляции...${C_RESET}"
diag port set port 0-3 state enable 2>/dev/null || true
diag port set port 0-3 link-up enable 2>/dev/null || true
diag port set port 0-3 isolation-set 0 2>/dev/null || true

# 4. Патч веб-интерфейса (разблокировка Layer 2 Bridged для Default WAN)
echo "${C_YELLOW}[4/5] Разблокировка 'Layer 2 Bridged' в родной веб-админке...${C_RESET}"
HTML="/opt/httpd/data/pages/support/support_wan_setting_ipv6.html"
CMD="/opt/httpd/data/cgi-bin/service_wan_vlan_setting.cmd"

if [ -f "$HTML" ]; then
    sed -i 's/hidden_elem: \[".ipv4_dake"\]/hidden_elem: \[\]/g' "$HTML"
fi

if [ -f "$CMD" ]; then
    sed -i 's/echo "This Vlan ID has been used, Please choose another one." && exit/# echo "VLAN allowed" #/' "$CMD"
fi

# 5. Установка удобной CLI-команды `calix`
echo "${C_YELLOW}[5/5] Установка консольной утилиты 'calix'...${C_RESET}"
cat > /usr/bin/calix << 'EOF'
#!/bin/sh
ACTION=$1
VLAN=$2
PORT=$3

usage() {
    echo "Использование утилиты calix:"
    echo "  calix status                           - Показать состояние WAN, моста, VoIP и оптики"
    echo "  calix bridge <VLAN_ID> <LAN_PORT 1-4>  - Пробросить VLAN на указанный LAN порт"
    echo "  calix route <VLAN_ID>                  - Вернуть режим роутера (Routed IPoE)"
    echo "  calix optical                          - Показать уровень оптического сигнала (dBm)"
    echo "  calix unlock                           - Разблокировать все 4 LAN-порта"
    echo ""
    echo "Пример (перевести VLAN 40 в мост на LAN2):"
    echo "  calix bridge 40 2"
    exit 1
}

case "$ACTION" in
    status)
        echo "=== WAN & Bridge State ==="
        grep -E '^(dev_wan1_|wan1_enable|wan1_if_name|brwan1_enable|brwan1_vid|brwan1_portmask|brwan1_name)' /etc/wwwctrl/metafile.dat
        echo ""
        echo "=== VoIP SIP Telephony (pon1.4090) ==="
        ifconfig pon1.4090 2>/dev/null | grep -E '(inet addr|RX packets)' || echo "SIP интерфейс не поднят"
        echo ""
        echo "=== OMCI Anti-Reset ==="
        omcicli -c "env batchtab_wanif_feature" 2>/dev/null || grep -o '<batchtab_wanif_feature>.*</batchtab_wanif_feature>' /etc/omci/omcienv.xml 2>/dev/null
        ;;
    bridge)
        [ -z "$VLAN" ] || [ -z "$PORT" ] && usage
        SHIFT=$((PORT - 1))
        PORTMASK=$(printf "0x%x" $((1 << SHIFT)))
        echo "[*] Включение моста: VLAN $VLAN -> LAN$PORT (mask $PORTMASK)..."
        META_TMP=/tmp/br_apply.$$
        cat > $META_TMP << EO_BR
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
EO_BR
        /etc/init.d/cmd_dispatcher.sh diff $META_TMP >/dev/null 2>&1
        rm -f $META_TMP
        diag port set port 0-3 isolation-set 0 2>/dev/null || true
        diag port set port 0-3 state enable 2>/dev/null || true
        sync; sync
        echo "[+] Готово! Мост активирован на порт LAN$PORT."
        ;;
    route)
        [ -z "$VLAN" ] && VLAN=40
        echo "[*] Возврат в режим роутера (Routed IPoE)..."
        META_TMP=/tmp/rt_apply.$$
        cat > $META_TMP << EO_RT
dev_wan1_interface=pon2.${VLAN}
wan1_enable=1
wan1_if_name=ipoe_veip1-${VLAN}
brwan1_enable=0
brwan1_name=
brwan1_vid=0
brwan1_portmask=0
system_default_route_interface=dev_wan1_interface
EO_RT
        /etc/init.d/cmd_dispatcher.sh diff $META_TMP >/dev/null 2>&1
        rm -f $META_TMP
        sync; sync
        echo "[+] Готово! Роутер возвращен в дефолтный режим."
        ;;
    optical)
        /etc/init.d/bosa.sh report 2>/dev/null || echo "BOSA модуль не отвечает"
        ;;
    unlock)
        diag port set port 0-3 state enable 2>/dev/null || true
        diag port set port 0-3 link-up enable 2>/dev/null || true
        diag port set port 0-3 isolation-set 0 2>/dev/null || true
        echo "[+] Все 4 порта свитча разблокированы."
        ;;
    *)
        usage
        ;;
esac
EOF

chmod +x /usr/bin/calix 2>/dev/null || chmod +x /bin/calix 2>/dev/null || true
sync; sync

echo ""
echo "${C_GREEN}[✔] ПАТЧ УСПЕШНО УСТАНОВЛЕН!${C_RESET}"
echo ""
echo "Теперь ты можешь:"
echo "1. ${C_CYAN}Через веб-морду (Support -> Service WAN VLANs):${C_RESET}"
echo "   Нажать Edit на ipoe_veip1-40, выбрать 'Layer 2 Bridged' и указать LAN-порт."
echo ""
echo "2. ${C_CYAN}Прямо из консоли терминала одной командой:${C_RESET}"
echo "   calix bridge 40 2      # пробросить VLAN 40 на LAN2"
echo "   calix status           # проверить состояние"
echo ""
echo "3. ${C_YELLOW}ВАЖНО ДЛЯ РОУТЕРА ЗА МОДЕМОМ (Keenetic, Mikrotik, Linux):${C_RESET}"
echo "   Казахтелеком требует DHCP Option 60:"
echo "   Option 60 (Vendor ID): ${C_GREEN}813Gv2-2.ONT.dslforum.org${C_RESET}"
echo "   Option 12 (Host name): ${C_GREEN}813Gv2-2${C_RESET}"
echo ""
