# easyMusic M0 技术验证（Spike）结论报告

- 日期：2026-11-08
- 验证目标：证明（或证伪）「MyGo Music 的网易云插件能在 Flutter + QuickJS 里跑通搜索，并解析出可播放的音频流地址」
- 结果截图：`~/workspace/easyMusic/spike-result.png`（数据为实测输出渲染，非假数据）

## 一句话结论

**通。** 原版未修改的网易云插件（hubandad/mygo-music-netease v1.0.0）在 Flutter + QuickJS（flutter_js 0.8.7）中成功跑通：匿名搜索返回真实结果，第一条结果的 `stream` 解析出带签名的真实流 URL，Range 请求核验返回 HTTP 206 + `audio/mpeg` + 真实 MP3 字节（ID3 头）。

边界声明：本机无声卡，**没有实际出声播放**；核验到「URL 可达且返回真实音频数据」为止。登录（扫码/网页）不在 M0 范围，未验证。

## 被测插件

- 选用 `hubandad/mygo-music-netease` v1.0.0：直连网易云 EAPI（`interface.music.163.com`），不依赖任何第三方 API 服务，搜索/播放对未登录用户可用。插件源码原样保存在 `spike/plugins/netease/`（plugin.json + index.js，527 行，零改动）。
- 结构相同的同类插件还有 sogud 版等（宿主 API 用法一致），本 spike 的桥接层对它们同样适用。
- 插件协议（来自 egoist/mygo-music README 与插件实测）：插件是一个含 `plugin.json`（id/name/version/main/playback/permissions/settings/navigation）+ 一个 JS/TS 文件的文件夹；通过导出函数提供能力（`search({query,kind,offset}) → {tracks, more}`、`stream({id,quality}) → {url,type,headers,...}`、`lyrics`、`playlist` 等）；宿主提供全局 `fetch`、`host.storage`、`host.setting`、`host.crypto.md5`、`host.crypto.aesEcbEncrypt` 等。
- 该网易云插件的加密方式是网易云 EAPI：`params = AES-128-ECB-PKCS7(key="e82ckenh8dichen8", path + "-36cd479b6b5-" + json + "-36cd479b6b5-" + md5("nobody"+path+"use"+json+"md5forencrypt"))`，宿主只需提供 md5 与 aesEcbEncrypt 两个同步原语。

## 运行方式

- 运行时：`flutter_js` 0.8.7（内置 QuickJS）。以 `flutter test` 在 Linux 主机上无头运行（QuickJS 走 FFI，与 Android 上同一引擎、同一 .so 家族）。
  - 踩坑 1：`flutter test` 下 FFI 库 `libquickjs_c_bridge_plugin.so` 不在加载路径，需把 pub 缓存中 flutter_js 的 `linux/shared/` 目录加到 `LD_LIBRARY_PATH`。真机/模拟器运行无此问题（.so 随 APK 打包）。
  - 踩坑 2：`getJavascriptRuntime()` 默认开 xhr 桥，会经 rootBundle 加载资产，需要 ServicesBinding；传 `xhr: false` 关掉（我们自带 fetch 桥，不需要它）。
  - 踩坑 3：不能初始化 `TestWidgetsFlutterBinding`——它会把 HttpClient 全局替换成永远返回 400 的 mock。普通 `test()` 不需要 binding。
- 加载方式：插件是 ES module，桌面版宿主有打包/转译步骤；spike 的加载器做了等价处理：去掉 `export` 关键字后求值，再按协议规定的导出名清单收集到 `__plugin` 对象。其余源码一字未改。
- 异步桥接：flutter_js 的 `sendMessage`/`onMessage` 做 JS↔Dart 通道；调用插件函数时用一个完成通道 + 泵 QuickJS job 队列（`executePendingJob`）等待 Promise 落定。
  - 注意：flutter_js 传给 Dart 的消息参数是已 JSON 解码的对象（不是字符串），handler 需兼容 Map 与 String 两种形态。
  - 注意：同步的 Dart handler 在 JS 侧拿到的 `sendMessage` 返回值可能不是 Promise（为 undefined），fire-and-forget 调用必须判空再 `.then`。

## 实现的宿主桥接清单（spike 最小子集）

JS 侧引导脚本 `spike/assets/bootstrap.js` + Dart 侧 `spike/lib/plugin_host.dart`：

| 能力 | 实现 | 备注 |
|---|---|---|
| `fetch(url, opts)` | JS 垫片 → Dart `HttpClient`（sendMessage 通道） | 返回 `{ok,status,headers{get,getSetCookie,has},json(),text()}`；Dart 侧处理代理与系统 CA |
| `host.crypto.md5(text)` | 纯 JS MD5（RFC 1321，含 UTF-8 编码） | 同步调用，必须在 JS 内实现 |
| `host.crypto.aesEcbEncrypt(key, text)` | 纯 JS AES-128-ECB + PKCS#7，输出 hex | 同上 |
| `host.storage.get/set/remove` | JS 内存 Map（同步读）+ 异步回写 Dart 侧留底 | 桌面版是持久化的；spike 只做到内存级 |
| `host.setting(key)` | 启动配置注入 | spike 里为空（插件仅登录方式用到） |
| `host.platform/arch/dir/dataDir` | 常量注入（android/arm64） | |
| `host.t / host.language` | 原样返回 / `zh-CN` | 插件未在搜索路径用到 |
| `setTimeout/clearTimeout/setInterval/clearInterval` | 经 Dart `Future.delayed` 桥接 | 插件用它做请求超时与扫码轮询 |
| `AbortController/AbortSignal` | JS 垫片（仅 aborted 标志与监听） | fetch 垫片未真正中断请求，插件只读 `signal.aborted` |
| `URL` | JS 最小垫片（protocol/host/hostname/pathname/search/href/origin） | QuickJS 无内置 URL；插件 stream() 用到 |
| `console.*` | 转发到 Dart print | |
| `host.signInPrompt / webSignIn / waitForRedirect / spawn` | 抛错占位 | 登录与进程能力不在 M0 范围 |

## 实测证据（2026-11-08 运行，`flutter test` 全绿）

密码学自检（EAPI 的前提）：
- `md5("abc") = 900150983cd24fb0d6963f7d28e17f72`、`md5("") = d41d8cd98f00b204e9800998ecf8427e`（RFC 向量）；`md5("稻香") = 7cde2145bef063b156ed13fd6dae8ffc`（UTF-8 路径）
- AES-128 块加密 FIPS-197 向量：`69c4e0d86a7b0430d8cdb78070b4c55a` ✓
- AES-ECB+PKCS7 与系统 openssl 对同一输入逐字节一致：`9162b385e77683daca4851f6403256dc` ✓

插件加载：收集到 33 个导出函数（search/stream/lyrics/playlists/album/artist/comments 等全套）。

搜索：`search({query:"周杰伦 稻香", kind:"tracks", offset:0})`
- 返回 **50 条**，`more=true`
- 第 1 条：id `3381542797`《稻香(治愈版)》，歌手「周杰伦. / 街道办GDC / 欧阳耀莹.」，时长 120022ms（2:00）
- （搜索排序把翻唱/合作版排在了前面，周杰伦原版《稻香》不在第一条；这是网易云搜索本身的排序，与插件/桥接无关。完整前 10 条见 capture.json 与结果截图。）

播放地址解析：`stream({id:"3381542797", quality:"standard"})`
- 返回 `type=mp3, level=standard, br=128003, size=1921197`
- URL（带签名、约 1 小时有效）：`http://m701.music.126.net/20261108105951/fc63.../....mp3?vuutv=...`（完整 URL 见 capture.json）

流 URL 核验（Dart HttpClient，`Range: bytes=0-2047`）：
- HTTP **206**，`Content-Type: audio/mpeg; charset=utf-8`，读到 2048 字节
- 头部字节 `49 44 33 04 00 00 00 00 00 23 54 53 53 45 00 00`，即 ASCII `ID3....#TSSE..` —— 标准 MP3 的 ID3v2 标签头，确系真实音频数据

重跑方式：
```bash
source ~/.bashrc
cd ~/workspace/easyMusic/spike
LD_LIBRARY_PATH=$HOME/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared \
  flutter test test/spike_test.dart     # 完整断言版
  flutter test test/capture_test.dart   # 生成 capture.json（截图数据源）
```

## Android 构建

- `flutter build apk --debug` **成功**：`spike/build/app/outputs/flutter-apk/app-debug.apk`（约 154MB），内含自检页（点按钮在真机上重跑同一套搜索→解析→核验流程）。未在真机/模拟器上实际运行过（本机无 KVM、无模拟器），这一点如实标注。
- 构建修复一处：flutter_js 的 Kotlin/Java JVM target 不一致（1.8 vs 11），在 `spike/android/gradle.properties` 加了 `kotlin.jvm.target.validation.mode=warning`。
- 构建期间按 DEV_ENV.md 刷新过 Java 信任库（出口 CA 轮换坑）；前两次失败均为该问题，刷新后通过。

## 已知缺口与对 v1 的建议

1. **登录未做**：插件的 `signIn` 需要 `host.signInPrompt`（二维码展示）或 `host.webSignIn`（内嵌网页登录抓 Cookie）。v1 若要支持登录/会员音质/歌单同步，需要补这两个桥（二维码展示容易；webSignIn 需要一个隔离的 WebView 并读取指定 Cookie）。未登录状态下：免费歌曲可搜可播，VIP/付费歌曲 stream 会抛 `unavailable`——这是预期行为。
2. **storage 需落盘**：spike 是内存 Map；v1 应接到 SQLite/文件持久化（桌面版语义是跨启动保留），并注意 session cookie 的更新写回。
3. **crypto 放 JS 纯实现够用但可下沉**：MD5/AES 纯 JS 已验证正确，性能对 EAPI 的小报文无压力；v1 也可改走 Dart 同步 FFI 直调 QuickJS 原生函数注册（flutter_js 支持注册同步函数？本 spike 未验证，sendMessage 是异步的——这正是把 crypto 放在 JS 侧的原因。若 v1 需要同步 Dart 回调，需先验证 flutter_js 的 `evaluate` 同步扩展点或换 fjs 等运行时）。
4. **fetch 桥需补强**：v1 应支持请求取消（AbortSignal 真正中断）、二进制响应（部分插件/封面场景）、重定向与 Cookie 的完整语义、以及按 plugin.json `permissions.network` 做域名白名单校验（spike 未做权限校验，v1 必须补，这是插件沙箱的安全边界）。
5. **URL/TextEncoder 等 Web 垫片**：QuickJS 缺的 Web API 不止 URL；其他插件可能用到 `TextEncoder/TextDecoder`、`URLSearchParams`、`btoa/atob`。v1 建议沉淀一个统一的 web-shims 引导脚本，随插件加载时先行注入。
6. **插件加载**：v1 需要真正的 ESM 处理（去掉 import/export 的简单替换只适用于无 import 的单文件插件）；建议引入轻量转译（如 esbuild 打包成单文件）或选支持 ES module 的 QuickJS 配置。TypeScript 插件同样需要这一层（桌面版接受 TS）。
7. **播放器本体**：M0 只证明「能拿到可播地址」；真正的播放（just_audio 等）、后台播放、锁屏控制、缓存按原 v1 范围推进即可，地址解析这层已无悬念。
8. **其他平台**：本 spike 只验了 QuickJS(FFI) 路线在 Linux 测试宿主 + Android 打包。iOS/macOS/Windows 上 flutter_js 同样有 QuickJS 后端，预期一致，但需各自实测一次（尤其 iOS 的 JIT 限制下 QuickJS 是解释执行，性能需关注）。

## 产物清单

- `spike/`：Flutter 工程（lib/main.dart 自检页、lib/plugin_host.dart 宿主、assets/bootstrap.js 桥接垫片、assets/ 内插件副本、plugins/netease/ 插件源码留存、test/ 两个测试、capture.json 实测数据、result.html + make_result_page.py + take_screenshot.mjs 截图流水线）
- `~/workspace/easyMusic/spike-result.png`：结果截图
- `reference/`：调研克隆（egoist/mygo-music、两个网易云插件仓库）

## 仓库推送状态

- 已尝试用 GitHub 连接器 `push-files` 把 SPIKE_M0.md 与 spike 代码（22 个文件）推到 `defeatbug/easyMusic` 的 main 作为初始提交；**写审批在等待中超时（approval_expired），推送未执行**，已复核仓库仍为空仓（size 0）。成果全部留在本地，待审批通道可用时可一键重推（文件清单生成方式见 spike 旁注，命令参数：owner=defeatbug, repo=easyMusic, branch=main, source-dir=~/workspace/easyMusic）。
