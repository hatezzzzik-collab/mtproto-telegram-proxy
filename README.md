# 🛡 MTProto Proxy (All-in-One Script)

Простой и удобный скрипт для установки и управления MTProto Proxy через Docker.

## 🚀 Возможности
- HEX secret (fake-TLS)
- Домен вместо IP
- Авто-проверка DNS
- Поддержка TAG
- Один файл управления

## 📦 Установка
git clone https://github.com/yourusername/mtproto-proxy.git
cd mtproto-proxy
chmod +x install.sh
sudo ./install.sh install

## 🌐 Важно
Создай A-запись:
mtproto1.cfd → ВАШ_IP

## ⚙️ Команды
sudo ./install.sh install
sudo ./install.sh domain
./install.sh link

## 🔗 Пример
https://t.me/proxy?server=mtproto1.cfd&port=443&secret=SECRET