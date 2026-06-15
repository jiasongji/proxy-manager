# Proxy Manager Audit

审计日期：2026-06-15
审计范围：A/B Shadowsocks 落地分流、多用户管理、流量/限额降级策略、脚本交互、CI、公开文档脱敏。

> 公开仓库不得包含真实服务器 IP、真实域名、登录端口、节点密码、B 上游凭据、订阅链接、token、证书/key 文件或本地凭据文件。

## 1. 本轮整改目标

- [x] 新增节点角色：`standalone`、`entry_a`、`egress_b`。
- [x] 明确服务器 A / 服务器 B 拓扑：用户连接 A，A 可通过 B 的 Shadowsocks 出站。
- [x] 新增路由模式：`split`、`all_via_b`、`all_direct`。
- [x] `split` 模式支持 AI / Google / 自定义域名或关键词走 B，其余流量走 A。
- [x] B 的 Shadowsocks 凭据只作为 A 的上游配置，不进入用户客户端导出。
- [x] 新增 `config/users.json` 多用户数据库。
- [x] 新增用户管理命令：list/add/show/enable/disable/del/passwd/quota/reset-usage/export。
- [x] 客户端配置按用户导出到 `config/client/<user>/`。
- [x] 新增 `stats probe`、`traffic`、`quota check` 与不可用时的降级提示。
- [x] 新增 `doctor` 与 `topology` 诊断/拓扑入口。
- [x] 更新 README 与 HTML 运维手册。
- [x] 扩展 GitHub Actions smoke test。

## 2. 静态检查

本地检查结果：

- [x] `bash -n proxy-manager.sh` 通过。
- [ ] `shellcheck proxy-manager.sh`：本机未安装 shellcheck，已在 CI 中保留 ShellCheck 步骤。
- [x] CLI help smoke 通过：
  - `bash proxy-manager.sh help`
  - `bash proxy-manager.sh user help`
  - `bash proxy-manager.sh route help`
  - `bash proxy-manager.sh stats help`
  - `bash proxy-manager.sh traffic help`
  - `bash proxy-manager.sh quota help`
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
- [x] `entry_a + split` 可生成 AI/Google/custom route rules。
- [x] 旧单用户 env 可迁移为 `users.json` 中的 `default` 用户。
- [x] AnyTLS inbound 可从 `users.json` 渲染用户列表。
- [x] 用户客户端导出目录不包含 B 的 Shadowsocks 密码。
- [x] `egress_b` 可生成 `ss-landing-in` Shadowsocks inbound 与 `direct` outbound。

已执行的关键断言：

```bash
jq -e '.outbounds[] | select(.tag=="egress-b")' "$tmp/config/sing-box.json"
jq -e '.route.rules[0].domain_suffix | index("example.net")' "$tmp/config/sing-box.json"
jq -e '.inbounds[] | select(.tag=="anytls-in") | .users[0].name == "default"' "$tmp/config/sing-box.json"
! grep -R "<B_TEST_SECRET>" "$tmp/config/client"
```

## 5. 新增功能验收清单

服务器端部署后仍需实机验证：

### 5.1 服务器 B

- [ ] `p-m install --yes --node-role egress_b ...` 成功。
- [ ] `p-m check` 通过。
- [ ] B 的 Shadowsocks 端口可由 A 访问。
- [ ] B 的安全组/防火墙仅允许 A 的公网 IP 访问该端口。

### 5.2 服务器 A

- [ ] `p-m install --yes --node-role entry_a ... --route-mode split` 成功。
- [ ] 用户通过 AnyTLS 连接 A 成功。
- [ ] 用户通过 NaiveProxy 连接 A 成功。
- [ ] `split` 模式下普通流量显示 A 出口 IP。
- [ ] `split` 模式下 AI / Google / 自定义命中流量显示 B 出口 IP，或在 B 日志可观察到。
- [ ] `all_via_b` 模式下全部流量显示 B 出口 IP。
- [ ] `all_direct` 模式下全部流量回到 A 出口 IP。

### 5.3 多用户

- [ ] `p-m user add alice --protocols anytls,naive --quota 100GB` 成功。
- [ ] 重复用户名被拒绝。
- [ ] `p-m user disable alice` 后配置中不再包含该用户。
- [ ] `p-m user enable alice` 后恢复。
- [ ] `p-m user passwd alice all` 后旧凭据失效，新导出可用。
- [ ] `p-m user export alice` 输出客户端配置，且不包含 B 上游密码。
- [ ] `p-m user del alice` 删除用户及对应客户端目录。

### 5.4 流量与限额

- [ ] `p-m stats probe` 能准确报告镜像是否支持 V2Ray API stats。
- [ ] stats + grpcurl 可用时，`p-m traffic <user>` 能读取用户流量。
- [ ] stats + grpcurl 可用时，`p-m quota check` 可禁用超额用户。
- [ ] stats 或 grpcurl 不可用时，`traffic` / `quota` 只给出降级提示，不破坏代理服务。

## 6. CI 更新

`.github/workflows/ci.yml` 已扩展：

- [x] 安装 `shellcheck jq`。
- [x] 保留 Bash syntax。
- [x] 保留 ShellCheck。
- [x] 保留公开文档审计。
- [x] 新增 CLI help smoke tests。
- [x] 更新菜单 smoke tests，覆盖新菜单编号。
- [x] 新增临时目录 generated config smoke tests，验证 `entry_a split` 与 B 密码不进入客户端导出。

## 7. 实机 A/B 验收结果

> 以下只记录脱敏结论；真实服务器 IP、域名、端口和密钥不写入公开审计文件。

- [x] GitHub Release `v0.4.1` 已创建，`latest/download/proxy-manager.sh` 下载后 `VERSION="0.4.1"` 且 `bash -n` 通过。
- [x] `v0.4.1` Release asset SHA-256：`fb6c3a453fca6e0e96683527d630e6c582ede6161cb5a70aeb0a1f70212eb690`。
- [x] main 分支 CI 已通过：Bash syntax、ShellCheck、公开文档审计、CLI smoke、菜单 smoke、生成配置 smoke。
- [x] 测试服务器 B 已以 `egress_b` 模式部署 Shadowsocks landing，`p-m check` 通过，容器与 TCP/UDP 监听正常。
- [ ] 测试服务器 B 的 SS 测试端口来源限制：当前脚本已放行端口；尝试自动收敛为仅允许 A 来源 IP 时被当前权限策略拦截，需人工或在更高权限模式下执行。
- [x] 测试服务器 A 已以 `entry_a` 模式部署 AnyTLS + NaiveProxy，`p-m check` 通过，容器与监听正常。
- [x] AnyTLS 客户端经 A 访问普通 IP 检测站显示 A 出口；访问自定义走 B 域名显示 B 出口。
- [x] NaiveProxy 客户端经 A 访问普通 IP 检测站显示 A 出口；访问自定义走 B 域名显示 B 出口。
- [x] `all_via_b` 模式验证：普通 IP 检测站显示 B 出口。
- [x] `all_direct` 模式验证：自定义走 B 域名回到 A 出口。
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
- ShellCheck：待 CI 或安装 shellcheck 后确认。
- Docker / sing-box 实际 `check -c`：待有 Docker daemon 的环境确认。
- A/B 实机连通与出口 IP 验证：待测试服务器执行。

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
- 初版分流规则使用内置域名/关键词和自定义列表，不自动下载远程 rule-set。
- YouTube 默认不走 B，避免大流量视频消耗 B 带宽；可通过自定义域名加入。
- 本轮未在真实服务器上执行会改变端口、用户和路由的部署矩阵。
