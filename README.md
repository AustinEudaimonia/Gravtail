# Gravtail｜重力光标

> 让你的光标知道：你已经坐太久了。

<p align="center">
  <img src="Resources/HeavyCursorIconMaster.png" alt="Gravtail comet icon" width="180" />
</p>

Gravtail 是一个轻量的 macOS 菜单栏应用。它不靠突然弹出的系统通知打断你，而是把“久坐时间”变成光标本身的环境反馈：使用电脑越久，光标后的 comet（彗尾）越长、越粗，鼠标响应也会逐渐变重；起身离开一段时间后，光标恢复轻盈。

## 为什么要做 Gravtail

传统久坐提醒往往在某个瞬间弹出一条通知，把人从正在做的事情里拽出来。Gravtail 选择了另一种方式：

- **提醒融入正在使用的对象**：光标一直在屏幕上，不需要额外的弹窗或健康面板。
- **变化是渐进的**：你会先看到很轻的 comet，越接近设定时间，轨迹越明显，身体可以自然形成“变重了，该起来走走”的反馈。
- **保持克制**：没有 TODO、打卡、排行榜或生产力评分，核心只做一件事——帮助你离开椅子。

## 核心交互

| 连续使用时间 | 视觉反馈 | 鼠标响应 |
| --- | --- | --- |
| 前半段 | 第一次真实输入后显示很轻的 comet | 保持原始灵敏度 |
| 后半段 | comet 平滑变长、变粗，颜色逐渐变暖 | 逐步降低加速度 |
| 达到设定时间 | 顶部居中的小胶囊提示起身，comet 保持最强 | 达到最重状态，强加重最低约为原响应的 10% |
| 完成休息 | comet 和重量逐渐清除 | 恢复启动前保存的原始设置 |

你可以选择 **45 / 60 / 90 分钟**的连续使用时间，以及 **3 / 5 / 10 分钟**的休息时长。应用启动或重置后，会等到第一次真实的键盘/鼠标输入才开始计时。每 15 分钟，屏幕上方会出现一个短暂的小胶囊，告诉你距离起身还剩多久；到点后胶囊会显示休息倒计时。键盘或鼠标输入会重新开始休息倒计时，完整休息后进入下一轮。

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
- During the second half, a comet grows continuously and pointer response eases down to 10% at maximum weight.
- Every 15 minutes, a four-second pill reports how long remains before it is time to move.
- At the selected limit, the pill stays visible with a live break countdown and Quit action.
- During that break countdown, the native pointer remains fully usable (including text I-beam hit testing) while the system acceleration stays reduced; keyboard or pointer input simply restarts the countdown.
- Pills sit at the upper center of the main screen, below the menu bar and away from bottom-center voice tools such as Typeless.
- A single small comet/cursor icon is pinned near the center of the top menu-bar strip (automatically avoiding a MacBook notch) and opens work and break settings, Reset Session, and Quit. It remains visible over full-screen apps and never relies on the system's hidden status-item overflow.
- The first physical keyboard or pointer input starts a new work session; any keyboard or pointer input restarts the break countdown.
- Completing the break restores the original pointer response and starts a new session.
- Reset or quit at any time from the menu bar.

## Build and run

Gravtail supports macOS 13 or later and builds a universal app for Apple
silicon and Intel Macs. Install the Xcode Command Line Tools first.

```sh
./test.sh
./scripts/ensure-local-signing-identity.sh
./build.sh
open ".build/Gravtail.app"
```

The comet works as soon as the first physical input starts a session. Gravtail
can lower the system HID acceleration without Accessibility access, but macOS
Accessibility permission is required for the stronger event-tap weighting that
reaches the intended 10% response. Choose **开启鼠标加重…** from the Gravtail
menu; macOS requests access for the exact running app and offers the direct
System Settings → Privacy & Security → Accessibility route. The request is
throttled to once per app launch so duplicate prompts cannot stack.

When testing a fresh build from a new folder, make sure the exact
`Gravtail.app` you launched is the enabled entry in this list. macOS can keep
an older Gravtail entry enabled while treating a newly moved or rebuilt copy
as a separate accessibility client.

Gravtail temporarily lowers the active mouse and trackpad acceleration
while the cursor is heavy, backs up the original values first, and restores
them after a completed break or normal quit. If the process is force-killed,
launch it once more so the saved acceleration backup can be restored. A local
build also exposes an explicit emergency command:

```sh
".build/Gravtail.app/Contents/MacOS/HeavyCursor" --restore-hid
```

The app measures physical keyboard and pointer inactivity from macOS HID
events; window redraws, notifications, and changing message content do not
count as work input. It cannot verify whether a person physically stood up.
The configured break duration is therefore a practical inactivity-based proxy
for taking a break.

For troubleshooting, Gravtail records only state transitions—not keyboard
content, pointer coordinates, or browsing activity—in
`~/Library/Logs/Gravtail/Gravtail.log`.

## Download and install

Download the latest `Gravtail-*-macOS.zip` from GitHub Releases, unzip it,
and move `Gravtail.app` to Applications. This project intentionally uses a
certificate-backed self-signed release, so macOS will require Control-click →
Open on the first launch, followed by the Accessibility permission step above.

macOS identifies privacy-authorized code using its bundle identity and signing
requirements. The setup script creates a certificate-backed self-signed
identity named `Heavy Cursor Local`; the certificate and its private key—not
the display name—are the identity. Keep that exact key pair unchanged for all
official releases, keep the private key out of the repository, and do not
generate a new certificate for every version. A different certificate, Bundle
ID, or unsigned build can require Accessibility approval again.

The public product is named **Gravtail**, while `Heavy Cursor Local` is kept as
the existing signing identity so already-authorized local installations do not
needlessly change code identity. This name is only a certificate/keychain
label; users download and launch `Gravtail.app`.

For a local, non-persistent preview of the full 45-minute effect:

```sh
open ".build/Gravtail.app" --args --preview-45
```

Preview mode does not automatically open the Accessibility permission prompt.
If you want to test physical pointer weighting, choose **开启鼠标加重…** from
the menu-bar icon once, or grant Gravtail access manually
in System Settings.

To preview a 15-minute progress pill without waiting:

```sh
open ".build/Gravtail.app" --args --preview-ui --preview-progress
```

## Packaging a self-signed release

```sh
./scripts/ensure-local-signing-identity.sh
./package.sh
```

This rebuilds and then produces a universal macOS zip signed with the certificate-backed
`Heavy Cursor Local` identity, a rebuildable source zip, and a
`SHA256SUMS.txt` file in `dist/`. The certificate must already exist in your
login keychain; run the setup script once and keep the resulting certificate
and private key for every release. The app is intentionally self-signed: it
is not notarized, so users must Control-click → Open on first launch.

To use a named fixed self-signed identity, pass that identity explicitly:

```sh
SIGNING_IDENTITY="Heavy Cursor Local" ./package.sh
```

Do not run the identity setup script again on another machine and publish that
build as an update: the same display name does not mean the same certificate.
For GitHub Actions releases, import the original `.p12` certificate as an
encrypted repository secret and use `.github/workflows/release.yml`; never
commit the private key.

The release workflow expects these repository secrets:

- `GRAVTAIL_SIGNING_IDENTITY`: the exact certificate name, normally `Heavy Cursor Local`
- `GRAVTAIL_SIGNING_P12_BASE64`: base64-encoded export of that certificate and private key
- `GRAVTAIL_SIGNING_P12_PASSWORD`: the password used for the `.p12` export

Only the original release certificate should be exported for this purpose. A
new self-signed certificate with the same name changes the code identity and
can cause Accessibility approval to be requested again.

The repository CI also uses a certificate-backed self-signed identity for
testing. Ad-hoc and unsigned packages are intentionally rejected by the build
scripts and are not release formats for Gravtail.

## Attribution

The transparent multi-display overlay and comet approach are based on [MouseTrail](https://github.com/changymon/MouseTrail) by Reggie Chang, used under the MIT License. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
