#!/bin/bash
set -e

# -------------------------------
# Настройки GitHub
# -------------------------------
REPO_RAW="https://raw.githubusercontent.com/hatezzzzik-collab/mtproto-telegram-proxy/main"
SCRIPT_NAME="script.sh"
CONFIG_DIR="/opt/mtg"

# -------------------------------
# Создаём папку
# -------------------------------
mkdir -p "$CONFIG_DIR"

# -------------------------------
# Скачиваем основной скрипт
# -------------------------------
echo "📥 Скачиваем основной скрипт на сервер..."
curl -sSL "$REPO_RAW/$SCRIPT_NAME" -o "$CONFIG_DIR/$SCRIPT_NAME"

# Делаем исполняемым
chmod +x "$CONFIG_DIR/$SCRIPT_NAME"

# -------------------------------
# Информация для пользователя
# -------------------------------
echo ""
echo "✅ Файлы загружены в $CONFIG_DIR"
echo ""
echo "Теперь используйте команды через скрипт:"
echo ""
echo "$CONFIG_DIR/$SCRIPT_NAME install   — установка прокси"
echo "$CONFIG_DIR/$SCRIPT_NAME link      — показать ссылку"
echo "$CONFIG_DIR/$SCRIPT_NAME regen     — новый секрет"
echo "$CONFIG_DIR/$SCRIPT_NAME domain    — сменить домен"
echo "$CONFIG_DIR/$SCRIPT_NAME faketls   — сменить fake-TLS"
echo "$CONFIG_DIR/$SCRIPT_NAME tag       — сменить TAG"
echo "$CONFIG_DIR/$SCRIPT_NAME restart   — перезапуск"
echo ""
echo "Для удобства можно сделать симлинк:"
echo "sudo ln -s $CONFIG_DIR/$SCRIPT_NAME /usr/local/bin/mtproxy"
echo "Тогда команды будут короче, например: mtproxy link"
