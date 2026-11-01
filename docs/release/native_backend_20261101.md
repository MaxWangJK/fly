# 原生 Ubuntu 后台交付

2026-11-01。用户服务器无法下载 Docker，改为系统 PostgreSQL 独立安装、Python 虚拟环境独立运行、systemd 管理。使用 Ubuntu 24.04 自带软件包即可，主流程为安装 PostgreSQL/建库、上传公开代码和私有发件配置、运行 `sudo bash deploy/install-native.sh`、复用已有 Nginx 路由。

部署入口：[简单步骤](../../server/deploy/ubuntu-native.md)。安装器、初始化工具和服务模板分别为 `server/deploy/install-native.sh`、`prepare_native.py`、`fly-sync.service`。安装器检查固定部署目录与私有配置，不重建已有数据库或覆盖 `.env`；创建独立运行用户、安装虚拟环境依赖，自动增量迁移和开启自启。Python 仍只监听 `127.0.0.1:18766`，只信任本机 Nginx 代理头。官网 PHP 及证书保留，不新增公网数据库或后台监听。

原有 Docker 文件保留兼容，默认文档入口改为原生方案。没有改动客户端、同步协议和账号业务逻辑；后台仍为迁移 `0004`，包含此前找回密码和注销，云端不传文件内容。

本轮针对原生配置、特殊字符密码、IPv4/IPv6/域名、自定义端口、无效输入、旧配置不覆盖、迁移保留旧数据和真实 Python 进程启动共 20 项通过；Bash 语法检查通过。进程测试使用隔离 SQLite、临时文件和本机回环，不是 PostgreSQL/systemd 的 Ubuntu 真机验收。此前账号后台全量 49 项记录仍保留，不将本轮 20 项称作全量测试。没有实际 SMTP、SSH、官网或生产数据库操作。

独立原生源码包：`dist/Fly-Sync-native-20261101.tar.gz`。只含运行源码、迁移、固定依赖和原生部署文件；不含 `.env`、SMTP 凭据、虚拟环境、测试数据库或客户数据。包内 `server/SOURCE.json` 说明来源于当前未提交工作区，并列出各公开文件的校验值。客户端未重新打包，Git 未提交/推送，旧 build43 Windows/APK 不因此获得新界面。

包校验值见 [CURRENT_STATE.json](../handoff/CURRENT_STATE.json) 的 `nativeBackendBundle`。需求来源为当前聊天新增的一条，累计 152 条。


## build44 后续交付

上述为该阶段当时记录。现已随源码 `404aea3` 一起提交并纳入2.0.8+44 Windows/APK及原生后台包，后台全量61项、客户端全量与修复复测证据见 [build44](fly_2_0_8_build44.md)。原生部署仍由用户自行执行，未真实发件或部署。
