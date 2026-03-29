#!/bin/bash
set -e

CONFIG="/opt/mtg/config.toml"

generate_secret() {
    DOMAIN=$1
    HEX=$(openssl rand -hex 16)
    DHEX=$(echo -n "$DOMAIN" | xxd -ps)
    echo "ee${HEX}${DHEX}"
}

get_ip() {
    curl -4 -s ifconfig.me || hostname -I | awk '{print $1}'
}

check_dns() {
    HOST=$1
    SERVER_IP=$(get_ip)
    RESOLVED_IP=$(getent ahosts $HOST | awk '{print $1}' | head -n1)

    if [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
        echo "❌ DNS mismatch: $RESOLVED_IP != $SERVER_IP"
        exit 1
    fi
}

install_proxy() {
    HOST=$1
    FAKE=$2
    TAG=$3

    # если не передали — спрашиваем
    if [ -z "$HOST" ]; then
        read -p "🌐 Домен: " HOST
    fi

    if [ -z "$FAKE" ]; then
        FAKE="www.ozon.ru"
    fi

    echo "🌐 Домен: $HOST"
    echo "🌐 Fake-TLS: $FAKE"

    check_dns "$HOST"

    if ! command -v docker &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq docker.io
        systemctl enable --now docker
    fi

    SECRET=$(generate_secret "$FAKE")

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

case "$1" in
    install)
        install_proxy "$2" "$3" "$4"
        ;;
    *)
        echo ""
        echo "Использование:"
        echo "bash <(curl -sL URL) install <domain> [fakeTLS] [tag]"
        echo ""
        ;;
esac
