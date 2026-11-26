# MikroTik RouterOS: Настройка DHCP-клиента для Казахтелеком за Calix в режиме Bridge

# 1. Создаем DHCP Option 60 (Vendor Class Identifier)
/ip dhcp-client option add code=60 name=kt-vendor-class value="'813Gv2-2.ONT.dslforum.org'"

# 2. Создаем DHCP Option 12 (Host Name)
/ip dhcp-client option add code=12 name=kt-hostname value="'813Gv2-2'"

# 3. Привязываем опции к вашему WAN-интерфейсу (замените ether1 на ваш порт)
/ip dhcp-client set [find interface=ether1] dhcp-options=kt-vendor-class,kt-hostname,clientid

# 4. Перезапускаем DHCP клиент
/ip dhcp-client release [find interface=ether1]
/ip dhcp-client renew [find interface=ether1]
