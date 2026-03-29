#!/bin/bash
# ============================================
# MTProto Proxy + @MTProxybot HEX secret + CLI tag manager
# One-file installer: install.sh
# ============================================

set -euo pipefail

BASE_DIR="/opt/mtproxy"
DATA_DIR="${BASE_DIR}/data"
CONF_DIR="${BASE_DIR}/conf"
BIN_PATH="/usr/local/bin/mtproxyctl"
CONTAINER_NAME="mtproxy"
IMAGE="alexdoesh/mtproxy:latest"
EXTERNAL_PORT="443"
INTERNAL_PORT="443"
DEFAULT_FAKE_TLS_DOMAIN="www.google.com"

# -----------------------------
# Helpers
# -----------------------------
log()  { echo -e "$*"; }
ok()   { echo -e "   ✅ $*"; }
warn() { echo -e "   ⚠️  $*"; }
err()  { echo -e "   ❌ $*"; }
die()  { err "$*"; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Запусти скрипт от root: sudo ./install.sh"
  fi
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_packages() {
  log ""
  log "📦 Проверяю зависимости..."

  apt-get update -qq

  local pkgs=()
  cmd_exists curl || pkgs+=(curl)
  cmd_exists xxd  || pkgs+=(xxd)

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    apt-get install -y -qq "${pkgs[@]}" >/dev/null 2>&1
    ok "Установлены пакеты: ${pkgs[*]}"
  else
    ok "curl и xxd уже установлены"
  fi

  if ! cmd_exists docker; then
    log "📦 Устанавливаю Docker..."
    apt-get install -y -qq docker.io >/dev/null 2>&1
    systemctl enable --now docker >/dev/null 2>&1
    ok "Docker установлен"
  else
    ok "Docker уже установлен"
    systemctl enable --now docker >/dev/null 2>&1 || true
  fi
}

get_ip() {
  curl -4 -fsS ifconfig.me 2>/dev/null \
    || curl -4 -fsS icanhazip.com 2>/dev/null \
    || hostname -I | awk '{print $1}'
}

validate_hex32() {
  [[ "$1" =~ ^[0-9a-fA-F]{32}$ ]]
}

lower_hex() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

domain_to_hex() {
  printf "%s" "$1" | xxd -ps -c 256 | tr -d '\n'
}

generate_hex_secret() {
  head -c 16 /dev/urandom | xxd -ps -c 256 | tr -d '\n'
}

ensure_dirs() {
  mkdir -p "$DATA_DIR" "$CONF_DIR"
}

save_value() {
  local path="$1"
  local value="$2"
  printf "%s\n" "$value" > "$path"
  chmod 600 "$path"
}

load_value() {
  local path="$1"
  [[ -f "$path" ]] && cat "$path"
}

build_fake_tls_secret() {
  local bot_secret="$1"
  local domain="$2"
  local domain_hex
  domain_hex="$(domain_to_hex "$domain")"
  printf "ee%s%s" "$bot_secret" "$domain_hex"
}

print_summary() {
  local ip="$1"
  local bot_secret="$2"
  local tag="$3"
  local domain="$4"
  local fake_tls_secret
  local link

  fake_tls_secret="$(build_fake_tls_secret "$bot_secret" "$domain")"
  link="https://t.me/proxy?server=${ip}&port=${EXTERNAL_PORT}&secret=${fake_tls_secret}"

  log ""
  log "========================================="
  log "✅ Готово! Прокси запущен."
  log ""
  log "🌐 IP сервера: ${ip}"
  log "🔑 Secret для @MTProxybot (HEX):"
  log "   ${bot_secret}"
  log ""
  if [[ -n "$tag" ]]; then
    log "🏷  Tag:"
    log "   ${tag}"
    log ""
  else
    log "🏷  Tag: не задан"
    log ""
  fi
  log "🌍 Fake TLS domain:"
  log "   ${domain}"
  log ""
  log "📎 Ссылка для подключения в Telegram:"
  log "   ${link}"
  log ""
  log "🛠  Команды после установки:"
  log "   mtproxyctl status"
  log "   mtproxyctl secret show"
  log "   mtproxyctl tag show"
  log "   mtproxyctl tag set <32hex>"
  log "   mtproxyctl tag clear"
  log "   mtproxyctl domain show"
  log "   mtproxyctl domain set <domain>"
  log "   mtproxyctl link"
  log "   mtproxyctl restart"
  log "========================================="
}

write_cli() {
  cat > "$BIN_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail

BASE_DIR="/opt/mtproxy"
DATA_DIR="${BASE_DIR}/data"
CONF_DIR="${BASE_DIR}/conf"
CONTAINER_NAME="mtproxy"
IMAGE="alexdoesh/mtproxy:latest"
EXTERNAL_PORT="443"
INTERNAL_PORT="443"
DEFAULT_FAKE_TLS_DOMAIN="www.google.com"

BOT_SECRET_FILE="${CONF_DIR}/bot_secret.hex"
TAG_FILE="${CONF_DIR}/tag.hex"
DOMAIN_FILE="${CONF_DIR}/fake_tls_domain.txt"

die() {
  echo "❌ $*" >&2
  exit 1
}

validate_hex32() {
  [[ "$1" =~ ^[0-9a-fA-F]{32}$ ]]
}

lower_hex() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

domain_to_hex() {
  printf "%s" "$1" | xxd -ps -c 256 | tr -d '\n'
}

load_value() {
  local path="$1"
  [[ -f "$path" ]] && cat "$path"
}

save_value() {
  local path="$1"
  local value="$2"
  printf "%s\n" "$value" > "$path"
  chmod 600 "$path"
}

get_ip() {
  curl -4 -fsS ifconfig.me 2>/dev/null \
    || curl -4 -fsS icanhazip.com 2>/dev/null \
    || hostname -I | awk '{print $1}'
}

build_fake_tls_secret() {
  local bot_secret="$1"
  local domain="$2"
  local domain_hex
  domain_hex="$(domain_to_hex "$domain")"
  printf "ee%s%s" "$bot_secret" "$domain_hex"
}

run_container() {
  local bot_secret tag
  bot_secret="$(load_value "$BOT_SECRET_FILE")"
  tag="$(load_value "$TAG_FILE")"

  [[ -n "$bot_secret" ]] || die "Не найден bot secret: $BOT_SECRET_FILE"

  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  if [[ -n "${tag:-}" ]]; then
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart always \
      -p "${EXTERNAL_PORT}:${INTERNAL_PORT}" \
      -v "${DATA_DIR}:/data" \
      -e SECRET="$bot_secret" \
      -e TAG="$tag" \
      "$IMAGE" >/dev/null
  else
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart always \
      -p "${EXTERNAL_PORT}:${INTERNAL_PORT}" \
      -v "${DATA_DIR}:/data" \
      -e SECRET="$bot_secret" \
      "$IMAGE" >/dev/null
  fi

  sleep 2

  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "✅ Контейнер перезапущен"
  else
    echo "❌ Ошибка запуска контейнера. Логи:"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
}

show_status() {
  local bot_secret tag domain ip fake_tls_secret link
  bot_secret="$(load_value "$BOT_SECRET_FILE")"
  tag="$(load_value "$TAG_FILE")"
  domain="$(load_value "$DOMAIN_FILE")"
  [[ -n "$domain" ]] || domain="$DEFAULT_FAKE_TLS_DOMAIN"
  ip="$(get_ip)"
  fake_tls_secret="$(build_fake_tls_secret "$bot_secret" "$domain")"
  link="https://t.me/proxy?server=${ip}&port=${EXTERNAL_PORT}&secret=${fake_tls_secret}"

  echo "Container : $CONTAINER_NAME"
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "Status    : running"
  else
    echo "Status    : stopped"
  fi
  echo "IP        : $ip"
  echo "BotSecret : $bot_secret"
  echo "Tag       : ${tag:-<empty>}"
  echo "Domain    : $domain"
  echo "Link      : $link"
}

usage() {
  cat <<USAGE
Использование:
  mtproxyctl status
  mtproxyctl restart

  mtproxyctl secret show

  mtproxyctl tag show
  mtproxyctl tag set <32hex>
  mtproxyctl tag clear

  mtproxyctl domain show
  mtproxyctl domain set <domain>

  mtproxyctl link
USAGE
}

cmd="${1:-}"

case "$cmd" in
  status)
    show_status
    ;;
  restart)
    run_container
    ;;
  secret)
    sub="${2:-}"
    case "$sub" in
      show)
        load_value "$BOT_SECRET_FILE"
        ;;
      *)
        usage; exit 1 ;;
    esac
    ;;
  tag)
    sub="${2:-}"
    case "$sub" in
      show)
        if [[ -f "$TAG_FILE" ]] && [[ -n "$(cat "$TAG_FILE")" ]]; then
          cat "$TAG_FILE"
        else
          echo "<empty>"
        fi
        ;;
      set)
        value="${3:-}"
        [[ -n "$value" ]] || die "Укажи tag: mtproxyctl tag set <32hex>"
        validate_hex32 "$value" || die "Tag должен быть ровно 32 hex-символа"
        value="$(lower_hex "$value")"
        save_value "$TAG_FILE" "$value"
        run_container
        echo "✅ Tag установлен: $value"
        ;;
      clear)
        : > "$TAG_FILE"
        chmod 600 "$TAG_FILE"
        run_container
        echo "✅ Tag очищен"
        ;;
      *)
        usage; exit 1 ;;
    esac
    ;;
  domain)
    sub="${2:-}"
    case "$sub" in
      show)
        if [[ -f "$DOMAIN_FILE" ]] && [[ -n "$(cat "$DOMAIN_FILE")" ]]; then
          cat "$DOMAIN_FILE"
        else
          echo "$DEFAULT_FAKE_TLS_DOMAIN"
        fi
        ;;
      set)
        value="${3:-}"
        [[ -n "$value" ]] || die "Укажи домен: mtproxyctl domain set <domain>"
        printf "%s\n" "$value" > "$DOMAIN_FILE"
        chmod 600 "$DOMAIN_FILE"
        echo "✅ Fake TLS domain установлен: $value"
        echo "ℹ️  Новая ссылка:"
        "$0" link
        ;;
      *)
        usage; exit 1 ;;
    esac
    ;;
  link)
    bot_secret="$(load_value "$BOT_SECRET_FILE")"
    [[ -n "$bot_secret" ]] || die "Не найден bot secret"
    domain="$(load_value "$DOMAIN_FILE")"
    [[ -n "$domain" ]] || domain="$DEFAULT_FAKE_TLS_DOMAIN"
    ip="$(get_ip)"
    fake_tls_secret="$(build_fake_tls_secret "$bot_secret" "$domain")"
    echo "https://t.me/proxy?server=${ip}&port=${EXTERNAL_PORT}&secret=${fake_tls_secret}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
EOF

  chmod +x "$BIN_PATH"
}

parse_args() {
  INITIAL_TAG=""
  INITIAL_SECRET=""
  INITIAL_DOMAIN="$DEFAULT_FAKE_TLS_DOMAIN"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        INITIAL_TAG="${2:-}"
        shift 2
        ;;
      --secret)
        INITIAL_SECRET="${2:-}"
        shift 2
        ;;
      --domain)
        INITIAL_DOMAIN="${2:-}"
        shift 2
        ;;
      *)
        die "Неизвестный параметр: $1
Использование:
  ./install.sh [--secret 32hex] [--tag 32hex] [--domain example.com]"
        ;;
    esac
  done

  if [[ -n "$INITIAL_SECRET" ]]; then
    validate_hex32 "$INITIAL_SECRET" || die "Secret должен быть ровно 32 hex-символа"
    INITIAL_SECRET="$(lower_hex "$INITIAL_SECRET")"
  fi

  if [[ -n "$INITIAL_TAG" ]]; then
    validate_hex32 "$INITIAL_TAG" || die "Tag должен быть ровно 32 hex-символа"
    INITIAL_TAG="$(lower_hex "$INITIAL_TAG")"
  fi

  [[ -n "$INITIAL_DOMAIN" ]] || INITIAL_DOMAIN="$DEFAULT_FAKE_TLS_DOMAIN"
}

start_container() {
  local bot_secret="$1"
  local tag="$2"

  docker pull "$IMAGE" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  log "🚀 Запускаю прокси..."

  if [[ -n "$tag" ]]; then
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart always \
      -p "${EXTERNAL_PORT}:${INTERNAL_PORT}" \
      -v "${DATA_DIR}:/data" \
      -e SECRET="$bot_secret" \
      -e TAG="$tag" \
      "$IMAGE" >/dev/null
  else
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart always \
      -p "${EXTERNAL_PORT}:${INTERNAL_PORT}" \
      -v "${DATA_DIR}:/data" \
      -e SECRET="$bot_secret" \
      "$IMAGE" >/dev/null
  fi

  sleep 3

  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    ok "Прокси запущен"
  else
    err "Ошибка запуска! Логи:"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
}

main() {
  need_root
  parse_args "$@"

  log ""
  log "🛡  Установка MTProto Proxy для Telegram"
  log "========================================="

  install_packages
  ensure_dirs

  local bot_secret tag domain ip
  bot_secret="$INITIAL_SECRET"
  tag="$INITIAL_TAG"
  domain="$INITIAL_DOMAIN"

  if [[ -z "$bot_secret" ]]; then
    bot_secret="$(generate_hex_secret)"
    ok "Сгенерирован HEX secret для @MTProxybot"
  else
    ok "Используется переданный HEX secret"
  fi

  save_value "${CONF_DIR}/bot_secret.hex" "$bot_secret"
  save_value "${CONF_DIR}/fake_tls_domain.txt" "$domain"

  if [[ -n "$tag" ]]; then
    save_value "${CONF_DIR}/tag.hex" "$tag"
    ok "Сохранён tag"
  else
    : > "${CONF_DIR}/tag.hex"
    chmod 600 "${CONF_DIR}/tag.hex"
    warn "Tag не задан"
  fi

  write_cli
  ok "Установлена CLI-команда: mtproxyctl"

  start_container "$bot_secret" "$tag"

  ip="$(get_ip)"
  [[ -n "$ip" ]] || die "Не удалось определить внешний IP"

  print_summary "$ip" "$bot_secret" "$tag" "$domain"
}

main "$@"
