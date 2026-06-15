# Proxy Manager Audit

审计日期：2026-06-15
审计范围：A/B Shadowsocks 落地分流、多用户管理、流量/限额降级策略、安全升级与失败回退、脚本交互、CI、公开文档脱敏。

> 公开仓库不得包含真实服务器 IP、真实域名、登录端口、节点密码、B 上游凭据、订阅链接、token、证书/key 文件或本地凭据文件。

## 1. 本轮整改目标

- [x] 新增节点角色：`standalone`、`entry_a`、`egress_b`。
- [x] 明确服务器 A / 服务器 B 拓扑：用户连接 A，A 可通过 B 的 Shadowsocks 出站。
- [x] 新增路由模式：`split`、`all_via_b`、`all_direct`。
- [x] `split` 模式支持 AI 远程 `.srs` rule-set、Google、自定义域名或关键词走 B，其余流量走 A。
- [x] B 的 Shadowsocks 凭据只作为 A 的上游配置，不进入用户客户端导出。
- [x] 新增 `config/users.json` 多用户数据库。
- [x] 新增用户管理命令：list/add/show/enable/disable/del/passwd/quota/reset-usage/export。
- [x] 客户端配置按用户导出到 `config/client/<user>/`。
- [x] 新增 `stats probe`、`traffic`、`quota check` 与不可用时的降级提示。
- [x] 新增 `doctor` 与 `topology` 诊断/拓扑入口。
- [x] 更新 README 与 HTML 运维手册。
- [x] 扩展 GitHub Actions smoke test。
- [x] 新增安全升级路径：`p-m upgrade` 拉取候选 sing-box 镜像、执行配置校验，失败自动恢复更新前快照。
- [x] 新增配置快照可视化与回退命令：`p-m backup list`、`p-m rollback latest|TIMESTAMP`。

## 2. 静态检查

本地检查结果：

- [x] `bash -n proxy-manager.sh` 通过。
- [x] `shellcheck proxy-manager.sh`：本机通过 Docker `koalaman/shellcheck:stable` 执行通过；GitHub Actions 历史 run `27535910193` 的 ShellCheck 已通过。
- [x] CLI help smoke 通过：
  - `bash proxy-manager.sh help`
  - `bash proxy-manager.sh user help`
  - `bash proxy-manager.sh route help`
  - `bash proxy-manager.sh stats help`
  - `bash proxy-manager.sh traffic help`
  - `bash proxy-manager.sh quota help`
  - `bash proxy-manager.sh backup help`
  - `bash proxy-manager.sh rollback help`
  - `bash proxy-manager.sh upgrade help`
- [x] 公开文档中无 GitHub/Docker 未替换占位。
- [x] README、HTML、Dockerfile、AUDIT 未命中私钥、GitHub token、AWS key、测试用 B 密码、旧本地凭据文件名。
- [x] README/HTML 未展示本地连接、脚本上传、SSH 私钥操作等步骤。

## 3. 菜单烟测

本地输入流烟测结果：

- [x] 主菜单直接回车退出：`printf '\n' | bash proxy-manager.sh menu` 通过。
- [x] 主菜单输入 `0` 退出：`printf '0\n' | bash proxy-manager.sh menu` 通过。
- [x] 进入用户管理二级菜单后直接回车返回上一页：`printf '3\n\n\n' | bash proxy-manager.sh menu` 通过。
- [x] 进入分流管理二级菜单后输入 `0` 返回上一页：`printf '4\n0\n0\n' | bash proxy-manager.sh menu` 通过。
- [x] 非法输入不会触发安装、卸载、重启等危险操作：`printf 'x\n\n' | bash proxy-manager.sh menu` 通过。

## 4. 生成配置烟测

本地使用临时目录验证，不启动真实服务、不修改生产路径：

- [x] `entry_a + split` 可生成 `egress-b` Shadowsocks outbound。
- [x] `entry_a + split` 可生成 OpenAI、Anthropic、AI 总规则三个远程 `.srs` `route.rule_set`，且规则顺序为 OpenAI → Anthropic → AI 总规则。
- [x] `entry_a + split` 可保留 Google/custom 内联 route rules。
- [x] 生成配置可用上游 `ghcr.io/sagernet/sing-box:latest` 执行真实 `check -c`。
- [x] 临时目录可执行 `backup list`、`rollback latest` 和 `upgrade --image ghcr.io/sagernet/sing-box:latest` smoke；候选镜像拉取失败时恢复更新前 `manager.env`。
- [x] 旧单用户 env 可迁移为 `users.json` 中的 `default` 用户。
- [x] AnyTLS inbound 可从 `users.json` 渲染用户列表。
- [x] 用户客户端导出目录不包含 B 的 Shadowsocks 密码。
- [x] `egress_b` 可生成 `ss-landing-in` Shadowsocks inbound 与 `direct` outbound。

已执行的关键断言：

```bash
jq -e '.outbounds[] | select(.tag=="egress-b")' "$tmp/config/sing-box.json"
jq -e '.route.rule_set | length == 3' "$tmp/config/sing-box.json"
jq -e '.route.rules[0].rule_set == ["openai"] and .route.rules[1].rule_set == ["anthropic"] and .route.rules[2].rule_set == ["category-ai-not-cn"]' "$tmp/config/sing-box.json"
jq -e '[.route.rule_set[] | select(.type=="remote" and .format=="binary" and .update_interval=="1d")] | length == 3' "$tmp/config/sing-box.json"
jq -e '[.route.rules[]? | select((.domain_suffix // []) | index("example.net"))] | length == 1' "$tmp/config/sing-box.json"
! grep -R "claude.srs" "$tmp/config/sing-box.json"
jq -e '.inbounds[] | select(.tag=="anytls-in") | .users[0].name == "default"' "$tmp/config/sing-box.json"
! grep -R "<B_TEST_SECRET>" "$tmp/config/client"
PM_ROOT="$tmp" bash proxy-manager.sh check
PM_ROOT="$tmp" bash proxy-manager.sh backup list
PM_ROOT="$tmp" bash proxy-manager.sh rollback latest
PM_ROOT="$tmp" bash proxy-manager.sh upgrade --image ghcr.io/sagernet/sing-box:latest
```

安全升级失败路径补充断言：候选镜像拉取失败时，`p-m upgrade` 返回非零并恢复更新前 `manager.env`，不会切换运行容器。

## 5. 新增功能验收清单

服务器端实机验证结果：

### 5.1 服务器 B

- [x] `p-m install --yes --node-role egress_b ...` 成功。
- [x] `p-m check` 通过。
- [x] B 的 Shadowsocks 端口可由 A 访问。
- [x] B 的安全组/防火墙仅允许 A 的公网 IP 访问该端口；已复核 A 仍可连接 B，上游服务正常。

### 5.2 服务器 A

- [x] `p-m install --yes --node-role entry_a ... --route-mode split` 成功。
- [x] 用户通过 AnyTLS 连接 A 成功。
- [x] 用户通过 NaiveProxy 连接 A 成功。
- [x] `split` 模式下普通流量显示 A 出口 IP。
- [x] `split` 模式下 AI 远程 rule-set、Google 或自定义命中流量显示 B 出口 IP，或在 B 日志可观察到。
- [x] `all_via_b` 模式下全部流量显示 B 出口 IP。
- [x] `all_direct` 模式下全部流量回到 A 出口 IP。

### 5.3 多用户

- [x] `p-m user add alice --protocols anytls,naive --quota 100GB` 成功。
- [x] 重复用户名被拒绝。
- [x] `p-m user disable alice` 后配置中不再包含该用户。
- [x] `p-m user enable alice` 后恢复。
- [x] `p-m user passwd alice all` 后旧凭据失效，新导出可用。
- [x] `p-m user export alice` 输出客户端配置，且不包含 B 上游密码。
- [x] 用户生命周期与客户端目录清理已验证；当前测试节点保留 `default` 与 `alice` 作为后续复测用户。

### 5.4 流量与限额

- [x] `p-m stats probe` 能准确报告镜像是否支持 V2Ray API stats。
- [x] 当前上游镜像不包含 `with_v2ray_api` 时，`p-m traffic <user>` 不进入真实读取路径并给出降级提示。
- [x] 当前上游镜像不包含 `with_v2ray_api` 时，`p-m quota check` 不执行超额禁用并给出降级提示。
- [x] stats 或 `grpcurl` 不可用时，`traffic` / `quota` 不破坏代理服务；支持 stats 的镜像需另行复测真实流量增长与超额禁用。

## 6. CI 更新

`.github/workflows/ci.yml` 已扩展：

- [x] 安装 `shellcheck jq`。
- [x] 保留 Bash syntax。
- [x] 保留 ShellCheck。
- [x] 保留公开文档审计。
- [x] 新增 CLI help smoke tests，覆盖 `backup`、`rollback`、`upgrade` 新命令帮助。
- [x] 更新菜单 smoke tests，覆盖新菜单编号。
- [x] 新增临时目录 generated config smoke tests，验证 `entry_a split`、AI 远程 `.srs` `route.rule_set`、规则顺序、自定义域名/关键词保留、无 `claude.srs` 与 B 密码不进入客户端导出。
- [x] 新增上游 sing-box 真实 `check -c`、`backup list`、`rollback latest`、`upgrade --image` 与候选镜像失败回退 smoke。

## 7. 实机 A/B 验收结果

> 以下只记录脱敏结论；真实服务器 IP、域名、端口和密钥不写入公开审计文件。

- [x] GitHub Release `v0.4.2` 已创建，`latest/download/proxy-manager.sh` 下载后 `VERSION="0.4.2"` 且 `bash -n` 通过。
- [x] `v0.4.2` Release asset SHA-256：`8f643c0171a335fd74a274e59afe37b00710fdb1848c0999b598756b22fba180`。
- [x] main 分支 CI 已通过：Bash syntax、ShellCheck、公开文档审计、CLI smoke、菜单 smoke、生成配置 smoke；v0.4.2 最新通过 run ID：`27529979679`。
- [x] 本轮 `VERSION="0.4.3"` 将 AI 分流生成迁移到 sing-box `route.rule_set` 远程 `.srs`；本地生成配置 smoke 与 Docker `sing-box check` 已覆盖 OpenAI、Anthropic、AI 总规则顺序和自定义规则保留。
- [x] 本轮 `VERSION="0.4.4"` 新增安全升级与回退：`p-m upgrade` 使用候选 sing-box 镜像执行 `check -c` 后再应用，`p-m rollback` 可恢复配置快照，`p-m backup list` 可查看快照。
- [x] `v0.4.4` Release 已附带 `proxy-manager.sh.sha256`，`p-m update` 可在下载脚本后进行 SHA-256 校验。
- [x] 测试服务器 B 已以 `egress_b` 模式部署 Shadowsocks landing，安装脚本 `VERSION="0.4.2"`，`p-m check` / `p-m doctor` 通过，容器与 TCP/UDP 监听正常。
- [x] 测试服务器 B 的 SS 测试端口来源限制已收敛为仅允许 A 来源 IP；复核未发现 `Anywhere` / `Anywhere (v6)` 全网放行规则，且 A 到 B 上游仍可达。
- [x] 测试服务器 A 已以 `entry_a` 模式部署 AnyTLS + NaiveProxy，安装脚本 `VERSION="0.4.2"`，`p-m check` / `p-m doctor` 通过，容器与监听正常。
- [x] A 可连接 B 的 SS 测试端口；A 当前 `route show` 为 `split`，自定义走 B 域名包含 `ifconfig.me`、`ipinfo.io`。
- [x] AnyTLS 客户端经 A 访问普通 IP 检测站显示 A 出口；访问自定义走 B 域名显示 B 出口。
- [x] NaiveProxy 客户端经 A 访问普通 IP 检测站显示 A 出口；访问自定义走 B 域名显示 B 出口。
- [x] `all_via_b` 模式验证：AnyTLS / NaiveProxy 访问普通 IP 检测站均显示 B 出口。
- [x] `all_direct` 模式验证：AnyTLS / NaiveProxy 访问自定义走 B 域名均回到 A 出口。
- [x] 路由矩阵复测后已恢复 `split` 模式，A/B `p-m check` 与 `p-m doctor` 仍通过。
- [x] 多用户生命周期验证通过：添加、重复添加拒绝、禁用、启用、改密、设置/取消限额、重置流量。
- [x] 禁用用户后，旧客户端导出文件被清理。
- [x] `doctor` 在 A/B 测试节点均完成且未发现阻塞项。
- [x] 当前上游 sing-box 镜像不包含 V2Ray API stats 编译能力，`stats probe` 按预期失败并进入 traffic/quota 降级路径。
- [x] `traffic` 在 stats 不可用时输出用户列表和降级提示。
- [x] `quota check` 在 stats 不可用时输出降级提示，不破坏运行中代理服务。
- [x] 发现并修复 Docker Compose project 名称冲突：`v0.4.1` 按容器名隔离 compose project，避免多个部署目录都叫 `compose` 时互相影响。

## 8. 安全结论

- 静态语法检查：通过。
- 菜单烟测：通过。
- 公开文档脱敏：通过。
- 本地临时配置生成：通过。
- B 上游密码隔离：本地临时配置检查通过。
- AI 远程 rule-set：本地临时配置检查覆盖 OpenAI、Anthropic、`category-ai-!cn` 三个远程 `.srs`、规则顺序、无 `claude.srs`。
- 安全升级与回退：临时目录检查覆盖 `p-m upgrade` 候选镜像校验、`p-m rollback latest` 配置恢复、候选镜像拉取失败时恢复更新前快照。
- ShellCheck：本地 Docker `koalaman/shellcheck:stable` 已通过；GitHub Actions 历史 run `27535910193` 已通过。
- Docker / sing-box 实际 `check -c`：本地临时配置已用 `ghcr.io/sagernet/sing-box:latest` 通过；A/B 测试服务器历史 `p-m check` 已通过。
- A/B 实机连通与出口 IP 验证：测试服务器已完成；最终复核确认 A 可达 B SS 端口、A/B 容器运行、监听正常，B 测试端口来源限制已收敛。

## 9. 代码审查修复

本轮 max-effort 代码审查后已修复：

- [x] 非法 `--route-mode` 不再静默回退 `split`，改为直接报错。
- [x] `entry_a` 缺少 B 地址时不再默认写入文档示例地址，必须明确提供真实 B 地址。
- [x] 用户启用/禁用、删除、改密、限额、重置流量前会执行旧单用户迁移，避免升级后 `default` 用户不可编辑。
- [x] 用户菜单“设置用户限额”已接入 `user_set_quota`。
- [x] `change-secret` 菜单“指定用户密码”已接入 `user_change_password`。
- [x] 重新渲染客户端配置时会清理旧用户子目录，禁用用户不再保留旧客户端凭据。
- [x] `ENABLE_TRAFFIC_STATS` / `ENABLE_QUOTA_ENFORCE` 会启用 V2Ray API stats 配置。
- [x] 用户、路由、限额变更后，如检测到容器正在运行，会尝试自动重建容器应用新配置；否则提示手动 `p-m restart`。
- [x] 自定义 `--root` 不再因目录名不是 `Proxy-Manager` 而被卸载保护误拒绝；仍保留绝对路径、关键目录和标识文件保护。
- [x] `quota install-cron` / `quota uninstall-cron` 已实现 crontab 标记行添加/移除。
- [x] `entry_a --yes` 未显式传 `--components` 时默认只启用 AnyTLS + NaiveProxy，不再继承全局 `ENABLE_SS=1`。

补充验证：

- [x] 禁用用户后，旧 `config/client/<user>/` 客户端文件被清理。
- [x] `ENABLE_TRAFFIC_STATS=1` 且 `ENABLE_V2RAY_API=0` 时，生成配置仍包含 `experimental.v2ray_api.stats`。
- [x] `p-m route mode <invalid>` 会失败而不是回退。

## 10. 已知限制

- per-user 流量统计依赖 sing-box V2Ray API stats、镜像编译能力以及宿主机 `grpcurl`；不可用时限额功能降级。
- AI 分流规则已使用 sing-box 新版 `route.rule_set` 远程二进制 `.srs`，来源为 MetaCubeX/meta-rules-dat `sing` 分支；OpenAI、Anthropic 先于 `category-ai-!cn` 总规则匹配，不使用旧 `geosite` / `geoip` 写法，也不使用 `claude.srs`。
- Google、YouTube 和自定义规则仍使用内联域名/关键词；YouTube 默认不走 B，避免大流量视频消耗 B 带宽，可通过自定义域名加入。
- 远程 `.srs` 规则依赖服务器能访问 GitHub raw；中国大陆网络环境如无法直连，需要在服务器侧提供可用网络路径或改用可访问的镜像源。
- `p-m upgrade` 依赖服务器能拉取目标 Docker 镜像；候选镜像拉取失败会恢复更新前配置，但不会解决服务器到 GHCR/Docker registry 的网络可达性问题。
- 回退快照覆盖关键运行配置，不替代完整系统级备份；证书文件、Docker daemon、云防火墙和外部镜像仓库仍需单独维护。
- 本轮已在测试服务器执行 A/B 部署、路由与多用户矩阵；B 测试端口已收敛为仅允许 A 来源，后续如不再需要测试服务应及时清理。
