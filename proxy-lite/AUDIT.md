# Proxy Lite Audit

审计日期：2026-06-15

审计范围：轻量 A/B 中转落地、AnyTLS、NaiveProxy、Shadowsocks、安全升级与失败回退、脚本交互、CI、公开文档脱敏。

> 公开仓库不得包含真实服务器 IP、真实域名、登录端口、节点密码、B 上游凭据、订阅链接、token、证书/key 文件或本地凭据文件。

发布状态：独立 GitHub 仓库 `https://github.com/jiasongji/proxy-lite` 已创建，`v0.1.0` Release 已发布，assets 为 `proxy-lite.sh` 与 `proxy-lite.sh.sha256`；脚本 SHA-256 为 `b0d299797188b03ca6dfac5323fe7cee865f08e072db9ac1477aee4880707169`。

## 1. 功能范围

- [x] 新建轻量项目副本：`proxy-lite/`。
- [x] 新增脚本：`proxy-lite/proxy-lite.sh`。
- [x] 新增命令映射设计：`PL` 与 `proxy-lite`，不占用完整项目的 `p-m`。
- [x] 保留 `entry_a` 与 `egress_b` A/B 拓扑。
- [x] 保留 AnyTLS、NaiveProxy、Shadowsocks 服务。
- [x] `entry_a` 固定经 `egress-b` Shadowsocks 出站，不提供 split 分流。
- [x] `egress_b` 只提供 Shadowsocks landing inbound 与 direct outbound。
- [x] 保留 `backup list`、`rollback`、`upgrade` 安全升级/回退能力。

## 2. 已裁剪功能

- [x] 无多用户数据库：不创建 `config/users.json`。
- [x] 无 `user` 命令。
- [x] 无分流：无 `route` 命令、无 `route.rule_set`、无 AI/Google/custom 规则。
- [x] 无流量与限额：无 `stats`、`traffic`、`quota` 命令。
- [x] 无 V2Ray API stats / grpcurl / quota cron 依赖。

## 3. 静态检查

计划/本地检查项：

```bash
bash -n proxy-lite/proxy-lite.sh
bash proxy-lite/proxy-lite.sh help
bash proxy-lite/proxy-lite.sh backup help
bash proxy-lite/proxy-lite.sh rollback help
bash proxy-lite/proxy-lite.sh upgrade help
```

如本机可用，执行：

```bash
shellcheck proxy-lite/proxy-lite.sh
```

## 4. 生成配置烟测

临时目录 smoke 应覆盖：

- [x] `entry_a` 可生成 AnyTLS 与 NaiveProxy inbound。
- [x] `entry_a` 可生成 `egress-b` Shadowsocks outbound。
- [x] `entry_a` 的 `route.final` 为 `egress-b`。
- [x] `entry_a` 不生成 `route.rule_set`。
- [x] `egress_b` 可生成 `ss-landing-in` Shadowsocks inbound。
- [x] `egress_b` 的 `route.final` 为 `direct`。
- [x] 不生成 `config/users.json`。
- [x] 客户端导出目录不包含 B 上游 Shadowsocks 密码。
- [x] 使用上游 `ghcr.io/sagernet/sing-box:latest` 执行真实 `check -c`。

关键断言示例：

```bash
jq -e '.outbounds[] | select(.tag=="egress-b")' "$tmp/config/sing-box.json"
jq -e '.route.final == "egress-b" and (.route.rule_set == null)' "$tmp/config/sing-box.json"
jq -e '.inbounds[] | select(.tag=="ss-landing-in")' "$tmp/config/sing-box.json"
! test -e "$tmp/config/users.json"
! grep -R "<B_SS_PASSWORD>" "$tmp/config/client"
```

## 5. 安全升级与回退

- [x] `PL upgrade --image ghcr.io/sagernet/sing-box:latest` 应拉取候选镜像、重新渲染配置并执行真实 `sing-box check -c`。
- [x] 候选镜像无法拉取时应返回非零并恢复更新前配置。
- [x] `PL backup list` 应列出包含 `lite.env`、`sing-box.json`、`docker-compose.yml` 和脚本副本的快照。
- [x] `PL rollback latest|TIMESTAMP` 应恢复配置并通过 `sing-box check -c`。

## 6. 已知限制

- Proxy Lite 是轻量副本，不提供多用户隔离、按用户导出、流量统计、限额或 split 分流。
- `entry_a` 固定经 B 出口；如需要 AI/Google/custom 分流、`all_direct` 或 `all_via_b` 切换，请使用完整项目 `proxy-manager`。
- `PL upgrade` 依赖服务器能拉取目标 Docker 镜像；镜像仓库不可达时只能恢复配置，不能解决网络可达性问题。
- 回退快照覆盖关键运行配置，不替代完整系统级备份；证书文件、Docker daemon、云防火墙和外部镜像仓库仍需单独维护。

## 7. 安全结论

- 公开文档仅使用占位主机、端口和密码。
- B 上游 Shadowsocks 凭据只保存在 A 的 `lite.env` 与服务端配置中，不写入用户客户端导出。
- `PL` 与 `proxy-lite` 不占用完整项目的 `p-m` / `proxy-manager` 命令。
- 生产运维命令要求 root 用户执行，避免权限不一致导致部署或回退失败。
