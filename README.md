# AmneziaWG для AsusWRT-Merlin

[![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg[![Release](https://img.shields.io/github/v/release/YOUR_USERNAME/asuswrt(https://github.com/YOUR_USERNAME/asuswrt-merlin-amneziawg/releasesный веб-интерфейс для управления AmneziaWG VPN на роутерах с прошивкой AsusWRT-Merlin. Полная поддержка **AmneziaWG 2.0** с расширенной обфускацией для обхода Deep Packet Inspection (DPI).

## 🌟 Возможности

✅ **Полная поддержка AWG 2.0**
- Все параметры обфускации: Jc, Jmin, Jmax, S1-S4, H1-H4
- Protocol Masking (I1-I5): имитация QUIC, DNS, SIP протоколов
- Custom Protocol Signature для маскировки VPN трафика

✅ **Простой веб-интерфейс**
- Интегрирован в меню VPN роутера
- Генерация ключей в один клик
- Готовые пресеты конфигурации
- Импорт/экспорт конфигураций

✅ **Безопасность**
- Kill-switch (блокировка трафика при обрыве VPN)
- Автоматическое переподключение
- Поддержка PresharedKey

✅ **Удобство**
- Автозапуск при загрузке роутера
- CLI интерфейс для управления
- Мониторинг состояния в реальном времени

## 📋 Требования

- AsusWRT-Merlin **388.x** или новее (или **3006.102.1+**)
- Entware установлен
- SSH доступ к роутеру
- ~2 MB свободного места в `/jffs/`

### Поддерживаемые модели

#### ARM64 (64-bit):
- RT-AX88U, RT-AX86U, RT-AX86U Pro
- RT-AX68U, RT-AX58U
- GT-AX11000, GT-AX6000
- И другие ARM64 модели

#### ARMv7 (32-bit):
- RT-AC86U, RT-AC68U
- RT-AC87U, RT-AC3200
- И другие ARMv7 модели

## 🚀 Установка

### Быстрая установка (одна команда):

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/YOUR_USERNAME/asuswrt-merlin-amneziawg/main/install.sh && sh /tmp/install.sh
```

### Ручная установка:

1. **Подключитесь по SSH к роутеру**

2. **Скачайте последний релиз:**
```bash
wget -O /tmp/amneziawg.tar.gz https://github.com/YOUR_USERNAME/asuswrt-merlin-amneziawg/releases/latest/download/asuswrt-merlin-amneziawg.tar.gz
```

3. **Распакуйте в /jffs/addons:**
```bash
tar -xzf /tmp/amneziawg.tar.gz -C /jffs/addons
```

4. **Сделайте скрипт исполняемым:**
```bash
chmod +x /jffs/addons/amneziawg/amneziawg
mv /jffs/addons/amneziawg/amneziawg /jffs/scripts/amneziawg
```

5. **Запустите установку:**
```bash
/jffs/scripts/amneziawg install
```

6. **Готово!** Перезайдите в веб-интерфейс роутера и найдите **VPN → AmneziaWG**

...(продолжите дальнейшую вставку README как в примере в файле README-amneziawg.md или файле  в этом диалоге)

***

Как только сохраните — сообщите мне, и я продолжу рекомендованный следующий этап (например, настройку GitHub Actions, добавление install.sh или иных скриптов/модулей).

[1](https://github.com/Sp0Xik/asuswrt-merlin-amneziawg/edit/main/README.md)
[2](https://github.com/Sp0Xik/asuswrt-merlin-amneziawg/edit/main/README.md)
