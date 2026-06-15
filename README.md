# Proxy Manager

Proxy Manager 是一个基于 `sing-box` 的一键代理管理脚本，面向 Docker host 网络部署。它既保留单机模式，也支持服务器 A / 服务器 B 双节点拓扑：用户连接服务器 A 的 AnyTLS / NaiveProxy，服务器 A 再按规则把 AI 远程 rule-set、Google 或自定义流量转发到服务器 B 的 Shadowsocks 落地出口。

默认管理命令：

```bash
p-m
# 等同于
proxy-manager
```

> 旧版短命令已统一更名为 `p-m`；后续文档和脚本均以 `p-m` 为准。

## 功能特性

- `standalone` 单机兼容模式：AnyTLS、NaiveProxy、Shadowsocks 按需组合
- `entry_a` 服务器 A 入口/分流模式：用户连接 A，A 按 AI 远程 rule-set、Google 和自定义规则走 A 或 B 出口
- `egress_b` 服务器 B 落地模式：提供给 A 使用的 Shadowsocks 出口
- 分流模式：`split`、`all_via_b`、`all_direct`
- 多用户管理：添加、删除、启用、禁用、改密、限额、导出客户端配置
- 每用户独立客户端配置目录：`config/client/<user>/`
- 自动备份关键配置：`manager.env`、`users.json`、`sing-box.json`、`docker-compose.yml`
- 安全升级 sing-box 镜像：拉取候选镜像、执行配置校验，失败自动回退到更新前快照
- 检测 UFW/firewalld 并尝试自动放行已启用组件端口
- V2Ray API stats 能力探测；可用时用于用户流量读取和限额检查，不可用时明确降级
- 支持从 GitHub 直接下载脚本安装，无需本地文件传输步骤

## A/B 拓扑说明

```text
用户客户端
  │ AnyTLS / NaiveProxy
  ▼
服务器 A（entry_a）
  ├─ split: AI 远程 rule-set / Google / 自定义规则 → Shadowsocks outbound → 服务器 B
  ├─ split: 其他流量 → direct → 服务器 A 出口
  ├─ all_via_b: 全部流量 → 服务器 B 出口
  └─ all_direct: 全部流量 → 服务器 A 出口

服务器 B（egress_b）
  └─ Shadowsocks inbound → direct 出站
```

- 用户只需要连接服务器 A。
- 服务器 B 的 Shadowsocks 凭据是 A 的上游凭据，不会写入用户客户端配置。
- `split` 模式下，AI 远程规则集、Google 或自定义域名/关键词命中时，目标网站看到的是 B 的出口 IP；其他流量看到的是 A 的出口 IP。
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

`split` 是推荐默认模式：AI 远程 rule-set、Google 和自定义规则走 B，其余走 A。

部署后先在两台服务器分别执行 `p-m check`、`p-m doctor`、`p-m status` 和 `p-m topology`；确认 B 是 `egress_b`，A 是 `entry_a`，再按下方“实机验收与复测流程”验证 AnyTLS、NaiveProxy 和出口 IP。

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
p-m update        # 从 GitHub 更新 Proxy Manager 脚本
p-m upgrade       # 安全升级 sing-box 镜像：拉取、校验、失败回退
p-m pull-image    # 仅拉取当前配置中的 Docker 镜像，不切换、不重启
p-m backup list   # 列出可回退配置快照
p-m rollback latest # 回退到最新配置快照
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

- `split`：AI 远程规则集、Google、自定义域名或关键词走 B，其余走 A
- `all_via_b`：全部流量走 B，用户访问网站显示 B 的出口 IP
- `all_direct`：全部流量走 A，用于 B 故障时回退

### AI 远程规则集

`split` 模式下，AI 服务使用 sing-box 新版 `route.rule_set` 远程 `.srs` 规则，不使用旧版 `geosite` / `geoip` 写法。规则来源为 MetaCubeX/meta-rules-dat 的 `sing` 分支：OpenAI 单独匹配、Claude / Anthropic 使用 `anthropic.srs` 单独匹配，其他 AI 服务再由 `category-ai-!cn` 总规则匹配。OpenAI 与 Anthropic 必须放在 AI 总规则前面，避免被大规则提前匹配；不要写成 `claude.srs`。

本项目生成的服务器 B 出站 tag 是 `egress-b`。如果你把下面片段粘贴到自己的 sing-box 配置，且代理出站 tag 叫 `proxy`，请把 `outbound` 的值从 `egress-b` 改成 `proxy`。如果原配置已经有 `route.rule_set` 和 `route.rules`，只把下列三个 rule-set 和三条 rules 追加进去，不要覆盖原有结构，并保持 rules 的先后顺序。

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "openai",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs",
        "update_interval": "1d"
      },
      {
        "tag": "anthropic",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/anthropic.srs",
        "update_interval": "1d"
      },
      {
        "tag": "category-ai-not-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ai-%21cn.srs",
        "update_interval": "1d"
      }
    ],
    "rules": [
      {
        "rule_set": ["openai"],
        "action": "route",
        "outbound": "egress-b"
      },
      {
        "rule_set": ["anthropic"],
        "action": "route",
        "outbound": "egress-b"
      },
      {
        "rule_set": ["category-ai-not-cn"],
        "action": "route",
        "outbound": "egress-b"
      }
    ],
    "final": "direct"
  }
}
```

Google、可选 YouTube、自定义域名和自定义关键词仍使用内联 `domain_suffix` / `domain_keyword` 规则；它们会排在上述 AI rule-set 规则之后。

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

## 实机验收与复测流程

以下步骤用于确认“用户连接服务器 A，但命中规则的流量通过服务器 B 出口”。所有命令中的主机、端口、用户和出口 IP 都使用占位符；不要把真实节点信息写入公开文档或 issue。

### 1. 服务器 B（egress_b）检查

在服务器 B 上确认 Shadowsocks 落地服务正常：

```bash
p-m check
p-m doctor
p-m status
p-m topology
```

预期结果：

- `topology` 显示当前角色为服务器 B / `egress_b`。
- `status` 显示 sing-box 容器运行中，Shadowsocks inbound 正在监听。
- 云安全组、UFW/firewalld 或面板防火墙只允许服务器 A 的公网 IP 访问 B 的 Shadowsocks 端口。

如果要从服务器 A 复测 B 上游连通性，可使用：

```bash
nc -vz -w 5 <SERVER_B_HOST> <B_SS_PORT>
# 或没有 nc 时：
timeout 5 bash -c '</dev/tcp/<SERVER_B_HOST>/<B_SS_PORT>'
```

### 2. 服务器 A（entry_a）检查

在服务器 A 上确认用户入口、分流和用户状态：

```bash
p-m check
p-m doctor
p-m status
p-m topology
p-m route show
p-m user list
p-m stats probe
p-m traffic
p-m quota check
```

预期结果：

- `topology` 显示当前角色为服务器 A / `entry_a`。
- `status` 显示 AnyTLS 与 NaiveProxy 入口正在监听。
- `route show` 显示当前路由模式和自定义走 B 规则。
- `user list` 中测试用户为 enabled，协议包含 `anytls` 和/或 `naive`。
- 如果当前 sing-box 镜像不支持 V2Ray API stats，`stats probe`、`traffic`、`quota check` 应给出明确降级提示，且不影响代理服务。

### 3. AnyTLS / NaiveProxy 出口矩阵

使用测试用户的导出配置连接服务器 A。可通过 `p-m user export <TEST_USER>` 获取客户端配置；该输出包含真实用户凭据，不要公开粘贴。

推荐至少复测以下矩阵：

| 路由模式 | 协议 | 测试目标 | 期望出口 |
| --- | --- | --- | --- |
| `split` | AnyTLS | 普通 IP 检测站 | `<A_EXPECTED_EXIT_IP>` |
| `split` | AnyTLS | AI rule-set / Google / 自定义走 B 目标 | `<B_EXPECTED_EXIT_IP>` |
| `split` | NaiveProxy | 普通 IP 检测站 | `<A_EXPECTED_EXIT_IP>` |
| `split` | NaiveProxy | AI rule-set / Google / 自定义走 B 目标 | `<B_EXPECTED_EXIT_IP>` |
| `all_via_b` | AnyTLS / NaiveProxy | 任意测试目标 | `<B_EXPECTED_EXIT_IP>` |
| `all_direct` | AnyTLS / NaiveProxy | 任意测试目标 | `<A_EXPECTED_EXIT_IP>` |

示例本地观察命令（以客户端本地 HTTP/SOCKS 入口为例）：

```bash
curl --proxy <LOCAL_TEST_PROXY> https://<NORMAL_IP_CHECK_HOST>
curl --proxy <LOCAL_TEST_PROXY> https://<B_ROUTE_TEST_HOST>
```

验收重点：客户端只配置连接服务器 A；B 的 Shadowsocks 地址和密码只存在于 A 的上游配置中，不应出现在用户客户端导出目录。

### 4. 多用户与凭据隔离

```bash
p-m user add <TEST_USER> --protocols anytls,naive --quota 100GB
p-m user list
p-m user show <TEST_USER>
p-m user export <TEST_USER>
p-m user disable <TEST_USER>
p-m user enable <TEST_USER>
p-m user passwd <TEST_USER> all
p-m user quota <TEST_USER> unlimited
p-m user reset-usage <TEST_USER>
```

检查项：

- 重复用户名应被拒绝。
- 禁用用户后，该用户不再进入服务端 inbound users，旧客户端导出目录会被清理。
- 启用、改密、限额、重置流量后，运行中的容器会尝试自动重建配置；如未运行则按提示手动 `p-m restart`。
- 用户客户端导出中不得包含 B 上游 Shadowsocks 密码。

### 5. 发布前复查

公开发布 README、HTML 运维手册或 `AUDIT.md` 前，至少复查：

```bash
git diff --check
bash -n proxy-manager.sh
bash proxy-manager.sh help
bash proxy-manager.sh user help
bash proxy-manager.sh route help
bash proxy-manager.sh stats help
bash proxy-manager.sh traffic help
bash proxy-manager.sh quota help
bash proxy-manager.sh backup help
bash proxy-manager.sh rollback help
bash proxy-manager.sh upgrade help
```

同时检查公开文件中没有真实服务器 IP、真实域名、SSH 端口、测试端口、私钥路径、证书路径、节点密码、B 上游凭据、用户客户端密码、token 或订阅链接。

## Docker 镜像

默认运行镜像：

```text
ghcr.io/sagernet/sing-box:latest
```

该镜像为官方 sing-box 运行时镜像，适合直接用于脚本生成的服务端配置。脚本生成的 AI 分流使用 sing-box 新版 `route.rule_set` 远程 `.srs`，容器运行环境需要能访问对应规则集 URL。由于上游 sing-box 会持续更新，生产环境推荐使用 `p-m upgrade` 完成镜像更新前校验与失败回退；若后续维护自定义镜像，可通过 `--image` 指定。

安装时可通过 `--image` 指定其他 sing-box 镜像：

```bash
p-m install --yes --domain example.com --image ghcr.io/sagernet/sing-box:latest
```

## 升级、校验与失败回退

建议把“管理脚本更新”和“sing-box 运行镜像更新”分开执行：

```bash
# 1. 更新 Proxy Manager 脚本；下载后会先执行 bash -n，若发布了 .sha256 会同时校验
p-m update

# 2. 查看已有可回退快照
p-m backup list

# 3. 安全升级 sing-box 镜像：拉取候选镜像、重新渲染配置、用候选镜像执行 sing-box check -c
p-m upgrade --image ghcr.io/sagernet/sing-box:latest

# 4. 升级后复核
p-m check
p-m status
```

`p-m update` 会优先从 GitHub Release 下载脚本；如 Release 下载失败，会回退到 main 分支 raw 文件。脚本下载后会先写入临时文件并执行 `bash -n`；若同路径存在 `proxy-manager.sh.sha256`，会校验 SHA-256 后再替换本地脚本。当前 release 若没有 checksum 文件，默认会给出警告并继续；如需强制校验，可设置 `PM_UPDATE_STRICT_CHECK=1`。

`p-m pull-image` 只做 `docker pull`，不会重写配置、不会执行 `sing-box check -c`、也不会重建容器；生产环境建议使用 `p-m upgrade`。`p-m upgrade` 会在更新前自动备份 `manager.env`、`users.json`、`sing-box.json` 和 `docker-compose.yml`，候选镜像无法解析当前配置时会恢复更新前快照且不切换运行容器；如果容器重建失败，会恢复快照并尝试重建回退态。

需要手动回退时执行：

```bash
p-m backup list
p-m rollback latest
# 或回退到指定快照
p-m rollback 20260615-120000
```

回退会恢复关键配置并再次执行 `sing-box check -c`；如果服务正在运行，会重建容器应用回退态。

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
- 服务器 B 的 Shadowsocks 端口应只允许服务器 A 的公网 IP 访问，不要长期全网放行。
- stats API 仅监听 `127.0.0.1`，不要暴露公网。
- README、HTML 运维手册和审计记录不得提交真实节点密码、订阅链接、token 或私钥。
- 每次修改端口、密码、分流、升级镜像或重配前会自动备份关键配置到 `backup/`。
- `p-m upgrade` 只在候选镜像通过 `sing-box check -c` 后应用；失败会恢复更新前配置快照。
- 卸载默认保留 Docker、Docker Compose 和宝塔证书。

## 审计要求

发布前至少完成：

- `bash -n proxy-manager.sh`
- 如可用，执行 `shellcheck proxy-manager.sh`
- CLI smoke：`help`、`user help`、`route help`、`stats help`、`traffic help`、`quota help`、`backup help`、`rollback help`、`upgrade help`
- 菜单烟测：主菜单回车退出、二级菜单回车返回、非法输入不触发危险操作
- 生成配置烟测：`entry_a split`、`entry_a all_via_b`、`egress_b`
- 安全升级烟测：`p-m upgrade --image <sing-box-image>` 先校验后应用；候选镜像或配置失败时恢复更新前快照；`p-m rollback latest` 可恢复并通过 `p-m check`
- 多用户测试：添加、重复添加拒绝、禁用、启用、改密、导出、删除
- 分流测试：AI 远程 rule-set、Google、自定义域名或关键词走 B，其余走 A；`all_via_b` 全部走 B；`all_direct` 全部走 A
- 流量限额测试：stats 可用时流量增长和超额禁用；不可用时降级提示
- 脱敏审计：公开文件不包含真实服务器 IP、域名、SSH 端口、私钥路径、节点密码或 B 凭据
- 卸载边界测试：确认不会删除 Docker、Compose、证书，删除项目目录必须输入 `DELETE`

详见 `AUDIT.md`。
