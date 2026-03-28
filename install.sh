#!/bin/bash
set -e

CONFIG="/opt/mtg/config.toml"

# --- функции ---
generate_secret() {
    DOMAIN=$1
    HEX=$(openssl rand -hex 16)
    DHEX=$(echo -n "$DOMAIN" | xxd -ps)
    echo "ee${HEX}${DHEX}"
}

get_secret() {
    grep secret $CONFIG 2>/dev/null | cut -d '"' -f2
}

get_ip() {
    curl -4 -s ifconfig.me || hostname -I | awk '{print $1}'
}

check_dns() {
    HOST=$1
    SERVER_IP=$(get_ip)
    RESOLVED_IP=$(getent ahosts $HOST | awk '{print $1}' | head -n1)

    if [ -z "$RESOLVED_IP" ]; then
        echo "❌ DNS не резолвится"
        exit 1
    fi

    if [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
        echo "❌ DNS указывает на $RESOLVED_IP, а сервер $SERVER_IP"
        exit 1
    fi
}

install_proxy() {
    echo "🚀 Установка прокси"

    if ! command -v docker &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq docker.io
        systemctl enable --now docker
    fi

    read -p "🌐 Домен (mtproto1.cfd): " HOST
    [ -z "$HOST" ] && echo "❌ нужен домен" && exit 1

    check_dns "$HOST"

    read -p "🌐 Fake TLS (Enter = www.ozon.ru): " FAKE
    FAKE=${FAKE:-www.ozon.ru}

    SECRET=$(generate_secret "$FAKE")

    read -p "TAG (Enter пропустить): " TAG

    mkdir -p /opt/mtg

    cat > $CONFIG <<EOF
secret = "${SECRET}"
bind-to = "0.0.0.0:3128"
EOF

    docker rm -f mtg 2>/dev/null || true

    docker run -d \
        --name mtg \
        --restart always \
        -p 443:3128 \
        -v $CONFIG:/config.toml:ro \
        nineseconds/mtg:2 run /config.toml

    if [ -n "$TAG" ]; then
        LINK="https://t.me/proxy?server=${HOST}&port=443&secret=${SECRET}&tag=${TAG}"
    else
        LINK="https://t.me/proxy?server=${HOST}&port=443&secret=${SECRET}"
    fi

    echo ""
    echo "✅ ГОТОВО:"
    echo "$LINK"
}

change_domain() {
    read -p "Новый fake-TLS домен: " DOMAIN

    SECRET=$(generate_secret "$DOMAIN")

    sed -i "s|secret = \".*\"|secret = \"$SECRET\"|" $CONFIG

    docker restart mtg

    echo "✅ Обновлено"
    echo "🔑 $SECRET"
}

show_link() {
    read -p "Домен/IP: " HOST

    SECRET=$(get_secret)

    echo ""
    echo "📎 Ссылка:"
    echo "https://t.me/proxy?server=$HOST&port=443&secret=$SECRET"
}

# --- меню ---
case "$1" in
    install)
        install_proxy
        ;;
    domain)
        change_domain
        ;;
    link)
        show_link
        ;;
    *)
        echo ""
        echo "Использование:"
        echo "  ./install.sh install   — установка"
        echo "  ./install.sh domain    — сменить fake-TLS"
        echo "  ./install.sh link      — получить ссылку"
        echo ""
        ;;
esac