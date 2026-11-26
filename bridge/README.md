# Calix GPON ONT Bridge & Anti-OMCI Tool 🚀

> **Комплексное решение для перевода оптических терминалов Calix (813Gv2-1, 813Gv2-2, 812G и др.) в прозрачный режим Bridge (мост) без сбросов со стороны провайдера (Казахтелеком и др.) и с сохранением SIP-телефонии.**

[![Platform](https://img.shields.io/badge/Platform-Calix%20Luna%20SDK%20%7C%20Realtek%20RTL960x-blue.svg)](#)
[![ISP](https://img.shields.io/badge/Tested%20ISP-Kazakhtelecom%20(VLAN%2040)-green.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)](#)

---

## ⚡ Быстрая установка (One-Liner)

Подключитесь к Calix по SSH (`ssh support@192.168.1.1`, пароль `support`) и выполните одну команду:

### Через `curl`:
```sh
curl -ksSL https://raw.githubusercontent.com/riverkz/calix/refs/heads/main/bridge/install.sh | sh
```

### Через `wget`:
```sh
wget -qO- --no-check-certificate https://raw.githubusercontent.com/riverkz/calix/refs/heads/main/bridge/install.sh | sh
```

---

## 🎯 Что решает этот проект?

У абонентов GPON Казахтелекома и других провайдеров, использующих ONT Calix, стандартно возникают следующие проблемы:
1. **Скрыт мост в веб-интерфейсе:** Для дефолтного профиля интернета (`is_dcs=1`, VLAN 40) вендор принудительно скрывает радиокнопку `Layer 2 Bridged`.
2. **Агрессивный TR-069:** Демон `cwmpmain` постоянно рапортует на `hdm.telecom.kz` и откатывает конфиг.
3. **OMCI MIB Audit Reset:** При проверке конфигурации с OLT демон `omcimain` (битовая маска `0x1fff`) сносит любые пользовательские мосты обратно в `layer3routed`.
4. **Падение телефонии:** При наивных попытках отключить OMCI отваливается SIP VoIP Казахтелекома.
5. **Изоляция портов:** Аппаратный свитч изолирует порты LAN, не пропуская локальный трафик.

### Решение:
* **Anti-Reset OMCI (`0x0ff3`):** Отключает биты `rgvlan_del_nonauto` и `rgvlan_ip_assign`, блокируя удаление мостов, но **сохраняет `iphost` — казахтелекомовская SIP-телефония на `pon1.4090` продолжает работать!**
* **Отключение TR-069:** Служба глушится, а ACS Казахтелекома отправляется на `127.0.0.1`.
* **Разблокировка Web UI:** Кнопка «Layer 2 Bridged» открывается прямо в родной админке (**Support -> Service WAN VLANs**), а блокировка повторного использования VLAN снимается.
* **Снятие аппаратной изоляции:** Все порты 0–3 открываются на уровне чипа Realtek.
* **Утилита `calix` в системе:** Удобное управление из консоли.

---

## 🛠️ Управление через CLI (Консоль)

После установки в системе доступна утилита `calix`:

```sh
# Пробросить VLAN 40 на порт LAN2 (режим Bridge)
calix bridge 40 2

# Вернуть режим роутера (Layer 3 Routed)
calix route 40

# Проверить статус моста, WAN и телефонии
calix status

# Показать уровень оптического сигнала (BOSA RX/TX power)
calix optical

# Разблокировать все 4 порта LAN
calix unlock
```

---

## 🌐 Управление через Веб-интерфейс (GUI)

1. Откройте `http://192.168.1.1` в браузере.
2. Перейдите в **Support -> Service WAN VLANs**.
3. Нажмите **Edit** напротив `ipoe_veip1-40`.
4. В графе **Connection Type** выберите **Layer 2 Bridged**.
5. Выберите нужный физический порт (например, `Ethernet Port 2`).
6. Нажмите **Apply**.

---

## 📡 Настройка вашего роутера за Calix (Option 60)

Казахтелеком выдает внешний белый IP по DHCP (IPoE) только при наличии **Option 60 (Vendor Class Identifier)**.

| Параметр | Значение |
| :--- | :--- |
| **Option 60 (Vendor Class Identifier)** | `813Gv2-2.ONT.dslforum.org` |
| **Option 12 (Host name)** | `813Gv2-2` |

Готовые конфигурации для популярных систем:
* [Keenetic](configs/keenetic.md)
* [MikroTik RouterOS](configs/mikrotik.rsc)
* [OpenWrt](configs/openwrt.sh)
* [Linux (dhclient)](configs/linux_dhclient.conf)

---

## 📦 Структура репозитория

```
├── install.sh                  # One-liner установщик для curl/wget
├── uninstall.sh                # Скрипт полного отката к заводскому состоянию
├── calix_super_patch.sh        # Исходный скрипт патча
├── calix_cli_bridge.sh         # Исходный скрипт утилиты calix
├── FORUM_POST_GUIDE.md         # Готовый текст для публикации на форумах (4PDA/Habr)
├── tools/
│   └── decrypt_backup.py       # Оффлайн дешифратор/шифратор бэкапов backupsettings.conf
└── configs/
    ├── keenetic.md             # Инструкция для Keenetic
    ├── mikrotik.rsc            # Скрипт для MikroTik
    ├── openwrt.sh              # Скрипт для OpenWrt
    └── linux_dhclient.conf     # Конфиг dhclient для Linux
```

---

## 🔄 Как откатить назад?

Если вам нужно вернуть терминал в полностью исходное заводское состояние (например, перед визитом монтера или сдачей оборудования):

```sh
curl -ksSL https://raw.githubusercontent.com/riverkz/calix/refs/heads/main/bridge/uninstall.sh | sh
```
Скрипт восстановит оригинальные файлы веб-интерфейса, вернет дефолтную маску OMCI `0x1fff`, запустит TR-069 и восстановит режим роутера.

---

## ⚠️ Отказ от ответственности (Disclaimer)
Все действия вы выполняете на свой страх и риск. Автор не несет ответственности за возможные санкции со стороны провайдера.
