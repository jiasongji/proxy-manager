# Proxy Lite

Proxy Lite 是 `proxy-manager` 的轻量化副本，面向只需要 A/B 中转落地的场景：用户连接服务器 A 的 AnyTLS / NaiveProxy / 可选 Shadowsocks 用户入口，服务器 A 固定通过服务器 B 的 Shadowsocks 出站落地；服务器 B 只提供 Shadowsocks 落地并 direct 出口。

默认命令：

```bash
PL
# 等同于
proxy-lite
```

> `PL` 是大写命令，Linux 命令大小写敏感。生产运维命令请在 root 用户下执行。Proxy Lite 不占用 `p-m`，可与完整项目 `proxy-manager` 共存。

## 发布信息

- GitHub：`https://github.com/jiasongji/proxy-lite`
- Latest Release：`v0.1.0`
- Release assets：`proxy-lite.sh`、`proxy-lite.sh.sha256`
- `v0.1.0` 脚本 SHA-256：`b0d299797188b03ca6dfac5323fe7cee865f08e072db9ac1477aee4880707169`

## 功能范围

保留：

- `entry_a`：服务器 A，AnyTLS / NaiveProxy / 可选 Shadowsocks 用户入口，固定经 B 出口。
- `egress_b`：服务器 B，Shadowsocks 落地入口，direct 出口。
- Docker host network 部署。
- TLS 证书挂载与 `sing-box check -c` 配置校验。
- 安全升级与失败回退：`PL upgrade`、`PL backup list`、`PL rollback latest`。

已裁剪：

- 无多用户：不创建 `config/users.json`，无 `user` 命令。
- 无分流：无 `route` 命令、无 `route.rule_set`、无 AI/Google/custom 规则。
- 无流量限制：无 `stats`、`traffic`、`quota` 命令。

## 快速安装

在目标服务器 root 用户下执行：

```bash
curl -fsSL https://github.com/jiasongji/proxy-lite/releases/latest/download/proxy-lite.sh -o /tmp/proxy-lite.sh
bash /tmp/proxy-lite.sh install
```

测试 main 分支开发版：

```bash
curl -fsSL https://raw.githubusercontent.com/jiasongji/proxy-lite/main/proxy-lite.sh -o /tmp/proxy-lite.sh
bash /tmp/proxy-lite.sh install
```

> 独立 GitHub 仓库已发布：`https://github.com/jiasongji/proxy-lite`。当前仓库内仍保留本地副本路径 `proxy-lite/proxy-lite.sh`，用于与完整项目一起做双项目 CI 和本地维护。

## A/B 部署示例

### 1. 服务器 B：Shadowsocks 落地

```bash
PL install --yes \
  --node-role egress_b \
  --domain b.example.com \
  --server-ip 198.51.100.20 \
  --b-ss-port 30003 \
  --b-ss-method aes-128-gcm \
  --b-ss-password '<B_SS_PASSWORD>'
```

建议在服务器 B 的云安全组、UFW/firewalld 或面板防火墙中，仅允许服务器 A 的公网 IP 访问 B 的 Shadowsocks 端口。

### 2. 服务器 A：用户入口，固定经 B 出口

```bash
PL install --yes \
  --node-role entry_a \
  --domain a.example.com \
  --server-ip 203.0.113.10 \
  --components anytls,naive \
  --cert-file /path/fullchain.pem \
  --key-file /path/privkey.pem \
  --anytls-port 30001 \
  --naive-port 30002 \
  --b-ss-host 198.51.100.20 \
  --b-ss-port 30003 \
  --b-ss-method aes-128-gcm \
  --b-ss-password '<B_SS_PASSWORD>'
```

`entry_a` 不做 split 分流，生成配置的 `route.final` 固定为 `egress-b`。B 的 Shadowsocks 凭据只写入 A 的上游配置，不写入用户客户端导出。

## 目录结构

```text
/www/wwwroot/<domain>/Proxy-Lite/
├── bin/proxy-lite.sh
├── config/lite.env
├── config/sing-box.json
├── config/client/
├── compose/docker-compose.yml
├── logs/
├── backup/
├── runtime/
└── docs/Proxy-Lite-部署运维手册.html
```

客户端配置生成到 `config/client/`：

- `anytls-outbound.json`
- `naive-outbound.json`
- `shadowsocks-outbound.json`（仅服务器 A 启用 Shadowsocks 用户入口时）
- `full-test-client.json`

## 常用命令

```bash
PL install          # 安装 / 重新部署 / 选择 A 或 B 角色
PL update           # 从 GitHub 更新 Proxy Lite 脚本
PL upgrade          # 安全升级 sing-box 镜像：拉取、校验、失败回退
PL pull-image       # 仅拉取当前配置中的 Docker 镜像
PL backup list      # 列出可回退配置快照
PL rollback latest  # 回退到最新配置快照
PL env-check        # 检查 Docker、Compose、jq 和命令映射
PL start            # 启动服务
PL stop             # 停止服务
PL restart          # 重启服务
PL status           # 查看容器、端口和最近日志
PL logs             # 查看实时日志
PL info             # 查看节点与客户端配置路径
PL check            # 检查 sing-box 配置
PL doctor           # 运行诊断
PL topology         # 查看当前拓扑
PL uninstall        # 卸载清理
```

## 安全升级与回退

```bash
PL update
PL backup list
PL upgrade --image ghcr.io/sagernet/sing-box:latest
PL check
PL status
```

`PL upgrade` 会先备份当前配置，拉取候选镜像，重新渲染配置，并使用候选镜像执行真实 `sing-box check -c`。校验通过才会应用；候选镜像拉取、配置渲染或配置检查失败时，会恢复更新前快照。

手动回退：

```bash
PL backup list
PL rollback latest
PL rollback 20260615-120000
```

## 审计要求

发布前至少完成：

- `bash -n proxy-lite/proxy-lite.sh`
- 如可用，执行 `shellcheck proxy-lite/proxy-lite.sh`
- CLI smoke：`help`、`backup help`、`rollback help`、`upgrade help`
- 生成配置 smoke：`entry_a`、`egress_b`
- Docker `sing-box check -c` 真实检查
- 安全升级 smoke：有效镜像通过、无效镜像失败并恢复快照
- 脱敏审计：公开文件不包含真实服务器 IP、域名、SSH 端口、节点密码、B 上游凭据、token、私钥、证书/key 路径或订阅链接

详见 `AUDIT.md`。
