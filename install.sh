#!/bin/bash
# ============================================
# MTProto Proxy — полный скрипт установки и управления
# ============================================
set -e

CONFIG_DIR="/opt/mtg"
ENV_FILE="$CONFIG_DIR/env"
DOCKER_IMAGE="nineseconds/mtg:2"

mkdir -p "$CONFIG_DIR"

# -------------------------------
# Инициализация файла env
# -------------------------------
if [ ! -f "$ENV_FILE" ]; then
  echo "DOMAIN=\"$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')\"" > "$ENV_FILE"
  echo "PORT=\"443\"" >> "$ENV_FILE"
  RAND_PART=$(head -c 16 /dev/urandom | xxd -ps -c 256)
  echo "SECRET=\"ee${RAND_PART}7777772e6f7a6f6e2e7275\"" >> "$ENV_FILE"  # www.ozon.ru
  echo "FAKE_TLS=\"www.ozon.ru\"" >> "$ENV_FILE"
  echo "TAG=\"\"" >> "$ENV_FILE"
fi

# -------------------------------
# Загружаем конфиг
# -------------------------------
source "$ENV_FILE"

save_env() {
  cat > "$ENV_FILE" <<EOF
DOMAIN="$DOMAIN"
PORT="$PORT"
SECRET="$SECRET"
FAKE_TLS="$FAKE_TLS"
TAG="$TAG"
EOF
}

# -------------------------------
# Генерация нового секрета
# -------------------------------
regen_secret() {
  RAND_PART=$(head -c 16 /dev/urandom | xxd -ps -c 256)
  SECRET="ee${RAND_PART}$(echo -n "$FAKE_TLS" | xxd -ps -c 256)"
  save_env
  echo "🔑 Новый секрет: $SECRET"
}

# -------------------------------
# Команды
# -------------------------------
case "$1" in

install)
  echo "📦 Проверяем Docker..."
  if ! command -v docker &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq docker.io
    systemctl enable --now docker
  fi

  echo "🚀 Запуск MTProto Proxy..."
  cat > "$CONFIG_DIR/config.toml" <<EOF
secret = "$SECRET"
bind-to = "0.0.0.0:$PORT"
prefer-ip = "prefer-ipv4"
allow-fallback-on-unknown-dc = true
concurrency = 8192
tolerate-time-skewness = "5s"

[network]
doh-ip = "1.1.1.1"

[network.timeout]
tcp = "10s"
http = "10s"
idle = "60s"
EOF

  docker rm -f mtg 2>/dev/null || true
  docker run -d \
    --name mtg \
    --restart always \
    -p "$PORT:$PORT" \
    -v "$CONFIG_DIR/config.toml:/config.toml:ro" \
    $DOCKER_IMAGE run /config.toml >/dev/null

  sleep 2

  if docker ps | grep -q mtg; then
    echo "✅ Прокси запущен"
  else
    echo "❌ Ошибка запуска! Логи:"
    docker logs mtg
    exit 1
  fi

  echo ""
  echo "📎 Ссылка для подключения:"
  echo "https://t.me/proxy?server=$DOMAIN&port=$PORT&secret=$SECRET"
  ;;

link)
  echo "https://t.me/proxy?server=$DOMAIN&port=$PORT&secret=$SECRET"
  ;;

regen)
  regen_secret
  ;;

domain)
  read -p "Введите новый домен/IP: " DOMAIN
  save_env
  echo "🌐 Новый домен/IP: $DOMAIN"
  ;;

faketls)
  read -p "Введите новый fake-TLS (по умолчанию www.ozon.ru): " FAKE_TLS
  save_env
  echo "🕵️ Новый fake-TLS: $FAKE_TLS"
  ;;

tag)
  read -p "Введите новый TAG от MTProxybot: " TAG
  save_env
  echo "🏷 TAG обновлён: $TAG"
  ;;

restart)
  docker restart mtg
  echo "🔄 Прокси перезапущен"
  ;;

*)
  echo "Команды:"
  echo "  install   — установка прокси"
  echo "  link      — показать ссылку"
  echo "  regen     — новый секрет"
  echo "  domain    — сменить домен"
  echo "  faketls   — сменить fake-TLS"
  echo "  tag       — сменить TAG"
  echo "  restart   — перезапуск"
  echo ""
  echo "Для удобства можно сделать симлинк:"
  echo "sudo ln -s $CONFIG_DIR/install.sh /usr/local/bin/mtproxy"
  echo "Тогда команды будут короче, например: mtproxy install"
  ;;
esac
