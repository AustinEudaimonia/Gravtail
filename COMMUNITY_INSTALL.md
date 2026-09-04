# 安装 Gravtail 社区版

Gravtail 需要 macOS 辅助功能权限才能实现强鼠标加重。社区版没有使用付费的 Apple Developer ID，因此首次安装需要把 App 绑定到这台 Mac 自己的本地代码签名。

## 首次安装

1. 完整解压从 GitHub Release 下载的 ZIP。
2. 按住 Control 点击 `安装 Gravtail.command`，选择“打开”。
3. 安装脚本会在你的登录钥匙串中创建一张名为 `Gravtail Local` 的本地代码签名证书，并把 App 固定安装到 `/Applications/Gravtail.app`。如果系统 Applications 不可写，会改装到你的 `~/Applications`。
4. 第一次启动 Gravtail 时，按住 Control 点击 App 并选择“打开”。
5. 点击屏幕顶部的 Gravtail 图标，选择“开启鼠标加重…”，然后在系统设置中授予 Gravtail 辅助功能权限。

本地证书的私钥只存在于你的 Mac 登录钥匙串中，不会上传给项目作者或 GitHub。该证书只配置为代码签名信任，不用于网页、邮件或其他用途。

首次创建和信任证书时，macOS 可能要求输入当前 Mac 的登录密码。这是钥匙串授权，不是 Apple ID、GitHub 或 Google 密码。

## 更新

下载新版本并再次运行新版 `安装 Gravtail.command`。脚本会复用同一张 `Gravtail Local` 证书重新签名，并安装到同一路径。请不要删除钥匙串中的这张证书，否则 macOS 可能要求重新授予辅助功能权限。

更新前需要先从 Gravtail 顶部菜单选择“退出 Gravtail”。安装脚本不会强制终止正在运行的版本；替换前的 App 会以带时间戳的 `Gravtail.previous-*.app` 名称保留在同一 Applications 文件夹中。

## 安装脚本会做什么

- 校验下载 App 的 Bundle ID 和现有代码签名完整性。
- 创建或复用当前用户自己的本地代码签名证书。
- 仅为代码签名用途信任这张证书。
- 在本机重新签名 Gravtail，并验证签名结果。
- 固定安装路径，避免从下载目录或不同文件夹启动导致权限身份混乱。

安装脚本不能、也不会替你授予辅助功能权限；最后一次系统开关必须由用户本人操作。
