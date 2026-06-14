#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.3.0"
REPO_URL="https://github.com/jiasongji/proxy-manager"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/jiasongji/proxy-manager/main/proxy-manager.sh"
RELEASE_SCRIPT_URL="https://github.com/jiasongji/proxy-manager/releases/latest/download/proxy-manager.sh"
DEFAULT_DOMAIN="example.com"
DEFAULT_SERVER_IP="203.0.113.10"
DEFAULT_CONTAINER_NAME="proxy-manager-sing-box"
DEFAULT_IMAGE="jiasongji/proxy-manager-sing-box:latest"
DEFAULT_TZ="Asia/Shanghai"
DEFAULT_SS_METHOD="aes-128-gcm"
DEFAULT_NAIVE_USERNAME="proxyuser"
PORT_MIN=20000
PORT_MAX=60000

resolve_path() {
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$1" 2>/dev/null && return 0
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1" 2>/dev/null && return 0
  fi
  printf '%s\n' "$1"
}

SCRIPT_PATH="$(resolve_path "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "bin" ]]; then
  DERIVED_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  DERIVED_ROOT="/www/wwwroot/${DEFAULT_DOMAIN}/Proxy-Manager"
fi
PM_ROOT="${PM_ROOT:-$DERIVED_ROOT}"
ENV_FILE="$PM_ROOT/config/manager.env"

safe_source_env() {
  local file="$1" uid perm
  [[ -f "$file" ]] || return 0
  if command -v stat >/dev/null 2>&1; then
    uid="$(stat -c '%u' "$file" 2>/dev/null || printf '')"
    perm="$(stat -c '%a' "$file" 2>/dev/null || printf '')"
    if [[ -n "$uid" && "$uid" != "0" && "$uid" != "$(id -u)" ]]; then
      printf '[ERROR] 配置文件属主异常，拒绝读取：%s\n' "$file" >&2
      exit 1
    fi
    if [[ -n "$perm" && "$perm" != "600" && "$perm" != "400" ]]; then
      chmod 600 "$file" 2>/dev/null || {
        printf '[ERROR] 配置文件权限异常且无法修正：%s\n' "$file" >&2
        exit 1
      }
    fi
  fi
  # manager.env 由本脚本按白名单键写入，并强制 root/600 权限后读取。
  # shellcheck disable=SC1090
  source "$file"
}

if [[ -f "$ENV_FILE" ]]; then
  safe_source_env "$ENV_FILE"
fi

PM_DOMAIN="${PM_DOMAIN:-$DEFAULT_DOMAIN}"
PM_ROOT="${PM_ROOT:-$DERIVED_ROOT}"
PM_SERVER_IP="${PM_SERVER_IP:-$DEFAULT_SERVER_IP}"
PM_CONTAINER_NAME="${PM_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
PM_IMAGE="${PM_IMAGE:-$DEFAULT_IMAGE}"
PM_TZ="${PM_TZ:-$DEFAULT_TZ}"
ENABLE_ANYTLS="${ENABLE_ANYTLS:-1}"
ENABLE_NAIVE="${ENABLE_NAIVE:-1}"
ENABLE_SS="${ENABLE_SS:-1}"
SS_METHOD="${SS_METHOD:-$DEFAULT_SS_METHOD}"
NAIVE_USERNAME="${NAIVE_USERNAME:-$DEFAULT_NAIVE_USERNAME}"
ANYTLS_NAME="${ANYTLS_NAME:-proxy}"
CERT_FILE="${CERT_FILE:-}"
KEY_FILE="${KEY_FILE:-}"
ANYTLS_PORT="${ANYTLS_PORT:-}"
NAIVE_PORT="${NAIVE_PORT:-}"
SS_PORT="${SS_PORT:-}"
ANYTLS_PASSWORD="${ANYTLS_PASSWORD:-}"
NAIVE_PASSWORD="${NAIVE_PASSWORD:-}"
SS_PASSWORD="${SS_PASSWORD:-}"
CREATED_AT="${CREATED_AT:-}"

AUTO_YES=0
COMMAND="${1:-menu}"
shift || true
CLI_DOMAIN=""
CLI_ROOT=""
CLI_SERVER_IP=""
CLI_CONTAINER_NAME=""
CLI_IMAGE=""
CLI_TZ=""
CLI_COMPONENTS=""
CLI_CERT_FILE=""
CLI_KEY_FILE=""
CLI_ANYTLS_PORT=""
CLI_NAIVE_PORT=""
CLI_SS_PORT=""
CLI_ANYTLS_NAME=""
CLI_ANYTLS_PASSWORD=""
CLI_NAIVE_USERNAME=""
CLI_NAIVE_PASSWORD=""
CLI_SS_PASSWORD=""

parse_arg_value() {
  local current="$1" next="${2:-}" opt_name="$3"
  if [[ "$current" == *=* ]]; then
    printf '%s\n' "${current#*=}"
  else
    [[ -n "$next" ]] || { printf '[ERROR] 参数 %s 缺少值\n' "$opt_name" >&2; exit 2; }
    printf '%s\n' "$next"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      shift
      ;;
    --domain|--domain=*)
      CLI_DOMAIN="$(parse_arg_value "$1" "${2:-}" --domain)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --root|--root=*)
      CLI_ROOT="$(parse_arg_value "$1" "${2:-}" --root)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --server-ip|--server-ip=*)
      CLI_SERVER_IP="$(parse_arg_value "$1" "${2:-}" --server-ip)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --container-name|--container-name=*)
      CLI_CONTAINER_NAME="$(parse_arg_value "$1" "${2:-}" --container-name)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --image|--image=*)
      CLI_IMAGE="$(parse_arg_value "$1" "${2:-}" --image)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --tz|--tz=*)
      CLI_TZ="$(parse_arg_value "$1" "${2:-}" --tz)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --components|--components=*|--mode|--mode=*)
      CLI_COMPONENTS="$(parse_arg_value "$1" "${2:-}" --components)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --cert-file|--cert-file=*)
      CLI_CERT_FILE="$(parse_arg_value "$1" "${2:-}" --cert-file)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --key-file|--key-file=*)
      CLI_KEY_FILE="$(parse_arg_value "$1" "${2:-}" --key-file)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --anytls-port|--anytls-port=*)
      CLI_ANYTLS_PORT="$(parse_arg_value "$1" "${2:-}" --anytls-port)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --naive-port|--naive-port=*)
      CLI_NAIVE_PORT="$(parse_arg_value "$1" "${2:-}" --naive-port)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --ss-port|--ss-port=*)
      CLI_SS_PORT="$(parse_arg_value "$1" "${2:-}" --ss-port)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --anytls-name|--anytls-name=*)
      CLI_ANYTLS_NAME="$(parse_arg_value "$1" "${2:-}" --anytls-name)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --anytls-password|--anytls-password=*)
      CLI_ANYTLS_PASSWORD="$(parse_arg_value "$1" "${2:-}" --anytls-password)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --naive-username|--naive-username=*)
      CLI_NAIVE_USERNAME="$(parse_arg_value "$1" "${2:-}" --naive-username)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --naive-password|--naive-password=*)
      CLI_NAIVE_PASSWORD="$(parse_arg_value "$1" "${2:-}" --naive-password)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    --ss-password|--ss-password=*)
      CLI_SS_PASSWORD="$(parse_arg_value "$1" "${2:-}" --ss-password)"
      if [[ "$1" == *=* ]]; then shift; else shift 2; fi
      ;;
    *)
      printf '[ERROR] 未知参数：%s\n' "$1" >&2
      exit 2
      ;;
  esac
done

CONFIG_DIR() { printf '%s/config' "$PM_ROOT"; }
COMPOSE_DIR() { printf '%s/compose' "$PM_ROOT"; }
CLIENT_DIR() { printf '%s/config/client' "$PM_ROOT"; }
BACKUP_DIR() { printf '%s/backup' "$PM_ROOT"; }
RUNTIME_DIR() { printf '%s/runtime' "$PM_ROOT"; }
DOCS_DIR() { printf '%s/docs' "$PM_ROOT"; }
CONFIG_FILE() { printf '%s/config/sing-box.json' "$PM_ROOT"; }
COMPOSE_FILE() { printf '%s/compose/docker-compose.yml' "$PM_ROOT"; }

log() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

is_enabled() { [[ "${1:-0}" == "1" ]]; }
needs_tls() { is_enabled "$ENABLE_ANYTLS" || is_enabled "$ENABLE_NAIVE"; }

component_summary() {
  local parts=() out="" part
  is_enabled "$ENABLE_ANYTLS" && parts+=("AnyTLS")
  is_enabled "$ENABLE_NAIVE" && parts+=("NaiveProxy")
  is_enabled "$ENABLE_SS" && parts+=("Shadowsocks 落地")
  if [[ "${#parts[@]}" -eq 0 ]]; then
    printf '未选择组件'
  else
    for part in "${parts[@]}"; do
      if [[ -n "$out" ]]; then
        out+=" + "
      fi
      out+="$part"
    done
    printf '%s' "$out"
  fi
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 用户执行。"
}

ensure_dirs() {
  mkdir -p "$PM_ROOT/bin" "$(CONFIG_DIR)" "$(CLIENT_DIR)" "$(COMPOSE_DIR)" "$(BACKUP_DIR)" "$(RUNTIME_DIR)" "$(DOCS_DIR)" "$PM_ROOT/logs"
  chmod 700 "$(CONFIG_DIR)" "$(CLIENT_DIR)" "$(BACKUP_DIR)" "$(RUNTIME_DIR)" 2>/dev/null || true
}

prompt_value() {
  local label="$1" default_value="${2:-}" value
  if [[ "$AUTO_YES" -eq 1 ]]; then
    printf '%s\n' "$default_value"
    return 0
  fi
  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " value || true
    printf '%s\n' "${value:-$default_value}"
  else
    read -r -p "$label: " value || true
    printf '%s\n' "$value"
  fi
}

prompt_yes_no() {
  local label="$1" default_value="${2:-Y}" value
  if [[ "$AUTO_YES" -eq 1 ]]; then
    [[ "$default_value" =~ ^[Yy]$ ]]
    return $?
  fi
  read -r -p "$label [$default_value]: " value || true
  value="${value:-$default_value}"
  [[ "$value" =~ ^[Yy]$ ]]
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    printf '\n'
  fi
}

random_port_raw() {
  if command -v shuf >/dev/null 2>&1; then
    shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1
  else
    local n
    n="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
    printf '%s\n' $((PORT_MIN + (n % (PORT_MAX - PORT_MIN + 1))))
  fi
}

port_in_use() {
  local port="$1"
  ss -H -lntu 2>/dev/null | grep -Eq "[:.]${port}([[:space:]]|$)"
}

random_free_port() {
  local port _try
  for _try in $(seq 1 100); do
    port="$(random_port_raw)"
    if [[ "$port" != "${ANYTLS_PORT:-}" && "$port" != "${NAIVE_PORT:-}" && "$port" != "${SS_PORT:-}" ]] && ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done
  return 1
}

validate_port_number() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 )) || return 1
}

prompt_port() {
  local label="$1" current="${2:-}" suggested value
  suggested="$current"
  if [[ -z "$suggested" ]]; then
    suggested="$(random_free_port || true)"
  fi
  while true; do
    value="$(prompt_value "$label，直接回车使用随机高位端口" "$suggested")"
    [[ -n "$value" ]] || value="$(random_free_port || true)"
    validate_port_number "$value" || { warn "端口无效：$value"; suggested="$(random_free_port || true)"; continue; }
    if [[ "$value" != "$current" ]] && port_in_use "$value"; then
      warn "端口已被占用：$value"
      suggested="$(random_free_port || true)"
      continue
    fi
    printf '%s\n' "$value"
    return 0
  done
}

validate_enabled_components() {
  if ! is_enabled "$ENABLE_ANYTLS" && ! is_enabled "$ENABLE_NAIVE" && ! is_enabled "$ENABLE_SS"; then
    die "至少需要启用一个组件：AnyTLS、NaiveProxy 或 Shadowsocks 落地。"
  fi
}

validate_unique_ports() {
  validate_enabled_components
  local ports=() names=() i j
  if is_enabled "$ENABLE_ANYTLS"; then
    validate_port_number "$ANYTLS_PORT" || die "AnyTLS 端口无效：$ANYTLS_PORT"
    ports+=("$ANYTLS_PORT"); names+=("AnyTLS")
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    validate_port_number "$NAIVE_PORT" || die "NaiveProxy 端口无效：$NAIVE_PORT"
    ports+=("$NAIVE_PORT"); names+=("NaiveProxy")
  fi
  if is_enabled "$ENABLE_SS"; then
    validate_port_number "$SS_PORT" || die "Shadowsocks 端口无效：$SS_PORT"
    ports+=("$SS_PORT"); names+=("Shadowsocks")
  fi
  for ((i=0; i<${#ports[@]}; i++)); do
    for ((j=i+1; j<${#ports[@]}; j++)); do
      [[ "${ports[$i]}" != "${ports[$j]}" ]] || die "端口重复：${names[$i]} 与 ${names[$j]} 都使用 ${ports[$i]}。"
    done
  done
}

active_port_regex() {
  local ports=()
  is_enabled "$ENABLE_ANYTLS" && ports+=("$ANYTLS_PORT")
  is_enabled "$ENABLE_NAIVE" && ports+=("$NAIVE_PORT")
  is_enabled "$ENABLE_SS" && ports+=("$SS_PORT")
  local IFS='|'
  printf '%s' "${ports[*]}"
}

detect_public_ip() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -4 -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    [[ -n "$ip" ]] || ip="$(curl -4 -fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s\n' "${ip:-$DEFAULT_SERVER_IP}"
}

detect_cert_pair() {
  local domain="$1" dir cert key
  for dir in \
    "/www/server/panel/vhost/cert/$domain" \
    "/www/server/panel/vhost/ssl/$domain" \
    "/www/server/panel/vhost/cert/${domain}_ecc" \
    "/www/server/panel/vhost/ssl/${domain}_ecc"; do
    for cert in "$dir/fullchain.pem" "$dir/cert.pem"; do
      for key in "$dir/privkey.pem" "$dir/key.pem"; do
        if [[ -s "$cert" && -s "$key" ]]; then
          printf '%s\n%s\n' "$cert" "$key"
          return 0
        fi
      done
    done
  done
  return 1
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

shell_quote() {
  printf '%q' "$1"
}

write_env() {
  ensure_dirs
  umask 077
  {
    printf 'PM_DOMAIN=%s\n' "$(shell_quote "$PM_DOMAIN")"
    printf 'PM_ROOT=%s\n' "$(shell_quote "$PM_ROOT")"
    printf 'PM_SERVER_IP=%s\n' "$(shell_quote "$PM_SERVER_IP")"
    printf 'PM_CONTAINER_NAME=%s\n' "$(shell_quote "$PM_CONTAINER_NAME")"
    printf 'PM_IMAGE=%s\n' "$(shell_quote "$PM_IMAGE")"
    printf 'PM_TZ=%s\n' "$(shell_quote "$PM_TZ")"
    printf 'ENABLE_ANYTLS=%s\n' "$(shell_quote "$ENABLE_ANYTLS")"
    printf 'ENABLE_NAIVE=%s\n' "$(shell_quote "$ENABLE_NAIVE")"
    printf 'ENABLE_SS=%s\n' "$(shell_quote "$ENABLE_SS")"
    printf 'ANYTLS_PORT=%s\n' "$(shell_quote "$ANYTLS_PORT")"
    printf 'NAIVE_PORT=%s\n' "$(shell_quote "$NAIVE_PORT")"
    printf 'SS_PORT=%s\n' "$(shell_quote "$SS_PORT")"
    printf 'ANYTLS_NAME=%s\n' "$(shell_quote "$ANYTLS_NAME")"
    printf 'ANYTLS_PASSWORD=%s\n' "$(shell_quote "$ANYTLS_PASSWORD")"
    printf 'NAIVE_USERNAME=%s\n' "$(shell_quote "$NAIVE_USERNAME")"
    printf 'NAIVE_PASSWORD=%s\n' "$(shell_quote "$NAIVE_PASSWORD")"
    printf 'SS_METHOD=%s\n' "$(shell_quote "$SS_METHOD")"
    printf 'SS_PASSWORD=%s\n' "$(shell_quote "$SS_PASSWORD")"
    printf 'CERT_FILE=%s\n' "$(shell_quote "$CERT_FILE")"
    printf 'KEY_FILE=%s\n' "$(shell_quote "$KEY_FILE")"
    printf 'CREATED_AT=%s\n' "$(shell_quote "${CREATED_AT:-$(date '+%F %T')}")"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

load_env_required() {
  ENV_FILE="$PM_ROOT/config/manager.env"
  [[ -f "$ENV_FILE" ]] || die "未找到配置文件：$ENV_FILE，请先执行 proxy-manager install 或 p-m install。"
  safe_source_env "$ENV_FILE"
}

backup_configs() {
  ensure_dirs
  local ts dir
  ts="$(date '+%Y%m%d-%H%M%S')"
  dir="$(BACKUP_DIR)/$ts"
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  [[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$dir/manager.env"
  [[ -f "$(CONFIG_FILE)" ]] && cp -a "$(CONFIG_FILE)" "$dir/sing-box.json"
  [[ -f "$(COMPOSE_FILE)" ]] && cp -a "$(COMPOSE_FILE)" "$dir/docker-compose.yml"
  log "已备份当前配置到：$dir"
}

append_inbound_sep() {
  local file="$1" first_flag="$2"
  if [[ "$first_flag" -eq 0 ]]; then
    printf ',\n' >> "$file"
  fi
}

render_singbox_config() {
  ensure_dirs
  validate_enabled_components
  local file d cert key any_pass naive_user naive_pass ss_pass ss_method any_name first
  file="$(CONFIG_FILE)"
  d="$(json_escape "$PM_DOMAIN")"
  cert="$(json_escape "$CERT_FILE")"
  key="$(json_escape "$KEY_FILE")"
  any_pass="$(json_escape "$ANYTLS_PASSWORD")"
  any_name="$(json_escape "$ANYTLS_NAME")"
  naive_user="$(json_escape "$NAIVE_USERNAME")"
  naive_pass="$(json_escape "$NAIVE_PASSWORD")"
  ss_pass="$(json_escape "$SS_PASSWORD")"
  ss_method="$(json_escape "$SS_METHOD")"
  cat > "$file" <<'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
  first=1
  if is_enabled "$ENABLE_ANYTLS"; then
    append_inbound_sep "$file" "$first"; first=0
    cat >> "$file" <<EOF
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "0.0.0.0",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "name": "$any_name",
          "password": "$any_pass"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$d",
        "certificate_path": "$cert",
        "key_path": "$key"
      }
    }
EOF
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    append_inbound_sep "$file" "$first"; first=0
    cat >> "$file" <<EOF
    {
      "type": "naive",
      "tag": "naive-in",
      "listen": "0.0.0.0",
      "listen_port": ${NAIVE_PORT},
      "users": [
        {
          "username": "$naive_user",
          "password": "$naive_pass"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$d",
        "certificate_path": "$cert",
        "key_path": "$key"
      }
    }
EOF
  fi
  if is_enabled "$ENABLE_SS"; then
    append_inbound_sep "$file" "$first"; first=0
    cat >> "$file" <<EOF
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "listen_port": ${SS_PORT},
      "method": "$ss_method",
      "password": "$ss_pass"
    }
EOF
  fi
  cat >> "$file" <<'EOF'
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
  chmod 600 "$file" 2>/dev/null || true
}

append_outbound_sep() {
  local file="$1" first_flag="$2"
  if [[ "$first_flag" -eq 0 ]]; then
    printf ',\n' >> "$file"
  fi
}

render_client_configs() {
  ensure_dirs
  validate_enabled_components
  local d any_pass naive_user naive_pass ss_pass ss_method full first tags final_tag i
  d="$(json_escape "$PM_DOMAIN")"
  any_pass="$(json_escape "$ANYTLS_PASSWORD")"
  naive_user="$(json_escape "$NAIVE_USERNAME")"
  naive_pass="$(json_escape "$NAIVE_PASSWORD")"
  ss_pass="$(json_escape "$SS_PASSWORD")"
  ss_method="$(json_escape "$SS_METHOD")"
  rm -f "$(CLIENT_DIR)/anytls-outbound.json" "$(CLIENT_DIR)/naive-outbound.json" "$(CLIENT_DIR)/shadowsocks-outbound.json" "$(CLIENT_DIR)/full-test-client.json"

  if is_enabled "$ENABLE_ANYTLS"; then
    cat > "$(CLIENT_DIR)/anytls-outbound.json" <<EOF
{
  "type": "anytls",
  "tag": "anytls-out",
  "server": "$d",
  "server_port": ${ANYTLS_PORT},
  "password": "$any_pass",
  "tls": {
    "enabled": true,
    "server_name": "$d"
  }
}
EOF
  fi

  if is_enabled "$ENABLE_NAIVE"; then
    cat > "$(CLIENT_DIR)/naive-outbound.json" <<EOF
{
  "type": "naive",
  "tag": "naive-out",
  "server": "$d",
  "server_port": ${NAIVE_PORT},
  "username": "$naive_user",
  "password": "$naive_pass",
  "tls": {
    "enabled": true,
    "server_name": "$d"
  }
}
EOF
  fi

  if is_enabled "$ENABLE_SS"; then
    cat > "$(CLIENT_DIR)/shadowsocks-outbound.json" <<EOF
{
  "type": "shadowsocks",
  "tag": "ss-out",
  "server": "$d",
  "server_port": ${SS_PORT},
  "method": "$ss_method",
  "password": "$ss_pass"
}
EOF
  fi

  full="$(CLIENT_DIR)/full-test-client.json"
  tags=()
  cat > "$full" <<'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080
    }
  ],
  "outbounds": [
EOF
  first=1
  if is_enabled "$ENABLE_ANYTLS"; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("anytls-out")
    cat >> "$full" <<EOF
    {
      "type": "anytls",
      "tag": "anytls-out",
      "server": "$d",
      "server_port": ${ANYTLS_PORT},
      "password": "$any_pass",
      "tls": {
        "enabled": true,
        "server_name": "$d"
      }
    }
EOF
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("naive-out")
    cat >> "$full" <<EOF
    {
      "type": "naive",
      "tag": "naive-out",
      "server": "$d",
      "server_port": ${NAIVE_PORT},
      "username": "$naive_user",
      "password": "$naive_pass",
      "tls": {
        "enabled": true,
        "server_name": "$d"
      }
    }
EOF
  fi
  if is_enabled "$ENABLE_SS"; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("ss-out")
    cat >> "$full" <<EOF
    {
      "type": "shadowsocks",
      "tag": "ss-out",
      "server": "$d",
      "server_port": ${SS_PORT},
      "method": "$ss_method",
      "password": "$ss_pass"
    }
EOF
  fi

  if [[ "${#tags[@]}" -gt 1 ]]; then
    append_outbound_sep "$full" "$first"; first=0
    cat >> "$full" <<'EOF'
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": [
EOF
    for ((i=0; i<${#tags[@]}; i++)); do
      if [[ "$i" -gt 0 ]]; then printf ',\n' >> "$full"; fi
      printf '        "%s"' "${tags[$i]}" >> "$full"
    done
    cat >> "$full" <<EOF
      ],
      "default": "${tags[0]}"
    }
EOF
    final_tag="proxy"
  else
    final_tag="${tags[0]}"
  fi

  append_outbound_sep "$full" "$first"
  cat >> "$full" <<EOF
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "$final_tag"
  }
}
EOF
  chmod 600 "$(CLIENT_DIR)"/*.json 2>/dev/null || true
}

render_compose() {
  ensure_dirs
  local cert_dir key_dir config_file compose_file image container tz root
  config_file="$(CONFIG_FILE)"
  compose_file="$(COMPOSE_FILE)"
  image="$PM_IMAGE"
  container="$PM_CONTAINER_NAME"
  tz="$PM_TZ"
  root="$PM_ROOT"
  cat > "$compose_file" <<EOF
services:
  sing-box:
    image: "$image"
    container_name: "$container"
    restart: unless-stopped
    network_mode: host
    command: ["run", "-c", "/etc/sing-box/config.json"]
    volumes:
      - "$config_file:/etc/sing-box/config.json:ro"
EOF
  if needs_tls; then
    cert_dir="$(dirname "$CERT_FILE")"
    key_dir="$(dirname "$KEY_FILE")"
    printf '      - "%s:%s:ro"\n' "$cert_dir" "$cert_dir" >> "$compose_file"
    if [[ "$key_dir" != "$cert_dir" ]]; then
      printf '      - "%s:%s:ro"\n' "$key_dir" "$key_dir" >> "$compose_file"
    fi
  fi
  cat >> "$compose_file" <<EOF
      - "$root/logs:/var/log/proxy-manager"
    environment:
      - TZ=$tz
EOF
  chmod 600 "$compose_file" 2>/dev/null || true
}

render_all() {
  validate_unique_ports
  if needs_tls; then
    [[ -s "$CERT_FILE" ]] || die "证书文件不存在或为空：$CERT_FILE"
    [[ -s "$KEY_FILE" ]] || die "私钥文件不存在或为空：$KEY_FILE"
  fi
  if is_enabled "$ENABLE_ANYTLS"; then
    [[ -n "$ANYTLS_PASSWORD" ]] || die "AnyTLS 密码为空。"
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    [[ -n "$NAIVE_USERNAME" && -n "$NAIVE_PASSWORD" ]] || die "NaiveProxy 用户名或密码为空。"
  fi
  if is_enabled "$ENABLE_SS"; then
    [[ "$SS_METHOD" == "$DEFAULT_SS_METHOD" ]] || die "当前脚本按需求仅支持 Shadowsocks method=$DEFAULT_SS_METHOD，当前值：$SS_METHOD"
    [[ -n "$SS_PASSWORD" ]] || die "Shadowsocks 密码为空。"
  fi
  write_env
  render_singbox_config
  render_client_configs
  render_compose
  printf 'Proxy Manager installed at %s\n' "$(date '+%F %T')" > "$(RUNTIME_DIR)/installed.flag"
  chmod 600 "$(RUNTIME_DIR)/installed.flag" 2>/dev/null || true
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 || die "未检测到 Docker。当前需求是不自动安装 Docker，请先通过宝塔或系统包安装 Docker。"
  docker info >/dev/null 2>&1 || die "Docker 命令存在，但 Docker daemon 不可用。"
}

compose_available() {
  docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1
}

ensure_compose() {
  if compose_available; then
    return 0
  fi
  require_root
  local arch
  arch="$(uname -m)"
  [[ "$arch" == "x86_64" || "$arch" == "amd64" ]] || die "当前脚本仅按需求自动安装 linux-x86_64 docker-compose，当前架构：$arch"
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 Docker Compose。"
  log "未检测到 Docker Compose，开始安装独立二进制到 /usr/bin/docker-compose"
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/bin/docker-compose
  chmod +x /usr/bin/docker-compose
  docker-compose --version
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    (cd "$(COMPOSE_DIR)" && docker compose "$@")
  else
    (cd "$(COMPOSE_DIR)" && docker-compose "$@")
  fi
}

open_firewall_ports() {
  local opened=0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    if [[ "$AUTO_YES" -eq 1 ]] || prompt_yes_no '检测到 UFW 防火墙，是否自动放行已启用组件端口' 'Y'; then
      if is_enabled "$ENABLE_ANYTLS"; then ufw allow "${ANYTLS_PORT}/tcp"; opened=1; fi
      if is_enabled "$ENABLE_NAIVE"; then ufw allow "${NAIVE_PORT}/tcp"; ufw allow "${NAIVE_PORT}/udp"; opened=1; fi
      if is_enabled "$ENABLE_SS"; then ufw allow "${SS_PORT}/tcp"; ufw allow "${SS_PORT}/udp"; opened=1; fi
    fi
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if [[ "$AUTO_YES" -eq 1 ]] || prompt_yes_no '检测到 firewalld，是否自动放行已启用组件端口' 'Y'; then
      if is_enabled "$ENABLE_ANYTLS"; then firewall-cmd --permanent --add-port="${ANYTLS_PORT}/tcp"; opened=1; fi
      if is_enabled "$ENABLE_NAIVE"; then firewall-cmd --permanent --add-port="${NAIVE_PORT}/tcp"; firewall-cmd --permanent --add-port="${NAIVE_PORT}/udp"; opened=1; fi
      if is_enabled "$ENABLE_SS"; then firewall-cmd --permanent --add-port="${SS_PORT}/tcp"; firewall-cmd --permanent --add-port="${SS_PORT}/udp"; opened=1; fi
      firewall-cmd --reload
    fi
  fi
  if [[ "$opened" -eq 1 ]]; then
    log "已尝试放行当前启用组件端口。云厂商安全组如存在，仍需在面板放行。"
  else
    warn "未检测到受支持的本机防火墙或未放行端口；如外网不通，请检查 UFW/安全组/宝塔防火墙。"
  fi
}

singbox_check() {
  ensure_docker
  [[ -f "$(CONFIG_FILE)" ]] || die "缺少 sing-box 配置：$(CONFIG_FILE)"
  local args=()
  args+=(--rm)
  args+=(-v "$(CONFIG_FILE):/etc/sing-box/config.json:ro")
  if needs_tls; then
    args+=(-v "$(dirname "$CERT_FILE"):$(dirname "$CERT_FILE"):ro")
    if [[ "$(dirname "$KEY_FILE")" != "$(dirname "$CERT_FILE")" ]]; then
      args+=(-v "$(dirname "$KEY_FILE"):$(dirname "$KEY_FILE"):ro")
    fi
  fi
  log "执行 sing-box 配置检查：$PM_IMAGE"
  docker run "${args[@]}" "$PM_IMAGE" check -c /etc/sing-box/config.json
}

install_symlinks() {
  require_root
  ensure_dirs
  if [[ "$SCRIPT_PATH" != "$PM_ROOT/bin/proxy-manager.sh" ]]; then
    cp -f "$SCRIPT_PATH" "$PM_ROOT/bin/proxy-manager.sh"
  fi
  chmod +x "$PM_ROOT/bin/proxy-manager.sh"
  ln -sf "$PM_ROOT/bin/proxy-manager.sh" /usr/local/bin/proxy-manager
  ln -sf "$PM_ROOT/bin/proxy-manager.sh" /usr/local/bin/p-m
  if [[ -L /usr/local/bin/pro-m ]]; then
    rm -f /usr/local/bin/pro-m
    log "已移除旧短命令：pro-m"
  elif [[ -e /usr/local/bin/pro-m ]]; then
    warn "检测到 /usr/local/bin/pro-m 不是符号链接，未自动删除；请确认后手动处理。"
  fi
  log "已创建命令：proxy-manager / p-m"
}

update_script() {
  require_root
  ensure_dirs
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法从 GitHub 下载脚本。"
  local url tmp
  url="${SCRIPT_DOWNLOAD_URL:-$RELEASE_SCRIPT_URL}"
  tmp="$(mktemp)"
  log "从 GitHub 下载 Proxy Manager 脚本：$url"
  if ! curl -fsSL "$url" -o "$tmp"; then
    warn "Release 下载失败，尝试 main 分支开发版：$RAW_SCRIPT_URL"
    curl -fsSL "$RAW_SCRIPT_URL" -o "$tmp"
  fi
  bash -n "$tmp"
  cp -f "$tmp" "$PM_ROOT/bin/proxy-manager.sh"
  rm -f "$tmp"
  chmod +x "$PM_ROOT/bin/proxy-manager.sh"
  ln -sf "$PM_ROOT/bin/proxy-manager.sh" /usr/local/bin/proxy-manager
  ln -sf "$PM_ROOT/bin/proxy-manager.sh" /usr/local/bin/p-m
  [[ -L /usr/local/bin/pro-m ]] && rm -f /usr/local/bin/pro-m
  log "脚本已更新。以后可执行：p-m 或 proxy-manager"
}

pull_image() {
  load_env_required
  ensure_docker
  log "拉取 Docker 镜像：$PM_IMAGE"
  docker pull "$PM_IMAGE"
}

check_stack() {
  load_env_required
  singbox_check
}

check_environment() {
  printf '\n== Proxy Manager ==\n'
  printf '版本: %s\n' "$VERSION"
  printf '仓库: %s\n' "$REPO_URL"
  printf '默认镜像: %s\n' "$DEFAULT_IMAGE"
  printf '\n== 命令 ==\n'
  if command -v p-m >/dev/null 2>&1; then
    printf 'p-m: %s\n' "$(command -v p-m)"
  else
    warn '未检测到 p-m，请先执行 install。'
  fi
  if command -v proxy-manager >/dev/null 2>&1; then
    printf 'proxy-manager: %s\n' "$(command -v proxy-manager)"
  else
    warn '未检测到 proxy-manager，请先执行 install。'
  fi
  if command -v pro-m >/dev/null 2>&1; then
    warn "检测到旧短命令 pro-m；新版本已改为 p-m，可重新执行 install/update 清理。"
  fi
  printf '\n== Docker ==\n'
  if command -v docker >/dev/null 2>&1; then
    docker --version || true
    if docker info >/dev/null 2>&1; then
      log 'Docker daemon 可用。'
    else
      warn 'Docker 命令存在，但 Docker daemon 当前不可用。'
    fi
  else
    warn '未检测到 Docker。'
  fi
  if compose_available; then
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
  else
    warn '未检测到 Docker Compose。'
  fi
}

apply_components_value() {
  local raw normalized item _component_items
  raw="$1"
  normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '+/' ',,')"
  normalized="${normalized// /}"
  ENABLE_ANYTLS=0
  ENABLE_NAIVE=0
  ENABLE_SS=0
  case "$normalized" in
    all|full|全部) ENABLE_ANYTLS=1; ENABLE_NAIVE=1; ENABLE_SS=1 ;;
    anytls) ENABLE_ANYTLS=1 ;;
    naive|naiveproxy) ENABLE_NAIVE=1 ;;
    ss|shadowsocks|landing|落地) ENABLE_SS=1 ;;
    *)
      IFS=',' read -r -a _component_items <<< "$normalized"
      for item in "${_component_items[@]}"; do
        case "$item" in
          anytls) ENABLE_ANYTLS=1 ;;
          naive|naiveproxy) ENABLE_NAIVE=1 ;;
          ss|shadowsocks|landing|落地) ENABLE_SS=1 ;;
          '' ) ;;
          *) die "未知组件：$item。支持 all、anytls、naive、ss 或逗号组合。" ;;
        esac
      done
      ;;
  esac
  validate_enabled_components
}

select_components() {
  local choice
  if [[ -n "$CLI_COMPONENTS" ]]; then
    apply_components_value "$CLI_COMPONENTS"
    log "当前组件：$(component_summary)"
    return 0
  fi
  if [[ "$AUTO_YES" -eq 1 ]]; then
    ENABLE_ANYTLS="${ENABLE_ANYTLS:-1}"
    ENABLE_NAIVE="${ENABLE_NAIVE:-1}"
    ENABLE_SS="${ENABLE_SS:-1}"
    validate_enabled_components
    return 0
  fi
  cat <<EOF
请选择要安装/启用的组件：
1) 全部安装：AnyTLS + NaiveProxy + Shadowsocks 落地
2) 仅安装 AnyTLS 入口
3) 仅安装 NaiveProxy 入口
4) 仅安装 Shadowsocks 落地服务
5) 自定义组合
EOF
  read -r -p '选择组件 [1]: ' choice || true
  choice="${choice:-1}"
  case "$choice" in
    1) ENABLE_ANYTLS=1; ENABLE_NAIVE=1; ENABLE_SS=1 ;;
    2) ENABLE_ANYTLS=1; ENABLE_NAIVE=0; ENABLE_SS=0 ;;
    3) ENABLE_ANYTLS=0; ENABLE_NAIVE=1; ENABLE_SS=0 ;;
    4) ENABLE_ANYTLS=0; ENABLE_NAIVE=0; ENABLE_SS=1 ;;
    5)
      if prompt_yes_no '启用 AnyTLS 入口' 'Y'; then ENABLE_ANYTLS=1; else ENABLE_ANYTLS=0; fi
      if prompt_yes_no '启用 NaiveProxy 入口' 'Y'; then ENABLE_NAIVE=1; else ENABLE_NAIVE=0; fi
      if prompt_yes_no '启用 Shadowsocks 落地服务' 'Y'; then ENABLE_SS=1; else ENABLE_SS=0; fi
      ;;
    *) die '无效组件选择。' ;;
  esac
  validate_enabled_components
  log "当前组件：$(component_summary)"
}

collect_tls_inputs_if_needed() {
  local pair cert key
  if ! needs_tls; then
    CERT_FILE="${CLI_CERT_FILE:-${CERT_FILE:-}}"
    KEY_FILE="${CLI_KEY_FILE:-${KEY_FILE:-}}"
    return 0
  fi
  [[ -n "$CLI_CERT_FILE" ]] && CERT_FILE="$CLI_CERT_FILE"
  [[ -n "$CLI_KEY_FILE" ]] && KEY_FILE="$CLI_KEY_FILE"
  if [[ -z "${CERT_FILE:-}" || -z "${KEY_FILE:-}" ]]; then
    pair="$(detect_cert_pair "$PM_DOMAIN" || true)"
    if [[ -n "$pair" ]]; then
      cert="$(printf '%s\n' "$pair" | sed -n '1p')"
      key="$(printf '%s\n' "$pair" | sed -n '2p')"
      if prompt_yes_no "检测到证书 $cert 和私钥 $key，是否使用" "Y"; then
        CERT_FILE="$cert"
        KEY_FILE="$key"
      fi
    fi
  fi
  if [[ -z "${CERT_FILE:-}" ]]; then
    CERT_FILE="$(prompt_value '证书 fullchain/cert 文件路径' "${CERT_FILE:-}")"
  fi
  if [[ -z "${KEY_FILE:-}" ]]; then
    KEY_FILE="$(prompt_value '证书 privkey/key 文件路径' "${KEY_FILE:-}")"
  fi
  [[ -s "$CERT_FILE" ]] || die "证书文件不存在或为空：$CERT_FILE"
  [[ -s "$KEY_FILE" ]] || die "私钥文件不存在或为空：$KEY_FILE"
}

collect_install_inputs() {
  local default_root detected_ip image_default root_default
  if [[ -n "$CLI_DOMAIN" ]]; then PM_DOMAIN="$CLI_DOMAIN"; else PM_DOMAIN="$(prompt_value '部署域名' "${PM_DOMAIN:-$DEFAULT_DOMAIN}")"; fi
  default_root="/www/wwwroot/${PM_DOMAIN}/Proxy-Manager"
  root_default="${PM_ROOT:-$default_root}"
  if [[ "$root_default" == "/www/wwwroot/${DEFAULT_DOMAIN}/Proxy-Manager" && "$PM_DOMAIN" != "$DEFAULT_DOMAIN" ]]; then
    root_default="$default_root"
  fi
  if [[ -n "$CLI_ROOT" ]]; then PM_ROOT="$CLI_ROOT"; else PM_ROOT="$(prompt_value '项目目录' "$root_default")"; fi
  ENV_FILE="$PM_ROOT/config/manager.env"
  detected_ip="$(detect_public_ip)"
  if [[ -n "$CLI_SERVER_IP" ]]; then PM_SERVER_IP="$CLI_SERVER_IP"; else PM_SERVER_IP="$(prompt_value '服务器 IP / 节点显示地址' "${PM_SERVER_IP:-$detected_ip}")"; fi
  if [[ -n "$CLI_CONTAINER_NAME" ]]; then PM_CONTAINER_NAME="$CLI_CONTAINER_NAME"; else PM_CONTAINER_NAME="$(prompt_value '容器名称' "${PM_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}")"; fi
  image_default="${PM_IMAGE:-$DEFAULT_IMAGE}"
  if [[ -n "$CLI_IMAGE" ]]; then PM_IMAGE="$CLI_IMAGE"; else PM_IMAGE="$(prompt_value 'sing-box Docker 镜像（默认使用 Docker Hub 发布镜像，可自定义）' "$image_default")"; fi
  if [[ -n "$CLI_TZ" ]]; then PM_TZ="$CLI_TZ"; else PM_TZ="$(prompt_value '时区' "${PM_TZ:-$DEFAULT_TZ}")"; fi

  select_components
  collect_tls_inputs_if_needed

  if is_enabled "$ENABLE_ANYTLS"; then
    if [[ -n "$CLI_ANYTLS_PORT" ]]; then ANYTLS_PORT="$CLI_ANYTLS_PORT"; else ANYTLS_PORT="$(prompt_port 'AnyTLS 监听端口' "${ANYTLS_PORT:-}")"; fi
    if [[ -n "$CLI_ANYTLS_NAME" ]]; then ANYTLS_NAME="$CLI_ANYTLS_NAME"; else ANYTLS_NAME="$(prompt_value 'AnyTLS 用户名' "${ANYTLS_NAME:-proxy}")"; fi
    if [[ -n "$CLI_ANYTLS_PASSWORD" ]]; then ANYTLS_PASSWORD="$CLI_ANYTLS_PASSWORD"; else ANYTLS_PASSWORD="$(prompt_value 'AnyTLS 密码，回车自动生成' "${ANYTLS_PASSWORD:-$(random_hex)}")"; fi
  else
    ANYTLS_PORT=""; ANYTLS_PASSWORD=""
  fi

  if is_enabled "$ENABLE_NAIVE"; then
    if [[ -n "$CLI_NAIVE_PORT" ]]; then NAIVE_PORT="$CLI_NAIVE_PORT"; else NAIVE_PORT="$(prompt_port 'NaiveProxy 监听端口' "${NAIVE_PORT:-}")"; fi
    if [[ -n "$CLI_NAIVE_USERNAME" ]]; then NAIVE_USERNAME="$CLI_NAIVE_USERNAME"; else NAIVE_USERNAME="$(prompt_value 'NaiveProxy 用户名' "${NAIVE_USERNAME:-$DEFAULT_NAIVE_USERNAME}")"; fi
    if [[ -n "$CLI_NAIVE_PASSWORD" ]]; then NAIVE_PASSWORD="$CLI_NAIVE_PASSWORD"; else NAIVE_PASSWORD="$(prompt_value 'NaiveProxy 密码，回车自动生成' "${NAIVE_PASSWORD:-$(random_hex)}")"; fi
  else
    NAIVE_PORT=""; NAIVE_PASSWORD=""
  fi

  if is_enabled "$ENABLE_SS"; then
    if [[ -n "$CLI_SS_PORT" ]]; then SS_PORT="$CLI_SS_PORT"; else SS_PORT="$(prompt_port 'Shadowsocks 落地监听端口' "${SS_PORT:-}")"; fi
    SS_METHOD="$DEFAULT_SS_METHOD"
    if [[ -n "$CLI_SS_PASSWORD" ]]; then SS_PASSWORD="$CLI_SS_PASSWORD"; else SS_PASSWORD="$(prompt_value 'Shadowsocks 密码，回车自动生成' "${SS_PASSWORD:-$(random_hex)}")"; fi
  else
    SS_PORT=""; SS_PASSWORD=""
  fi

  validate_unique_ports
  CREATED_AT="${CREATED_AT:-$(date '+%F %T')}"
}

install_stack() {
  require_root
  ensure_docker
  ensure_compose
  collect_install_inputs
  ensure_dirs
  install_symlinks
  if [[ -f "$ENV_FILE" ]]; then
    backup_configs
  fi
  render_all
  singbox_check
  open_firewall_ports
  compose_cmd up -d --force-recreate
  sleep 2
  status_stack
  show_info
  log "安装完成。以后可直接执行：p-m 或 proxy-manager"
}

start_stack() {
  load_env_required
  ensure_docker
  ensure_compose
  compose_cmd up -d
  status_stack
}

stop_stack() {
  load_env_required
  ensure_docker
  ensure_compose
  compose_cmd down
}

restart_stack() {
  load_env_required
  ensure_docker
  ensure_compose
  compose_cmd up -d --force-recreate
  sleep 2
  status_stack
}

status_stack() {
  load_env_required
  local regex
  regex="$(active_port_regex)"
  printf '\n== 当前组件 ==\n%s\n' "$(component_summary)"
  printf '\n== Docker 容器 ==\n'
  docker ps -a --filter "name=${PM_CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
  printf '\n== 监听端口 ==\n'
  if [[ -n "$regex" ]]; then
    ss -lntup 2>/dev/null | grep -E ":(${regex})([[:space:]]|$)" || true
  fi
  printf '\n== 最近日志 ==\n'
  docker logs --tail=80 "$PM_CONTAINER_NAME" 2>&1 || true
}

logs_stack() {
  load_env_required
  docker logs -f --tail=200 "$PM_CONTAINER_NAME"
}

show_info() {
  load_env_required
  cat <<EOF

================ Proxy Manager 节点信息 ================
域名:        $PM_DOMAIN
服务器 IP:   $PM_SERVER_IP
项目目录:    $PM_ROOT
容器名称:    $PM_CONTAINER_NAME
Docker 镜像: $PM_IMAGE
启用组件:    $(component_summary)
EOF
  if needs_tls; then
    cat <<EOF
证书文件:    $CERT_FILE
私钥文件:    $KEY_FILE
EOF
  fi
  if is_enabled "$ENABLE_ANYTLS"; then
    cat <<EOF

[AnyTLS 入口]
地址:        $PM_DOMAIN
端口:        $ANYTLS_PORT
用户:        $ANYTLS_NAME
密码:        $ANYTLS_PASSWORD
客户端片段:  $(CLIENT_DIR)/anytls-outbound.json
EOF
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    cat <<EOF

[NaiveProxy 入口]
地址:        $PM_DOMAIN
端口:        $NAIVE_PORT
用户名:      $NAIVE_USERNAME
密码:        $NAIVE_PASSWORD
URL:         https://${NAIVE_USERNAME}:${NAIVE_PASSWORD}@${PM_DOMAIN}:${NAIVE_PORT}
客户端片段:  $(CLIENT_DIR)/naive-outbound.json
EOF
  fi
  if is_enabled "$ENABLE_SS"; then
    cat <<EOF

[Shadowsocks 落地]
地址:        $PM_DOMAIN
端口:        $SS_PORT
method:      $SS_METHOD
password:    $SS_PASSWORD
UDP:         enabled
客户端片段:  $(CLIENT_DIR)/shadowsocks-outbound.json
EOF
  fi
  cat <<EOF

[完整测试客户端]
$(CLIENT_DIR)/full-test-client.json
本地 socks/mixed 端口: 127.0.0.1:2080

敏感提示：以上包含真实密码，请不要公开粘贴。
========================================================
EOF
}

change_port() {
  load_env_required
  require_root
  local choice new_port
  cat <<EOF
当前端口：
1) AnyTLS:      ${ANYTLS_PORT:-未启用}
2) NaiveProxy:  ${NAIVE_PORT:-未启用}
3) Shadowsocks: ${SS_PORT:-未启用}
4) 全部启用组件重新随机
0) 取消
EOF
  read -r -p '请选择要修改的端口: ' choice || true
  case "$choice" in
    1) is_enabled "$ENABLE_ANYTLS" || die 'AnyTLS 未启用。'; new_port="$(prompt_port '新的 AnyTLS 端口' '')"; ANYTLS_PORT="$new_port" ;;
    2) is_enabled "$ENABLE_NAIVE" || die 'NaiveProxy 未启用。'; new_port="$(prompt_port '新的 NaiveProxy 端口' '')"; NAIVE_PORT="$new_port" ;;
    3) is_enabled "$ENABLE_SS" || die 'Shadowsocks 未启用。'; new_port="$(prompt_port '新的 Shadowsocks 端口' '')"; SS_PORT="$new_port" ;;
    4)
      is_enabled "$ENABLE_ANYTLS" && ANYTLS_PORT="$(random_free_port)"
      is_enabled "$ENABLE_NAIVE" && NAIVE_PORT="$(random_free_port)"
      is_enabled "$ENABLE_SS" && SS_PORT="$(random_free_port)"
      ;;
    0|'') log '已取消。'; return 0 ;;
    *) die '无效选择。' ;;
  esac
  validate_unique_ports
  backup_configs
  render_all
  singbox_check
  open_firewall_ports
  restart_stack
  show_info
}

change_secret() {
  load_env_required
  require_root
  local choice value
  cat <<EOF
当前可修改项：
1) AnyTLS 密码      ${ENABLE_ANYTLS:+}
2) NaiveProxy 用户名/密码
3) Shadowsocks 密码
4) 全部启用组件重新生成
0) 取消
EOF
  read -r -p '请选择要修改的密码: ' choice || true
  case "$choice" in
    1) is_enabled "$ENABLE_ANYTLS" || die 'AnyTLS 未启用。'; value="$(prompt_value '新的 AnyTLS 密码，回车自动生成' "$(random_hex)")"; ANYTLS_PASSWORD="$value" ;;
    2) is_enabled "$ENABLE_NAIVE" || die 'NaiveProxy 未启用。'; NAIVE_USERNAME="$(prompt_value '新的 NaiveProxy 用户名' "$NAIVE_USERNAME")"; NAIVE_PASSWORD="$(prompt_value '新的 NaiveProxy 密码，回车自动生成' "$(random_hex)")" ;;
    3) is_enabled "$ENABLE_SS" || die 'Shadowsocks 未启用。'; value="$(prompt_value '新的 Shadowsocks 密码，回车自动生成' "$(random_hex)")"; SS_PASSWORD="$value" ;;
    4)
      is_enabled "$ENABLE_ANYTLS" && ANYTLS_PASSWORD="$(random_hex)"
      is_enabled "$ENABLE_NAIVE" && NAIVE_PASSWORD="$(random_hex)"
      is_enabled "$ENABLE_SS" && SS_PASSWORD="$(random_hex)"
      ;;
    0|'') log '已取消。'; return 0 ;;
    *) die '无效选择。' ;;
  esac
  backup_configs
  render_all
  singbox_check
  open_firewall_ports
  restart_stack
  show_info
}

safe_project_root_or_die() {
  [[ -n "${PM_ROOT:-}" ]] || die "PM_ROOT 为空，拒绝继续。"
  [[ "$PM_ROOT" != "/" && "$PM_ROOT" != "/root" && "$PM_ROOT" != "/home" && "$PM_ROOT" != "/usr" && "$PM_ROOT" != "/usr/local" && "$PM_ROOT" != "/www" && "$PM_ROOT" != "/www/wwwroot" ]] || die "PM_ROOT 指向系统关键目录，拒绝继续：$PM_ROOT"
  [[ "$(basename "$PM_ROOT")" == "Proxy-Manager" ]] || die "项目目录末级必须为 Proxy-Manager，当前：$PM_ROOT"
  [[ -f "$(RUNTIME_DIR)/installed.flag" || -f "$(CONFIG_FILE)" ]] || die "未发现 Proxy Manager 标识文件，拒绝删除：$PM_ROOT"
}

regen_all() {
  load_env_required
  require_root
  warn "将重新生成所有已启用组件的端口和密码，域名、证书路径、镜像保持不变。"
  if ! prompt_yes_no '确认继续' 'N'; then
    log '已取消。'
    return 0
  fi
  backup_configs
  is_enabled "$ENABLE_ANYTLS" && { ANYTLS_PORT="$(random_free_port)"; ANYTLS_PASSWORD="$(random_hex)"; }
  is_enabled "$ENABLE_NAIVE" && { NAIVE_PORT="$(random_free_port)"; NAIVE_PASSWORD="$(random_hex)"; }
  is_enabled "$ENABLE_SS" && { SS_PORT="$(random_free_port)"; SS_PASSWORD="$(random_hex)"; }
  render_all
  singbox_check
  open_firewall_ports
  restart_stack
  show_info
}

uninstall_stack() {
  load_env_required
  require_root
  safe_project_root_or_die
  warn "危险操作：将停止并删除容器，移除 /usr/local/bin/proxy-manager 与 /usr/local/bin/p-m。"
  warn "如检测到旧短命令 /usr/local/bin/pro-m，也会一并清理。"
  warn "默认不会删除 Docker、Docker Compose、宝塔证书。"
  local confirm delete_dir
  read -r -p "请输入域名 $PM_DOMAIN 确认卸载: " confirm || true
  [[ "$confirm" == "$PM_DOMAIN" ]] || die "确认文本不匹配，已取消。"
  backup_configs
  compose_cmd down || true
  docker rm -f "$PM_CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -f /usr/local/bin/proxy-manager /usr/local/bin/p-m
  [[ -L /usr/local/bin/pro-m ]] && rm -f /usr/local/bin/pro-m
  read -r -p "是否删除项目目录 $PM_ROOT ? 输入 DELETE 确认删除，其他输入保留: " delete_dir || true
  if [[ "$delete_dir" == "DELETE" ]]; then
    rm -rf "$PM_ROOT"
    log "已删除项目目录：$PM_ROOT"
  else
    log "已保留项目目录：$PM_ROOT"
  fi
  log "卸载完成。"
}

pause_return() {
  local _pause
  if [[ -t 0 ]]; then
    read -r -p '按回车返回上一页...' _pause || true
  fi
}

run_menu_action() {
  "$@"
  pause_return
}

print_main_menu() {
  cat <<EOF

Proxy Manager v$VERSION - $PM_DOMAIN
命令别名：proxy-manager / p-m
当前组件：$(component_summary)

1) 安装 / 更新
2) 服务管理
3) 配置管理
4) 状态 / 日志
5) 节点信息
6) 审计 / 自检
7) 卸载清理
0) 退出

提示：主菜单直接回车退出；二级菜单直接回车返回上一页。
EOF
}

install_menu() {
  local choice
  while true; do
    cat <<EOF

安装 / 更新

1) 安装 / 重新部署 / 选择组件
2) 从 GitHub 更新脚本
3) 拉取当前 Docker 镜像
4) 检查运行环境
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action install_stack ;;
      2) run_menu_action update_script ;;
      3) run_menu_action pull_image ;;
      4) run_menu_action check_environment ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

service_menu() {
  local choice
  while true; do
    cat <<EOF

服务管理

1) 启动服务
2) 停止服务
3) 重启服务
4) 查看运行状态
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action start_stack ;;
      2) run_menu_action stop_stack ;;
      3) run_menu_action restart_stack ;;
      4) run_menu_action status_stack ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

config_menu() {
  local choice
  while true; do
    cat <<EOF

配置管理

1) 修改端口
2) 修改 / 重新生成密码
3) 重新生成已启用组件的端口和密码
4) 重新部署 / 切换组件
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action change_port ;;
      2) run_menu_action change_secret ;;
      3) run_menu_action regen_all ;;
      4) run_menu_action install_stack ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

status_menu() {
  local choice
  while true; do
    cat <<EOF

状态 / 日志

1) 查看运行状态
2) 查看实时日志
3) 检查 sing-box 配置
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action status_stack ;;
      2) logs_stack ;;
      3) run_menu_action check_stack ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

info_menu() {
  local choice
  while true; do
    cat <<EOF

节点信息

1) 查看节点信息
2) 查看帮助
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action show_info ;;
      2) run_menu_action usage ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

audit_menu() {
  local choice
  while true; do
    cat <<EOF

审计 / 自检

1) 检查运行环境
2) 检查 sing-box 配置
3) 查看当前状态
4) 显示版本与下载地址
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action check_environment ;;
      2) run_menu_action check_stack ;;
      3) run_menu_action status_stack ;;
      4) printf '\n版本: %s\n仓库: %s\nRelease: %s\n开发版: %s\n' "$VERSION" "$REPO_URL" "$RELEASE_SCRIPT_URL" "$RAW_SCRIPT_URL"; pause_return ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

remove_menu() {
  local choice
  while true; do
    cat <<EOF

卸载清理

1) 卸载 Proxy Manager
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action uninstall_stack ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

menu() {
  local choice
  while true; do
    print_main_menu
    read -r -p '请选择操作 [回车退出]: ' choice || true
    case "$choice" in
      1) install_menu ;;
      2) service_menu ;;
      3) config_menu ;;
      4) status_menu ;;
      5) info_menu ;;
      6) audit_menu ;;
      7) remove_menu ;;
      0|'') exit 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

usage() {
  cat <<EOF
Proxy Manager v$VERSION

仓库：$REPO_URL

用法：
  p-m [command] [--yes]
  proxy-manager [command] [--yes]

不带 command 时进入交互菜单：主菜单回车退出，二级菜单回车返回上一页。

命令：
  install          安装 / 重新部署 / 选择组件
  update           从 GitHub 更新脚本
  pull-image       拉取当前配置中的 Docker 镜像
  env-check        检查本机 Docker、Compose 和命令映射
  start            启动服务
  stop             停止服务
  restart          重启服务
  status           查看状态、端口和最近日志
  logs             查看实时日志
  info             查看节点信息
  change-port      修改端口
  change-secret    修改 / 重新生成密码
  regen            重新生成已启用组件的端口和密码
  check            检查 sing-box 配置
  uninstall        卸载清理
  help             查看帮助

组件模式：
  install 过程中可选择：全部、仅 AnyTLS、仅 NaiveProxy、仅 Shadowsocks 落地、自定义组合。

install 可选参数：
  --yes                         接受默认值/随机值
  --domain DOMAIN               部署域名
  --root PATH                   项目目录
  --server-ip IP                节点显示 IP
  --image IMAGE                 sing-box Docker 镜像
  --components LIST             all / anytls / naive / ss / anytls,ss 等组合
  --cert-file PATH              TLS 证书 fullchain/cert 路径
  --key-file PATH               TLS 私钥路径
  --anytls-port PORT            AnyTLS 端口
  --anytls-name NAME            AnyTLS 用户名
  --anytls-password PASSWORD    AnyTLS 密码
  --naive-port PORT             NaiveProxy 端口
  --naive-username USER         NaiveProxy 用户名
  --naive-password PASSWORD     NaiveProxy 密码
  --ss-port PORT                Shadowsocks 落地端口
  --ss-password PASSWORD        Shadowsocks 密码

GitHub 下载安装：
  curl -fsSL $RELEASE_SCRIPT_URL -o /tmp/proxy-manager.sh
  sudo bash /tmp/proxy-manager.sh install

开发版安装：
  curl -fsSL $RAW_SCRIPT_URL -o /tmp/proxy-manager.sh
  sudo bash /tmp/proxy-manager.sh install

一键参数示例：
  p-m install --yes --domain example.com --components anytls,ss --cert-file /path/fullchain.pem --key-file /path/privkey.pem --anytls-port 30001 --ss-port 30003

说明：
  --yes 用于 install 时接受默认值、随机端口和随机密码；首次安装默认全部组件，已有配置时沿用当前组件开关。
EOF
}

case "$COMMAND" in
  menu) menu ;;
  install) install_stack ;;
  update) update_script ;;
  pull-image) pull_image ;;
  env-check) check_environment ;;
  start) start_stack ;;
  stop) stop_stack ;;
  restart) restart_stack ;;
  status) status_stack ;;
  logs) logs_stack ;;
  info) show_info ;;
  change-port) change_port ;;
  change-secret) change_secret ;;
  regen) regen_all ;;
  check) check_stack ;;
  uninstall) uninstall_stack ;;
  help|-h|--help) usage ;;
  *) err "未知命令：$COMMAND"; usage; exit 2 ;;
esac
