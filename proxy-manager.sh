#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.4.2"
REPO_URL="https://github.com/jiasongji/proxy-manager"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/jiasongji/proxy-manager/main/proxy-manager.sh"
RELEASE_SCRIPT_URL="https://github.com/jiasongji/proxy-manager/releases/latest/download/proxy-manager.sh"
DEFAULT_DOMAIN="example.com"
DEFAULT_SERVER_IP="203.0.113.10"
DEFAULT_CONTAINER_NAME="proxy-manager-sing-box"
DEFAULT_IMAGE="ghcr.io/sagernet/sing-box:latest"
DEFAULT_TZ="Asia/Shanghai"
DEFAULT_SS_METHOD="aes-128-gcm"
DEFAULT_NAIVE_USERNAME="proxyuser"
DEFAULT_ROUTE_CATEGORIES="ai,google"
DEFAULT_V2RAY_API_LISTEN="127.0.0.1:10085"
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
PM_NODE_ROLE="${PM_NODE_ROLE:-standalone}"
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
B_SS_HOST="${B_SS_HOST:-}"
B_SS_PORT="${B_SS_PORT:-}"
B_SS_METHOD="${B_SS_METHOD:-$DEFAULT_SS_METHOD}"
B_SS_PASSWORD="${B_SS_PASSWORD:-}"
ROUTE_MODE="${ROUTE_MODE:-split}"
ROUTE_B_CATEGORIES="${ROUTE_B_CATEGORIES:-$DEFAULT_ROUTE_CATEGORIES}"
ROUTE_B_CUSTOM_DOMAINS="${ROUTE_B_CUSTOM_DOMAINS:-}"
ROUTE_B_CUSTOM_KEYWORDS="${ROUTE_B_CUSTOM_KEYWORDS:-}"
ROUTE_B_INCLUDE_YOUTUBE="${ROUTE_B_INCLUDE_YOUTUBE:-0}"
ENABLE_V2RAY_API="${ENABLE_V2RAY_API:-0}"
V2RAY_API_LISTEN="${V2RAY_API_LISTEN:-$DEFAULT_V2RAY_API_LISTEN}"
ENABLE_TRAFFIC_STATS="${ENABLE_TRAFFIC_STATS:-0}"
ENABLE_QUOTA_ENFORCE="${ENABLE_QUOTA_ENFORCE:-0}"
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
CLI_NODE_ROLE=""
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
CLI_ROUTE_MODE=""
CLI_B_SS_HOST=""
CLI_B_SS_PORT=""
CLI_B_SS_METHOD=""
CLI_B_SS_PASSWORD=""
CLI_ROUTE_B_CUSTOM_DOMAINS=""
CLI_ROUTE_B_CUSTOM_KEYWORDS=""
CLI_ROUTE_B_INCLUDE_YOUTUBE=""
CLI_ENABLE_V2RAY_API=""
CLI_V2RAY_API_LISTEN=""
CLI_ENABLE_TRAFFIC_STATS=""
CLI_ENABLE_QUOTA_ENFORCE=""
POSITIONAL=()

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
      AUTO_YES=1; shift ;;
    --domain|--domain=*)
      CLI_DOMAIN="$(parse_arg_value "$1" "${2:-}" --domain)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --root|--root=*)
      CLI_ROOT="$(parse_arg_value "$1" "${2:-}" --root)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --server-ip|--server-ip=*)
      CLI_SERVER_IP="$(parse_arg_value "$1" "${2:-}" --server-ip)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --container-name|--container-name=*)
      CLI_CONTAINER_NAME="$(parse_arg_value "$1" "${2:-}" --container-name)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --image|--image=*)
      CLI_IMAGE="$(parse_arg_value "$1" "${2:-}" --image)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --tz|--tz=*)
      CLI_TZ="$(parse_arg_value "$1" "${2:-}" --tz)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --node-role|--node-role=*|--role|--role=*)
      CLI_NODE_ROLE="$(parse_arg_value "$1" "${2:-}" --node-role)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --components|--components=*|--mode|--mode=*)
      CLI_COMPONENTS="$(parse_arg_value "$1" "${2:-}" --components)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --cert-file|--cert-file=*)
      CLI_CERT_FILE="$(parse_arg_value "$1" "${2:-}" --cert-file)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --key-file|--key-file=*)
      CLI_KEY_FILE="$(parse_arg_value "$1" "${2:-}" --key-file)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --anytls-port|--anytls-port=*)
      CLI_ANYTLS_PORT="$(parse_arg_value "$1" "${2:-}" --anytls-port)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --naive-port|--naive-port=*)
      CLI_NAIVE_PORT="$(parse_arg_value "$1" "${2:-}" --naive-port)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --ss-port|--ss-port=*)
      CLI_SS_PORT="$(parse_arg_value "$1" "${2:-}" --ss-port)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --anytls-name|--anytls-name=*)
      CLI_ANYTLS_NAME="$(parse_arg_value "$1" "${2:-}" --anytls-name)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --anytls-password|--anytls-password=*)
      CLI_ANYTLS_PASSWORD="$(parse_arg_value "$1" "${2:-}" --anytls-password)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --naive-username|--naive-username=*)
      CLI_NAIVE_USERNAME="$(parse_arg_value "$1" "${2:-}" --naive-username)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --naive-password|--naive-password=*)
      CLI_NAIVE_PASSWORD="$(parse_arg_value "$1" "${2:-}" --naive-password)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --ss-password|--ss-password=*)
      CLI_SS_PASSWORD="$(parse_arg_value "$1" "${2:-}" --ss-password)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --route-mode|--route-mode=*)
      CLI_ROUTE_MODE="$(parse_arg_value "$1" "${2:-}" --route-mode)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-host|--b-ss-host=*)
      CLI_B_SS_HOST="$(parse_arg_value "$1" "${2:-}" --b-ss-host)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-port|--b-ss-port=*)
      CLI_B_SS_PORT="$(parse_arg_value "$1" "${2:-}" --b-ss-port)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-method|--b-ss-method=*)
      CLI_B_SS_METHOD="$(parse_arg_value "$1" "${2:-}" --b-ss-method)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-password|--b-ss-password=*)
      CLI_B_SS_PASSWORD="$(parse_arg_value "$1" "${2:-}" --b-ss-password)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --route-b-domains|--route-b-domains=*)
      CLI_ROUTE_B_CUSTOM_DOMAINS="$(parse_arg_value "$1" "${2:-}" --route-b-domains)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --route-b-keywords|--route-b-keywords=*)
      CLI_ROUTE_B_CUSTOM_KEYWORDS="$(parse_arg_value "$1" "${2:-}" --route-b-keywords)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --include-youtube|--include-youtube=*)
      if [[ "$1" == *=* ]]; then CLI_ROUTE_B_INCLUDE_YOUTUBE="${1#*=}"; shift; else CLI_ROUTE_B_INCLUDE_YOUTUBE="1"; shift; fi ;;
    --enable-v2ray-api|--enable-v2ray-api=*)
      if [[ "$1" == *=* ]]; then CLI_ENABLE_V2RAY_API="${1#*=}"; shift; else CLI_ENABLE_V2RAY_API="1"; shift; fi ;;
    --v2ray-api-listen|--v2ray-api-listen=*)
      CLI_V2RAY_API_LISTEN="$(parse_arg_value "$1" "${2:-}" --v2ray-api-listen)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --enable-traffic-stats|--enable-traffic-stats=*)
      if [[ "$1" == *=* ]]; then CLI_ENABLE_TRAFFIC_STATS="${1#*=}"; shift; else CLI_ENABLE_TRAFFIC_STATS="1"; shift; fi ;;
    --enable-quota-enforce|--enable-quota-enforce=*)
      if [[ "$1" == *=* ]]; then CLI_ENABLE_QUOTA_ENFORCE="${1#*=}"; shift; else CLI_ENABLE_QUOTA_ENFORCE="1"; shift; fi ;;
    --)
      shift; POSITIONAL+=("$@"); break ;;
    *)
      POSITIONAL+=("$1"); shift ;;
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
USERS_FILE() { printf '%s/config/users.json' "$PM_ROOT"; }
STATS_PROTO_FILE() { printf '%s/runtime/v2ray-stats.proto' "$PM_ROOT"; }
STATS_FLAG_FILE() { printf '%s/runtime/stats-supported.flag' "$PM_ROOT"; }

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
  is_enabled "$ENABLE_SS" && parts+=("Shadowsocks")
  if [[ "${#parts[@]}" -eq 0 ]]; then
    out="未选择组件"
  else
    for part in "${parts[@]}"; do
      [[ -n "$out" ]] && out+=" + "
      out+="$part"
    done
  fi
  printf '%s' "$out"
}

role_label() {
  case "${PM_NODE_ROLE:-standalone}" in
    standalone) printf '单机模式' ;;
    entry_a) printf '服务器 A 入口/分流模式' ;;
    egress_b) printf '服务器 B Shadowsocks 落地模式' ;;
    *) printf '%s' "$PM_NODE_ROLE" ;;
  esac
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 用户执行。"
}

ensure_dirs() {
  mkdir -p "$PM_ROOT/bin" "$(CONFIG_DIR)" "$(CLIENT_DIR)" "$(COMPOSE_DIR)" "$(BACKUP_DIR)" "$(RUNTIME_DIR)" "$(DOCS_DIR)" "$PM_ROOT/logs"
  chmod 700 "$(CONFIG_DIR)" "$(CLIENT_DIR)" "$(BACKUP_DIR)" "$(RUNTIME_DIR)" 2>/dev/null || true
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 || die "多用户、分流与限额功能需要 jq。请先安装 jq 后重试。"
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
    if [[ "$port" != "${ANYTLS_PORT:-}" && "$port" != "${NAIVE_PORT:-}" && "$port" != "${SS_PORT:-}" && "$port" != "${B_SS_PORT:-}" ]] && ! port_in_use "$port"; then
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

validate_node_role() {
  case "${PM_NODE_ROLE:-standalone}" in
    standalone|entry_a|egress_b) ;;
    *) die "未知节点角色：$PM_NODE_ROLE。支持 standalone、entry_a、egress_b。" ;;
  esac
}

normalize_route_mode() {
  local raw="$1"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
  case "$raw" in
    split) printf 'split' ;;
    all-via-b|allviab|all_via_b) printf 'all_via_b' ;;
    all-direct|alldirect|all_direct) printf 'all_direct' ;;
    *) return 1 ;;
  esac
}

validate_route_mode() {
  normalize_route_mode "${ROUTE_MODE:-split}" >/dev/null || die "未知路由模式：$ROUTE_MODE。支持 split、all_via_b、all_direct。"
  ROUTE_MODE="$(normalize_route_mode "$ROUTE_MODE")"
}

validate_enabled_components() {
  if [[ "${PM_NODE_ROLE:-standalone}" == "egress_b" ]]; then
    ENABLE_ANYTLS=0
    ENABLE_NAIVE=0
    ENABLE_SS=1
  fi
  if ! is_enabled "$ENABLE_ANYTLS" && ! is_enabled "$ENABLE_NAIVE" && ! is_enabled "$ENABLE_SS"; then
    die "至少需要启用一个组件：AnyTLS、NaiveProxy 或 Shadowsocks。"
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

validate_topology_config() {
  validate_node_role
  validate_route_mode
  case "$PM_NODE_ROLE" in
    entry_a)
      if [[ "$ROUTE_MODE" != "all_direct" ]]; then
        [[ -n "$B_SS_HOST" ]] || die "服务器 A 的 $ROUTE_MODE 模式需要填写 B_SS_HOST。"
        validate_port_number "$B_SS_PORT" || die "B_SS_PORT 无效：$B_SS_PORT"
        [[ -n "$B_SS_METHOD" ]] || die "B_SS_METHOD 为空。"
        [[ -n "$B_SS_PASSWORD" ]] || die "B_SS_PASSWORD 为空。"
      fi
      ;;
    egress_b)
      B_SS_PORT="${B_SS_PORT:-${SS_PORT:-}}"
      B_SS_METHOD="${B_SS_METHOD:-${SS_METHOD:-$DEFAULT_SS_METHOD}}"
      B_SS_PASSWORD="${B_SS_PASSWORD:-${SS_PASSWORD:-}}"
      validate_port_number "$B_SS_PORT" || die "服务器 B 的 Shadowsocks 端口无效：$B_SS_PORT"
      [[ -n "$B_SS_METHOD" ]] || die "服务器 B 的 Shadowsocks method 为空。"
      [[ -n "$B_SS_PASSWORD" ]] || die "服务器 B 的 Shadowsocks 密码为空。"
      SS_PORT="$B_SS_PORT"
      SS_METHOD="$B_SS_METHOD"
      SS_PASSWORD="$B_SS_PASSWORD"
      ENABLE_ANYTLS=0
      ENABLE_NAIVE=0
      ENABLE_SS=1
      ;;
  esac
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

mask_secret() {
  local s="${1:-}"
  if [[ -z "$s" ]]; then
    printf '未设置'
  elif [[ "${#s}" -le 8 ]]; then
    printf '****'
  else
    printf '%s****%s' "${s:0:4}" "${s: -4}"
  fi
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
    printf 'PM_NODE_ROLE=%s\n' "$(shell_quote "$PM_NODE_ROLE")"
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
    printf 'B_SS_HOST=%s\n' "$(shell_quote "$B_SS_HOST")"
    printf 'B_SS_PORT=%s\n' "$(shell_quote "$B_SS_PORT")"
    printf 'B_SS_METHOD=%s\n' "$(shell_quote "$B_SS_METHOD")"
    printf 'B_SS_PASSWORD=%s\n' "$(shell_quote "$B_SS_PASSWORD")"
    printf 'ROUTE_MODE=%s\n' "$(shell_quote "$ROUTE_MODE")"
    printf 'ROUTE_B_CATEGORIES=%s\n' "$(shell_quote "$ROUTE_B_CATEGORIES")"
    printf 'ROUTE_B_CUSTOM_DOMAINS=%s\n' "$(shell_quote "$ROUTE_B_CUSTOM_DOMAINS")"
    printf 'ROUTE_B_CUSTOM_KEYWORDS=%s\n' "$(shell_quote "$ROUTE_B_CUSTOM_KEYWORDS")"
    printf 'ROUTE_B_INCLUDE_YOUTUBE=%s\n' "$(shell_quote "$ROUTE_B_INCLUDE_YOUTUBE")"
    printf 'ENABLE_V2RAY_API=%s\n' "$(shell_quote "$ENABLE_V2RAY_API")"
    printf 'V2RAY_API_LISTEN=%s\n' "$(shell_quote "$V2RAY_API_LISTEN")"
    printf 'ENABLE_TRAFFIC_STATS=%s\n' "$(shell_quote "$ENABLE_TRAFFIC_STATS")"
    printf 'ENABLE_QUOTA_ENFORCE=%s\n' "$(shell_quote "$ENABLE_QUOTA_ENFORCE")"
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
  PM_NODE_ROLE="${PM_NODE_ROLE:-standalone}"
  ROUTE_MODE="${ROUTE_MODE:-split}"
  ROUTE_B_CATEGORIES="${ROUTE_B_CATEGORIES:-$DEFAULT_ROUTE_CATEGORIES}"
  ROUTE_B_CUSTOM_DOMAINS="${ROUTE_B_CUSTOM_DOMAINS:-}"
  ROUTE_B_CUSTOM_KEYWORDS="${ROUTE_B_CUSTOM_KEYWORDS:-}"
  ROUTE_B_INCLUDE_YOUTUBE="${ROUTE_B_INCLUDE_YOUTUBE:-0}"
  B_SS_METHOD="${B_SS_METHOD:-$DEFAULT_SS_METHOD}"
  ENABLE_V2RAY_API="${ENABLE_V2RAY_API:-0}"
  V2RAY_API_LISTEN="${V2RAY_API_LISTEN:-$DEFAULT_V2RAY_API_LISTEN}"
  ENABLE_TRAFFIC_STATS="${ENABLE_TRAFFIC_STATS:-0}"
  ENABLE_QUOTA_ENFORCE="${ENABLE_QUOTA_ENFORCE:-0}"
  validate_node_role
  validate_route_mode
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then
    B_SS_PORT="${B_SS_PORT:-${SS_PORT:-}}"
    B_SS_PASSWORD="${B_SS_PASSWORD:-${SS_PASSWORD:-}}"
    B_SS_METHOD="${B_SS_METHOD:-${SS_METHOD:-$DEFAULT_SS_METHOD}}"
    SS_PORT="${SS_PORT:-$B_SS_PORT}"
    SS_PASSWORD="${SS_PASSWORD:-$B_SS_PASSWORD}"
    SS_METHOD="${SS_METHOD:-$B_SS_METHOD}"
    ENABLE_ANYTLS=0
    ENABLE_NAIVE=0
    ENABLE_SS=1
  fi
}

backup_configs() {
  ensure_dirs
  local ts dir
  ts="$(date '+%Y%m%d-%H%M%S')"
  dir="$(BACKUP_DIR)/$ts"
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  [[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$dir/manager.env"
  [[ -f "$(USERS_FILE)" ]] && cp -a "$(USERS_FILE)" "$dir/users.json"
  [[ -f "$(CONFIG_FILE)" ]] && cp -a "$(CONFIG_FILE)" "$dir/sing-box.json"
  [[ -f "$(COMPOSE_FILE)" ]] && cp -a "$(COMPOSE_FILE)" "$dir/docker-compose.yml"
  log "已备份当前配置到：$dir"
}

validate_users_json() {
  ensure_jq
  local file
  file="$(USERS_FILE)"
  [[ -f "$file" ]] || return 1
  jq -e 'type == "object" and (.users | type == "array") and ((.version // 1) | tonumber >= 1)' "$file" >/dev/null
}

ensure_users_file() {
  ensure_dirs
  ensure_jq
  local file
  file="$(USERS_FILE)"
  if [[ ! -f "$file" ]]; then
    umask 077
    printf '{\n  "version": 1,\n  "users": []\n}\n' > "$file"
    chmod 600 "$file"
  fi
  chmod 600 "$file" 2>/dev/null || true
  validate_users_json || die "用户数据库格式错误：$file"
}

load_users_required() {
  ensure_users_file
}

validate_username() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || return 1
}

user_exists() {
  local name="$1"
  ensure_users_file
  jq -e --arg name "$name" '.users[]? | select(.name == $name)' "$(USERS_FILE)" >/dev/null
}

parse_bool01() {
  local raw="${1:-0}"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on|enable|enabled) printf '1' ;;
    *) printf '0' ;;
  esac
}

parse_bytes() {
  local raw="${1:-0}" lower number unit
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  lower="${lower// /}"
  case "$lower" in
    ''|0|unlimited|none|no|off) printf '0'; return 0 ;;
  esac
  if [[ "$lower" =~ ^([0-9]+)(b|bytes)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"; return 0
  fi
  if [[ "$lower" =~ ^([0-9]+)(k|kb|kib|m|mb|mib|g|gb|gib|t|tb|tib)$ ]]; then
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
      k|kb|kib) awk -v n="$number" 'BEGIN{printf "%.0f", n*1024}' ;;
      m|mb|mib) awk -v n="$number" 'BEGIN{printf "%.0f", n*1024*1024}' ;;
      g|gb|gib) awk -v n="$number" 'BEGIN{printf "%.0f", n*1024*1024*1024}' ;;
      t|tb|tib) awk -v n="$number" 'BEGIN{printf "%.0f", n*1024*1024*1024*1024}' ;;
    esac
    return 0
  fi
  return 1
}

format_bytes() {
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN{
    split("B KiB MiB GiB TiB", u, " ");
    i=1;
    while (b>=1024 && i<5) { b/=1024; i++ }
    if (i==1) printf "%.0f %s", b, u[i]; else printf "%.2f %s", b, u[i]
  }'
}

protocols_default() {
  local parts=()
  is_enabled "$ENABLE_ANYTLS" && parts+=("anytls")
  is_enabled "$ENABLE_NAIVE" && parts+=("naive")
  is_enabled "$ENABLE_SS" && [[ "$PM_NODE_ROLE" != "egress_b" ]] && parts+=("shadowsocks")
  local IFS=','
  printf '%s' "${parts[*]}"
}

protocol_in_list() {
  local protocol="$1" list="$2" normalized
  normalized=",$(printf '%s' "$list" | tr '[:upper:]' '[:lower:]' | tr '+/' ',,') ,"
  normalized="${normalized// /}"
  [[ "$normalized" == *",$protocol,"* ]]
}

migrate_legacy_single_user() {
  ensure_users_file
  local count file tmp any_enabled naive_enabled ss_enabled any_pass naive_user naive_pass ss_pass now
  file="$(USERS_FILE)"
  count="$(jq '.users | length' "$file")"
  [[ "$count" == "0" ]] || return 0
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then
    return 0
  fi
  any_enabled=false
  naive_enabled=false
  ss_enabled=false
  any_pass="${ANYTLS_PASSWORD:-$(random_hex)}"
  naive_user="${NAIVE_USERNAME:-$DEFAULT_NAIVE_USERNAME}"
  naive_pass="${NAIVE_PASSWORD:-$(random_hex)}"
  ss_pass="${SS_PASSWORD:-$(random_hex)}"
  is_enabled "$ENABLE_ANYTLS" && any_enabled=true
  is_enabled "$ENABLE_NAIVE" && naive_enabled=true
  is_enabled "$ENABLE_SS" && ss_enabled=true
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp)"
  jq \
    --arg now "$now" \
    --arg any_pass "$any_pass" \
    --arg naive_user "$naive_user" \
    --arg naive_pass "$naive_pass" \
    --arg ss_method "$SS_METHOD" \
    --arg ss_pass "$ss_pass" \
    --argjson any_enabled "$any_enabled" \
    --argjson naive_enabled "$naive_enabled" \
    --argjson ss_enabled "$ss_enabled" \
    '.users += [{
      name: "default",
      enabled: true,
      created_at: $now,
      updated_at: $now,
      protocols: {
        anytls: {enabled: $any_enabled, password: $any_pass},
        naive: {enabled: $naive_enabled, username: $naive_user, password: $naive_pass},
        shadowsocks: {enabled: $ss_enabled, method: $ss_method, password: $ss_pass}
      },
      quota: {enabled: false, limit_bytes: 0, reset_cycle: "monthly", last_reset_at: ""},
      traffic: {used_bytes: 0, uplink_bytes: 0, downlink_bytes: 0, last_checked_at: ""},
      note: "migrated from manager.env"
    }]' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

write_users_tmp() {
  local tmp="$1"
  mv "$tmp" "$(USERS_FILE)"
  chmod 600 "$(USERS_FILE)"
}

user_add_impl() {
  local name="$1" protocols="$2" quota_raw="${3:-0}" note="${4:-}" file tmp now any_enabled=false naive_enabled=false ss_enabled=false quota_bytes quota_enabled=false
  validate_username "$name" || die "用户名无效：$name。仅允许字母、数字、点、下划线和中划线，长度 1-64。"
  user_exists "$name" && die "用户已存在：$name"
  quota_bytes="$(parse_bytes "$quota_raw")" || die "流量限额无效：$quota_raw"
  [[ "$quota_bytes" != "0" ]] && quota_enabled=true
  protocols="${protocols:-$(protocols_default)}"
  protocol_in_list anytls "$protocols" && is_enabled "$ENABLE_ANYTLS" && any_enabled=true
  protocol_in_list naive "$protocols" && is_enabled "$ENABLE_NAIVE" && naive_enabled=true
  protocol_in_list shadowsocks "$protocols" && is_enabled "$ENABLE_SS" && [[ "$PM_NODE_ROLE" != "egress_b" ]] && ss_enabled=true
  if [[ "$any_enabled" == false && "$naive_enabled" == false && "$ss_enabled" == false ]]; then
    die "没有可为用户启用的协议。请检查组件开关或 --protocols。"
  fi
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  file="$(USERS_FILE)"
  tmp="$(mktemp)"
  jq \
    --arg name "$name" \
    --arg now "$now" \
    --arg any_pass "$(random_hex)" \
    --arg naive_user "$name" \
    --arg naive_pass "$(random_hex)" \
    --arg ss_method "$SS_METHOD" \
    --arg ss_pass "$(random_hex)" \
    --argjson any_enabled "$any_enabled" \
    --argjson naive_enabled "$naive_enabled" \
    --argjson ss_enabled "$ss_enabled" \
    --argjson quota_enabled "$quota_enabled" \
    --argjson quota_bytes "$quota_bytes" \
    --arg note "$note" \
    '.users += [{
      name: $name,
      enabled: true,
      created_at: $now,
      updated_at: $now,
      protocols: {
        anytls: {enabled: $any_enabled, password: $any_pass},
        naive: {enabled: $naive_enabled, username: $naive_user, password: $naive_pass},
        shadowsocks: {enabled: $ss_enabled, method: $ss_method, password: $ss_pass}
      },
      quota: {enabled: $quota_enabled, limit_bytes: $quota_bytes, reset_cycle: "monthly", last_reset_at: ""},
      traffic: {used_bytes: 0, uplink_bytes: 0, downlink_bytes: 0, last_checked_at: ""},
      note: $note
    }]' "$file" > "$tmp"
  write_users_tmp "$tmp"
  log "已添加用户：$name"
}

user_list() {
  load_env_required
  load_users_required
  migrate_legacy_single_user
  printf '\n%-20s %-8s %-28s %-16s %-16s\n' "USER" "STATUS" "PROTOCOLS" "USED" "QUOTA"
  jq -r '.users[]? | [
    .name,
    (if .enabled then "enabled" else "disabled" end),
    ([if .protocols.anytls.enabled then "anytls" else empty end, if .protocols.naive.enabled then "naive" else empty end, if .protocols.shadowsocks.enabled then "ss" else empty end] | join(",")),
    (.traffic.used_bytes // 0 | tostring),
    (if (.quota.enabled // false) then (.quota.limit_bytes // 0 | tostring) else "unlimited" end)
  ] | @tsv' "$(USERS_FILE)" | while IFS=$'\t' read -r name status protocols used quota; do
    [[ -n "$name" ]] || continue
    if [[ "$quota" == "unlimited" ]]; then
      printf '%-20s %-8s %-28s %-16s %-16s\n' "$name" "$status" "${protocols:-none}" "$(format_bytes "$used")" "$quota"
    else
      printf '%-20s %-8s %-28s %-16s %-16s\n' "$name" "$status" "${protocols:-none}" "$(format_bytes "$used")" "$(format_bytes "$quota")"
    fi
  done
}

user_show() {
  local name="$1"
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  jq -r --arg name "$name" '
    .users[] | select(.name == $name) |
    "用户: \(.name)\n状态: \(if .enabled then "enabled" else "disabled" end)\n创建: \(.created_at // "")\n更新: \(.updated_at // "")\n协议: " +
    ([if .protocols.anytls.enabled then "AnyTLS" else empty end, if .protocols.naive.enabled then "NaiveProxy" else empty end, if .protocols.shadowsocks.enabled then "Shadowsocks" else empty end] | join(", ")) +
    "\n限额: " + (if (.quota.enabled // false) then ((.quota.limit_bytes // 0) | tostring) + " bytes" else "unlimited" end) +
    "\n已用: " + ((.traffic.used_bytes // 0) | tostring) + " bytes" +
    "\n客户端目录: "
  ' "$(USERS_FILE)"
  printf '%s/%s\n' "$(CLIENT_DIR)" "$name"
}

user_set_enabled() {
  local name="$1" enabled="$2" tmp now
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp)"
  jq --arg name "$name" --arg now "$now" --argjson enabled "$enabled" '(.users[] | select(.name == $name)) |= (.enabled = $enabled | .updated_at = $now)' "$(USERS_FILE)" > "$tmp"
  write_users_tmp "$tmp"
  backup_configs
  render_all
  apply_runtime_if_running
  log "已更新用户状态：$name -> $enabled"
}

user_delete() {
  local name="$1" tmp
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  if [[ "$AUTO_YES" -ne 1 ]] && ! prompt_yes_no "确认删除用户 $name" "N"; then
    log "已取消。"
    return 0
  fi
  tmp="$(mktemp)"
  jq --arg name "$name" '.users = [.users[] | select(.name != $name)]' "$(USERS_FILE)" > "$tmp"
  write_users_tmp "$tmp"
  rm -rf "$(CLIENT_DIR)/${name:?}"
  backup_configs
  render_all
  apply_runtime_if_running
  log "已删除用户：$name"
}

user_change_password() {
  local name="$1" protocol="${2:-all}" tmp now any_pass naive_pass ss_pass
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in all|anytls|naive|shadowsocks|ss) ;; *) die "协议无效：$protocol" ;; esac
  any_pass="$(random_hex)"
  naive_pass="$(random_hex)"
  ss_pass="$(random_hex)"
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp)"
  jq --arg name "$name" --arg protocol "$protocol" --arg now "$now" --arg any_pass "$any_pass" --arg naive_pass "$naive_pass" --arg ss_pass "$ss_pass" '
    (.users[] | select(.name == $name)) |= (
      .updated_at = $now |
      if ($protocol == "all" or $protocol == "anytls") then .protocols.anytls.password = $any_pass else . end |
      if ($protocol == "all" or $protocol == "naive") then .protocols.naive.password = $naive_pass else . end |
      if ($protocol == "all" or $protocol == "shadowsocks" or $protocol == "ss") then .protocols.shadowsocks.password = $ss_pass else . end
    )' "$(USERS_FILE)" > "$tmp"
  write_users_tmp "$tmp"
  backup_configs
  render_all
  apply_runtime_if_running
  log "已重置用户密码：$name ($protocol)"
}

user_set_quota() {
  local name="$1" quota_raw="$2" quota_bytes quota_enabled=false tmp now
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  quota_bytes="$(parse_bytes "$quota_raw")" || die "流量限额无效：$quota_raw"
  [[ "$quota_bytes" != "0" ]] && quota_enabled=true
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp)"
  jq --arg name "$name" --arg now "$now" --argjson quota_enabled "$quota_enabled" --argjson quota_bytes "$quota_bytes" '
    (.users[] | select(.name == $name)) |= (.quota.enabled = $quota_enabled | .quota.limit_bytes = $quota_bytes | .updated_at = $now)
  ' "$(USERS_FILE)" > "$tmp"
  write_users_tmp "$tmp"
  log "已设置用户限额：$name -> $(format_bytes "$quota_bytes")"
}

user_reset_usage() {
  local name="$1" tmp now
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp)"
  jq --arg name "$name" --arg now "$now" '(.users[] | select(.name == $name)) |= (.traffic.used_bytes = 0 | .traffic.uplink_bytes = 0 | .traffic.downlink_bytes = 0 | .traffic.last_checked_at = $now | .quota.last_reset_at = $now | .updated_at = $now)' "$(USERS_FILE)" > "$tmp"
  write_users_tmp "$tmp"
  log "已重置用户流量：$name"
}

user_export() {
  local name="$1" file
  load_env_required
  load_users_required
  migrate_legacy_single_user
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  render_client_config_for_user "$name"
  printf '\n== 用户 %s 客户端配置 ==\n' "$name"
  for file in "$(CLIENT_DIR)/$name"/*.json; do
    [[ -f "$file" ]] || continue
    printf '\n--- %s ---\n' "$file"
    sed 's/^/  /' "$file"
  done
  warn "以上为用户客户端凭据，请勿公开粘贴。"
}

user_add_cmd() {
  load_env_required
  load_users_required
  migrate_legacy_single_user
  local name="" protocols="" quota="0" note="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do
    case "${args[$i]}" in
      --name) i=$((i+1)); name="${args[$i]:-}" ;;
      --name=*) name="${args[$i]#*=}" ;;
      --protocols) i=$((i+1)); protocols="${args[$i]:-}" ;;
      --protocols=*) protocols="${args[$i]#*=}" ;;
      --quota) i=$((i+1)); quota="${args[$i]:-0}" ;;
      --quota=*) quota="${args[$i]#*=}" ;;
      --note) i=$((i+1)); note="${args[$i]:-}" ;;
      --note=*) note="${args[$i]#*=}" ;;
      *)
        if [[ -z "$name" ]]; then
          name="${args[$i]}"
        else
          die "未知 user add 参数：${args[$i]}"
        fi
        ;;
    esac
  done
  if [[ -z "$name" ]]; then
    name="$(prompt_value '用户名' '')"
  fi
  [[ -n "$protocols" ]] || protocols="$(protocols_default)"
  user_add_impl "$name" "$protocols" "$quota" "$note"
  backup_configs
  render_all
  apply_runtime_if_running
}

user_help() {
  cat <<'EOF'
用户管理：
  p-m user list
  p-m user add <name> [--protocols anytls,naive,shadowsocks] [--quota 100GB]
  p-m user show <name>
  p-m user enable <name>
  p-m user disable <name>
  p-m user del <name>
  p-m user passwd <name> [all|anytls|naive|ss]
  p-m user quota <name> <unlimited|100GB|1048576>
  p-m user reset-usage <name>
  p-m user export <name>
EOF
}

user_cmd() {
  local sub="${POSITIONAL[0]:-help}" name value protocol args
  args=("${POSITIONAL[@]:1}")
  case "$sub" in
    help|-h|--help) user_help ;;
    list) user_list ;;
    add) user_add_cmd "${args[@]}" ;;
    show) name="${args[0]:-}"; [[ -n "$name" ]] || die "缺少用户名。"; user_show "$name" ;;
    enable) name="${args[0]:-}"; [[ -n "$name" ]] || die "缺少用户名。"; user_set_enabled "$name" true ;;
    disable) name="${args[0]:-}"; [[ -n "$name" ]] || die "缺少用户名。"; user_set_enabled "$name" false ;;
    del|delete|rm) name="${args[0]:-}"; [[ -n "$name" ]] || die "缺少用户名。"; user_delete "$name" ;;
    passwd|password) name="${args[0]:-}"; protocol="${args[1]:-all}"; [[ -n "$name" ]] || die "缺少用户名。"; user_change_password "$name" "$protocol" ;;
    quota) name="${args[0]:-}"; value="${args[1]:-}"; [[ -n "$name" && -n "$value" ]] || die "用法：p-m user quota <name> <unlimited|100GB>"; user_set_quota "$name" "$value" ;;
    reset-usage) name="${args[0]:-}"; [[ -n "$name" ]] || die "缺少用户名。"; user_reset_usage "$name" ;;
    export) name="${args[0]:-}"; [[ -n "$name" ]] || die "缺少用户名。"; user_export "$name" ;;
    *) die "未知 user 子命令：$sub" ;;
  esac
}

render_singbox_config() {
  ensure_dirs
  ensure_jq
  validate_topology_config
  ensure_users_file
  migrate_legacy_single_user
  local file enable_v2ray_effective
  file="$(CONFIG_FILE)"
  enable_v2ray_effective="$ENABLE_V2RAY_API"
  if is_enabled "$ENABLE_TRAFFIC_STATS" || is_enabled "$ENABLE_QUOTA_ENFORCE"; then
    enable_v2ray_effective=1
  fi
  jq -n \
    --slurpfile db "$(USERS_FILE)" \
    --arg role "$PM_NODE_ROLE" \
    --arg enable_anytls "$ENABLE_ANYTLS" \
    --arg enable_naive "$ENABLE_NAIVE" \
    --arg enable_ss "$ENABLE_SS" \
    --arg domain "$PM_DOMAIN" \
    --arg cert "$CERT_FILE" \
    --arg key "$KEY_FILE" \
    --arg anytls_port "${ANYTLS_PORT:-0}" \
    --arg naive_port "${NAIVE_PORT:-0}" \
    --arg ss_port "${SS_PORT:-0}" \
    --arg ss_method "$SS_METHOD" \
    --arg ss_pass "$SS_PASSWORD" \
    --arg b_host "$B_SS_HOST" \
    --arg b_port "${B_SS_PORT:-0}" \
    --arg b_method "$B_SS_METHOD" \
    --arg b_pass "$B_SS_PASSWORD" \
    --arg route_mode "$ROUTE_MODE" \
    --arg route_categories "$ROUTE_B_CATEGORIES" \
    --arg custom_domains "$ROUTE_B_CUSTOM_DOMAINS" \
    --arg custom_keywords "$ROUTE_B_CUSTOM_KEYWORDS" \
    --arg include_youtube "$ROUTE_B_INCLUDE_YOUTUBE" \
    --arg enable_v2ray "$enable_v2ray_effective" \
    --arg v2ray_listen "$V2RAY_API_LISTEN" \
    '
    def csv($s): (($s // "") | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)));
    def cats: csv($route_categories);
    def hascat($c): ((cats | index($c)) != null);
    def active_users($proto): (($db[0].users // []) | map(select((.enabled // false) == true and ((.protocols[$proto].enabled // false) == true))));
    def ai_domains: ["openai.com","chatgpt.com","oaistatic.com","oaiusercontent.com","anthropic.com","claude.ai","perplexity.ai","poe.com","mistral.ai","cohere.com","huggingface.co"];
    def google_domains: ["google.com","googleapis.com","gstatic.com","ggpht.com","googleusercontent.com","gmail.com"];
    def youtube_domains: ["youtube.com","ytimg.com","googlevideo.com"];
    def route_domains: (((if hascat("ai") then ai_domains else [] end) + (if hascat("google") then google_domains else [] end) + (if $include_youtube == "1" then youtube_domains else [] end) + csv($custom_domains)) | unique);
    def route_keywords: (csv($custom_keywords) | unique);
    def anytls_in:
      if $enable_anytls == "1" then
        {type:"anytls", tag:"anytls-in", listen:"0.0.0.0", listen_port:($anytls_port|tonumber), users: [active_users("anytls")[] | {name:.name, password:.protocols.anytls.password}], tls:{enabled:true, server_name:$domain, certificate_path:$cert, key_path:$key}}
      else empty end;
    def naive_in:
      if $enable_naive == "1" then
        {type:"naive", tag:"naive-in", listen:"0.0.0.0", listen_port:($naive_port|tonumber), users: [active_users("naive")[] | {username:(.protocols.naive.username // .name), password:.protocols.naive.password}], tls:{enabled:true, server_name:$domain, certificate_path:$cert, key_path:$key}}
      else empty end;
    def ss_user_in:
      if $enable_ss == "1" then
        {type:"shadowsocks", tag:"ss-in", listen:"0.0.0.0", listen_port:($ss_port|tonumber), method:$ss_method, password:$ss_pass, users: [active_users("shadowsocks")[] | {name:.name, password:.protocols.shadowsocks.password}]}
      else empty end;
    def ss_landing_in:
      {type:"shadowsocks", tag:"ss-landing-in", listen:"0.0.0.0", listen_port:($b_port|tonumber), method:$b_method, password:$b_pass};
    def direct_out: {type:"direct", tag:"direct"};
    def egress_b_out: {type:"shadowsocks", tag:"egress-b", server:$b_host, server_port:($b_port|tonumber), method:$b_method, password:$b_pass};
    def b_rule:
      if ((route_domains | length) > 0 or (route_keywords | length) > 0) then
        ({} + (if (route_domains | length) > 0 then {domain_suffix: route_domains} else {} end) + (if (route_keywords | length) > 0 then {domain_keyword: route_keywords} else {} end) + {action:"route", outbound:"egress-b"})
      else empty end;
    def route_obj:
      if $role == "entry_a" then
        if $route_mode == "all_via_b" then {final:"egress-b"}
        elif $route_mode == "split" then {rules:[b_rule], final:"direct"}
        else {final:"direct"} end
      else {final:"direct"} end;
    {
      log: {level:"info", timestamp:true},
      inbounds: (if $role == "egress_b" then [ss_landing_in] else [anytls_in, naive_in, ss_user_in] end),
      outbounds: (if $role == "entry_a" and $route_mode != "all_direct" then [direct_out, egress_b_out] else [direct_out] end),
      route: route_obj
    }
    + (if $enable_v2ray == "1" and $role != "egress_b" then {experimental:{v2ray_api:{listen:$v2ray_listen, stats:{enabled:true, users:[($db[0].users // [])[] | select((.enabled // false) == true) | .name]}}}} else {} end)
    ' > "$file"
  chmod 600 "$file" 2>/dev/null || true
}

append_outbound_sep() {
  local file="$1" first_flag="$2"
  if [[ "$first_flag" -eq 0 ]]; then
    printf ',\n' >> "$file"
  fi
}

render_client_config_for_user() {
  local name="$1" user_dir d any_enabled naive_enabled ss_enabled any_pass naive_user naive_pass ss_pass ss_method full first tags final_tag i
  ensure_users_file
  validate_username "$name" || die "用户名无效：$name"
  user_exists "$name" || die "用户不存在：$name"
  user_dir="$(CLIENT_DIR)/$name"
  mkdir -p "$user_dir"
  chmod 700 "$user_dir" 2>/dev/null || true
  d="$(json_escape "$PM_DOMAIN")"
  any_enabled="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.enabled and .protocols.anytls.enabled)' "$(USERS_FILE)")"
  naive_enabled="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.enabled and .protocols.naive.enabled)' "$(USERS_FILE)")"
  ss_enabled="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.enabled and .protocols.shadowsocks.enabled)' "$(USERS_FILE)")"
  rm -f "$user_dir"/*.json

  if [[ "$any_enabled" == "true" && "$ENABLE_ANYTLS" == "1" ]]; then
    any_pass="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | .protocols.anytls.password' "$(USERS_FILE)")"
    any_pass="$(json_escape "$any_pass")"
    cat > "$user_dir/anytls-outbound.json" <<EOF
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

  if [[ "$naive_enabled" == "true" && "$ENABLE_NAIVE" == "1" ]]; then
    naive_user="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.protocols.naive.username // .name)' "$(USERS_FILE)")"
    naive_pass="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | .protocols.naive.password' "$(USERS_FILE)")"
    naive_user="$(json_escape "$naive_user")"
    naive_pass="$(json_escape "$naive_pass")"
    cat > "$user_dir/naive-outbound.json" <<EOF
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

  if [[ "$ss_enabled" == "true" && "$ENABLE_SS" == "1" && "$PM_NODE_ROLE" != "egress_b" ]]; then
    ss_method="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.protocols.shadowsocks.method // "aes-128-gcm")' "$(USERS_FILE)")"
    ss_pass="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | .protocols.shadowsocks.password' "$(USERS_FILE)")"
    ss_method="$(json_escape "$ss_method")"
    ss_pass="$(json_escape "$ss_pass")"
    cat > "$user_dir/shadowsocks-outbound.json" <<EOF
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

  full="$user_dir/full-test-client.json"
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
  if [[ -f "$user_dir/anytls-outbound.json" ]]; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("anytls-out")
    sed 's/^/    /' "$user_dir/anytls-outbound.json" >> "$full"
  fi
  if [[ -f "$user_dir/naive-outbound.json" ]]; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("naive-out")
    sed 's/^/    /' "$user_dir/naive-outbound.json" >> "$full"
  fi
  if [[ -f "$user_dir/shadowsocks-outbound.json" ]]; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("ss-out")
    sed 's/^/    /' "$user_dir/shadowsocks-outbound.json" >> "$full"
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
    final_tag="${tags[0]:-direct}"
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
  chmod 600 "$user_dir"/*.json 2>/dev/null || true
}

render_client_configs() {
  ensure_dirs
  ensure_users_file
  migrate_legacy_single_user
  local name
  find "$(CLIENT_DIR)" -mindepth 1 -maxdepth 1 -type f -name '*.json' -delete 2>/dev/null || true
  find "$(CLIENT_DIR)" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    render_client_config_for_user "$name"
  done < <(jq -r '.users[]? | select(.enabled == true) | .name' "$(USERS_FILE)")
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
  ensure_jq
  validate_topology_config
  validate_unique_ports
  if needs_tls; then
    [[ -s "$CERT_FILE" ]] || die "证书文件不存在或为空：$CERT_FILE"
    [[ -s "$KEY_FILE" ]] || die "私钥文件不存在或为空：$KEY_FILE"
  fi
  if is_enabled "$ENABLE_ANYTLS"; then
    [[ -n "$ANYTLS_PASSWORD" ]] || ANYTLS_PASSWORD="$(random_hex)"
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    [[ -n "$NAIVE_USERNAME" ]] || NAIVE_USERNAME="$DEFAULT_NAIVE_USERNAME"
    [[ -n "$NAIVE_PASSWORD" ]] || NAIVE_PASSWORD="$(random_hex)"
  fi
  if is_enabled "$ENABLE_SS"; then
    [[ -n "$SS_METHOD" ]] || SS_METHOD="$DEFAULT_SS_METHOD"
    [[ -n "$SS_PASSWORD" ]] || SS_PASSWORD="$(random_hex)"
  fi
  write_env
  ensure_users_file
  migrate_legacy_single_user
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

compose_project_name() {
  local raw project
  raw="pm-${PM_CONTAINER_NAME:-proxy-manager}"
  project="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_')"
  printf '%s' "${project%_}"
}

compose_cmd() {
  local project
  project="$(compose_project_name)"
  if docker compose version >/dev/null 2>&1; then
    (cd "$(COMPOSE_DIR)" && docker compose -p "$project" "$@")
  else
    (cd "$(COMPOSE_DIR)" && docker-compose -p "$project" "$@")
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
    if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then
      warn "服务器 B 的 Shadowsocks 端口建议仅允许服务器 A 的公网 IP 访问。"
    fi
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
  printf '\n== 依赖 ==\n'
  if command -v jq >/dev/null 2>&1; then jq --version; else warn '未检测到 jq，多用户功能不可用。'; fi
  if command -v grpcurl >/dev/null 2>&1; then grpcurl -version 2>/dev/null || true; else warn '未检测到 grpcurl，V2Ray API 流量查询将降级。'; fi
  printf '\n== Docker ==\n'
  if command -v docker >/dev/null 2>&1; then
    docker --version || true
    if docker info >/dev/null 2>&1; then log 'Docker daemon 可用。'; else warn 'Docker 命令存在，但 Docker daemon 当前不可用。'; fi
  else
    warn '未检测到 Docker。'
  fi
  if compose_available; then docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true; else warn '未检测到 Docker Compose。'; fi
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
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then
    ENABLE_ANYTLS=0; ENABLE_NAIVE=0; ENABLE_SS=1
    log "服务器 B 模式固定启用 Shadowsocks 落地服务。"
    return 0
  fi
  if [[ -n "$CLI_COMPONENTS" ]]; then
    apply_components_value "$CLI_COMPONENTS"
    log "当前组件：$(component_summary)"
    return 0
  fi
  if [[ "$AUTO_YES" -eq 1 ]]; then
    if [[ "$PM_NODE_ROLE" == "entry_a" ]]; then
      ENABLE_ANYTLS=1; ENABLE_NAIVE=1; ENABLE_SS=0
    else
      ENABLE_ANYTLS="${ENABLE_ANYTLS:-1}"; ENABLE_NAIVE="${ENABLE_NAIVE:-1}"; ENABLE_SS="${ENABLE_SS:-1}"
    fi
    validate_enabled_components
    return 0
  fi
  cat <<EOF
请选择要安装/启用的组件：
1) 全部安装：AnyTLS + NaiveProxy + Shadowsocks
2) 仅安装 AnyTLS 入口
3) 仅安装 NaiveProxy 入口
4) 仅安装 Shadowsocks 服务
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
      if prompt_yes_no '启用 Shadowsocks 服务' 'N'; then ENABLE_SS=1; else ENABLE_SS=0; fi
      ;;
    *) die '无效组件选择。' ;;
  esac
  validate_enabled_components
  log "当前组件：$(component_summary)"
}

select_node_role() {
  local choice role
  if [[ -n "$CLI_NODE_ROLE" ]]; then
    role="$(printf '%s' "$CLI_NODE_ROLE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
  elif [[ "$AUTO_YES" -eq 1 ]]; then
    role="${PM_NODE_ROLE:-standalone}"
  else
    cat <<EOF
请选择部署角色：
1) standalone：单机兼容模式
2) entry_a：服务器 A，用户入口 + 分流到 B
3) egress_b：服务器 B，Shadowsocks 落地出口
EOF
    read -r -p '选择角色 [1]: ' choice || true
    choice="${choice:-1}"
    case "$choice" in
      1) role="standalone" ;;
      2) role="entry_a" ;;
      3) role="egress_b" ;;
      *) die '无效角色选择。' ;;
    esac
  fi
  case "$role" in
    standalone|entry_a|egress_b) PM_NODE_ROLE="$role" ;;
    a|server_a|entry) PM_NODE_ROLE="entry_a" ;;
    b|server_b|egress|landing) PM_NODE_ROLE="egress_b" ;;
    *) die "未知节点角色：$role" ;;
  esac
  validate_node_role
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
  if [[ -z "${CERT_FILE:-}" ]]; then CERT_FILE="$(prompt_value '证书 fullchain/cert 文件路径' "${CERT_FILE:-}")"; fi
  if [[ -z "${KEY_FILE:-}" ]]; then KEY_FILE="$(prompt_value '证书 privkey/key 文件路径' "${KEY_FILE:-}")"; fi
  [[ -s "$CERT_FILE" ]] || die "证书文件不存在或为空：$CERT_FILE"
  [[ -s "$KEY_FILE" ]] || die "私钥文件不存在或为空：$KEY_FILE"
}

collect_topology_inputs() {
  select_node_role
  if [[ -n "$CLI_ROUTE_MODE" ]]; then
    ROUTE_MODE="$(normalize_route_mode "$CLI_ROUTE_MODE")" || die "路由模式无效：$CLI_ROUTE_MODE"
  else
    ROUTE_MODE="$(normalize_route_mode "${ROUTE_MODE:-split}")" || die "路由模式无效：$ROUTE_MODE"
  fi
  if [[ -n "$CLI_ROUTE_B_CUSTOM_DOMAINS" ]]; then ROUTE_B_CUSTOM_DOMAINS="$CLI_ROUTE_B_CUSTOM_DOMAINS"; fi
  if [[ -n "$CLI_ROUTE_B_CUSTOM_KEYWORDS" ]]; then ROUTE_B_CUSTOM_KEYWORDS="$CLI_ROUTE_B_CUSTOM_KEYWORDS"; fi
  if [[ -n "$CLI_ROUTE_B_INCLUDE_YOUTUBE" ]]; then ROUTE_B_INCLUDE_YOUTUBE="$(parse_bool01 "$CLI_ROUTE_B_INCLUDE_YOUTUBE")"; fi
  if [[ -n "$CLI_ENABLE_V2RAY_API" ]]; then ENABLE_V2RAY_API="$(parse_bool01 "$CLI_ENABLE_V2RAY_API")"; fi
  if [[ -n "$CLI_V2RAY_API_LISTEN" ]]; then V2RAY_API_LISTEN="$CLI_V2RAY_API_LISTEN"; fi
  if [[ -n "$CLI_ENABLE_TRAFFIC_STATS" ]]; then ENABLE_TRAFFIC_STATS="$(parse_bool01 "$CLI_ENABLE_TRAFFIC_STATS")"; fi
  if [[ -n "$CLI_ENABLE_QUOTA_ENFORCE" ]]; then ENABLE_QUOTA_ENFORCE="$(parse_bool01 "$CLI_ENABLE_QUOTA_ENFORCE")"; fi
  if is_enabled "$ENABLE_TRAFFIC_STATS" || is_enabled "$ENABLE_QUOTA_ENFORCE"; then ENABLE_V2RAY_API=1; fi

  case "$PM_NODE_ROLE" in
    entry_a)
      if [[ "$AUTO_YES" -eq 0 ]]; then
        ROUTE_MODE="$(prompt_value '路由模式 split/all_via_b/all_direct' "${ROUTE_MODE:-split}")"
        ROUTE_MODE="$(normalize_route_mode "$ROUTE_MODE")" || die "路由模式无效。"
      fi
      if [[ "$ROUTE_MODE" != "all_direct" ]]; then
        if [[ -n "$CLI_B_SS_HOST" ]]; then B_SS_HOST="$CLI_B_SS_HOST"; else B_SS_HOST="$(prompt_value '服务器 B Shadowsocks 地址/IP' "${B_SS_HOST:-}")"; fi
        if [[ -n "$CLI_B_SS_PORT" ]]; then B_SS_PORT="$CLI_B_SS_PORT"; else B_SS_PORT="$(prompt_port '服务器 B Shadowsocks 端口' "${B_SS_PORT:-}")"; fi
        if [[ -n "$CLI_B_SS_METHOD" ]]; then B_SS_METHOD="$CLI_B_SS_METHOD"; else B_SS_METHOD="$(prompt_value '服务器 B Shadowsocks method' "${B_SS_METHOD:-$DEFAULT_SS_METHOD}")"; fi
        if [[ -n "$CLI_B_SS_PASSWORD" ]]; then B_SS_PASSWORD="$CLI_B_SS_PASSWORD"; else B_SS_PASSWORD="$(prompt_value '服务器 B Shadowsocks 密码，回车自动生成' "${B_SS_PASSWORD:-$(random_hex)}")"; fi
      fi
      ;;
    egress_b)
      if [[ -n "$CLI_B_SS_PORT" ]]; then B_SS_PORT="$CLI_B_SS_PORT"; elif [[ -n "$CLI_SS_PORT" ]]; then B_SS_PORT="$CLI_SS_PORT"; else B_SS_PORT="$(prompt_port '服务器 B Shadowsocks 落地监听端口' "${B_SS_PORT:-${SS_PORT:-}}")"; fi
      if [[ -n "$CLI_B_SS_METHOD" ]]; then B_SS_METHOD="$CLI_B_SS_METHOD"; else B_SS_METHOD="$(prompt_value '服务器 B Shadowsocks method' "${B_SS_METHOD:-$DEFAULT_SS_METHOD}")"; fi
      if [[ -n "$CLI_B_SS_PASSWORD" ]]; then B_SS_PASSWORD="$CLI_B_SS_PASSWORD"; elif [[ -n "$CLI_SS_PASSWORD" ]]; then B_SS_PASSWORD="$CLI_SS_PASSWORD"; else B_SS_PASSWORD="$(prompt_value '服务器 B Shadowsocks 密码，回车自动生成' "${B_SS_PASSWORD:-${SS_PASSWORD:-$(random_hex)}}")"; fi
      SS_PORT="$B_SS_PORT"; SS_METHOD="$B_SS_METHOD"; SS_PASSWORD="$B_SS_PASSWORD"
      ENABLE_ANYTLS=0; ENABLE_NAIVE=0; ENABLE_SS=1
      ;;
  esac
}

collect_install_inputs() {
  local default_root detected_ip image_default root_default
  if [[ -n "$CLI_DOMAIN" ]]; then PM_DOMAIN="$CLI_DOMAIN"; else PM_DOMAIN="$(prompt_value '部署域名' "${PM_DOMAIN:-$DEFAULT_DOMAIN}")"; fi
  default_root="/www/wwwroot/${PM_DOMAIN}/Proxy-Manager"
  root_default="${PM_ROOT:-$default_root}"
  if [[ "$root_default" == "/www/wwwroot/${DEFAULT_DOMAIN}/Proxy-Manager" && "$PM_DOMAIN" != "$DEFAULT_DOMAIN" ]]; then root_default="$default_root"; fi
  if [[ -n "$CLI_ROOT" ]]; then PM_ROOT="$CLI_ROOT"; else PM_ROOT="$(prompt_value '项目目录' "$root_default")"; fi
  ENV_FILE="$PM_ROOT/config/manager.env"
  detected_ip="$(detect_public_ip)"
  if [[ -n "$CLI_SERVER_IP" ]]; then PM_SERVER_IP="$CLI_SERVER_IP"; else PM_SERVER_IP="$(prompt_value '服务器 IP / 节点显示地址' "${PM_SERVER_IP:-$detected_ip}")"; fi
  if [[ -n "$CLI_CONTAINER_NAME" ]]; then PM_CONTAINER_NAME="$CLI_CONTAINER_NAME"; else PM_CONTAINER_NAME="$(prompt_value '容器名称' "${PM_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}")"; fi
  image_default="${PM_IMAGE:-$DEFAULT_IMAGE}"
  if [[ -n "$CLI_IMAGE" ]]; then PM_IMAGE="$CLI_IMAGE"; else PM_IMAGE="$(prompt_value 'sing-box Docker 镜像（默认使用 Docker Hub 发布镜像，可自定义）' "$image_default")"; fi
  if [[ -n "$CLI_TZ" ]]; then PM_TZ="$CLI_TZ"; else PM_TZ="$(prompt_value '时区' "${PM_TZ:-$DEFAULT_TZ}")"; fi

  collect_topology_inputs
  select_components
  collect_tls_inputs_if_needed

  if is_enabled "$ENABLE_ANYTLS"; then
    if [[ -n "$CLI_ANYTLS_PORT" ]]; then ANYTLS_PORT="$CLI_ANYTLS_PORT"; else ANYTLS_PORT="$(prompt_port 'AnyTLS 监听端口' "${ANYTLS_PORT:-}")"; fi
    if [[ -n "$CLI_ANYTLS_NAME" ]]; then ANYTLS_NAME="$CLI_ANYTLS_NAME"; else ANYTLS_NAME="$(prompt_value 'AnyTLS 默认用户名前缀' "${ANYTLS_NAME:-proxy}")"; fi
    if [[ -n "$CLI_ANYTLS_PASSWORD" ]]; then ANYTLS_PASSWORD="$CLI_ANYTLS_PASSWORD"; else ANYTLS_PASSWORD="$(prompt_value '迁移默认 AnyTLS 密码，回车自动生成' "${ANYTLS_PASSWORD:-$(random_hex)}")"; fi
  else
    ANYTLS_PORT=""; ANYTLS_PASSWORD=""
  fi

  if is_enabled "$ENABLE_NAIVE"; then
    if [[ -n "$CLI_NAIVE_PORT" ]]; then NAIVE_PORT="$CLI_NAIVE_PORT"; else NAIVE_PORT="$(prompt_port 'NaiveProxy 监听端口' "${NAIVE_PORT:-}")"; fi
    if [[ -n "$CLI_NAIVE_USERNAME" ]]; then NAIVE_USERNAME="$CLI_NAIVE_USERNAME"; else NAIVE_USERNAME="$(prompt_value '迁移默认 NaiveProxy 用户名' "${NAIVE_USERNAME:-$DEFAULT_NAIVE_USERNAME}")"; fi
    if [[ -n "$CLI_NAIVE_PASSWORD" ]]; then NAIVE_PASSWORD="$CLI_NAIVE_PASSWORD"; else NAIVE_PASSWORD="$(prompt_value '迁移默认 NaiveProxy 密码，回车自动生成' "${NAIVE_PASSWORD:-$(random_hex)}")"; fi
  else
    NAIVE_PORT=""; NAIVE_PASSWORD=""
  fi

  if is_enabled "$ENABLE_SS" && [[ "$PM_NODE_ROLE" != "egress_b" ]]; then
    if [[ -n "$CLI_SS_PORT" ]]; then SS_PORT="$CLI_SS_PORT"; else SS_PORT="$(prompt_port 'Shadowsocks 用户入口监听端口' "${SS_PORT:-}")"; fi
    SS_METHOD="$DEFAULT_SS_METHOD"
    if [[ -n "$CLI_SS_PASSWORD" ]]; then SS_PASSWORD="$CLI_SS_PASSWORD"; else SS_PASSWORD="$(prompt_value '迁移默认 Shadowsocks 密码，回车自动生成' "${SS_PASSWORD:-$(random_hex)}")"; fi
  elif [[ "$PM_NODE_ROLE" != "egress_b" ]]; then
    SS_PORT=""; SS_PASSWORD=""
  fi

  validate_topology_config
  validate_unique_ports
  CREATED_AT="${CREATED_AT:-$(date '+%F %T')}"
}

install_stack() {
  require_root
  ensure_jq
  ensure_docker
  ensure_compose
  collect_install_inputs
  ensure_dirs
  install_symlinks
  if [[ -f "$ENV_FILE" ]]; then backup_configs; fi
  render_all
  singbox_check
  open_firewall_ports
  compose_cmd up -d --force-recreate
  sleep 2
  status_stack
  show_info
  log "安装完成。以后可直接执行：p-m 或 proxy-manager"
}

start_stack() { load_env_required; ensure_docker; ensure_compose; compose_cmd up -d; status_stack; }
stop_stack() { load_env_required; ensure_docker; ensure_compose; compose_cmd down; }
restart_stack() { load_env_required; ensure_docker; ensure_compose; compose_cmd up -d --force-recreate; sleep 2; status_stack; }

apply_runtime_if_running() {
  if command -v docker >/dev/null 2>&1 && [[ -f "$(COMPOSE_FILE)" ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$PM_CONTAINER_NAME"; then
    if compose_available; then
      log "检测到服务正在运行，正在重建容器应用新配置。"
      compose_cmd up -d --force-recreate || warn "自动应用配置失败，请手动执行：p-m restart"
    else
      warn "配置已生成，但未检测到 Docker Compose，请手动修复后执行：p-m restart"
    fi
  else
    warn "配置已生成；如服务正在运行，请执行：p-m restart 应用。"
  fi
}

status_stack() {
  load_env_required
  local regex
  regex="$(active_port_regex)"
  printf '\n== 当前角色 ==\n%s\n' "$(role_label)"
  printf '\n== 当前组件 ==\n%s\n' "$(component_summary)"
  printf '\n== Docker 容器 ==\n'
  docker ps -a --filter "name=${PM_CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
  printf '\n== 监听端口 ==\n'
  if [[ -n "$regex" ]]; then ss -lntup 2>/dev/null | grep -E ":(${regex})([[:space:]]|$)" || true; fi
  printf '\n== 最近日志 ==\n'
  docker logs --tail=80 "$PM_CONTAINER_NAME" 2>&1 || true
}

logs_stack() { load_env_required; docker logs -f --tail=200 "$PM_CONTAINER_NAME"; }

show_info() {
  load_env_required
  local user_count enabled_count
  user_count="未初始化"
  enabled_count="未初始化"
  if [[ -f "$(USERS_FILE)" ]] && command -v jq >/dev/null 2>&1; then
    user_count="$(jq '.users | length' "$(USERS_FILE)" 2>/dev/null || printf '未知')"
    enabled_count="$(jq '[.users[]? | select(.enabled == true)] | length' "$(USERS_FILE)" 2>/dev/null || printf '未知')"
  fi
  cat <<EOF

================ Proxy Manager 节点信息 ================
域名:        $PM_DOMAIN
服务器 IP:   $PM_SERVER_IP
项目目录:    $PM_ROOT
容器名称:    $PM_CONTAINER_NAME
Docker 镜像: $PM_IMAGE
节点角色:    $(role_label)
启用组件:    $(component_summary)
用户数量:    $enabled_count / $user_count 启用
EOF
  if needs_tls; then
    cat <<EOF
证书文件:    $CERT_FILE
私钥文件:    $KEY_FILE
EOF
  fi
  if [[ "$PM_NODE_ROLE" == "entry_a" ]]; then
    cat <<EOF

[A/B 分流]
路由模式:    $ROUTE_MODE
B 地址:      ${B_SS_HOST:-未配置}
B 端口:      ${B_SS_PORT:-未配置}
B method:    ${B_SS_METHOD:-未配置}
B 密码:      $(mask_secret "$B_SS_PASSWORD")
AI/Google:   $ROUTE_B_CATEGORIES
自定义域名:  ${ROUTE_B_CUSTOM_DOMAINS:-无}
自定义关键词:${ROUTE_B_CUSTOM_KEYWORDS:-无}
YouTube:     ${ROUTE_B_INCLUDE_YOUTUBE}
EOF
  fi
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then
    cat <<EOF

[服务器 B Shadowsocks 落地]
监听端口:    $SS_PORT
method:      $SS_METHOD
password:    $(mask_secret "$SS_PASSWORD")
安全提示:    建议安全组/防火墙仅允许服务器 A 的 IP 访问该端口。
EOF
  fi
  if is_enabled "$ENABLE_ANYTLS"; then
    cat <<EOF

[AnyTLS 入口]
地址:        $PM_DOMAIN
端口:        $ANYTLS_PORT
客户端目录:  $(CLIENT_DIR)/<user>/anytls-outbound.json
EOF
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    cat <<EOF

[NaiveProxy 入口]
地址:        $PM_DOMAIN
端口:        $NAIVE_PORT
客户端目录:  $(CLIENT_DIR)/<user>/naive-outbound.json
EOF
  fi
  if is_enabled "$ENABLE_SS" && [[ "$PM_NODE_ROLE" != "egress_b" ]]; then
    cat <<EOF

[Shadowsocks 用户入口]
地址:        $PM_DOMAIN
端口:        $SS_PORT
method:      $SS_METHOD
客户端目录:  $(CLIENT_DIR)/<user>/shadowsocks-outbound.json
EOF
  fi
  cat <<EOF

[完整测试客户端]
$(CLIENT_DIR)/<user>/full-test-client.json
本地 socks/mixed 端口: 127.0.0.1:2080

管理命令：
  p-m user list
  p-m user export <user>
  p-m route show
  p-m doctor

敏感提示：用户导出配置包含真实密码，请不要公开粘贴。
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
4) B Shadowsocks 上游/落地: ${B_SS_PORT:-未配置}
5) 全部启用组件重新随机
0) 取消
EOF
  read -r -p '请选择要修改的端口: ' choice || true
  case "$choice" in
    1) is_enabled "$ENABLE_ANYTLS" || die 'AnyTLS 未启用。'; new_port="$(prompt_port '新的 AnyTLS 端口' '')"; ANYTLS_PORT="$new_port" ;;
    2) is_enabled "$ENABLE_NAIVE" || die 'NaiveProxy 未启用。'; new_port="$(prompt_port '新的 NaiveProxy 端口' '')"; NAIVE_PORT="$new_port" ;;
    3) is_enabled "$ENABLE_SS" || die 'Shadowsocks 未启用。'; new_port="$(prompt_port '新的 Shadowsocks 端口' '')"; SS_PORT="$new_port"; [[ "$PM_NODE_ROLE" == "egress_b" ]] && B_SS_PORT="$new_port" ;;
    4) new_port="$(prompt_port '新的 B Shadowsocks 端口' '')"; B_SS_PORT="$new_port"; [[ "$PM_NODE_ROLE" == "egress_b" ]] && SS_PORT="$new_port" ;;
    5) is_enabled "$ENABLE_ANYTLS" && ANYTLS_PORT="$(random_free_port)"; is_enabled "$ENABLE_NAIVE" && NAIVE_PORT="$(random_free_port)"; is_enabled "$ENABLE_SS" && SS_PORT="$(random_free_port)"; [[ "$PM_NODE_ROLE" == "egress_b" ]] && B_SS_PORT="$SS_PORT" ;;
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
  local choice value name protocol
  cat <<EOF
当前可修改项：
1) 迁移默认 AnyTLS 密码
2) 迁移默认 NaiveProxy 用户名/密码
3) 迁移默认 Shadowsocks 密码
4) B Shadowsocks 上游/落地密码
5) 指定用户密码（推荐）
0) 取消
EOF
  read -r -p '请选择要修改的密码: ' choice || true
  case "$choice" in
    1) is_enabled "$ENABLE_ANYTLS" || die 'AnyTLS 未启用。'; value="$(prompt_value '新的 AnyTLS 默认密码，回车自动生成' "$(random_hex)")"; ANYTLS_PASSWORD="$value" ;;
    2) is_enabled "$ENABLE_NAIVE" || die 'NaiveProxy 未启用。'; NAIVE_USERNAME="$(prompt_value '新的 NaiveProxy 默认用户名' "$NAIVE_USERNAME")"; NAIVE_PASSWORD="$(prompt_value '新的 NaiveProxy 默认密码，回车自动生成' "$(random_hex)")" ;;
    3) is_enabled "$ENABLE_SS" || die 'Shadowsocks 未启用。'; value="$(prompt_value '新的 Shadowsocks 默认密码，回车自动生成' "$(random_hex)")"; SS_PASSWORD="$value"; [[ "$PM_NODE_ROLE" == "egress_b" ]] && B_SS_PASSWORD="$value" ;;
    4) value="$(prompt_value '新的 B Shadowsocks 密码，回车自动生成' "$(random_hex)")"; B_SS_PASSWORD="$value"; [[ "$PM_NODE_ROLE" == "egress_b" ]] && SS_PASSWORD="$value" ;;
    5) read -r -p '用户名: ' name || true; protocol="$(prompt_value '协议 all/anytls/naive/ss' 'all')"; user_change_password "$name" "$protocol"; return 0 ;;
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
  [[ "$PM_ROOT" == /* ]] || die "PM_ROOT 必须是绝对路径，拒绝继续：$PM_ROOT"
  [[ "$PM_ROOT" != "/" && "$PM_ROOT" != "/root" && "$PM_ROOT" != "/home" && "$PM_ROOT" != "/usr" && "$PM_ROOT" != "/usr/local" && "$PM_ROOT" != "/www" && "$PM_ROOT" != "/www/wwwroot" ]] || die "PM_ROOT 指向系统关键目录，拒绝继续：$PM_ROOT"
  [[ -f "$(RUNTIME_DIR)/installed.flag" || -f "$(CONFIG_FILE)" ]] || die "未发现 Proxy Manager 标识文件，拒绝删除：$PM_ROOT"
}

regen_all() {
  load_env_required
  require_root
  warn "将重新生成已启用组件的端口、默认密码和所有用户客户端配置；用户数据库保留。"
  if ! prompt_yes_no '确认继续' 'N'; then log '已取消。'; return 0; fi
  backup_configs
  is_enabled "$ENABLE_ANYTLS" && { ANYTLS_PORT="$(random_free_port)"; ANYTLS_PASSWORD="$(random_hex)"; }
  is_enabled "$ENABLE_NAIVE" && { NAIVE_PORT="$(random_free_port)"; NAIVE_PASSWORD="$(random_hex)"; }
  is_enabled "$ENABLE_SS" && { SS_PORT="$(random_free_port)"; SS_PASSWORD="$(random_hex)"; }
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then B_SS_PORT="$SS_PORT"; B_SS_PASSWORD="$SS_PASSWORD"; fi
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
  if [[ "$delete_dir" == "DELETE" ]]; then rm -rf "$PM_ROOT"; log "已删除项目目录：$PM_ROOT"; else log "已保留项目目录：$PM_ROOT"; fi
  log "卸载完成。"
}

route_help() {
  cat <<'EOF'
分流管理：
  p-m route show
  p-m route mode split|all-via-b|all-direct
  p-m route add-domain example.com
  p-m route del-domain example.com
  p-m route add-keyword keyword
  p-m route del-keyword keyword

说明：split 模式下 AI / Google / 自定义规则走服务器 B，其余走服务器 A；all-via-b 全部走 B；all-direct 全部走 A。
EOF
}

csv_add_value() {
  local csv="$1" value="$2" normalized item out=()
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$value" ]] || { printf '%s' "$csv"; return 0; }
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]:-}"; do
    item="${item// /}"
    [[ -n "$item" ]] || continue
    [[ "$item" == "$value" ]] && normalized=1
    out+=("$item")
  done
  [[ "${normalized:-0}" == "1" ]] || out+=("$value")
  local IFS=','
  printf '%s' "${out[*]}"
}

csv_del_value() {
  local csv="$1" value="$2" item out=()
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]:-}"; do
    item="${item// /}"
    [[ -n "$item" ]] || continue
    [[ "$item" == "$value" ]] && continue
    out+=("$item")
  done
  local IFS=','
  printf '%s' "${out[*]}"
}

route_show() {
  load_env_required
  cat <<EOF
节点角色:      $(role_label)
路由模式:      $ROUTE_MODE
B 出口:        ${B_SS_HOST:-未配置}:${B_SS_PORT:-未配置}
默认分类:      $ROUTE_B_CATEGORIES
自定义域名:    ${ROUTE_B_CUSTOM_DOMAINS:-无}
自定义关键词:  ${ROUTE_B_CUSTOM_KEYWORDS:-无}
YouTube 走 B:  $ROUTE_B_INCLUDE_YOUTUBE
EOF
}

route_apply_and_render() {
  backup_configs
  render_all
  apply_runtime_if_running
}

route_cmd() {
  local sub="${POSITIONAL[0]:-help}" value normalized
  case "$sub" in
    help|-h|--help) route_help ;;
    show) route_show ;;
    mode)
      value="${POSITIONAL[1]:-}"; [[ -n "$value" ]] || die "缺少路由模式。"
      normalized="$(normalize_route_mode "$value")" || die "路由模式无效：$value"
      load_env_required
      ROUTE_MODE="$normalized"
      validate_topology_config
      write_env
      route_apply_and_render
      log "已设置路由模式：$ROUTE_MODE"
      ;;
    add-domain)
      value="${POSITIONAL[1]:-}"; [[ -n "$value" ]] || die "缺少域名。"
      load_env_required
      ROUTE_B_CUSTOM_DOMAINS="$(csv_add_value "$ROUTE_B_CUSTOM_DOMAINS" "$value")"
      write_env; route_apply_and_render ;;
    del-domain)
      value="${POSITIONAL[1]:-}"; [[ -n "$value" ]] || die "缺少域名。"
      load_env_required
      ROUTE_B_CUSTOM_DOMAINS="$(csv_del_value "$ROUTE_B_CUSTOM_DOMAINS" "$value")"
      write_env; route_apply_and_render ;;
    add-keyword)
      value="${POSITIONAL[1]:-}"; [[ -n "$value" ]] || die "缺少关键词。"
      load_env_required
      ROUTE_B_CUSTOM_KEYWORDS="$(csv_add_value "$ROUTE_B_CUSTOM_KEYWORDS" "$value")"
      write_env; route_apply_and_render ;;
    del-keyword)
      value="${POSITIONAL[1]:-}"; [[ -n "$value" ]] || die "缺少关键词。"
      load_env_required
      ROUTE_B_CUSTOM_KEYWORDS="$(csv_del_value "$ROUTE_B_CUSTOM_KEYWORDS" "$value")"
      write_env; route_apply_and_render ;;
    *) die "未知 route 子命令：$sub" ;;
  esac
}

ensure_stats_proto() {
  ensure_dirs
  cat > "$(STATS_PROTO_FILE)" <<'EOF'
syntax = "proto3";
package experimental.v2rayapi;
message GetStatsRequest { string name = 1; bool reset = 2; }
message Stat { string name = 1; int64 value = 2; }
message GetStatsResponse { Stat stat = 1; }
message QueryStatsRequest { string pattern = 1; bool reset = 2; repeated string patterns = 3; bool regexp = 4; }
message QueryStatsResponse { repeated Stat stat = 1; }
service StatsService {
  rpc GetStats(GetStatsRequest) returns (GetStatsResponse);
  rpc QueryStats(QueryStatsRequest) returns (QueryStatsResponse);
}
EOF
  chmod 600 "$(STATS_PROTO_FILE)" 2>/dev/null || true
}

probe_v2ray_api_support() {
  load_env_required
  ensure_docker
  ensure_dirs
  local tmp status=1
  tmp="$(mktemp "$(RUNTIME_DIR)/stats-probe.XXXXXX.json")"
  cat > "$tmp" <<EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"},
  "experimental": {
    "v2ray_api": {
      "listen": "$V2RAY_API_LISTEN",
      "stats": {"enabled": true, "users": ["probe"]}
    }
  }
}
EOF
  if docker run --rm -v "$tmp:/etc/sing-box/config.json:ro" "$PM_IMAGE" check -c /etc/sing-box/config.json; then
    printf 'yes\n' > "$(STATS_FLAG_FILE)"
    log "镜像支持 V2Ray API stats 配置语法。"
    status=0
  else
    printf 'no\n' > "$(STATS_FLAG_FILE)"
    warn "镜像不支持或未启用 V2Ray API stats；traffic/quota 将降级。"
  fi
  rm -f "$tmp"
  return "$status"
}

stats_available() {
  [[ -f "$(STATS_FLAG_FILE)" ]] && grep -qx 'yes' "$(STATS_FLAG_FILE)"
}

traffic_read_user_values() {
  local name="$1" output uplink downlink total
  stats_available || return 1
  command -v grpcurl >/dev/null 2>&1 || return 1
  ensure_stats_proto
  output="$(grpcurl -plaintext -proto "$(STATS_PROTO_FILE)" -d "{\"patterns\":[\"user>>>${name}>>>traffic>>>\"],\"reset\":false}" "$V2RAY_API_LISTEN" experimental.v2rayapi.StatsService/QueryStats 2>/dev/null || true)"
  [[ -n "$output" ]] || return 1
  uplink="$(printf '%s' "$output" | jq '[.stat[]? | select(.name | endswith("uplink")) | (.value | tonumber)] | add // 0')"
  downlink="$(printf '%s' "$output" | jq '[.stat[]? | select(.name | endswith("downlink")) | (.value | tonumber)] | add // 0')"
  total=$((uplink + downlink))
  printf '%s %s %s\n' "$uplink" "$downlink" "$total"
}

traffic_show() {
  load_env_required
  load_users_required
  migrate_legacy_single_user
  local target="${1:-}" name values up down total tmp now
  if ! stats_available; then
    warn "尚未确认 stats 可用。请先执行：p-m stats probe；如镜像或 grpcurl 不支持，将无法按用户统计。"
    user_list
    return 0
  fi
  printf '\n%-20s %-16s %-16s %-16s\n' "USER" "UPLINK" "DOWNLINK" "TOTAL"
  while IFS= read -r name; do
    [[ -n "$target" && "$name" != "$target" ]] && continue
    values="$(traffic_read_user_values "$name" || true)"
    if [[ -z "$values" ]]; then
      printf '%-20s %-16s %-16s %-16s\n' "$name" "N/A" "N/A" "N/A"
      continue
    fi
    read -r up down total <<< "$values"
    printf '%-20s %-16s %-16s %-16s\n' "$name" "$(format_bytes "$up")" "$(format_bytes "$down")" "$(format_bytes "$total")"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    tmp="$(mktemp)"
    jq --arg name "$name" --arg now "$now" --argjson up "$up" --argjson down "$down" --argjson total "$total" '(.users[] | select(.name == $name)) |= (.traffic.uplink_bytes = $up | .traffic.downlink_bytes = $down | .traffic.used_bytes = $total | .traffic.last_checked_at = $now)' "$(USERS_FILE)" > "$tmp"
    write_users_tmp "$tmp"
  done < <(jq -r '.users[]? | .name' "$(USERS_FILE)")
}

quota_check_all() {
  load_env_required
  load_users_required
  migrate_legacy_single_user
  if ! stats_available; then
    warn "stats 不可用，无法自动执行用户流量限额。请先执行 p-m stats probe，并确认 grpcurl 可查询 $V2RAY_API_LISTEN。"
    return 0
  fi
  local name values up down total limit enabled changed=0 tmp now
  while IFS= read -r name; do
    values="$(traffic_read_user_values "$name" || true)"
    [[ -n "$values" ]] || { warn "无法读取用户流量：$name"; continue; }
    read -r up down total <<< "$values"
    limit="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.quota.limit_bytes // 0)' "$(USERS_FILE)")"
    enabled="$(jq -r --arg name "$name" '.users[] | select(.name == $name) | (.quota.enabled // false)' "$(USERS_FILE)")"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    tmp="$(mktemp)"
    jq --arg name "$name" --arg now "$now" --argjson up "$up" --argjson down "$down" --argjson total "$total" '(.users[] | select(.name == $name)) |= (.traffic.uplink_bytes = $up | .traffic.downlink_bytes = $down | .traffic.used_bytes = $total | .traffic.last_checked_at = $now)' "$(USERS_FILE)" > "$tmp"
    write_users_tmp "$tmp"
    if [[ "$enabled" == "true" && "$limit" -gt 0 && "$total" -ge "$limit" ]]; then
      warn "用户 $name 已超额：$(format_bytes "$total") / $(format_bytes "$limit")，将禁用。"
      tmp="$(mktemp)"
      jq --arg name "$name" --arg now "$now" '(.users[] | select(.name == $name)) |= (.enabled = false | .updated_at = $now)' "$(USERS_FILE)" > "$tmp"
      write_users_tmp "$tmp"
      changed=1
    fi
  done < <(jq -r '.users[]? | select(.enabled == true) | .name' "$(USERS_FILE)")
  if [[ "$changed" -eq 1 ]]; then
    backup_configs
    render_all
    apply_runtime_if_running
  else
    log "限额检查完成，无需禁用用户。"
  fi
}

quota_cron_line() {
  printf '*/5 * * * * PM_ROOT=%s /usr/local/bin/p-m quota check >> %s 2>&1 # proxy-manager-quota\n' "$(shell_quote "$PM_ROOT")" "$(shell_quote "$PM_ROOT/logs/quota.log")"
}

quota_install_cron() {
  load_env_required
  command -v crontab >/dev/null 2>&1 || die "未检测到 crontab，无法安装定时限额检查。"
  ensure_dirs
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v 'proxy-manager-quota' > "$tmp" || true
  quota_cron_line >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  log "已安装限额检查定时任务：每 5 分钟执行 p-m quota check。"
}

quota_uninstall_cron() {
  load_env_required
  command -v crontab >/dev/null 2>&1 || die "未检测到 crontab，无法移除定时限额检查。"
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v 'proxy-manager-quota' > "$tmp" || true
  crontab "$tmp"
  rm -f "$tmp"
  log "已移除 Proxy Manager 限额检查定时任务。"
}

stats_help() { printf 'stats 命令：\n  p-m stats probe\n'; }
traffic_help() { printf 'traffic 命令：\n  p-m traffic [user]\n'; }
quota_help() { printf 'quota 命令：\n  p-m quota check\n  p-m quota install-cron\n  p-m quota uninstall-cron\n'; }

stats_cmd() {
  local sub="${POSITIONAL[0]:-help}"
  case "$sub" in probe) probe_v2ray_api_support ;; help|-h|--help) stats_help ;; *) die "未知 stats 子命令：$sub" ;; esac
}

traffic_cmd() {
  local sub="${POSITIONAL[0]:-}"
  case "$sub" in help|-h|--help) traffic_help ;; *) traffic_show "$sub" ;; esac
}

quota_cmd() {
  local sub="${POSITIONAL[0]:-help}"
  case "$sub" in
    check) quota_check_all ;;
    install-cron) quota_install_cron ;;
    uninstall-cron) quota_uninstall_cron ;;
    help|-h|--help) quota_help ;;
    *) die "未知 quota 子命令：$sub" ;;
  esac
}

doctor() {
  local have_error=0
  printf '\n== Proxy Manager Doctor ==\n'
  printf '版本: %s\n' "$VERSION"
  if [[ -f "$ENV_FILE" ]]; then
    safe_source_env "$ENV_FILE"
    printf '配置: %s\n' "$ENV_FILE"
    printf '角色: %s\n' "$(role_label)"
  else
    warn "未找到 manager.env；尚未安装。"
    have_error=1
  fi
  if command -v jq >/dev/null 2>&1; then log "jq 可用：$(jq --version)"; else warn "jq 不可用。"; have_error=1; fi
  if [[ -f "$(USERS_FILE)" ]]; then
    if validate_users_json; then log "users.json 合法：$(USERS_FILE)"; else warn "users.json 格式错误。"; have_error=1; fi
  else
    warn "users.json 尚未创建。"
  fi
  if [[ -f "$(CONFIG_FILE)" ]]; then log "sing-box 配置存在：$(CONFIG_FILE)"; else warn "sing-box 配置不存在。"; fi
  if command -v docker >/dev/null 2>&1; then
    docker --version || true
  else
    warn "Docker 不可用。"
    have_error=1
  fi
  if [[ "${PM_NODE_ROLE:-}" == "entry_a" && "${ROUTE_MODE:-split}" != "all_direct" ]]; then
    if [[ -n "${B_SS_HOST:-}" && -n "${B_SS_PORT:-}" && -n "${B_SS_PASSWORD:-}" ]]; then
      log "B Shadowsocks 上游字段完整：$B_SS_HOST:$B_SS_PORT"
    else
      warn "B Shadowsocks 上游字段不完整。"
      have_error=1
    fi
  fi
  if stats_available; then log "stats probe: yes"; else warn "stats probe 未通过或未执行。"; fi
  if [[ "$have_error" -eq 0 ]]; then log "doctor 完成：未发现阻塞项。"; else warn "doctor 完成：存在需要处理的项目。"; fi
}

topology_show() {
  load_env_required
  printf '\n== 当前拓扑 ==\n'
  printf '角色: %s\n' "$(role_label)"
  case "$PM_NODE_ROLE" in
    entry_a)
      printf '用户入口: %s:%s AnyTLS, %s:%s NaiveProxy\n' "$PM_DOMAIN" "${ANYTLS_PORT:-未启用}" "$PM_DOMAIN" "${NAIVE_PORT:-未启用}"
      printf '路由模式: %s\n' "$ROUTE_MODE"
      if [[ "$ROUTE_MODE" == "all_direct" ]]; then
        printf '出站: 全部 direct，经服务器 A 出口。\n'
      else
        printf 'B 出口: %s:%s (%s)\n' "${B_SS_HOST:-未配置}" "${B_SS_PORT:-未配置}" "${B_SS_METHOD:-未配置}"
        if [[ "$ROUTE_MODE" == "all_via_b" ]]; then
          printf '出站: 全部经服务器 B。\n'
        else
          printf '出站: AI/Google/custom 经服务器 B，其余 direct 经服务器 A。\n'
        fi
      fi
      ;;
    egress_b)
      printf 'Shadowsocks 落地: %s:%s (%s)\n' "$PM_SERVER_IP" "${SS_PORT:-未配置}" "${SS_METHOD:-未配置}"
      printf '出站: direct，经服务器 B 出口。\n'
      ;;
    *)
      printf '单机模式: 已启用组件 %s，默认 direct 出站。\n' "$(component_summary)"
      ;;
  esac
}

topology_cmd() {
  local sub="${POSITIONAL[0]:-show}"
  case "$sub" in
    show|help|-h|--help) topology_show ;;
    *) die "未知 topology 子命令：$sub" ;;
  esac
}

pause_return() {
  local _pause
  if [[ -t 0 ]]; then read -r -p '按回车返回上一页...' _pause || true; fi
}

run_menu_action() { "$@"; pause_return; }

print_main_menu() {
  cat <<EOF

Proxy Manager v$VERSION - $PM_DOMAIN
命令别名：proxy-manager / p-m
节点角色：$(role_label)
当前组件：$(component_summary)

1) 安装 / 更新
2) 服务管理
3) 用户管理
4) 分流管理
5) 流量 / 限额
6) 状态 / 日志 / 诊断
7) 节点信息
8) 审计 / 自检
9) 卸载清理
0) 退出

提示：主菜单直接回车退出；二级菜单直接回车返回上一页。
EOF
}

install_menu() {
  local choice
  while true; do
    cat <<EOF

安装 / 更新

1) 安装 / 重新部署 / 选择角色与组件
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

user_menu() {
  local choice name quota
  while true; do
    cat <<EOF

用户管理

1) 用户列表
2) 添加用户
3) 查看用户
4) 启用用户
5) 禁用用户
6) 删除用户
7) 重置用户密码
8) 设置用户限额
9) 导出用户客户端
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action user_list ;;
      2) run_menu_action user_add_cmd ;;
      3) read -r -p '用户名: ' name || true; run_menu_action user_show "$name" ;;
      4) read -r -p '用户名: ' name || true; run_menu_action user_set_enabled "$name" true ;;
      5) read -r -p '用户名: ' name || true; run_menu_action user_set_enabled "$name" false ;;
      6) read -r -p '用户名: ' name || true; run_menu_action user_delete "$name" ;;
      7) read -r -p '用户名: ' name || true; run_menu_action user_change_password "$name" all ;;
      8) read -r -p '用户名: ' name || true; read -r -p '限额（unlimited/100GB/字节数）: ' quota || true; run_menu_action user_set_quota "$name" "$quota" ;;
      9) read -r -p '用户名: ' name || true; run_menu_action user_export "$name" ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

route_menu() {
  local choice value
  while true; do
    cat <<EOF

分流管理

1) 查看分流
2) 切换路由模式
3) 添加走 B 域名
4) 删除走 B 域名
5) 添加走 B 关键词
6) 删除走 B 关键词
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action route_show ;;
      2) read -r -p '路由模式 split/all_via_b/all_direct: ' value || true; POSITIONAL=(mode "$value"); run_menu_action route_cmd ;;
      3) read -r -p '域名: ' value || true; POSITIONAL=(add-domain "$value"); run_menu_action route_cmd ;;
      4) read -r -p '域名: ' value || true; POSITIONAL=(del-domain "$value"); run_menu_action route_cmd ;;
      5) read -r -p '关键词: ' value || true; POSITIONAL=(add-keyword "$value"); run_menu_action route_cmd ;;
      6) read -r -p '关键词: ' value || true; POSITIONAL=(del-keyword "$value"); run_menu_action route_cmd ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

traffic_menu() {
  local choice name
  while true; do
    cat <<EOF

流量 / 限额

1) 探测 stats 能力
2) 查看全部用户流量
3) 查看指定用户流量
4) 执行限额检查
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action probe_v2ray_api_support ;;
      2) run_menu_action traffic_show ;;
      3) read -r -p '用户名: ' name || true; run_menu_action traffic_show "$name" ;;
      4) run_menu_action quota_check_all ;;
      0|'') return 0 ;;
      *) warn '无效选择。'; pause_return ;;
    esac
  done
}

status_menu() {
  local choice
  while true; do
    cat <<EOF

状态 / 日志 / 诊断

1) 查看运行状态
2) 查看实时日志
3) 检查 sing-box 配置
4) 运行 doctor
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action status_stack ;;
      2) logs_stack ;;
      3) run_menu_action check_stack ;;
      4) run_menu_action doctor ;;
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
3) 查看拓扑
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action show_info ;;
      2) run_menu_action usage ;;
      3) run_menu_action topology_show ;;
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
5) 运行 doctor
0) 返回上一页
EOF
    read -r -p '请选择操作 [回车返回]: ' choice || true
    case "$choice" in
      1) run_menu_action check_environment ;;
      2) run_menu_action check_stack ;;
      3) run_menu_action status_stack ;;
      4) printf '\n版本: %s\n仓库: %s\nRelease: %s\n开发版: %s\n' "$VERSION" "$REPO_URL" "$RELEASE_SCRIPT_URL" "$RAW_SCRIPT_URL"; pause_return ;;
      5) run_menu_action doctor ;;
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

config_menu() {
  local choice
  while true; do
    cat <<EOF

配置管理

1) 修改端口
2) 修改 / 重新生成密码
3) 重新生成已启用组件的端口和密码
4) 重新部署 / 切换角色与组件
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

menu() {
  local choice
  while true; do
    print_main_menu
    read -r -p '请选择操作 [回车退出]: ' choice || true
    case "$choice" in
      1) install_menu ;;
      2) service_menu ;;
      3) user_menu ;;
      4) route_menu ;;
      5) traffic_menu ;;
      6) status_menu ;;
      7) info_menu ;;
      8) audit_menu ;;
      9) remove_menu ;;
      c) config_menu ;;
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
  install          安装 / 重新部署 / 选择角色与组件
  update           从 GitHub 更新脚本
  pull-image       拉取当前配置中的 Docker 镜像
  env-check        检查本机 Docker、Compose、jq、grpcurl 和命令映射
  start|stop|restart|status|logs
  info             查看节点信息
  user             多用户管理，详见 p-m user help
  route            A/B 分流管理，详见 p-m route help
  stats            V2Ray API stats 能力探测
  traffic          查看用户流量（依赖 stats + grpcurl）
  quota            执行限额检查（依赖 stats + grpcurl）
  doctor           运行诊断
  topology         查看当前拓扑
  change-port      修改端口
  change-secret    修改全局/迁移默认密码
  regen            重新生成已启用组件的端口和密码
  check            检查 sing-box 配置
  uninstall        卸载清理
  help             查看帮助

角色：
  standalone       单机兼容模式
  entry_a          服务器 A：AnyTLS/Naive 用户入口，AI/Google/custom 可走 B
  egress_b         服务器 B：Shadowsocks 落地出口

路由模式：
  split            AI/Google/custom 走 B，其余走 A
  all_via_b        全部流量走 B，用户看到的出口 IP 为 B
  all_direct       全部流量走 A，用于回退/排障

install 可选参数：
  --yes
  --domain DOMAIN
  --root PATH
  --server-ip IP
  --image IMAGE
  --node-role standalone|entry_a|egress_b
  --components all|anytls|naive|ss|anytls,naive
  --cert-file PATH
  --key-file PATH
  --anytls-port PORT
  --naive-port PORT
  --ss-port PORT
  --b-ss-host HOST
  --b-ss-port PORT
  --b-ss-method METHOD
  --b-ss-password PASSWORD
  --route-mode split|all_via_b|all_direct
  --route-b-domains example.com,example.net
  --route-b-keywords keyword1,keyword2
  --include-youtube
  --enable-v2ray-api
  --v2ray-api-listen 127.0.0.1:10085
  --enable-traffic-stats
  --enable-quota-enforce

服务器 B 示例：
  p-m install --yes --node-role egress_b --domain b.example.com --server-ip 198.51.100.20 --b-ss-port 30003 --b-ss-password '<B_SS_PASSWORD>'

服务器 A split 示例：
  p-m install --yes --node-role entry_a --domain a.example.com --server-ip 203.0.113.10 --components anytls,naive --cert-file /path/fullchain.pem --key-file /path/privkey.pem --b-ss-host 198.51.100.20 --b-ss-port 30003 --b-ss-password '<B_SS_PASSWORD>' --route-mode split

GitHub 下载安装：
  curl -fsSL $RELEASE_SCRIPT_URL -o /tmp/proxy-manager.sh
  sudo bash /tmp/proxy-manager.sh install
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
  user) user_cmd ;;
  route) route_cmd ;;
  stats) stats_cmd ;;
  traffic) traffic_cmd ;;
  quota) quota_cmd ;;
  doctor) doctor ;;
  topology) topology_cmd ;;
  change-port) change_port ;;
  change-secret) change_secret ;;
  regen) regen_all ;;
  check) check_stack ;;
  uninstall) uninstall_stack ;;
  help|-h|--help) usage ;;
  *) err "未知命令：$COMMAND"; usage; exit 2 ;;
esac
