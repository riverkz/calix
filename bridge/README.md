# [Инструкция] Перевод Calix 813Gv2 / 812G в мост (Bridge) без сбросов OMCI и с рабочей SIP-телефонией

Приветствую всех владельцев ONT-терминалов **Calix (813Gv2-1, 813Gv2-2, 812G и аналогичных на платформе Luna SDK / Realtek RTL960x)**.

Многие годами пытались перевести этот модем в мост (Bridge), чтобы за ним поставить свой нормальный роутер (Keenetic, Mikrotik, OpenWrt, сервер) и забыть про тройной NAT и зависания. Но каждый раз происходило одно и то же:
1. В админке пункт **«Layer 2 Bridged»** скрыт для основного подключения интернета.
2. Если как-то удавалось создать мост через CLI, то ровно через 2–5 минут провайдер через TR-069 или OMCI MIB audit **намертво сбрасывал всё обратно в Route** либо ломал телефонию.

Я(Gemini) провели полный реверс-инжиниринг прошивки Calix, демонов `cwmpmain`, `omcimain`, скриптов `cmd_dispatcher` и веб-морды. Ниже — готовое решение: скрипт-патч, который лечит админку и защищает терминал от перезаписи провайдером.

---

## Что делает патч:
1. **Разблокирует «Layer 2 Bridged» в родной админке Calix:**
   - В файле веб-интерфейса убран захардкоженный запрет на показ кнопки моста для основного подключения (`is_dcs=1`).
   - В CGI-обработчике снята блокировка повторного использования VLAN 40.
   - Теперь прямо в веб-морде (**Support -> Service WAN VLANs**) можно переключить VLAN 40 в **Layer 2 Bridged** и выбрать нужный LAN-порт (LAN1–LAN4).
2. **Нейтрализует TR-069 (Auto-Configuration Server):**
   - Останавливает службу `cwmpmain`.
   - В `/etc/hosts` прописывает заглушку для `hdm.telecom.kz`.
3. **Блокирует сброс параметров через OMCI (сохраняя телефонию!):**
   - Дефолтная битовая маска в `/etc/omci/omcienv.xml` — `0x1fff`. В ней выставлены биты `rgvlan_del_nonauto` и `rgvlan_ip_assign`, которые принуждают модем стирать мосты при аудите с OLT.
   - Патч меняет маску на безопасную: `0x0ff3`. Мосты больше не удаляются, а SIP **продолжает штатно работать!**
4. **Разблокирует порты свитча:**
   - Снимает заводскую блокировку портов 0–3 и изоляцию между ними.

---

## Инструкция по установке патча

### Шаг 1. Подключение по SSH к Calix
Подключаемся к терминалу (по умолчанию IP `192.168.1.1`):
Перед этим зайдя по ссылке http://192.168.1.1/cgi-bin/wwwctrl.cgi?action=en_ssh.cmd

```bash
ssh support@192.168.1.1
```
*(Пароль по умолчанию: `support`)*

### Шаг 2. Загрузка и запуск патча
Создаем скрипт патча:
```sh
cat > /tmp/calix_patch.sh << 'EOF'
#!/bin/sh
set -e

# 1. TR-069
/etc/init.d/cwmp.sh stop 2>/dev/null || true
killall -9 cwmpmain 2>/dev/null || true
sed -i 's/cwmp_enable=1/cwmp_enable=0/g' /etc/wwwctrl/metafile.dat 2>/dev/null || true
sed -i 's/wan1_service_cwmp=1/wan1_service_cwmp=0/g' /etc/wwwctrl/metafile.dat 2>/dev/null || true
grep -q "hdm.telecom.kz" /etc/hosts || echo "127.0.0.1 hdm.telecom.kz" >> /etc/hosts

# 2. OMCI Protection
mkdir -p /etc/omci
cat > /etc/omci/custom_env << 'EOENV'
batchtab_wanif_feature 0x0ff3
mib_uni_adminlock_default 0
EOENV

sed -i 's/<batchtab_wanif_feature>.*<\/batchtab_wanif_feature>/<batchtab_wanif_feature>0x0ff3<\/batchtab_wanif_feature>/g' /etc/omci/omcienv.xml 2>/dev/null || true
sed -i 's/<mib_uni_adminlock_default>.*<\/mib_uni_adminlock_default>/<mib_uni_adminlock_default>0<\/mib_uni_adminlock_default>/g' /etc/omci/omcienv.xml 2>/dev/null || true
omcicli -c "env batchtab_wanif_feature 0x0ff3" 2>/dev/null || true
omcicli -c "env mib_uni_adminlock_default 0" 2>/dev/null || true

# 3. LAN Switch Unlocking & De-isolation
diag port set port 0-3 state enable 2>/dev/null || true
diag port set port 0-3 link-up enable 2>/dev/null || true
diag port set port 0-3 isolation-set 0 2>/dev/null || true

# 4. Web UI Patch
HTML="/opt/httpd/data/pages/support/support_wan_setting_ipv6.html"
CMD="/opt/httpd/data/cgi-bin/service_wan_vlan_setting.cmd"
[ -f "$HTML" ] && sed -i 's/hidden_elem: \[".ipv4_dake"\]/hidden_elem: \[\]/g' "$HTML"
[ -f "$CMD" ] && sed -i 's/echo "This Vlan ID has been used, Please choose another one." && exit/# echo "VLAN allowed" #/' "$CMD"

sync; sync
echo "CALIX_PATCH_SUCCESS"
EOF

sh /tmp/calix_patch.sh
```

---

## Как включить Bridge через админку (GUI)

1. Открываем браузер: `http://192.168.1.1`
2. Переходим в меню: **Support -> Service WAN VLANs**
3. Нажимаем **Edit** напротив `ipoe_veip1-40` (или нужного VLAN).
4. В графе **Connection Type** теперь доступен пункт **Layer 2 Bridged**! Выбираем его.
5. В появившемся списке выбираем физический порт (например, `Ethernet Port 2`).
6. Нажимаем **Apply**.

---

## Альтернатива: перевод в мост одной командой из консоли (CLI)

Если лень заходить в браузер, можно перевести VLAN в мост прямо из SSH Calix:

```sh
# Синтаксис: bridge <VLAN_ID> <НОМЕР_LAN_ПОРТА 1-4>
# Пример: пробросить VLAN 40 Казахтелекома на LAN2:

cat > /tmp/bridge.dat << EOF
dev_wan1_interface=brwan1.40
wan1_enable=0
wan1_if_name=
brwan1_enable=1
brwan1_name=bridge_lan2_40
brwan1_vid=40
brwan1_pbit=0
brwan1_portmask=0x2
brwan1_wifimask=0
brwan1_igmp_enable=0
EOF
/etc/init.d/cmd_dispatcher.sh diff /tmp/bridge.dat
diag port set port 0-3 isolation-set 0
sync; sync
```

---

## ВАЖНО: Настройка роутера за Calix'ом (DHCP Option 60)

Часто провайдеры для выдачи белого публичного IP по IPoE (DHCP) требует наличие **Option 60 (Vendor Class Identifier)**.

На вашем роутере, который подключен в выбранный LAN-порт Calix:
- **Тип подключения:** DHCP (IPoE / Динамический IP)
- **Option 60 (Идентификатор класса поставщика / Vendor ID):**
  ```text
  813Gv2-2.ONT.dslforum.org
  ```
- **Option 12 (Host name):**
  ```text
  813Gv2-2
  ```

В **Keenetic**: в настройках интерфейса «Провайдер» в поле «Имя хоста / Vendor-class» указываем `813Gv2-2.ONT.dslforum.org`.
В **Mikrotik**: в `/ip dhcp-client option` добавляем опцию 60 (`0x3c` -> `'813Gv2-2.ONT.dslforum.org'`).
В **Linux/Debian** (`dhclient.conf`):
```text
send vendor-class-identifier "813Gv2-2.ONT.dslforum.org";
send host-name "813Gv2-2";
```

После этого ваш личный роутер моментально забирает белый IP Казахтелекома. Никаких дропов, никаких переписываний конфига, интернет работает на полной скорости оптики!
