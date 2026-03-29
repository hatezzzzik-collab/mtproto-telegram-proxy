#!/bin/bash
set -e

CONFIG_DIR="/opt/mtg"
CONFIG_FILE="$CONFIG_DIR/config.toml"
ENV_FILE="$CONFIG_DIR/env"
CONTAINER_NAME="mtg"

# -------------------------------
# Генерация HEX секрета (32 байта)
# -------------------------------
gen_secret() {
    echo "ee$(openssl rand -hex 16)"
}

# -------------------------------
# Загрузка конфига
# -------------------------------
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
}

# -------------------------------
# Сохранение конфига
# -------------------------------
save_env() {
    cat > "$ENV_FILE" <<EOF
DOMAIN="$DOMAIN"
PORT="$PORT"
SECRET="$SECRET"
TAG="$TAG"
EOF
}

# -------------------------------
# Создание config.toml
# -------------------------------
generate_config() {
    cat > "$CONFIG_FILE" <<EOF
secret = "${SECRET}"
bind-to = "0.0.0.0:${PORT}"
prefer-ip = "prefer-ipv4"
allow-fallback-on-unknown-dc = true
concurrency = 8192

$( [ -n "$TAG" ] && echo "tag = \"$TAG\"" )

[network]
doh-ip = "1.1.1.1"
EOF
}

# -------------------------------
# Запуск / перезапуск
# -------------------------------
restart_proxy() {
    docker rm -f $CONTAINER_NAME 2>/dev/null || true

    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        -p 443:${PORT} \
        -v $CONFIG_FILE:/config.toml:ro \
        nineseconds/mtg:2 run /config.toml >/dev/null

    echo "✅ Прокси перезапущен"
}

# -------------------------------
# Установка
# -------------------------------
install() {
    mkdir -p $CONFIG_DIR

    echo "👉 Введите домен или IP:"
    read DOMAIN

    echo "👉 Введите порт (например 3128):"
    read PORT

    echo "👉 Введите TAG (или Enter чтобы пропустить):"
    read TAG

    SECRET=$(gen_secret)

    save_env
    generate_config
    restart_proxy

    echo ""
    echo "🚀 Установлено!"
    show_link
}

# -------------------------------
# Показ ссылки
# -------------------------------
show_link() {
    load_env

    echo ""
    echo "🔗 Ваша ссылка:"
    echo "https://t.me/proxy?server=${DOMAIN}&port=443&secret=${SECRET}"
    echo ""
}

# -------------------------------
# Смена секрета
# -------------------------------
regen_secret() {
    load_env

    SECRET=$(gen_secret)
    echo "🔑 Новый секрет: $SECRET"

    save_env
    generate_config
    restart_proxy

    echo "✅ Секрет обновлён"
    show_link
}

# -------------------------------
# Смена домена/IP
# -------------------------------
set_domain() {
    load_env

    echo "👉 Новый домен/IP:"
    read DOMAIN

    save_env
    show_link
}

# -------------------------------
# Смена TAG
# -------------------------------
set_tag() {
    load_env

    echo "👉 Новый TAG:"
    read TAG

    save_env
    generate_config
    restart_proxy

    echo "✅ TAG обновлён"
}

# -------------------------------
# Установка Docker
# -------------------------------
install_docker() {
    if ! command -v docker &>/dev/null; then
        echo "📦 Устанавливаю Docker..."
        apt-get update -qq
        apt-get install -y -qq docker.io >/dev/null 2>&1
        systemctl enable --now docker >/dev/null 2>&1
    fi
}

# -------------------------------
# CLI команды
# -------------------------------
case "$1" in
    install)
        install_docker
        install
        ;;
    link)
        show_link
        ;;
    regen)
        regen_secret
        ;;
    domain)
        set_domain
        ;;
    tag)
        set_tag
        ;;
    restart)
        load_env
        restart_proxy
        ;;
    *)
        echo ""
        echo "Использование:"
        echo "  $0 install   — установка"
        echo "  $0 link      — показать ссылку"
        echo "  $0 regen     — новый секрет"
        echo "  $0 domain    — сменить домен/IP"
        echo "  $0 tag       — сменить TAG"
        echo "  $0 restart   — перезапуск"
        echo ""
        ;;
esac
