# Proxy Manager

Proxy Manager 是一个基于 `sing-box` 的一键代理管理脚本，面向 Docker host 网络部署。它既保留单机模式，也支持服务器 A / 服务器 B 双节点拓扑：用户连接服务器 A 的 AnyTLS / NaiveProxy，服务器 A 再按规则把 AI、Google 或自定义流量转发到服务器 B 的 Shadowsocks 落地出口。

默认管理命令：

```bash
p-m
# 等同于
proxy-manager
```

> 旧版短命令已统一更名为 `p-m`；后续文档和脚本均以 `p-m` 为准。

## 功能特性

- `standalone` 单机兼容模式：AnyTLS、NaiveProxy、Shadowsocks 按需组合
- `entry_a` 服务器 A 入口/分流模式：用户连接 A，A 按规则走 A 或 B 出口
- `egress_b` 服务器 B 落地模式：提供给 A 使用的 Shadowsocks 出口
- 分流模式：`split`、`all_via_b`、`all_direct`
- 多用户管理：添加、删除、启用、禁用、改密、限额、导出客户端配置
- 每用户独立客户端配置目录：`config/client/<user>/`
- 自动备份关键配置：`manager.env`、`users.json`、`sing-box.json`、`docker-compose.yml`
- 检测 UFW/firewalld 并尝试自动放行已启用组件端口
- V2Ray API stats 能力探测；可用时用于用户流量读取和限额检查，不可用时明确降级
- 支持从 GitHub 直接下载脚本安装，无需本地文件传输步骤

## A/B 拓扑说明

```text
用户客户端
  │ AnyTLS / NaiveProxy
  ▼
服务器 A（entry_a）
  ├─ split: AI / Google / 自定义规则 → Shadowsocks outbound → 服务器 B
  ├─ split: 其他流量 → direct → 服务器 A 出口
  ├─ all_via_b: 全部流量 → 服务器 B 出口
  └─ all_direct: 全部流量 → 服务器 A 出口

服务器 B（egress_b）
  └─ Shadowsocks inbound → direct 出站
```

- 用户只需要连接服务器 A。
- 服务器 B 的 Shadowsocks 凭据是 A 的上游凭据，不会写入用户客户端配置。
- `split` 模式下，AI / Google / 自定义域名命中时，目标网站看到的是 B 的出口 IP；其他流量看到的是 A 的出口 IP。
- 如果希望所有访问都显示 B 的 IP，切换到 `all_via_b`。
- YouTube 默认不归入 Google 走 B，避免大流量视频无感消耗 B 带宽；可通过自定义域名或后续开关加入。

## 环境要求

- Linux 服务器，建议 root 用户执行安装
- 已安装并可用的 Docker
- 可用的 Docker Compose（脚本在缺失时会尝试安装独立二进制）
- `jq`：多用户、JSON 配置和分流管理需要
- 可选 `grpcurl`：V2Ray API stats 用户流量查询需要
- 如启用 AnyTLS 或 NaiveProxy，需要准备域名与 TLS 证书文件

## 快速安装

在目标服务器执行：

```bash
curl -fsSL https://github.com/jiasongji/proxy-manager/releases/latest/download/proxy-manager.sh -o /tmp/proxy-manager.sh
sudo bash /tmp/proxy-manager.sh install
```

测试 main 分支开发版：

```bash
curl -fsSL https://raw.githubusercontent.com/jiasongji/proxy-manager/main/proxy-manager.sh -o /tmp/proxy-manager.sh
sudo bash /tmp/proxy-manager.sh install
```

安装完成后运行：

```bash
p-m
```

## 双节点部署示例

### 1. 服务器 B：Shadowsocks 落地出口

先在 B 上安装 `egress_b`：

```bash
p-m install --yes \
  --node-role egress_b \
  --domain b.example.com \
  --server-ip 198.51.100.20 \
  --b-ss-port 30003 \
  --b-ss-method aes-128-gcm \
  --b-ss-password '<B_SS_PASSWORD>'
```

安全建议：在云安全组、防火墙或面板防火墙中，仅允许服务器 A 的公网 IP 访问 B 的 Shadowsocks 端口。

### 2. 服务器 A：用户入口与分流节点

在 A 上安装 `entry_a`，用户通过 AnyTLS / NaiveProxy 连接 A：

```bash
p-m install --yes \
  --node-role entry_a \
  --domain a.example.com \
  --server-ip 203.0.113.10 \
  --components anytls,naive \
  --cert-file /www/server/panel/vhost/cert/a.example.com/fullchain.pem \
  --key-file /www/server/panel/vhost/cert/a.example.com/privkey.pem \
  --anytls-port 30001 \
  --naive-port 30002 \
  --b-ss-host 198.51.100.20 \
  --b-ss-port 30003 \
  --b-ss-method aes-128-gcm \
  --b-ss-password '<B_SS_PASSWORD>' \
  --route-mode split
```

`split` 是推荐默认模式：AI / Google / 自定义规则走 B，其余走 A。

## 目录结构

默认项目目录会根据部署域名生成：

```text
/www/wwwroot/<domain>/Proxy-Manager/
├── bin/proxy-manager.sh
├── config/manager.env
├── config/users.json
├── config/sing-box.json
├── config/client/<user>/
├── compose/docker-compose.yml
├── logs/
├── backup/
├── runtime/
└── docs/Proxy-Manager-部署运维手册.html
```

## 交互菜单

运行 `p-m` 进入主菜单：

```text
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
```

交互规则：

- 主菜单直接回车：退出
- 主菜单输入 `0`：退出
- 二级菜单直接回车：返回上一页
- 二级菜单输入 `0`：返回上一页
- 修改端口、修改密码等子操作中直接回车：取消当前操作并返回

## 常用命令

```bash
p-m install       # 安装 / 重新部署 / 选择角色与组件
p-m update        # 从 GitHub 更新脚本
p-m pull-image    # 拉取当前配置中的 Docker 镜像
p-m env-check     # 检查 Docker、Compose、jq、grpcurl 和命令映射
p-m start         # 启动服务
p-m stop          # 停止服务
p-m restart       # 重启服务
p-m status        # 查看容器、端口和最近日志
p-m logs          # 查看实时日志
p-m info          # 查看节点与客户端配置路径
p-m check         # 检查 sing-box 配置
p-m doctor        # 运行诊断
p-m topology      # 查看当前拓扑
p-m uninstall     # 卸载清理
```

## 多用户管理

```bash
p-m user list
p-m user add alice --protocols anytls,naive --quota 100GB
p-m user show alice
p-m user disable alice
p-m user enable alice
p-m user passwd alice all
p-m user quota alice unlimited
p-m user reset-usage alice
p-m user export alice
p-m user del alice
```

说明：

- 用户信息存储在 `config/users.json`，脚本会设置为 `600` 权限。
- 每个用户的客户端配置生成到 `config/client/<user>/`。
- `p-m user export <user>` 会输出真实用户客户端密码，请勿公开粘贴。
- 禁用用户后，该用户会从生成的 sing-box inbound `users` 列表中移除。

## 分流管理

```bash
p-m route show
p-m route mode split
p-m route mode all-via-b
p-m route mode all-direct
p-m route add-domain example.net
p-m route del-domain example.net
p-m route add-keyword example-keyword
p-m route del-keyword example-keyword
```

路由模式：

- `split`：AI / Google / 自定义规则走 B，其余走 A
- `all_via_b`：全部流量走 B，用户访问网站显示 B 的出口 IP
- `all_direct`：全部流量走 A，用于 B 故障时回退

初版内置 AI / Google 域名规则，外加自定义域名和关键词；不依赖远程 rule-set，避免外部规则下载失败或供应链风险。

## 流量统计与限额

```bash
p-m stats probe
p-m traffic
p-m traffic alice
p-m quota check
```

注意：

- 用户流量统计优先使用 sing-box `experimental.v2ray_api.stats.users`。
- 该能力依赖镜像包含 V2Ray API / gRPC 支持，并且宿主机有可用的 `grpcurl`。
- `p-m stats probe` 用于探测镜像是否接受 V2Ray API stats 配置。
- stats 或 `grpcurl` 不可用时，`traffic` / `quota` 会降级提示，不影响代理、分流和用户 CRUD。
- stats API 默认监听 `127.0.0.1:10085`，不要暴露到公网。

## Docker 镜像

默认运行镜像：

```text
ghcr.io/sagernet/sing-box:latest
```

该镜像为官方 sing-box 运行时镜像，适合直接用于脚本生成的服务端配置。若后续维护自定义镜像，可通过 `--image` 指定。

安装时可通过 `--image` 指定其他 sing-box 镜像：

```bash
p-m install --yes --domain example.com --image ghcr.io/sagernet/sing-box:latest
```

## 升级

已安装后可执行：

```bash
p-m update
p-m pull-image
p-m restart
```

`p-m update` 会优先从 GitHub Release 下载脚本；如 Release 下载失败，会回退到 main 分支 raw 文件。

从旧单用户版本升级后，首次渲染会把旧 `manager.env` 中的凭据迁移为 `users.json` 中的 `default` 用户。

## 卸载

```bash
p-m uninstall
```

卸载会停止并删除 Proxy Manager 容器，移除 `p-m` 与 `proxy-manager` 命令映射；默认不会删除 Docker、Docker Compose 和证书文件。删除项目目录需要额外输入 `DELETE` 确认。

## 安全说明

- `manager.env` 包含全局配置和 B 上游凭据，权限应为 `600`。
- `users.json` 包含用户凭据、配额和流量统计，权限应为 `600`。
- 用户客户端导出目录包含真实密码，不要放到公开 Web 目录。
- B 的 Shadowsocks 凭据不会进入用户客户端配置。
- 服务器 B 的 Shadowsocks 端口建议只允许服务器 A 的公网 IP 访问。
- stats API 仅监听 `127.0.0.1`，不要暴露公网。
- README、HTML 运维手册和审计记录不得提交真实节点密码、订阅链接、token 或私钥。
- 每次修改端口、密码、分流或重配前会自动备份关键配置到 `backup/`。
- 卸载默认保留 Docker、Docker Compose 和宝塔证书。

## 审计要求

发布前至少完成：

- `bash -n proxy-manager.sh`
- 如可用，执行 `shellcheck proxy-manager.sh`
- CLI smoke：`help`、`user help`、`route help`、`stats help`、`traffic help`、`quota help`
- 菜单烟测：主菜单回车退出、二级菜单回车返回、非法输入不触发危险操作
- 生成配置烟测：`entry_a split`、`entry_a all_via_b`、`egress_b`
- 多用户测试：添加、重复添加拒绝、禁用、启用、改密、导出、删除
- 分流测试：AI / Google / 自定义域名走 B，其余走 A；`all_via_b` 全部走 B；`all_direct` 全部走 A
- 流量限额测试：stats 可用时流量增长和超额禁用；不可用时降级提示
- 脱敏审计：公开文件不包含真实服务器 IP、域名、SSH 端口、私钥路径、节点密码或 B 凭据
- 卸载边界测试：确认不会删除 Docker、Compose、证书，删除项目目录必须输入 `DELETE`

详见 `AUDIT.md`。
