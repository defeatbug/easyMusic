# easyMusic（app）

Flutter 跨平台音乐播放器 v1：版式复刻 MyGo Music 桌面版（左侧栏 232 +
内容区 + 底部 84 高播放条，浅色调色板取自桌面版 `paletteFor`），数据来自
MyGo 插件协议的音源插件（当前内置网易云插件，源码未改）。

响应式双版式（断点 `mobileBreakpoint = 600`，见 `ui/theme.dart`）：窗口
≥600 用桌面版式（720 以下侧栏收成 64 图标条）；<600 切手机版式——无侧栏，
内容全宽，底部是迷你播放条（封面/歌名/歌手/播放/下一首 + 顶部细进度线）
加 5 个标签的底部标签栏（发现/搜索/喜欢/本地/我的），与侧栏共用同一份
页面状态。

## 首页

- 问候标题（日期 + 时段问候），与桌面版 homeHello 一致
- 「为你发现」链接卡（插件 `home()` 的 links：每日推荐 / 排行榜）
- 「推荐歌单」卡片网格（插件 `home()` 的 playlists，真实封面/名称/曲目数），
  点卡进歌单详情页
- 「排行榜」卡片网格（插件 `browse({page:'charts'})` 的官方榜单），点卡进
  榜单详情页
- 「热歌榜」歌曲行（插件 `playlist()` 取热歌榜曲目，前 10 行），点行即以
  榜单为队列从该行开始播放；不可播行置灰不可点，正在播的行有高亮与
  播放标记
- 播放条呈现队列第一首可播歌曲（封面/歌名/歌手/时长），接通音频引擎
  后即为真实播放状态（见下节）

## 音频引擎

播放数据流：点歌（首页歌曲行 / 播放条）→ `AudioEngine.playQueue`
→ 逐曲调插件 `stream()` 解析真实地址（`PluginHomeRepository`
实现的 `StreamResolver`，与首页共用同一个 QuickJS 宿主）
→ just_audio 播放 → audio_service 把同一播放器镜像到系统通知 /
锁屏（播放、暂停、上一首 / 下一首、拖动都回调引擎，遵循同一套
队列规则）。本地歌曲不走解析：引擎直接加载文件（`loadFile`）。

```
lib/audio/
  audio_engine.dart        队列大脑（纯 Dart，ChangeNotifier）：播放
                           顺序只含可播曲目（到处跳过 unavailable）、
                           顺序/随机/列表循环/单曲循环、失败跳歌与
                           连续失败保险丝（连败数达到可播总数即停，
                           不无限循环）、错误经 errors 流弹 snackbar；
                           本地曲目（Track.localPath）直读文件
  player_backend.dart      播放器抽象（load/loadFile/play/pause/seek/
                           状态流），引擎只依赖它，单测用 fake 替换
  just_audio_backend.dart  just_audio 实现；在线曲目带 cacheDir 时走
                           LockCachingAudioSource 边播边缓存（按
                           track id 命名，签名 URL 变化不影响命中）
  engine_factory.dart      条件导出（同 plugin_host 先例）：IO 平台
                           用 real（建播放器 + AudioService.init，
                           通知频道 club.easymusic.easymusic.audio；
                           服务起不来时退化为纯应用内播放），Web 用
                           stub 返回惰性引擎，截图构建不受影响
```

Android 侧：MainActivity 继承 `AudioServiceActivity`，
AndroidManifest 已声明 AudioService / MediaButtonReceiver 与
INTERNET、WAKE_LOCK、FOREGROUND_SERVICE(_MEDIA_PLAYBACK) 权限，
外加本地音乐的 READ_MEDIA_AUDIO（旧系统 READ_EXTERNAL_STORAGE ≤32）。
`<application>` 另设 `android:usesCleartextTraffic="true"`：插件返回的
流地址由插件决定，网易云插件给的是 http:// 明文 CDN 地址，Android 9+
默认拦截明文会让 ExoPlayer 每首加载都失败（真机实测踩过）；本应用是
插件驱动的个人开源播放器，故全应用放行明文。

桌面条接通：播放/暂停、上一首/下一首、随机、循环模式、进度条拖动
seek、时间、音量；手机迷你条接通：播放/暂停、下一首、细进度线。
解析/缓冲中播放键显示转圈；引擎报错经 shell 弹 snackbar（带底层
异常摘要）。点桌面条左侧或手机迷你条（按钮外区域）打开全屏播放页。

## 账号与登录（登录桥）

按插件协议实现，与桌面宿主语义一致（参考 mygo-music 的 host.go /
websignin.go）：

- 插件的登录全在 `signIn()` 里：设置 `loginMethod` 为空/qr 时走扫码——
  插件自己取二维码、自己轮询状态，宿主只负责把 `host.signInPrompt
  ({qr, text})` 展示出来（即发即弃，无表单字段、无回传）；shell 用
  一个浮层渲染二维码（qr_flutter）与状态文案，插件每次更新都会刷新
  浮层。「取消登录」会放弃宿主调用（call-id 机制保证迟到的完成回调
  不会串扰后续调用；插件内部轮询会在其四分钟期限内自行停下）。
- `loginMethod=web` 时插件调 `host.webSignIn({url, cookiesOf, until,
  userAgent})`：应用内 WebView（webview_flutter）打开登录页，宿主经
  自有平台通道读 android.webkit.CookieManager 的 Cookie 头（能读到
  HttpOnly 的 MUSIC_U，这是选它的决定性理由），`until` 名单齐了就按
  桌面规则拼 Cookie 头回 `{cookie}`；提前关页/五分钟超时即失败。
  网页登录目前只在 Android 打通 cookie 读取，其他平台请用扫码。
- 登录态就是插件存在 `host.storage` 的 `session`（见下节落盘），
  `account()` 回来后侧边栏账号行显示头像/昵称，退出走 `signOut()`。
- 登录后接通的页面：侧边栏「我的歌单」（`playlists()`，点进详情）、
  喜欢的音乐（`liked()`，分页）、每日推荐（`browse(daily)`）、收藏
  专辑（`savedAlbums()`，分页）、我的播客（`shows()` + `show()`，
  节目单可播、分页）。未登录时插件以 code `signIn` 报错，页面显示
  登录引导而不是假数据。
- 注意：宿主调用是串行的（QuickJS 单运行时），最长四分钟的登录
  轮询期间其他插件调用（首页刷新、切歌解析）会排队/失败，这是与
  桌面版相同的约束，登录完成即恢复。

登录方式在「设置」页切换（扫码/网页），写入插件设置文件并重启
宿主生效（`host.setting()` 在启动时读取）。

## 宿主存储与设置落盘

插件宿主的 `host.storage` 与插件设置不再是内存级：

- storage 落盘到应用支持目录的 `plugin_storage.json`，宿主启动时
  读入、每次 `storage.set/remove` 后串行写回（临时文件 + 改名，
  崩溃不丢上一个好版本）；登录 session、deviceId 都因此重启不丢。
- 设置落盘到同目录 `plugin_settings.json`（目前只有 loginMethod）。
- Web/截图路径保持惰性：无存储文件即内存行为，截图回放不受影响。

## 搜索、详情、本地、播放页

- **搜索页**（侧边栏搜索框/手机搜索标签）：关键词调插件 `search()`，
  歌曲/歌单/专辑/歌手/节目五类分段切换，歌曲点行以结果为队列播放，
  其余点进各自详情；输入时有 `suggest()` 联想词；分页「加载更多」；
  加载/空/失败态齐全。
- **详情页**：歌单（含榜单）、专辑、歌手（热门歌曲 + 专辑）、节目
  （单集列表）四种，统一骨架——大封面头部 + 播放全部 + 歌曲列表，
  数据走插件 `playlist()` / `album()` / `artist()` / `show()`。
- **本地音乐**：先查权限（Android 13+ READ_MEDIA_AUDIO，以下为存储
  读权限；被永久拒绝时引导去系统设置）。歌曲来源优先 MediaStore
  （MainActivity 的平台通道查询标题/歌手/专辑/时长/路径，鸿蒙的
  Android 层同样有 MediaStore）；MediaStore 为空时退化为目录扫描
  （Music / Download / 共享存储浅层，跳过隐藏与 Android 目录），
  用 audio_metadata_reader 读标签，无标签时以文件名兜底。点行走
  同一引擎播文件。同名 `.lrc` 会被读出，在播放页显示。
- **全屏播放页**：点播放条/迷你条进入——大封面、歌名/歌手、可拖
  进度与时间、全套走带控制（播放/暂停/上下首/随机/循环），以及
  定时歌词：在线歌曲走插件 `lyrics()`（逐字行或 LRC 都归一化），
  本地歌曲读同名 `.lrc`；当前行高亮并自动滚动。

## 网络权限白名单

宿主 fetch 桥按插件 `plugin.json` 的 `permissions.network` 校验目标
域名（条目覆盖自身及其子域名），未声明的域名直接拒绝并返回明确
错误（`插件没有访问 X 的网络权限`）；webSignIn 的 cookiesOf 同样要
落在声明范围内，与桌面宿主的 checkWebSignIn 一致。已用网易云插件
的全部真实流量在线验证过：声明的两个域名足够，拦截不误伤。

## 结构

```
lib/
  main.dart                  正式入口：PluginHomeRepository（真实宿主）
                             + 真实音频引擎（engine_factory 构建）
  main_shot.dart             截图入口：CaptureHomeRepository（回放抓取数据）
  plugin_host.dart           条件导出：IO 平台用真实 QuickJS 宿主，Web 用桩
  plugin_host_real.dart      QuickJS 宿主：fetch（带网络白名单）/timer/
                             storage（落盘）/signInPrompt/webSignIn 通道
  plugin_host_stub.dart      Web 桩（QuickJS 依赖 dart:ffi，Web 不可用）
  plugin/sign_in.dart        登录桥类型（SignInPrompt/WebSignInRequest/
                             Cookie 头规则）与提示浮层状态控制器
  audio/                     音频引擎（见上节）
  data/
    models.dart              插件返回形状的模型（Track/PlaylistItem/
                             AccountInfo/各类 Detail/SearchResults…）
    home_repository.dart     HomeRepository 抽象（全部页面 API，默认
                             诚实空答）+ 插件实现（兼 StreamResolver）
    stream_resolver.dart      StreamResolver 接口 + ResolvedStream
    capture_home_repository.dart  截图回放实现（首页 + 榜单 + 热歌榜详情）
    json_file_store.dart     storage/设置共用的 JSON 落盘（临时文件改名）
    lyrics.dart              定时歌词模型 + LRC 解析（插件与本地共用）
    local_music.dart         本地音乐：权限、MediaStore 通道、目录
                             扫描兜底、.lrc 读取
  ui/
    theme.dart               MyGo 浅色调色板 + 尺寸常量
    shell.dart               双版式外壳，持有首页加载、账号状态、
                             登录流程、webSignIn 呈现与登录浮层
    sidebar.dart             侧栏（窄窗 <720 自动变 64 图标条）：导航、
                             我的歌单（真实数据）、账号行（头像/昵称）
    home_page.dart           首页
    library_pages.dart       每日推荐/喜欢/收藏专辑/排行榜/我的播客
    search_page.dart         搜索页（联想词 + 五类结果 + 分页）
    detail_pages.dart        歌单/专辑/歌手/节目详情页与打开入口
    local_page.dart          本地音乐页（权限对话 + 扫描 + 列表）
    now_playing_page.dart    全屏播放页（大封面/进度/走带/歌词）
    settings_page.dart       设置（兼手机「我的」）：账号、登录方式、关于
    web_signin_page.dart     网页登录页（WebView + Cookie 轮询）
    sign_in_overlay.dart     扫码登录浮层（二维码 + 状态 + 取消）
    player_bar.dart          桌面播放条（点左侧进播放页）
    mini_player_bar.dart     手机迷你播放条（点条身进播放页）
    mobile_tab_bar.dart      手机底部标签栏（与侧栏共用页面状态）
    placeholder_page.dart    占位/空状态页（现仅私人 FM）
    widgets.dart             封面、歌单/专辑卡、歌手/节目行、歌曲行、
                             列表组件（TrackRows）、通用状态视图
assets/
  bootstrap.js               宿主 JS 桥接垫片：fetch/timers/crypto/
                             storage/signInPrompt/webSignIn
  plugin/                    网易云插件（index.js + plugin.json，原样）
  fonts/                     Noto Sans CJK SC（系统字体提取，截图与无 CJK
                             字体环境用；正式版可按平台再议去留）
  capture/                   截图抓取数据（home_capture.json + covers/），
                             仅 main_shot 读取，正式入口不读
test/
  audio_engine_test.dart     引擎队列逻辑单测（fake 后端/解析器）：
                             next/prev 绕回、四种模式、跳过
                             unavailable、失败跳歌、连败保险丝、本地
                             文件播放（不经解析器、失败跳歌、无解析
                             器也能播本地队列）
  models_test.dart           新模型解析、LRC 解析、目录扫描兜底单测
  host_storage_test.dart     落盘往返、网络白名单匹配、Cookie 头规则、
                             登录提示控制器，以及真实宿主上的存储
                             跨重启、fetch 拦截、webSignIn 往返
  capture_home_test.dart     抓取工具（非 CI 测试）：真实跑一遍插件，
                             把首页数据与封面落盘到 assets/capture/
```

## 跑法

环境见 `../DEV_ENV.md`（先 `source ~/.bashrc`）。

```bash
cd ~/workspace/easyMusic/app
flutter pub get
flutter analyze            # 应为 No issues found
# 全量测试（宿主类测试需要 flutter_js 的 .so 在加载路径上）
LD_LIBRARY_PATH=$HOME/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared \
  flutter test             # 44 个：引擎 19 + 模型/扫描 10 + 宿主 14 + 抓取 1
flutter build apk --debug  # 正式入口（真实插件数据，需要可达的网络）
```

## 重出截图

```bash
# 1. 抓真实数据 + 封面（QuickJS 的 .so 需要在加载路径上）
LD_LIBRARY_PATH=$HOME/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared \
  flutter test test/capture_home_test.dart
# 2. 构建截图版 Web（入口换成回放，UI 代码与正式版同一份）
flutter build web --target=lib/main_shot.dart --no-web-resources-cdn
# 3. 起静态服务后用 Playwright 截图（脚本在 ../spike-ui-shot/）
(cd build/web && python3 -m http.server 8931 &)
(cd ../spike-ui-shot && node shot-home.mjs)   # 写 ../home-ui.png
(cd ../spike-ui-shot && node shot-home-mobile.mjs)   # 390×844 → ../home-ui-mobile.png
```

为什么要回放：QuickJS 走 dart:ffi，Web 构建跑不了；且无头浏览器直连
封面 CDN 不通。回放数据是第 1 步从真实插件调用抓下来的（含封面原图），
不是编造的。

## 已知缺口与真机待验

本机无声卡无模拟器、且登录要真人账号交互，下列只能在真机验
（2026-11-08 本轮交付时全部未验）：

- **登录全流程**：扫码（网易云 App 扫浮层二维码、状态文案刷新、
  确认后侧边栏变登录态、歌单同步）、网页登录（设置里切换后打开
  登录页、Cookie 读到 MUSIC_U 后自动完成）、退出登录、重启后
  登录态仍在（落盘生效）
- **搜索点播**：五类结果、联想词、分页；**详情页**：歌单/专辑/
  歌手/节目打开与播放全部
- **本地音乐**：权限弹窗与拒绝路径、MediaStore 列表与点播、
  放歌到 Music 后重扫可见
- **播放页**：大封面/进度拖动/歌词滚动高亮（在线与本地各一首）
- **音频引擎本体**：出声本体已在此前版本真机修复明文拦截后待复测；
  锁屏/通知控制、后台播放、耳机线控、缓存命中同样待复测确认；
  音频焦点/打断（来电、其他应用抢占）只做了 audio_session 的
  music 预设，未逐项验。引擎报错提示现带底层异常摘要，复测再
  失败时可直接看 snackbar 定位

其余已知缺口：

- 网页登录的 Cookie 读取只打通了 Android（自有通道读
  android.webkit.CookieManager）；iOS/桌面请用扫码登录
- 私人 FM 仍是占位：它要按口味持续接歌，交互与歌单不同，留待后续
- 插件加载仍是 spike 的去 `export` 方案，只适用于无 import 的单文件插件
- iOS/macOS/Windows 未实测（音频引擎的 Android 配置已齐，iOS 需在
  Xcode 侧开 Background Modes → Audio）
