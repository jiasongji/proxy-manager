# Proxy Manager Audit

审计日期：2026-06-14
审计范围：脚本交互、GitHub 下载安装、Docker 镜像、公开文档脱敏、发布流程。

> 公开仓库不得包含真实服务器 IP、真实域名、登录端口、节点密码、订阅链接、token、证书/key 文件或本地凭据文件。

## 1. 本轮整改目标

- [x] 短命令统一为 `p-m`，长命令保留 `proxy-manager`。
- [x] 交互菜单改为二级结构：主菜单回车退出，二级菜单回车返回上一页。
- [x] 安装说明改为从 GitHub 直接下载脚本，不再要求本地上传脚本。
- [x] HTML 运维手册移除本地连接、脚本上传、凭据权限修正等非必要内容。
- [x] 默认 Docker 镜像改为 `jiasongji/proxy-manager-sing-box:latest`。
- [x] Dockerfile source label 改为 `https://github.com/jiasongji/proxy-manager`。
- [x] 新增 `.gitignore`，排除本地凭据、证书、env、日志、运行时数据和备份目录。
- [x] 新增 `.dockerignore`，避免 Docker build context 携带本地凭据或运行时数据。

## 2. 静态检查

本地检查结果：

- [x] `bash -n proxy-manager.sh` 通过。
- [x] `docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable /mnt/proxy-manager.sh` 通过。
- [x] 公开文档中无旧短命令残留。
- [x] 公开文档中无 GitHub/Docker 未替换占位。
- [x] README、HTML、Dockerfile、AUDIT 未命中真实测试域名/IP/端口、本地凭据文件名或 private-key 标记。
- [x] README/HTML 未展示本地连接、脚本上传、凭据权限修正等步骤。

## 3. 菜单烟测

本地输入流烟测结果：

- [x] 主菜单直接回车退出：`printf '\n' | bash proxy-manager.sh menu` 通过。
- [x] 主菜单输入 `0` 退出：`printf '0\n' | bash proxy-manager.sh menu` 通过。
- [x] 进入二级菜单后直接回车返回上一页：`printf '3\n\n\n' | bash proxy-manager.sh menu` 通过。
- [x] 进入二级菜单后输入 `0` 返回上一页：`printf '3\n0\n0\n' | bash proxy-manager.sh menu` 通过。
- [x] 非法输入不会触发安装、卸载、重启等危险操作：`printf 'x\n\n' | bash proxy-manager.sh menu` 通过。

## 4. Docker 构建检查

本地构建结果：

- [x] `docker build -t jiasongji/proxy-manager-sing-box:latest .` 通过。
- [x] `docker image inspect jiasongji/proxy-manager-sing-box:latest` 通过，`org.opencontainers.image.source=https://github.com/jiasongji/proxy-manager`。
- [x] `docker run --rm jiasongji/proxy-manager-sing-box:latest version` 通过，sing-box 版本为 `1.13.12`。
- [x] `docker push jiasongji/proxy-manager-sing-box:v0.3.0` 通过，digest `sha256:b90a1f8d12fee77ffd9e56f5fabbef0b0b146053157ebf4e1986f02a06469e6d`。
- [x] `docker push jiasongji/proxy-manager-sing-box:latest` 通过，digest `sha256:b90a1f8d12fee77ffd9e56f5fabbef0b0b146053157ebf4e1986f02a06469e6d`。
- [x] `docker manifest inspect` 已验证 `latest` 与 `v0.3.0` manifest 可访问。

## 5. 组件矩阵与对抗测试

服务器端部署后至少验证：

- [ ] 仅 AnyTLS：`p-m install --yes --components anytls ...`
- [ ] 仅 NaiveProxy：`p-m install --yes --components naive ...`
- [ ] 仅 Shadowsocks：`p-m install --yes --components ss ...`
- [ ] 全部组件：`p-m install --yes --components all ...`
- [ ] 自定义组合：`p-m install --yes --components anytls,ss ...`
- [ ] 重复端口会被拒绝。
- [ ] 占用端口会被拒绝。
- [ ] TLS 证书/key 路径错误会被拒绝。
- [ ] 启用组件的空密码会被拒绝。
- [ ] 卸载默认保留 Docker、Compose 和证书文件。
- [ ] 删除项目目录必须输入 `DELETE`。

## 6. 发布检查

- [x] GitHub 仓库已创建：`https://github.com/jiasongji/proxy-manager`。
- [x] 默认分支：`main`。
- [x] Git tag 已推送：`v0.3.0`。
- [x] GitHub Release 已创建：`https://github.com/jiasongji/proxy-manager/releases/tag/v0.3.0`。
- [x] Release asset 已上传：`proxy-manager.sh`，SHA-256 `7e40f71608216c1310f0d08f9b383b3c11e5c61722891d2f83399463e7c2c430`。
- [x] Release latest 下载地址公开可用，下载后 `bash -n` 通过且版本为 `0.3.0`。
- [x] GitHub 仓库已切换为公开可见。
- [x] GitHub Actions `ci` 已通过：`27503983324`。
- [x] Docker 镜像已推送：`jiasongji/proxy-manager-sing-box:latest`。
- [x] Docker 版本镜像已推送：`jiasongji/proxy-manager-sing-box:v0.3.0`。
- [ ] 从 Release URL 在测试服务器直接安装通过：待服务器端实装验证。

## 7. 安全结论

- 静态检查：通过。
- 菜单烟测：通过。
- Docker 构建与推送：通过。
- GitHub Release 上传：通过。
- 公开文档脱敏：通过。
- 服务器端组件矩阵：待在目标测试服务器执行。
- 对抗输入测试：待在目标测试服务器执行。
