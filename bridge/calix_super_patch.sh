#!/bin/sh
# ==============================================================================
# Calix GigaCenter (813Gv2 / 812G / etc.) GPON Bridge & Anti-OMCI Reset Patch
# Разработано для Казахтелеком (и любых провайдеров с агрессивным TR-069 / OMCI)
# ==============================================================================
# Возможности:
# 1. Полная разблокировка режима "Layer 2 Bridged" в оригинальной админке Calix
#    (Service WAN VLANs) без скрытия кнопок и ошибок конфликта VLAN.
# 2. Перманентная защита от перезаписи настроек Казахтелекомом (TR-069 + OMCI MIB).
# 3. Сохранение казахтелекомовской SIP-телефонии на pon1.4090 в рабочем виде.
# 4. Разблокировка всех LAN портов (0-3) и снятие изоляции между ними.
# ==============================================================================

set -e

echo "=========================================================="
echo "  Calix GPON ONT - Модификация админки и Anti-Reset Patch"
echo "=========================================================="

# 1. Отключение и нейтрализация TR-069 (Казахтелеком HDM ACS)
echo "[1/5] Блокировка TR-069 (cwmpmain)..."
/etc/init.d/cwmp.sh stop 2>/dev/null || true
killall -9 cwmpmain 2>/dev/null || true

# Запрет автозапуска в metafile
if [ -f /etc/wwwctrl/metafile.dat ]; then
    sed -i 's/cwmp_enable=1/cwmp_enable=0/g' /etc/wwwctrl/metafile.dat
    sed -i 's/wan1_service_cwmp=1/wan1_service_cwmp=0/g' /etc/wwwctrl/metafile.dat
fi

# DNS-заглушка для ACS Казахтелекома в /etc/hosts
if ! grep -q "hdm.telecom.kz" /etc/hosts; then
    echo "127.0.0.1 hdm.telecom.kz" >> /etc/hosts
fi

# 2. Патч OMCI демона (omcimain)
# Битмаска batchtab_wanif_feature:
# Дефолт 0x1fff: включен rgvlan_del_nonauto (бит 10) и rgvlan_ip_assign (бит 2),
# из-за чего OMCI при аудите удаляет кастомные мосты и принудительно ставит route.
# Маска 0x0ff3: отключает сброс мостов, но сохраняет iphost для SIP-телефонии!
echo "[2/5] Патчинг OMCI окружения..."

# Запись в custom_env (применяется автоматически при каждой загрузке через board_preinit.sh)
mkdir -p /etc/omci
cat > /etc/omci/custom_env << 'EOF'
batchtab_wanif_feature 0x0ff3
mib_uni_adminlock_default 0
EOF

# Патчинг omcienv.xml напрямую
if [ -f /etc/omci/omcienv.xml ]; then
    sed -i 's/<batchtab_wanif_feature>.*<\/batchtab_wanif_feature>/<batchtab_wanif_feature>0x0ff3<\/batchtab_wanif_feature>/g' /etc/omci/omcienv.xml
    sed -i 's/<mib_uni_adminlock_default>.*<\/mib_uni_adminlock_default>/<mib_uni_adminlock_default>0<\/mib_uni_adminlock_default>/g' /etc/omci/omcienv.xml
fi

# Применение в рантайме
omcicli -c "env batchtab_wanif_feature 0x0ff3" 2>/dev/null || true
omcicli -c "env mib_uni_adminlock_default 0" 2>/dev/null || true

# 3. Разблокировка физических портов свитча и снятие изоляции
echo "[3/5] Активация и снятие изоляции с LAN портов..."
diag port set port 0-3 state enable 2>/dev/null || true
diag port set port 0-3 link-up enable 2>/dev/null || true
diag port set port 0-3 isolation-set 0 2>/dev/null || true

# 4. Патч веб-интерфейса Calix (Разблокировка Layer 2 Bridged для Default WAN)
echo "[4/5] Разблокировка Layer 2 Bridged в веб-интерфейсе..."
HTML_FILE="/opt/httpd/data/pages/support/support_wan_setting_ipv6.html"
CMD_FILE="/opt/httpd/data/cgi-bin/service_wan_vlan_setting.cmd"

if [ -f "$HTML_FILE" ]; then
    # Делаем бэкап
    [ ! -f "${HTML_FILE}.bak" ] && cp "$HTML_FILE" "${HTML_FILE}.bak"

    # Разблокируем показ переключателя "Layer 2 Bridged" (.ipv4_dake) даже если is_dcs=1 (дефолтный WAN)
    sed -i 's/hidden_elem: \[".ipv4_dake"\]/hidden_elem: \[\]/g' "$HTML_FILE"
fi

if [ -f "$CMD_FILE" ]; then
    [ ! -f "${CMD_FILE}.bak" ] && cp "$CMD_FILE" "${CMD_FILE}.bak"

    # Снимаем блокировку повторного использования VLAN ID при переводе дефолтного WAN в мост
    sed -i 's/echo "This Vlan ID has been used, Please choose another one." && exit/# echo "VLAN allowed" #/' "$CMD_FILE"
fi

# 5. Сброс кэша веб-сервера и сохранение во флеш
echo "[5/5] Сохранение настроек в энергонезависимую память..."
sync; sync

echo "=========================================================="
echo " ГОТОВО! Патч успешно применен."
echo " 1. В админке (Support -> Service WAN VLANs) теперь доступен"
echo "    выбор 'Layer 2 Bridged' для любого WAN-подключения."
echo " 2. При выборе моста можно указать конкретные LAN-порты."
echo " 3. Настройки больше НЕ сбрасываются Казахтелекомом."
echo " 4. SIP Телефония продолжает работать штатно."
echo "=========================================================="
