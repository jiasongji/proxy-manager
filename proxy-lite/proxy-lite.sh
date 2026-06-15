#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.1.0"
REPO_URL="https://github.com/jiasongji/proxy-lite"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/jiasongji/proxy-lite/main/proxy-lite.sh"
RELEASE_SCRIPT_URL="https://github.com/jiasongji/proxy-lite/releases/latest/download/proxy-lite.sh"
DEFAULT_DOMAIN="example.com"
DEFAULT_SERVER_IP="203.0.113.10"
DEFAULT_CONTAINER_NAME="proxy-lite-sing-box"
DEFAULT_IMAGE="ghcr.io/sagernet/sing-box:latest"
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
  DERIVED_ROOT="/www/wwwroot/${DEFAULT_DOMAIN}/Proxy-Lite"
fi
PM_ROOT="${PM_ROOT:-$DERIVED_ROOT}"
ENV_FILE="$PM_ROOT/config/lite.env"

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
  # lite.env 由本脚本按白名单键写入，并强制 root/600 权限后读取。
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
PM_NODE_ROLE="${PM_NODE_ROLE:-entry_a}"
ENABLE_ANYTLS="${ENABLE_ANYTLS:-1}"
ENABLE_NAIVE="${ENABLE_NAIVE:-1}"
ENABLE_SS="${ENABLE_SS:-0}"
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
CREATED_AT="${CREATED_AT:-}"
LAST_BACKUP_DIR=""

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
CLI_B_SS_HOST=""
CLI_B_SS_PORT=""
CLI_B_SS_METHOD=""
CLI_B_SS_PASSWORD=""
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
    --b-ss-host|--b-ss-host=*)
      CLI_B_SS_HOST="$(parse_arg_value "$1" "${2:-}" --b-ss-host)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-port|--b-ss-port=*)
      CLI_B_SS_PORT="$(parse_arg_value "$1" "${2:-}" --b-ss-port)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-method|--b-ss-method=*)
      CLI_B_SS_METHOD="$(parse_arg_value "$1" "${2:-}" --b-ss-method)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
    --b-ss-password|--b-ss-password=*)
      CLI_B_SS_PASSWORD="$(parse_arg_value "$1" "${2:-}" --b-ss-password)"; if [[ "$1" == *=* ]]; then shift; else shift 2; fi ;;
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

log() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

is_enabled() { [[ "${1:-0}" == "1" ]]; }
needs_tls() { is_enabled "$ENABLE_ANYTLS" || is_enabled "$ENABLE_NAIVE"; }
require_root() { [[ "$(id -u)" -eq 0 ]] || die "请使用 root 用户执行。"; }

is_help_like_command() {
  case "$COMMAND" in
    help|-h|--help) return 0 ;;
    backup|rollback|upgrade)
      case "${POSITIONAL[0]:-}" in help|-h|--help) return 0 ;; esac ;;
    user|route|stats|traffic|quota) return 0 ;;
  esac
  return 1
}

require_root_for_command() {
  if is_help_like_command; then return 0; fi
  if [[ "${PL_TEST_ALLOW_NON_ROOT:-0}" == "1" ]]; then return 0; fi
  require_root
}

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
  case "${PM_NODE_ROLE:-entry_a}" in
    entry_a) printf '服务器 A 入口/固定经 B 落地' ;;
    egress_b) printf '服务器 B Shadowsocks 落地出口' ;;
    *) printf '%s' "$PM_NODE_ROLE" ;;
  esac
}

ensure_dirs() {
  mkdir -p "$PM_ROOT/bin" "$(CONFIG_DIR)" "$(CLIENT_DIR)" "$(COMPOSE_DIR)" "$(BACKUP_DIR)" "$(RUNTIME_DIR)" "$(DOCS_DIR)" "$PM_ROOT/logs"
  chmod 700 "$(CONFIG_DIR)" "$(CLIENT_DIR)" "$(BACKUP_DIR)" "$(RUNTIME_DIR)" 2>/dev/null || true
}

ensure_jq() { command -v jq >/dev/null 2>&1 || die "配置生成需要 jq。请先安装 jq 后重试。"; }

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
  if [[ -z "$suggested" ]]; then suggested="$(random_free_port || true)"; fi
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
  case "${PM_NODE_ROLE:-entry_a}" in
    entry_a|egress_b) ;;
    *) die "未知节点角色：$PM_NODE_ROLE。proxy-lite 仅支持 entry_a、egress_b。" ;;
  esac
}

validate_enabled_components() {
  if [[ "${PM_NODE_ROLE:-entry_a}" == "egress_b" ]]; then
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
  if is_enabled "$ENABLE_ANYTLS"; then validate_port_number "$ANYTLS_PORT" || die "AnyTLS 端口无效：$ANYTLS_PORT"; ports+=("$ANYTLS_PORT"); names+=("AnyTLS"); fi
  if is_enabled "$ENABLE_NAIVE"; then validate_port_number "$NAIVE_PORT" || die "NaiveProxy 端口无效：$NAIVE_PORT"; ports+=("$NAIVE_PORT"); names+=("NaiveProxy"); fi
  if is_enabled "$ENABLE_SS"; then validate_port_number "$SS_PORT" || die "Shadowsocks 端口无效：$SS_PORT"; ports+=("$SS_PORT"); names+=("Shadowsocks"); fi
  for ((i=0; i<${#ports[@]}; i++)); do
    for ((j=i+1; j<${#ports[@]}; j++)); do
      [[ "${ports[$i]}" != "${ports[$j]}" ]] || die "端口重复：${names[$i]} 与 ${names[$j]} 都使用 ${ports[$i]}。"
    done
  done
}

validate_topology_config() {
  validate_node_role
  case "$PM_NODE_ROLE" in
    entry_a)
      [[ -n "$B_SS_HOST" ]] || die "服务器 A 需要填写 B_SS_HOST。"
      validate_port_number "$B_SS_PORT" || die "B_SS_PORT 无效：$B_SS_PORT"
      [[ -n "$B_SS_METHOD" ]] || die "B_SS_METHOD 为空。"
      [[ -n "$B_SS_PASSWORD" ]] || die "B_SS_PASSWORD 为空。"
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

json_string() { jq -Rn --arg v "$1" '$v|@json'; }

shell_quote() { printf '%q' "$1"; }

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
    printf 'CERT_FILE=%s\n' "$(shell_quote "$CERT_FILE")"
    printf 'KEY_FILE=%s\n' "$(shell_quote "$KEY_FILE")"
    printf 'CREATED_AT=%s\n' "$(shell_quote "${CREATED_AT:-$(date '+%F %T')}")"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

load_env_required() {
  ENV_FILE="$PM_ROOT/config/lite.env"
  [[ -f "$ENV_FILE" ]] || die "未找到配置文件：$ENV_FILE，请先执行 proxy-lite install 或 PL install。"
  safe_source_env "$ENV_FILE"
  PM_NODE_ROLE="${PM_NODE_ROLE:-entry_a}"
  B_SS_METHOD="${B_SS_METHOD:-$DEFAULT_SS_METHOD}"
  validate_node_role
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
  local ts base dir n
  ts="$(date '+%Y%m%d-%H%M%S')"
  base="$(BACKUP_DIR)/$ts"
  dir="$base"
  n=1
  while [[ -e "$dir" ]]; do
    dir="${base}-$n"
    n=$((n + 1))
  done
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  [[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$dir/lite.env"
  [[ -f "$(CONFIG_FILE)" ]] && cp -a "$(CONFIG_FILE)" "$dir/sing-box.json"
  [[ -f "$(COMPOSE_FILE)" ]] && cp -a "$(COMPOSE_FILE)" "$dir/docker-compose.yml"
  [[ -f "$PM_ROOT/bin/proxy-lite.sh" ]] && cp -a "$PM_ROOT/bin/proxy-lite.sh" "$dir/proxy-lite.sh"
  LAST_BACKUP_DIR="$dir"
  log "已备份当前配置到：$dir"
}

backup_usage() {
  cat <<'EOF'
用法：
  PL backup list     列出可回退配置快照
  PL backup help     查看帮助

说明：快照位于 backup/<timestamp>/，包含可用时的 lite.env、sing-box.json、docker-compose.yml 和脚本副本。
EOF
}

backup_file_mark() {
  local dir="$1" file="$2"
  if [[ -f "$dir/$file" ]]; then printf 'yes'; else printf 'no'; fi
}

list_backups() {
  ensure_dirs
  local root dir name found=0
  root="$(BACKUP_DIR)"
  printf '备份目录：%s\n' "$root"
  printf '%-18s %-10s %-13s %-18s %-14s\n' 'TIMESTAMP' 'lite.env' 'sing-box' 'docker-compose' 'script'
  for dir in "$root"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ "$name" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || continue
    found=1
    printf '%-18s %-10s %-13s %-18s %-14s\n' \
      "$name" \
      "$(backup_file_mark "$dir" lite.env)" \
      "$(backup_file_mark "$dir" sing-box.json)" \
      "$(backup_file_mark "$dir" docker-compose.yml)" \
      "$(backup_file_mark "$dir" proxy-lite.sh)"
  done
  if [[ "$found" -eq 0 ]]; then warn "暂无可用备份。"; fi
}

latest_backup_dir() {
  local root dir latest="" name
  root="$(BACKUP_DIR)"
  for dir in "$root"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ "$name" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || continue
    latest="$dir"
  done
  [[ -n "$latest" ]] || return 1
  printf '%s\n' "$latest"
}

resolve_backup_dir() {
  local target="${1:-latest}" root dir
  root="$(BACKUP_DIR)"
  if [[ "$target" == "latest" ]]; then
    latest_backup_dir || die "暂无可用备份。"
    return 0
  fi
  [[ "$target" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "备份标识无效：$target"
  dir="$root/$target"
  [[ -d "$dir" ]] || die "备份不存在：$target"
  printf '%s\n' "$dir"
}

restore_backup_files() {
  local dir="$1"
  [[ -d "$dir" ]] || die "备份目录不存在：$dir"
  [[ -f "$dir/lite.env" ]] || die "备份缺少 lite.env：$dir"
  ensure_dirs
  cp -a "$dir/lite.env" "$ENV_FILE"
  [[ -f "$dir/sing-box.json" ]] && cp -a "$dir/sing-box.json" "$(CONFIG_FILE)"
  [[ -f "$dir/docker-compose.yml" ]] && cp -a "$dir/docker-compose.yml" "$(COMPOSE_FILE)"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  log "已恢复配置快照：$dir"
}

restore_snapshot_or_warn() {
  local snapshot="$1"
  if [[ -n "$snapshot" && -d "$snapshot" ]]; then
    restore_backup_files "$snapshot" || warn "恢复快照失败：$snapshot"
    load_env_required || true
  else
    warn "未找到可恢复快照。"
  fi
}

parse_bool01() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) printf '1' ;;
    *) printf '0' ;;
  esac
}

normalize_components() {
  local raw="$1" item normalized="" token
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '+' ',')"
  IFS=',' read -r -a item <<< "$raw"
  for token in "${item[@]}"; do
    token="$(printf '%s' "$token" | tr -d '[:space:]')"
    [[ -n "$token" ]] || continue
    case "$token" in
      all) normalized="anytls,naive,ss" ;;
      anytls|any) normalized+="${normalized:+,}anytls" ;;
      naive|naiveproxy) normalized+="${normalized:+,}naive" ;;
      ss|shadowsocks) normalized+="${normalized:+,}ss" ;;
      *) die "未知组件：$token。支持 anytls、naive、ss、all。" ;;
    esac
  done
  printf '%s\n' "$normalized"
}

apply_components() {
  local normalized="$1"
  ENABLE_ANYTLS=0
  ENABLE_NAIVE=0
  ENABLE_SS=0
  [[ ",$normalized," == *,anytls,* ]] && ENABLE_ANYTLS=1
  [[ ",$normalized," == *,naive,* ]] && ENABLE_NAIVE=1
  [[ ",$normalized," == *,ss,* ]] && ENABLE_SS=1
}

select_components() {
  local default_components raw normalized
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then
    ENABLE_ANYTLS=0; ENABLE_NAIVE=0; ENABLE_SS=1
    return 0
  fi
  default_components="anytls,naive"
  if [[ -n "$CLI_COMPONENTS" ]]; then
    raw="$CLI_COMPONENTS"
  else
    raw="$(prompt_value '服务器 A 启用组件（anytls,naive,ss,all）' "$default_components")"
  fi
  normalized="$(normalize_components "$raw")"
  [[ -n "$normalized" ]] || die "至少需要选择一个组件。"
  apply_components "$normalized"
}

collect_tls_inputs_if_needed() {
  local detected=() cert key
  if ! needs_tls; then CERT_FILE=""; KEY_FILE=""; return 0; fi
  if [[ -n "$CLI_CERT_FILE" ]]; then CERT_FILE="$CLI_CERT_FILE"; fi
  if [[ -n "$CLI_KEY_FILE" ]]; then KEY_FILE="$CLI_KEY_FILE"; fi
  if [[ -z "$CERT_FILE" || -z "$KEY_FILE" ]]; then
    if mapfile -t detected < <(detect_cert_pair "$PM_DOMAIN"); then
      cert="${detected[0]:-}"
      key="${detected[1]:-}"
      if [[ -z "$CERT_FILE" ]]; then CERT_FILE="$cert"; fi
      if [[ -z "$KEY_FILE" ]]; then KEY_FILE="$key"; fi
    fi
  fi
  CERT_FILE="$(prompt_value 'TLS 证书 fullchain/cert 路径' "$CERT_FILE")"
  KEY_FILE="$(prompt_value 'TLS 私钥 privkey/key 路径' "$KEY_FILE")"
  [[ -s "$CERT_FILE" ]] || die "证书文件不存在或为空：$CERT_FILE"
  [[ -s "$KEY_FILE" ]] || die "私钥文件不存在或为空：$KEY_FILE"
}

collect_topology_inputs() {
  if [[ -n "$CLI_NODE_ROLE" ]]; then
    PM_NODE_ROLE="$CLI_NODE_ROLE"
  else
    PM_NODE_ROLE="$(prompt_value '节点角色：entry_a=服务器A入口，egress_b=服务器B落地' "${PM_NODE_ROLE:-entry_a}")"
  fi
  validate_node_role
  if [[ "$PM_NODE_ROLE" == "entry_a" ]]; then
    if [[ -n "$CLI_B_SS_HOST" ]]; then B_SS_HOST="$CLI_B_SS_HOST"; else B_SS_HOST="$(prompt_value '服务器 B Shadowsocks 地址' "$B_SS_HOST")"; fi
    if [[ -n "$CLI_B_SS_PORT" ]]; then B_SS_PORT="$CLI_B_SS_PORT"; else B_SS_PORT="$(prompt_port '服务器 B Shadowsocks 端口' "$B_SS_PORT")"; fi
    if [[ -n "$CLI_B_SS_METHOD" ]]; then B_SS_METHOD="$CLI_B_SS_METHOD"; else B_SS_METHOD="$(prompt_value '服务器 B Shadowsocks method' "${B_SS_METHOD:-$DEFAULT_SS_METHOD}")"; fi
    if [[ -n "$CLI_B_SS_PASSWORD" ]]; then B_SS_PASSWORD="$CLI_B_SS_PASSWORD"; else B_SS_PASSWORD="$(prompt_value '服务器 B Shadowsocks 密码' "$B_SS_PASSWORD")"; fi
  fi
}

collect_install_inputs() {
  local default_root detected_ip image_default root_default
  if [[ -n "$CLI_DOMAIN" ]]; then PM_DOMAIN="$CLI_DOMAIN"; else PM_DOMAIN="$(prompt_value '部署域名' "${PM_DOMAIN:-$DEFAULT_DOMAIN}")"; fi
  default_root="/www/wwwroot/${PM_DOMAIN}/Proxy-Lite"
  root_default="${PM_ROOT:-$default_root}"
  if [[ "$root_default" == "/www/wwwroot/${DEFAULT_DOMAIN}/Proxy-Lite" && "$PM_DOMAIN" != "$DEFAULT_DOMAIN" ]]; then root_default="$default_root"; fi
  if [[ -n "$CLI_ROOT" ]]; then PM_ROOT="$CLI_ROOT"; else PM_ROOT="$(prompt_value '项目目录' "$root_default")"; fi
  ENV_FILE="$PM_ROOT/config/lite.env"
  detected_ip="$(detect_public_ip)"
  if [[ -n "$CLI_SERVER_IP" ]]; then PM_SERVER_IP="$CLI_SERVER_IP"; else PM_SERVER_IP="$(prompt_value '服务器 IP / 节点显示地址' "${PM_SERVER_IP:-$detected_ip}")"; fi
  if [[ -n "$CLI_CONTAINER_NAME" ]]; then PM_CONTAINER_NAME="$CLI_CONTAINER_NAME"; else PM_CONTAINER_NAME="$(prompt_value '容器名称' "${PM_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}")"; fi
  image_default="${PM_IMAGE:-$DEFAULT_IMAGE}"
  if [[ -n "$CLI_IMAGE" ]]; then PM_IMAGE="$CLI_IMAGE"; else PM_IMAGE="$(prompt_value 'sing-box Docker 镜像' "$image_default")"; fi
  if [[ -n "$CLI_TZ" ]]; then PM_TZ="$CLI_TZ"; else PM_TZ="$(prompt_value '时区' "${PM_TZ:-$DEFAULT_TZ}")"; fi

  collect_topology_inputs
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

  if is_enabled "$ENABLE_SS" && [[ "$PM_NODE_ROLE" != "egress_b" ]]; then
    if [[ -n "$CLI_SS_PORT" ]]; then SS_PORT="$CLI_SS_PORT"; else SS_PORT="$(prompt_port 'Shadowsocks 用户入口监听端口' "${SS_PORT:-}")"; fi
    SS_METHOD="$DEFAULT_SS_METHOD"
    if [[ -n "$CLI_SS_PASSWORD" ]]; then SS_PASSWORD="$CLI_SS_PASSWORD"; else SS_PASSWORD="$(prompt_value 'Shadowsocks 用户入口密码，回车自动生成' "${SS_PASSWORD:-$(random_hex)}")"; fi
  elif [[ "$PM_NODE_ROLE" != "egress_b" ]]; then
    SS_PORT=""; SS_PASSWORD=""
  fi

  validate_topology_config
  validate_unique_ports
  CREATED_AT="${CREATED_AT:-$(date '+%F %T')}"
}

render_singbox_config() {
  ensure_dirs
  ensure_jq
  validate_topology_config
  local file tmp
  file="$(CONFIG_FILE)"
  tmp="$(mktemp "$(dirname "$file")/.sing-box.XXXXXX")"
  if ! jq -n \
    --arg role "$PM_NODE_ROLE" \
    --arg enable_anytls "$ENABLE_ANYTLS" \
    --arg enable_naive "$ENABLE_NAIVE" \
    --arg enable_ss "$ENABLE_SS" \
    --arg domain "$PM_DOMAIN" \
    --arg cert "$CERT_FILE" \
    --arg key "$KEY_FILE" \
    --arg anytls_port "${ANYTLS_PORT:-0}" \
    --arg anytls_name "$ANYTLS_NAME" \
    --arg anytls_pass "$ANYTLS_PASSWORD" \
    --arg naive_port "${NAIVE_PORT:-0}" \
    --arg naive_user "$NAIVE_USERNAME" \
    --arg naive_pass "$NAIVE_PASSWORD" \
    --arg ss_port "${SS_PORT:-0}" \
    --arg ss_method "$SS_METHOD" \
    --arg ss_pass "$SS_PASSWORD" \
    --arg b_host "$B_SS_HOST" \
    --arg b_port "${B_SS_PORT:-0}" \
    --arg b_method "$B_SS_METHOD" \
    --arg b_pass "$B_SS_PASSWORD" \
    '
    def anytls_in:
      if $enable_anytls == "1" then
        {type:"anytls", tag:"anytls-in", listen:"0.0.0.0", listen_port:($anytls_port|tonumber), users:[{name:$anytls_name, password:$anytls_pass}], tls:{enabled:true, server_name:$domain, certificate_path:$cert, key_path:$key}}
      else empty end;
    def naive_in:
      if $enable_naive == "1" then
        {type:"naive", tag:"naive-in", listen:"0.0.0.0", listen_port:($naive_port|tonumber), users:[{username:$naive_user, password:$naive_pass}], tls:{enabled:true, server_name:$domain, certificate_path:$cert, key_path:$key}}
      else empty end;
    def ss_user_in:
      if $enable_ss == "1" and $role == "entry_a" then
        {type:"shadowsocks", tag:"ss-in", listen:"0.0.0.0", listen_port:($ss_port|tonumber), method:$ss_method, password:$ss_pass}
      else empty end;
    def ss_landing_in:
      {type:"shadowsocks", tag:"ss-landing-in", listen:"0.0.0.0", listen_port:($b_port|tonumber), method:$b_method, password:$b_pass};
    def direct_out: {type:"direct", tag:"direct"};
    def egress_b_out: {type:"shadowsocks", tag:"egress-b", server:$b_host, server_port:($b_port|tonumber), method:$b_method, password:$b_pass};
    {
      log: {level:"info", timestamp:true},
      inbounds: (if $role == "egress_b" then [ss_landing_in] else [anytls_in, naive_in, ss_user_in] end),
      outbounds: (if $role == "entry_a" then [direct_out, egress_b_out] else [direct_out] end),
      route: (if $role == "entry_a" then {final:"egress-b"} else {final:"direct"} end)
    }
    ' > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$file"
}

append_outbound_sep() {
  local file="$1" first_flag="$2"
  if [[ "$first_flag" -eq 0 ]]; then printf ',\n' >> "$file"; fi
}

render_client_configs() {
  ensure_dirs
  [[ "$PM_NODE_ROLE" == "entry_a" ]] || { rm -f "$(CLIENT_DIR)"/*.json 2>/dev/null || true; return 0; }
  local d any_name any_pass naive_user naive_pass ss_method ss_pass full first tags final_tag i
  rm -f "$(CLIENT_DIR)"/*.json 2>/dev/null || true
  d="$(json_string "$PM_DOMAIN")"
  if is_enabled "$ENABLE_ANYTLS"; then
    any_name="$(json_string "$ANYTLS_NAME")"
    any_pass="$(json_string "$ANYTLS_PASSWORD")"
    cat > "$(CLIENT_DIR)/anytls-outbound.json" <<EOF
{
  "type": "anytls",
  "tag": "anytls-out",
  "server": $d,
  "server_port": ${ANYTLS_PORT},
  "password": $any_pass,
  "tls": {
    "enabled": true,
    "server_name": $d
  }
}
EOF
    : "$any_name"
  fi
  if is_enabled "$ENABLE_NAIVE"; then
    naive_user="$(json_string "$NAIVE_USERNAME")"
    naive_pass="$(json_string "$NAIVE_PASSWORD")"
    cat > "$(CLIENT_DIR)/naive-outbound.json" <<EOF
{
  "type": "naive",
  "tag": "naive-out",
  "server": $d,
  "server_port": ${NAIVE_PORT},
  "username": $naive_user,
  "password": $naive_pass,
  "tls": {
    "enabled": true,
    "server_name": $d
  }
}
EOF
  fi
  if is_enabled "$ENABLE_SS"; then
    ss_method="$(json_string "$SS_METHOD")"
    ss_pass="$(json_string "$SS_PASSWORD")"
    cat > "$(CLIENT_DIR)/shadowsocks-outbound.json" <<EOF
{
  "type": "shadowsocks",
  "tag": "ss-out",
  "server": $d,
  "server_port": ${SS_PORT},
  "method": $ss_method,
  "password": $ss_pass
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
  if [[ -f "$(CLIENT_DIR)/anytls-outbound.json" ]]; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("anytls-out")
    sed 's/^/    /' "$(CLIENT_DIR)/anytls-outbound.json" >> "$full"
  fi
  if [[ -f "$(CLIENT_DIR)/naive-outbound.json" ]]; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("naive-out")
    sed 's/^/    /' "$(CLIENT_DIR)/naive-outbound.json" >> "$full"
  fi
  if [[ -f "$(CLIENT_DIR)/shadowsocks-outbound.json" ]]; then
    append_outbound_sep "$full" "$first"; first=0; tags+=("ss-out")
    sed 's/^/    /' "$(CLIENT_DIR)/shadowsocks-outbound.json" >> "$full"
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
    if [[ "$key_dir" != "$cert_dir" ]]; then printf '      - "%s:%s:ro"\n' "$key_dir" "$key_dir" >> "$compose_file"; fi
  fi
  cat >> "$compose_file" <<EOF
      - "$root/logs:/var/log/proxy-lite"
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
  if is_enabled "$ENABLE_ANYTLS"; then [[ -n "$ANYTLS_PASSWORD" ]] || ANYTLS_PASSWORD="$(random_hex)"; fi
  if is_enabled "$ENABLE_NAIVE"; then
    [[ -n "$NAIVE_USERNAME" ]] || NAIVE_USERNAME="$DEFAULT_NAIVE_USERNAME"
    [[ -n "$NAIVE_PASSWORD" ]] || NAIVE_PASSWORD="$(random_hex)"
  fi
  if is_enabled "$ENABLE_SS"; then
    [[ -n "$SS_METHOD" ]] || SS_METHOD="$DEFAULT_SS_METHOD"
    [[ -n "$SS_PASSWORD" ]] || SS_PASSWORD="$(random_hex)"
  fi
  write_env || return 1
  render_singbox_config || return 1
  render_client_configs || return 1
  render_compose || return 1
  printf 'Proxy Lite installed at %s\n' "$(date '+%F %T')" > "$(RUNTIME_DIR)/installed.flag"
  chmod 600 "$(RUNTIME_DIR)/installed.flag" 2>/dev/null || true
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 || die "未检测到 Docker。当前需求是不自动安装 Docker，请先通过宝塔或系统包安装 Docker。"
  docker info >/dev/null 2>&1 || die "Docker 命令存在，但 Docker daemon 不可用。"
}

compose_available() { docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; }

ensure_compose() {
  if compose_available; then return 0; fi
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
  raw="pl-${PM_CONTAINER_NAME:-proxy-lite}"
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
    if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then warn "服务器 B 的 Shadowsocks 端口建议仅允许服务器 A 的公网 IP 访问。"; fi
  else
    warn "未检测到受支持的本机防火墙或未放行端口；如外网不通，请检查 UFW/安全组/宝塔防火墙。"
  fi
}

singbox_check() {
  ensure_docker
  [[ -s "$(CONFIG_FILE)" ]] || die "缺少 sing-box 配置或配置为空：$(CONFIG_FILE)"
  sync "$(CONFIG_FILE)" >/dev/null 2>&1 || sync >/dev/null 2>&1 || true
  sleep 0.2 2>/dev/null || sleep 1
  local image="${1:-$PM_IMAGE}" config_dir args=()
  config_dir="$(dirname "$(CONFIG_FILE)")"
  args+=(--rm)
  args+=(-v "$config_dir:/etc/sing-box:ro")
  if needs_tls; then
    args+=(-v "$(dirname "$CERT_FILE"):$(dirname "$CERT_FILE"):ro")
    if [[ "$(dirname "$KEY_FILE")" != "$(dirname "$CERT_FILE")" ]]; then
      args+=(-v "$(dirname "$KEY_FILE"):$(dirname "$KEY_FILE"):ro")
    fi
  fi
  log "执行 sing-box 配置检查：$image"
  docker run "${args[@]}" "$image" check -c /etc/sing-box/sing-box.json
}

install_symlinks() {
  require_root
  ensure_dirs
  if [[ "$SCRIPT_PATH" != "$PM_ROOT/bin/proxy-lite.sh" ]]; then cp -f "$SCRIPT_PATH" "$PM_ROOT/bin/proxy-lite.sh"; fi
  chmod +x "$PM_ROOT/bin/proxy-lite.sh"
  ln -sf "$PM_ROOT/bin/proxy-lite.sh" /usr/local/bin/proxy-lite
  if [[ -e /usr/local/bin/PL && ! -L /usr/local/bin/PL ]]; then
    warn "检测到 /usr/local/bin/PL 不是符号链接，未自动覆盖；请确认后手动处理。"
  else
    ln -sf "$PM_ROOT/bin/proxy-lite.sh" /usr/local/bin/PL
  fi
  log "已创建命令：proxy-lite / PL"
}

sha256_file() {
  local file="$1" sum
  if command -v sha256sum >/dev/null 2>&1; then
    IFS=' ' read -r sum _ < <(sha256sum "$file")
  elif command -v shasum >/dev/null 2>&1; then
    IFS=' ' read -r sum _ < <(shasum -a 256 "$file")
  else
    return 1
  fi
  printf '%s\n' "$sum"
}

verify_download_checksum() {
  local url="$1" file="$2" checksum_url checksum_tmp strict expected actual first
  checksum_url="${SCRIPT_CHECKSUM_URL:-${url}.sha256}"
  checksum_tmp="$(mktemp)"
  strict="$(parse_bool01 "${PL_UPDATE_STRICT_CHECK:-0}")"
  if curl -fsSL "$checksum_url" -o "$checksum_tmp"; then
    expected=""
    while IFS=' ' read -r first _; do
      if [[ "$first" =~ ^[A-Fa-f0-9]{64}$ ]]; then expected="$first"; break; fi
    done < "$checksum_tmp"
    rm -f "$checksum_tmp"
    if [[ -z "$expected" ]]; then
      if [[ "$strict" == "1" ]]; then die "校验文件格式无效：$checksum_url"; fi
      warn "校验文件格式无效，已跳过 SHA-256 校验：$checksum_url"
      return 0
    fi
    actual="$(sha256_file "$file")" || die "本机缺少 sha256sum/shasum，无法校验脚本。"
    expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
    [[ "$actual" == "$expected" ]] || die "脚本 SHA-256 校验失败：expected=$expected actual=$actual"
    log "脚本 SHA-256 校验通过。"
  else
    rm -f "$checksum_tmp"
    if [[ "$strict" == "1" ]]; then die "严格校验已开启，但无法下载校验文件：$checksum_url"; fi
    warn "未找到脚本 SHA-256 校验文件，已使用 bash -n 语法校验继续：$checksum_url"
  fi
}

update_script() {
  ensure_dirs
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法从 GitHub 下载脚本。"
  local url tmp
  url="${SCRIPT_DOWNLOAD_URL:-$RELEASE_SCRIPT_URL}"
  tmp="$(mktemp)"
  log "从 GitHub 下载 Proxy Lite 脚本：$url"
  if ! curl -fsSL "$url" -o "$tmp"; then
    warn "Release 下载失败，尝试 main 分支开发版：$RAW_SCRIPT_URL"
    url="$RAW_SCRIPT_URL"
    curl -fsSL "$url" -o "$tmp"
  fi
  bash -n "$tmp"
  verify_download_checksum "$url" "$tmp"
  backup_configs
  cp -f "$tmp" "$PM_ROOT/bin/proxy-lite.sh"
  rm -f "$tmp"
  chmod +x "$PM_ROOT/bin/proxy-lite.sh"
  ln -sf "$PM_ROOT/bin/proxy-lite.sh" /usr/local/bin/proxy-lite
  if [[ -e /usr/local/bin/PL && ! -L /usr/local/bin/PL ]]; then
    warn "检测到 /usr/local/bin/PL 不是符号链接，未自动覆盖。"
  else
    ln -sf "$PM_ROOT/bin/proxy-lite.sh" /usr/local/bin/PL
  fi
  log "脚本已更新。以后可执行：PL 或 proxy-lite"
  log "旧脚本备份目录：$LAST_BACKUP_DIR"
}

pull_image() { load_env_required; ensure_docker; log "拉取 Docker 镜像：$PM_IMAGE"; docker pull "$PM_IMAGE"; }
check_stack() { load_env_required; singbox_check; }
container_running() { command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$PM_CONTAINER_NAME"; }

upgrade_usage() {
  cat <<'EOF'
用法：
  PL upgrade [--image IMAGE]

说明：安全升级 sing-box 运行镜像。流程为备份当前配置、拉取候选镜像、重新渲染配置、用候选镜像执行 sing-box check -c，校验通过后才应用；失败会恢复更新前快照。
EOF
}

rollback_usage() {
  cat <<'EOF'
用法：
  PL rollback [latest|TIMESTAMP]
  PL rollback help

说明：从 backup/<timestamp>/ 恢复 lite.env、sing-box.json 和 docker-compose.yml。默认使用 latest。恢复后会执行 sing-box 配置检查；如果服务正在运行，会重建容器应用回退态。
EOF
}

upgrade_stack() {
  local sub="${POSITIONAL[0]:-}" old_image target_image snapshot was_running=0
  case "$sub" in help|-h|--help) upgrade_usage; return 0 ;; '') ;; *) err "未知 upgrade 参数：$sub"; upgrade_usage; exit 2 ;; esac
  load_env_required
  ensure_jq
  ensure_docker
  ensure_compose
  old_image="$PM_IMAGE"
  target_image="${CLI_IMAGE:-$PM_IMAGE}"
  [[ -n "$target_image" ]] || die "目标镜像不能为空。"
  if container_running; then was_running=1; fi
  backup_configs
  snapshot="$LAST_BACKUP_DIR"
  log "准备安全升级 sing-box 镜像：$old_image -> $target_image"
  if ! docker pull "$target_image"; then restore_snapshot_or_warn "$snapshot"; die "候选镜像拉取失败，已恢复更新前配置。"; fi
  PM_IMAGE="$target_image"
  if ! render_all; then restore_snapshot_or_warn "$snapshot"; die "候选配置渲染失败，已恢复更新前配置。"; fi
  if ! singbox_check "$target_image"; then restore_snapshot_or_warn "$snapshot"; die "候选镜像无法解析当前配置，已恢复更新前配置，未切换运行容器。"; fi
  if [[ "$was_running" -eq 1 ]]; then
    log "配置校验通过，正在重建容器应用候选镜像。"
    if compose_cmd up -d --force-recreate; then
      sleep 2; status_stack; log "安全升级完成。"
    else
      warn "候选镜像重建失败，正在恢复更新前快照：$snapshot"
      restore_snapshot_or_warn "$snapshot"
      if compose_cmd up -d --force-recreate; then sleep 2; status_stack; die "候选镜像重建失败，已恢复并重建回退态。"; fi
      die "候选镜像重建失败，且回退态重建也失败；请检查 Docker/Compose 后执行：PL rollback $(basename "$snapshot")"
    fi
  else
    log "配置校验通过；当前服务未运行，已保存候选配置。需要启动时执行：PL start"
  fi
}

rollback_stack() {
  local target="${POSITIONAL[0]:-latest}" snapshot safety was_running=0
  case "$target" in help|-h|--help) rollback_usage; return 0 ;; esac
  load_env_required
  ensure_docker
  ensure_compose
  if container_running; then was_running=1; fi
  snapshot="$(resolve_backup_dir "$target")"
  backup_configs
  safety="$LAST_BACKUP_DIR"
  restore_backup_files "$snapshot"
  load_env_required
  if ! singbox_check; then
    warn "目标快照无法通过 sing-box 配置检查，正在恢复回退前状态：$safety"
    restore_snapshot_or_warn "$safety"
    if [[ "$was_running" -eq 1 ]]; then compose_cmd up -d --force-recreate || warn "恢复回退前状态后重建容器失败，请手动执行：PL restart"; fi
    die "回退失败：目标快照配置检查未通过。"
  fi
  if [[ "$was_running" -eq 1 ]]; then
    log "配置检查通过，正在重建容器应用回退态。"
    if compose_cmd up -d --force-recreate; then sleep 2; status_stack; log "回退完成。"; else
      warn "回退态重建失败，正在恢复回退前状态：$safety"
      restore_snapshot_or_warn "$safety"
      compose_cmd up -d --force-recreate || warn "恢复回退前状态后重建容器失败，请手动执行：PL restart"
      die "回退失败：容器重建未通过。"
    fi
  else
    log "回退完成；当前服务未运行，需要启动时执行：PL start"
  fi
}

backup_cmd() {
  local sub="${POSITIONAL[0]:-help}"
  case "$sub" in list) list_backups ;; help|-h|--help) backup_usage ;; *) err "未知 backup 参数：$sub"; backup_usage; exit 2 ;; esac
}

install_stack() {
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
  log "安装完成。以后可直接执行：PL 或 proxy-lite"
}

start_stack() { load_env_required; ensure_docker; ensure_compose; compose_cmd up -d; status_stack; }
stop_stack() { load_env_required; ensure_docker; ensure_compose; compose_cmd down; }
restart_stack() { load_env_required; ensure_docker; ensure_compose; compose_cmd up -d --force-recreate; sleep 2; status_stack; }

apply_runtime_if_running() {
  if command -v docker >/dev/null 2>&1 && [[ -f "$(COMPOSE_FILE)" ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$PM_CONTAINER_NAME"; then
    if compose_available; then
      log "检测到服务正在运行，正在重建容器应用新配置。"
      compose_cmd up -d --force-recreate || warn "自动应用配置失败，请手动执行：PL restart"
    else
      warn "配置已生成，但未检测到 Docker Compose，请手动修复后执行：PL restart"
    fi
  else
    warn "配置已生成；如服务正在运行，请执行：PL restart 应用。"
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
  cat <<EOF
Proxy Lite v$VERSION
角色：$(role_label)
域名：$PM_DOMAIN
服务器显示地址：$PM_SERVER_IP
项目目录：$PM_ROOT
容器：$PM_CONTAINER_NAME
镜像：$PM_IMAGE
组件：$(component_summary)
模式：单实例 AB 中转落地；无多用户、无流量限额、无分流规则
AnyTLS：端口 ${ANYTLS_PORT:-未启用}，用户名 ${ANYTLS_NAME:-未启用}，密码 $(mask_secret "$ANYTLS_PASSWORD")
NaiveProxy：端口 ${NAIVE_PORT:-未启用}，用户名 ${NAIVE_USERNAME:-未启用}，密码 $(mask_secret "$NAIVE_PASSWORD")
Shadowsocks：端口 ${SS_PORT:-未启用}，method ${SS_METHOD:-未启用}，密码 $(mask_secret "$SS_PASSWORD")
B 上游/落地 Shadowsocks：${B_SS_HOST:-本机}:${B_SS_PORT:-未设置}，method ${B_SS_METHOD:-未设置}，密码 $(mask_secret "$B_SS_PASSWORD")
客户端配置目录：$(CLIENT_DIR)
EOF
}

check_environment() {
  printf 'Proxy Lite v%s\n' "$VERSION"
  printf '当前用户：%s\n' "$(id -un 2>/dev/null || id -u)"
  if [[ "$(id -u)" -eq 0 ]]; then log "当前为 root 用户。"; else warn "运维命令需要 root 用户执行。"; fi
  if command -v docker >/dev/null 2>&1; then
    log "Docker: $(docker --version)"
  else
    warn "Docker 未安装"
  fi
  if compose_available; then
    log "Docker Compose 可用"
  else
    warn "Docker Compose 未检测到"
  fi
  if command -v jq >/dev/null 2>&1; then
    log "jq: $(jq --version)"
  else
    warn "jq 未安装"
  fi
  if command -v PL >/dev/null 2>&1; then log "PL: $(command -v PL)"; else warn "未检测到 PL 命令映射。"; fi
  if command -v proxy-lite >/dev/null 2>&1; then log "proxy-lite: $(command -v proxy-lite)"; else warn "未检测到 proxy-lite 命令映射。"; fi
}

change_port_usage() {
  cat <<'EOF'
用法：
  PL change-port anytls PORT
  PL change-port naive PORT
  PL change-port ss PORT
  PL change-port b-ss PORT
EOF
}

change_port() {
  load_env_required
  local target="${POSITIONAL[0]:-}" port="${POSITIONAL[1]:-}"
  [[ -n "$target" && -n "$port" ]] || { change_port_usage; exit 2; }
  validate_port_number "$port" || die "端口无效：$port"
  backup_configs
  case "$target" in
    anytls) ANYTLS_PORT="$port" ;;
    naive) NAIVE_PORT="$port" ;;
    ss) SS_PORT="$port"; if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then B_SS_PORT="$port"; fi ;;
    b-ss) B_SS_PORT="$port"; if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then SS_PORT="$port"; fi ;;
    *) err "未知端口目标：$target"; change_port_usage; exit 2 ;;
  esac
  render_all
  apply_runtime_if_running
}

change_secret_usage() {
  cat <<'EOF'
用法：
  PL change-secret anytls [PASSWORD]
  PL change-secret naive [PASSWORD]
  PL change-secret ss [PASSWORD]
  PL change-secret b-ss [PASSWORD]
  PL change-secret all
EOF
}

change_secret() {
  load_env_required
  local target="${POSITIONAL[0]:-}" value="${POSITIONAL[1]:-}"
  [[ -n "$target" ]] || { change_secret_usage; exit 2; }
  backup_configs
  case "$target" in
    anytls) ANYTLS_PASSWORD="${value:-$(random_hex)}" ;;
    naive) NAIVE_PASSWORD="${value:-$(random_hex)}" ;;
    ss) SS_PASSWORD="${value:-$(random_hex)}"; if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then B_SS_PASSWORD="$SS_PASSWORD"; fi ;;
    b-ss) B_SS_PASSWORD="${value:-$(random_hex)}"; if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then SS_PASSWORD="$B_SS_PASSWORD"; fi ;;
    all)
      if is_enabled "$ENABLE_ANYTLS"; then ANYTLS_PASSWORD="$(random_hex)"; fi
      if is_enabled "$ENABLE_NAIVE"; then NAIVE_PASSWORD="$(random_hex)"; fi
      if is_enabled "$ENABLE_SS"; then SS_PASSWORD="$(random_hex)"; fi
      if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then B_SS_PASSWORD="$SS_PASSWORD"; fi
      ;;
    *) err "未知密码目标：$target"; change_secret_usage; exit 2 ;;
  esac
  render_all
  apply_runtime_if_running
}

regen_all() {
  load_env_required
  backup_configs
  if is_enabled "$ENABLE_ANYTLS"; then ANYTLS_PORT="$(random_free_port)"; ANYTLS_PASSWORD="$(random_hex)"; fi
  if is_enabled "$ENABLE_NAIVE"; then NAIVE_PORT="$(random_free_port)"; NAIVE_PASSWORD="$(random_hex)"; fi
  if is_enabled "$ENABLE_SS"; then SS_PORT="$(random_free_port)"; SS_PASSWORD="$(random_hex)"; fi
  if [[ "$PM_NODE_ROLE" == "egress_b" ]]; then B_SS_PORT="$SS_PORT"; B_SS_PASSWORD="$SS_PASSWORD"; fi
  render_all
  apply_runtime_if_running
}

doctor() {
  load_env_required
  printf '== Proxy Lite Doctor ==\n'
  check_environment
  printf '\n== 配置文件 ==\n'
  if [[ -s "$(CONFIG_FILE)" ]]; then
    log "sing-box.json 存在"
  else
    warn "sing-box.json 缺失或为空"
  fi
  if [[ -s "$(COMPOSE_FILE)" ]]; then
    log "docker-compose.yml 存在"
  else
    warn "docker-compose.yml 缺失或为空"
  fi
  printf '\n== 拓扑 ==\n'
  topology_show
  printf '\n== sing-box check ==\n'
  singbox_check
}

topology_show() {
  load_env_required
  cat <<EOF
角色：$(role_label)
A/B 行为：entry_a 固定经 B 的 Shadowsocks 出站；egress_b 固定 direct 落地。
B Shadowsocks：${B_SS_HOST:-本机}:${B_SS_PORT:-未设置}
组件：$(component_summary)
EOF
}

topology_cmd() { topology_show; }

safe_project_root_or_die() {
  [[ -n "$PM_ROOT" && "$PM_ROOT" == /* ]] || die "PM_ROOT 必须是绝对路径：$PM_ROOT"
  case "$PM_ROOT" in /|/root|/home|/usr|/usr/local|/www|/www/wwwroot) die "拒绝操作关键系统目录：$PM_ROOT" ;; esac
  [[ -f "$(RUNTIME_DIR)/installed.flag" || -f "$(CONFIG_FILE)" ]] || die "未发现 proxy-lite 安装痕迹，拒绝卸载：$PM_ROOT"
}

uninstall_stack() {
  load_env_required
  safe_project_root_or_die
  local confirm
  warn "即将停止并卸载 Proxy Lite：$PM_ROOT"
  confirm="$(prompt_value "请输入域名 $PM_DOMAIN 确认卸载" "")"
  [[ "$confirm" == "$PM_DOMAIN" ]] || die "确认失败，已取消卸载。"
  if compose_available && [[ -f "$(COMPOSE_FILE)" ]]; then compose_cmd down || true; fi
  if command -v docker >/dev/null 2>&1; then docker rm -f "$PM_CONTAINER_NAME" >/dev/null 2>&1 || true; fi
  [[ -L /usr/local/bin/proxy-lite ]] && rm -f /usr/local/bin/proxy-lite
  [[ -L /usr/local/bin/PL ]] && rm -f /usr/local/bin/PL
  if prompt_yes_no "是否删除项目目录 $PM_ROOT（输入 DELETE 前建议先备份）" 'N'; then
    rm -rf "$PM_ROOT"
    log "已删除项目目录。"
  else
    log "已停止服务并清理命令映射，项目目录保留：$PM_ROOT"
  fi
}

menu() {
  cat <<'EOF'

Proxy Lite 菜单
1) 安装 / 重新部署
2) 更新脚本
3) 安全升级 sing-box 镜像
4) 启动服务
5) 停止服务
6) 重启服务
7) 状态 / 日志摘要
8) 节点信息
9) 配置检查
10) 诊断
11) 拓扑
12) 备份列表
13) 回退最新备份
14) 修改端口
15) 修改密码
16) 重新生成本机端口和密码
0) 退出
EOF
  local choice
  read -r -p '请选择：' choice || true
  case "$choice" in
    1) install_stack ;;
    2) update_script ;;
    3) upgrade_stack ;;
    4) start_stack ;;
    5) stop_stack ;;
    6) restart_stack ;;
    7) status_stack ;;
    8) show_info ;;
    9) check_stack ;;
    10) doctor ;;
    11) topology_show ;;
    12) POSITIONAL=(list); backup_cmd ;;
    13) POSITIONAL=(latest); rollback_stack ;;
    14) change_port_usage ;;
    15) change_secret_usage ;;
    16) regen_all ;;
    0|"") exit 0 ;;
    *) warn "未知选择：$choice" ;;
  esac
}

removed_feature() {
  err "proxy-lite 已移除该功能：${COMMAND}。请使用完整项目 proxy-manager 的 p-m 命令。"
  exit 2
}

usage() {
  cat <<EOF
Proxy Lite v$VERSION

仓库：$REPO_URL

用法：
  PL [command] [--yes]
  proxy-lite [command] [--yes]

说明：生产运维命令请在 root 用户下执行；Linux 命令大小写敏感，短命令为大写 PL。
不带 command 时进入交互菜单：主菜单回车退出。

命令：
  install          安装 / 重新部署 / 选择 A 或 B 角色
  update           从 GitHub 更新脚本
  upgrade          安全升级 sing-box 镜像（拉取、校验、失败回退）
  pull-image       拉取当前配置中的 Docker 镜像（不切换、不重启）
  backup           查看配置备份，详见 PL backup help
  rollback         回退配置快照，详见 PL rollback help
  env-check        检查本机 Docker、Compose、jq 和命令映射
  start|stop|restart|status|logs
  info             查看节点信息
  doctor           运行诊断
  topology         查看当前拓扑
  change-port      修改端口
  change-secret    修改本机/上游密码
  regen            重新生成本机端口和密码
  check            检查 sing-box 配置
  uninstall        卸载清理
  help             查看帮助

已裁剪功能：user、route、stats、traffic、quota。

角色：
  entry_a          服务器 A：AnyTLS/NaiveProxy 用户入口，固定经 B Shadowsocks 落地
  egress_b         服务器 B：Shadowsocks 落地出口

install 可选参数：
  --yes
  --domain DOMAIN
  --root PATH
  --server-ip IP
  --image IMAGE
  --node-role entry_a|egress_b
  --components anytls|naive|ss|anytls,naive|all
  --cert-file PATH
  --key-file PATH
  --anytls-port PORT
  --naive-port PORT
  --ss-port PORT
  --b-ss-host HOST
  --b-ss-port PORT
  --b-ss-method METHOD
  --b-ss-password PASSWORD

服务器 B 示例：
  PL install --yes --node-role egress_b --domain b.example.com --server-ip 198.51.100.20 --b-ss-port 30003 --b-ss-password '<B_SS_PASSWORD>'

服务器 A 示例：
  PL install --yes --node-role entry_a --domain a.example.com --server-ip 203.0.113.10 --components anytls,naive --cert-file /path/fullchain.pem --key-file /path/privkey.pem --b-ss-host 198.51.100.20 --b-ss-port 30003 --b-ss-password '<B_SS_PASSWORD>'

GitHub 下载安装（root 用户下）：
  curl -fsSL $RELEASE_SCRIPT_URL -o /tmp/proxy-lite.sh
  bash /tmp/proxy-lite.sh install
EOF
}

require_root_for_command

case "$COMMAND" in
  menu) menu ;;
  install) install_stack ;;
  update) update_script ;;
  upgrade) upgrade_stack ;;
  pull-image) pull_image ;;
  backup) backup_cmd ;;
  rollback) rollback_stack ;;
  env-check) check_environment ;;
  start) start_stack ;;
  stop) stop_stack ;;
  restart) restart_stack ;;
  status) status_stack ;;
  logs) logs_stack ;;
  info) show_info ;;
  doctor) doctor ;;
  topology) topology_cmd ;;
  change-port) change_port ;;
  change-secret) change_secret ;;
  regen) regen_all ;;
  check) check_stack ;;
  uninstall) uninstall_stack ;;
  user|route|stats|traffic|quota) removed_feature ;;
  help|-h|--help) usage ;;
  *) err "未知命令：$COMMAND"; usage; exit 2 ;;
esac
