# Proxy Manager

Proxy Manager 是一个基于 `sing-box` 的一键代理管理脚本，面向 Docker host 网络部署，支持按需启用：

- AnyTLS inbound
- NaiveProxy inbound
- Shadowsocks inbound 落地服务
- 全部组件或自定义组合

默认管理命令：

```bash
p-m
# 等同于
proxy-manager
```

> 旧版短命令已统一更名为 `p-m`；后续文档和脚本均以 `p-m` 为准。

## 功能特性

- 首次安装 / 重新部署 / 选择组件
- 二级交互菜单：主菜单回车退出，二级菜单回车返回上一页
- 启动、停止、重启服务
- 查看状态、日志、节点信息
- 修改端口、修改或重新生成密码
- 重新生成已启用组件配置
- 自动备份关键配置
- 检测 UFW/firewalld 并尝试自动放行已启用组件端口
- 生成 sing-box 客户端 outbound 与完整测试客户端配置
- 支持从 GitHub 直接下载脚本安装，无需本地文件传输步骤

## 环境要求

- Linux 服务器，建议 root 用户执行安装
- 已安装并可用的 Docker
- 可用的 Docker Compose（脚本在缺失时会尝试安装独立二进制）
- 如启用 AnyTLS 或 NaiveProxy，需要准备域名与 TLS 证书文件

## 快速安装

在目标服务器执行以下命令即可从 GitHub 下载并安装：

```bash
curl -fsSL https://github.com/jiasongji/proxy-manager/releases/latest/download/proxy-manager.sh -o /tmp/proxy-manager.sh
sudo bash /tmp/proxy-manager.sh install
```

如果尚未创建 Release，或需要测试 main 分支开发版，可使用：

```bash
curl -fsSL https://raw.githubusercontent.com/jiasongji/proxy-manager/main/proxy-manager.sh -o /tmp/proxy-manager.sh
sudo bash /tmp/proxy-manager.sh install
```

安装完成后运行：

```bash
p-m
```

## 目录结构

默认项目目录会根据部署域名生成：

```text
/www/wwwroot/<domain>/Proxy-Manager/
├── bin/proxy-manager.sh
├── config/manager.env
├── config/sing-box.json
├── config/client/
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
3) 配置管理
4) 状态 / 日志
5) 节点信息
6) 审计 / 自检
7) 卸载清理
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
p-m install       # 安装 / 重新部署 / 选择组件
p-m update        # 从 GitHub 更新脚本
p-m pull-image    # 拉取当前配置中的 Docker 镜像
p-m env-check     # 检查 Docker、Compose 和命令映射
p-m start         # 启动服务
p-m stop          # 停止服务
p-m restart       # 重启服务
p-m status        # 查看容器、端口和最近日志
p-m logs          # 查看实时日志
p-m info          # 查看节点信息和客户端配置路径
p-m check         # 检查 sing-box 配置
p-m change-port   # 修改端口
p-m change-secret # 修改 / 重新生成密码
p-m regen         # 重新生成已启用组件的端口和密码
p-m uninstall     # 卸载清理
```

## 组件模式

安装过程中可选择：

```text
1) 全部安装：AnyTLS + NaiveProxy + Shadowsocks 落地
2) 仅安装 AnyTLS 入口
3) 仅安装 NaiveProxy 入口
4) 仅安装 Shadowsocks 落地服务
5) 自定义组合
```

也支持带参数一键配置，适合批量部署：

```bash
p-m install --yes \
  --domain example.com \
  --server-ip 203.0.113.10 \
  --components anytls,ss \
  --cert-file /www/server/panel/vhost/cert/example.com/fullchain.pem \
  --key-file /www/server/panel/vhost/cert/example.com/privkey.pem \
  --anytls-port 30001 \
  --ss-port 30003 \
  --anytls-password '<ANYTLS_PASSWORD>' \
  --ss-password '<SS_PASSWORD>'
```

`--components` 支持 `all`、`anytls`、`naive`、`ss` 或逗号组合，例如 `anytls,ss`。未指定的端口和密码会按脚本规则随机生成。

## Docker 镜像

默认发布镜像：

```text
jiasongji/proxy-manager-sing-box:latest
```

本地构建与推送示例：

```bash
docker build -t jiasongji/proxy-manager-sing-box:latest .
docker push jiasongji/proxy-manager-sing-box:latest
```

安装时可通过 `--image` 指定其他 sing-box 镜像：

```bash
p-m install --yes --domain example.com --image jiasongji/proxy-manager-sing-box:latest
```

## 升级

已安装后可执行：

```bash
p-m update
p-m pull-image
p-m restart
```

`p-m update` 会优先从 GitHub Release 下载脚本；如 Release 下载失败，会回退到 main 分支 raw 文件。

## 卸载

```bash
p-m uninstall
```

卸载会停止并删除 Proxy Manager 容器，移除 `p-m` 与 `proxy-manager` 命令映射；默认不会删除 Docker、Docker Compose 和证书文件。删除项目目录需要额外输入 `DELETE` 确认。

## 安全说明

- `manager.env` 包含真实端口和密码，脚本会设置为 `600` 权限。
- README、HTML 运维手册和审计记录不得提交真实节点密码、订阅链接、token 或私钥。
- 私钥、证书、env、日志、运行时目录和备份目录已通过 `.gitignore` 排除。
- 每次修改端口、密码、重配前会自动备份关键配置到 `backup/`。
- 卸载默认保留 Docker、Docker Compose 和宝塔证书。

## 审计要求

发布前至少完成：

- `bash -n proxy-manager.sh`
- 如可用，执行 `shellcheck proxy-manager.sh`
- 旧命令与占位审计：确认公开文档不再出现旧短命令或未替换发布占位
- 脱敏审计：确认公开文件不包含真实服务器 IP、域名、SSH 端口、私钥路径或节点密码
- 菜单烟测：主菜单回车退出、二级菜单回车返回、非法输入不触发危险操作
- Docker 构建：`docker build -t jiasongji/proxy-manager-sing-box:latest .`
- 组件矩阵测试：仅 AnyTLS、仅 NaiveProxy、仅 Shadowsocks、全部、自定义组合
- 错误输入测试：重复端口、占用端口、错误证书路径、空密码
- 卸载边界测试：确认不会删除 Docker、Compose、证书，删除项目目录必须输入 `DELETE`

详见 `AUDIT.md`。
