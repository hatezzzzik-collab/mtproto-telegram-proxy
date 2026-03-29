#!/bin/bash
set -e

CONFIG_DIR="/opt/mtg"
CONFIG_FILE="$CONFIG_DIR/config.toml"
ENV_FILE="$CONFIG_DIR/env"
CONTAINER_NAME="mtg"

# -------------------------------
# HEX кодирование строки
# -------------------------------
to_hex() {
    echo -n "$1" | xxd -ps | tr -d '\n'
}

# -------------------------------
# Генерация fake-TLS секрета
# -------------------------------
gen_secret() {
    RAND=$(openssl rand -hex 16)
    DOMAIN_HEX=$(to_hex "$FAKE_TLS")
    echo "ee${RAND}${DOMAIN_HEX}"
}

# -------------------------------
# Загрузка
# -------------------------------
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
}

# -------------------------------
# Сохранение
# -------------------------------
save_env() {
    cat > "$ENV_FILE" <<EOF
DOMAIN="$DOMAIN"
PORT="$PORT"
SECRET="$SECRET"
TAG="$TAG"
FAKE_TLS="$FAKE_TLS"
EOF
}

# -------------------------------
# Конфиг
# -------------------------------
generate_config() {
    cat > "$CONFIG_FILE" <<EOF
secret = "${SECRET}"
bind-to = "0.0.0.0:${PORT}"
prefer-ip = "prefer-ipv4"

$( [ -n "$TAG" ] && echo "tag = \"$TAG\"" )

[network]
doh-ip = "1.1.1.1"
EOF
}

# -------------------------------
# Перезапуск
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

    echo "👉 Домен или IP:"
    read DOMAIN

    echo "👉 Порт (например 3128):"
    read PORT

    echo "👉 TAG (Enter чтобы пропустить):"
    read TAG

    FAKE_TLS="www.ozon.ru"

    SECRET=$(gen_secret)

    save_env
    generate_config
    restart_proxy

    echo "🚀 Установлено!"
    show_link
}

# -------------------------------
# Показ ссылки
# -------------------------------
show_link() {
    load_env

    echo ""
    echo "🔗 Ссылка:"
    echo "https://t.me/proxy?server=${DOMAIN}&port=443&secret=${SECRET}"
    echo "🌐 Fake-TLS: ${FAKE_TLS}"
    echo ""
}

# -------------------------------
# Новый секрет
# -------------------------------
regen_secret() {
    load_env

    SECRET=$(gen_secret)

    save_env
    generate_config
    restart_proxy

    echo "🔑 Секрет обновлён"
    show_link
}

# -------------------------------
# Смена fake-TLS
# -------------------------------
set_fake_tls() {
    load_env

    echo "👉 Новый fake-TLS домен:"
    read FAKE_TLS

    SECRET=$(gen_secret)

    save_env
    generate_config
    restart_proxy

    echo "✅ Fake-TLS обновлён"
    show_link
}

# -------------------------------
# Смена домена
# -------------------------------
set_domain() {
    load_env

    echo "👉 Новый домен/IP:"
    read DOMAIN

    save_env
    show_link
}

# -------------------------------
# TAG
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
# Docker
# -------------------------------
install_docker() {
    if ! command -v docker &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq docker.io >/dev/null 2>&1
        systemctl enable --now docker >/dev/null 2>&1
    fi
}

# -------------------------------
# CLI
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
    faketls)
        set_fake_tls
        ;;
    restart)
        load_env
        restart_proxy
        ;;
    *)
        echo ""
        echo "Команды:"
        echo "  install   — установка"
        echo "  link      — ссылка"
        echo "  regen     — новый секрет"
        echo "  domain    — сменить домен"
        echo "  tag       — сменить TAG"
        echo "  faketls   — сменить fake-TLS"
        echo "  restart   — перезапуск"
        echo ""
        ;;
esac
