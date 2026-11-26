#!/bin/sh
# OpenWrt: Настройка WAN-интерфейса для Казахтелеком за Calix в режиме Bridge

# Устанавливаем Vendor Class (Option 60) и Hostname (Option 12) в UCI
uci set network.wan.vendorid='813Gv2-2.ONT.dslforum.org'
uci set network.wan.hostname='813Gv2-2'
uci commit network

# Перезапускаем интерфейс WAN
ifup wan

echo "[+] OpenWrt настроен! Проверьте получение IP: ifstatus wan"
