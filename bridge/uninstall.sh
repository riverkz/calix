#!/bin/sh
# ==============================================================================
# Calix GigaCenter: Скрипт полного отката к заводским настройкам
# ==============================================================================

set -e

BACKUP_DIR="/flash/calix_backup_orig"

echo "=== Откат модификаций Calix к исходному состоянию ==="

# 1. Восстановление веб-файлов
if [ -f "$BACKUP_DIR/support_wan_setting_ipv6.html" ]; then
    cp -f "$BACKUP_DIR/support_wan_setting_ipv6.html" /opt/httpd/data/pages/support/
    echo "[+] Восстановлен support_wan_setting_ipv6.html"
fi

if [ -f "$BACKUP_DIR/service_wan_vlan_setting.cmd" ]; then
    cp -f "$BACKUP_DIR/service_wan_vlan_setting.cmd" /opt/httpd/data/cgi-bin/
    echo "[+] Восстановлен service_wan_vlan_setting.cmd"
fi

# 2. Восстановление OMCI
rm -f /etc/omci/custom_env
if [ -f "$BACKUP_DIR/omcienv.xml" ]; then
    cp -f "$BACKUP_DIR/omcienv.xml" /etc/omci/
else
    sed -i 's/<batchtab_wanif_feature>.*<\/batchtab_wanif_feature>/<batchtab_wanif_feature>0x1fff<\/batchtab_wanif_feature>/g' /etc/omci/omcienv.xml 2>/dev/null || true
fi
omcicli -c "env batchtab_wanif_feature 0x1fff" 2>/dev/null || true
echo "[+] Восстановлен дефолтный OMCI"

# 3. Восстановление TR-069
sed -i '/hdm.telecom.kz/d' /etc/hosts 2>/dev/null || true
if [ -f /etc/wwwctrl/metafile.dat ]; then
    sed -i 's/cwmp_enable=0/cwmp_enable=1/g' /etc/wwwctrl/metafile.dat
    sed -i 's/wan1_service_cwmp=0/wan1_service_cwmp=1/g' /etc/wwwctrl/metafile.dat
fi
/etc/init.d/cwmp.sh start 2>/dev/null || true
echo "[+] Восстановлен TR-069"

# 4. Возврат WAN1 в режим Route
if [ -x /usr/bin/calix ]; then
    calix route 40 2>/dev/null || true
    rm -f /usr/bin/calix
fi

sync; sync
echo "=== Готово! Модем возвращен в исходное состояние ==="
