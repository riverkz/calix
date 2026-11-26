# Настройка Keenetic за Calix ONT (Казахтелеком IPoE)

Казахтелеком выдает белый публичный IP по DHCP только при передаче специального идентификатора **Option 60 (Vendor Class Identifier)**.

### Вариант 1. Через Web-интерфейс Keenetic
1. Откройте панель управления Keenetic (`192.168.1.1` или `my.keenetic.net`).
2. Перейдите в раздел **«Сетевые правила» -> «Интернет» -> «Провайдер» (или Ethernet)**.
3. В параметрах IP выберите **«Автоматическая (DHCP)»**.
4. Найдите блок **«Параметры DHCP» / «Дополнительные параметры»**:
   - В поле **Имя хоста (Option 12)**: `813Gv2-2`
   - В поле **Идентификатор класса поставщика (Option 60 / Vendor-class)**: `813Gv2-2.ONT.dslforum.org`
5. Нажмите **«Сохранить»**.

---

### Вариант 2. Через командную строку (CLI / Telnet / SSH Keenetic)
```text
interface GigabitEthernet0/Vlan2
    ip dhcp client hostname 813Gv2-2
    ip dhcp client vendor-id 813Gv2-2.ONT.dslforum.org
system configuration save
```
*(Замените имя интерфейса на ваш внешний WAN-интерфейс, например ISP или GigabitEthernet0/Vlan2)*
