# Gravtail｜重力光标

> 让你的光标知道：你已经坐太久了。

<p align="center">
  <img src="Resources/HeavyCursorIconMaster.png" alt="Gravtail comet icon" width="180" />
</p>

<p align="center"><strong>工作越久，鼠标越重；起身走一会，它才恢复。</strong></p>

<p align="center">
  <a href="https://github.com/AustinEudaimonia/Gravtail/releases/latest">下载 macOS 版</a>
  ·
  <a href="COMMUNITY_INSTALL.md">查看安装说明</a>
  ·
  <a href="https://github.com/AustinEudaimonia/Gravtail/issues">反馈问题</a>
</p>

Gravtail 是一个轻量的 macOS 菜单栏应用。它不靠突然弹出的系统通知打断你，而是把“久坐时间”变成光标本身的环境反馈：使用电脑越久，光标后的 comet（彗尾）越长、越粗，但工作阶段会保持克制的视觉强度；只有最后 10 分钟鼠标才开始从原生灵敏度平滑降到 50%，到达起身时间时再突然降到 10%，同时彗尾进入满强度；起身离开一段时间后，光标恢复轻盈。

它不是一个更复杂的生产力面板，也不是一套打卡系统。它只做一件事：在你忘记起身之前，让正在使用的鼠标先告诉你。

## 30 秒看懂

| 你连续使用电脑的时间 | 你会看到什么 | 鼠标会发生什么 |
| --- | --- | --- |
| 前半段 | 一条几乎看不见的 comet | 保持正常 |
| 最后 10 分钟 | 彗尾逐渐变长、变粗，但强度保持克制 | 灵敏度从 100% 平滑降到 50% |
| 到达设定时间 | 顶部出现“起身动一下”，彗尾开满 | 灵敏度瞬间降到 10% |
| 完成休息 | 彗尾消失，出现恢复提示 | 恢复原始设置 |

默认支持 **45 / 60 / 90 分钟**工作时长和 **3 / 5 / 10 分钟**休息时长。最重状态沿用约 10% 的加重曲线，同时设置绝对安全下限；鼠标始终由 macOS 原生事件系统控制，不会被 Gravtail 拦截、重定位或阻止文本输入。

## 为什么要做 Gravtail

传统久坐提醒往往在某个瞬间弹出一条通知，把人从正在做的事情里拽出来。Gravtail 选择了另一种方式：

- **提醒融入正在使用的对象**：光标一直在屏幕上，不需要额外的弹窗或健康面板。
- **变化有明确断点**：彗尾一直提供轻量的环境反馈；只有最后 10 分钟鼠标才逐渐变重，到了起身时间瞬间降到 10%，让“该起来走走”的感觉清晰可感知。
- **保持克制**：没有 TODO、打卡、排行榜或生产力评分，核心只做一件事——帮助你离开椅子。

## 核心交互

| 连续使用时间 | 视觉反馈 | 鼠标响应 |
| --- | --- | --- |
| 前半段 | 第一次真实输入后显示很轻的 comet | 保持原始灵敏度 |
| 前段与中段 | comet 持续提供轻量反馈 | 保持原始灵敏度 |
| 最后 10 分钟 | comet 平滑变长、变粗，颜色逐渐变暖，但视觉强度上限约 35% | 从 100% 平滑降到 50% |
| 达到设定时间 | 顶部居中的小胶囊提示起身，comet 开到 100% | 瞬间降到 10%，并保留安全响应下限 |
| 完成休息 | 清除 comet；确认恢复后显示完成提示 | 立即尝试恢复本轮加重前保存的原始设置 |

你可以选择 **45 / 60 / 90 分钟**的连续使用时间，以及 **3 / 5 / 10 分钟**的休息时长。应用启动或重置后，会等到第一次真实的键盘/鼠标输入才开始计时；工作阶段不会因为几分钟没有输入而自动把本轮归零。每 15 分钟，屏幕上方会出现一个短暂的小胶囊，告诉你距离起身还剩多久；到点后胶囊会显示休息倒计时。休息阶段的键盘或鼠标输入会重新开始休息倒计时，完整休息后进入下一轮。

每个进度胶囊、进入休息和休息完成都会播放一次短促的 macOS 内置音效；设置中可以关闭提醒音效，关闭后仍保留所有视觉提醒。

鼠标加重是独立开关：选择“暂不开启”或在设置里关闭后，所有阶段都只保留彗尾和提醒。Gravtail 不再需要辅助功能权限；旧版本升级后可以在系统设置中移除原先的 Gravtail 辅助功能授权。

打开或重新打开 `Gravtail.app` 会显示设置窗口。菜单栏空间不足、图标被 macOS 隐藏时，也能直接调整时长、关闭加重、重置或退出。关闭设置窗口不会退出应用。

首次完成 Gravtail 配置后，应用会询问是否要登录 macOS 后自动启动。点击“打开登录项设置”会直接跳到 macOS 的“系统设置 → 通用 → 登录项与扩展”，由用户手动把 Gravtail 加入“登录时打开”；Gravtail 不会偷偷修改系统设置，也不需要 Apple Developer 账号。之后可以在菜单栏或设置窗口再次打开这个页面。

硬件加重前会启动独立恢复进程。主循环超过约 5 秒没有心跳、进程退出、电脑睡眠或通信断开时，它会尝试恢复保存的设置；主程序恢复运行后不会自动重新加重，需要手动重置。恢复提示只在确认恢复成功后显示。此机制降低异常影响，但不能保证所有 macOS、鼠标驱动和硬件都兼容；不兼容时会直接保持系统原生鼠标，只显示彗尾和提醒。

## 视觉语言

Gravtail 的视觉元素都围绕“重量正在增加”这一件事：

```text
轻盈       ·  ·  ·        ───────────────▶       加重
短而清澈的 comet                                  长而厚的 comet
```

- **Comet 光标**：轨迹长度、粗细和下坠感连续变化，不是几个突兀的档位。
- **顶部胶囊**：位于主屏幕上方居中、避开菜单栏和底部语音工具，只显示当前真正需要知道的信息。
- **顶部菜单栏图标**：一个固定在屏幕上方、自动避开 Mac 刘海的 Gravtail 小图标，随时查看下一次起身时间，修改工作/休息时长、Reset Session 或 Quit。

## 灵感与开源致谢

Gravtail 的透明多显示器 overlay、全局光标轨迹和 comet 渲染思路，借鉴了 GitHub 上的 [MouseTrail](https://github.com/changymon/MouseTrail) 项目（Reggie Chang，MIT License）。

我们没有把 MouseTrail 原样复制成一个鼠标特效工具，而是沿用了它“在光标附近绘制轻量视觉层”的技术基础，把它改造成一个以久坐提醒为核心的产品：**轨迹不是为了装饰，而是用来表达光标正在变重。** 具体许可和第三方声明见 [LICENSE](LICENSE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

A deliberately small macOS menu bar app: the longer you use your Mac, the heavier its comet cursor becomes. Step away for the selected break duration and it becomes light again.

## Core behavior

- Choose a 45, 60, or 90 minute work interval.
- Choose a 3, 5, or 10 minute break duration.
- After the first physical input, a subtle comet confirms that Gravtail is running while physical pointer response stays unchanged during the first half.
- During the final ten minutes, the comet grows within a restrained 35% visual ceiling while pointer response eases from native sensitivity to 50%; when the break begins, the pointer switches immediately to 10% and the comet reaches full strength.
- Every 15 minutes, a four-second pill reports how long remains before it is time to move.
- Progress pills, break start, and break completion each play one short built-in macOS sound; sounds can be disabled without removing the visual reminders.
- At the selected limit, the pill stays visible with a live break countdown and Quit action.
- During that break countdown, the native pointer remains fully usable (including text I-beam hit testing) while the system acceleration stays reduced; keyboard or pointer input simply restarts the countdown.
- Pills sit at the upper center of the main screen, below the menu bar and away from bottom-center voice tools such as Typeless.
- A single small Gravtail comet/cursor icon is provided by one native macOS status item. It opens work and break settings, Reset Session, and Quit; macOS controls its placement and can move it with Command-drag. If macOS 26 or later hides third-party status items, allow Gravtail in System Settings → Menu Bar.
- The first physical keyboard or pointer input starts a new work session; any keyboard or pointer input restarts the break countdown.
- Completing the break restores the original pointer response and starts a new session.
- Reset or quit at any time from the menu bar.

## Build and run

Gravtail supports macOS 13 or later and builds a universal app for Apple
silicon and Intel Macs. Install the Xcode Command Line Tools first.

The physical HID cue is capability-detected at runtime because Apple does not
publish that interface as a stable SDK API. If a macOS version or pointing
device does not expose it, Gravtail keeps the comet and leaves native pointer
input unchanged; the menu shows the compatibility status instead of silently
retrying live input.

```sh
./test.sh
./scripts/ensure-local-signing-identity.sh
./build.sh
open ".build/Gravtail.app"
```

The comet works as soon as the first physical input starts a session. Physical
weighting uses one hardware-acceleration path and does not require Accessibility
permission. Gravtail does not install a global event tap, suppress input,
disconnect the physical device, or call `CGWarpMouseCursorPosition`; native
clicking, dragging and text I-beam behavior therefore remain under macOS.

The original HID values are backed up before a change and restored after a
completed break, reset, sleep, or normal quit. The 10% curve has an absolute
non-stalling floor and never writes zero acceleration.
Before the first HID change, Gravtail starts a small independent recovery
watchdog. If the main app crashes or is force-killed during a break, the
watchdog restores the saved values automatically. A persistent backup remains
as a second recovery layer. A local build also exposes an explicit emergency
command:

```sh
".build/Gravtail.app/Contents/MacOS/HeavyCursor" --restore-hid
```

The app measures physical keyboard and pointer inactivity from macOS HID
events; window redraws, notifications, and changing message content do not
count as work input. After a work session has started, a quiet period does not
reset the work interval. Once the work limit is reached, the configured break
duration is used as a practical inactivity-based proxy for taking a break.

For troubleshooting, Gravtail records only state transitions—not keyboard
content, pointer coordinates, or browsing activity—in
`~/Library/Logs/Gravtail/Gravtail.log`.

## 下载与安装（免费社区版）

社区版不要求每个用户信任作者的私有自签名身份，而是在每台 Mac 上创建独立的本地签名：

1. 从 GitHub Releases 下载并完整解压 `Gravtail-*-macOS.zip`。
2. 按住 Control 点击 **安装 Gravtail.command**，选择“打开”。
3. 安装程序会在当前用户的登录钥匙串中创建或复用 `Gravtail Local`，在本机重新签名，并把 App 安装到固定的 Applications 路径。
4. 安装完成后直接打开 `Gravtail.app`。安装器会先验证下载包和本地签名，再移除 App 的下载隔离标记，因此不再要求第二次按住 Control 打开。
5. 首次打开时按提示完成工作时长、休息时长和鼠标加重设置；随后可选择“打开登录项设置”，把 Gravtail 手动加入 macOS 的“登录时打开”。这一步不需要 Apple Developer 账号，也不会自动修改系统设置。
6. 点击顶部 Gravtail 图标，在设置中随时修改选项；不需要辅助功能权限。

请始终运行 Release ZIP 里的“安装 Gravtail.command”，不要直接双击 ZIP 内的 `Gravtail.app`。安装器会校验载荷、固定安装路径，并复用本机已有签名身份，包括早期版本使用的 `Heavy Cursor Local`。

私钥只留在这台 Mac，不会上传给项目作者或 GitHub；证书也只被信任用于代码签名。更新时先退出 Gravtail，再运行新版本中的同一个安装脚本；它会复用同一证书、Bundle ID 和安装路径。完整说明见 [COMMUNITY_INSTALL.md](COMMUNITY_INSTALL.md)。

For a local, non-persistent preview of the full 45-minute effect:

```sh
open ".build/Gravtail.app" --args --preview-45
```

Preview mode does not require Accessibility permission. Enable physical
weighting once in Gravtail settings if you want the preview to alter hardware
acceleration.

To preview a 15-minute progress pill without waiting:

```sh
open ".build/Gravtail.app" --args --preview-ui --preview-progress
```

## 打包社区版本

```sh
./scripts/ensure-local-signing-identity.sh
./package.sh
```

这会在 `dist/` 中生成通用架构的社区安装包、可重新构建的源码包和 `SHA256SUMS.txt`。维护者构建会先完成完整性签名；下载者运行安装脚本时，再用该 Mac 私有的 `Gravtail Local` 身份替换签名。

To use a named fixed self-signed identity, pass that identity explicitly:

```sh
SIGNING_IDENTITY="Gravtail Local" ./package.sh
```

维护者的私钥不会进入发布包。每个下载副本通过持续复用用户自己的本地证书，在该 Mac 上保持稳定身份。由于 App 没有经过 Apple 公证，第一次运行下载得到的安装脚本时，“按住 Control 点击 → 打开”仍是免费发行路线无法省略的步骤；通过验证的 App 本身无需再重复一次。

## Attribution

The transparent multi-display overlay and comet approach are based on [MouseTrail](https://github.com/changymon/MouseTrail) by Reggie Chang, used under the MIT License. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
