# Tricko 项目交接

本项目是以本地视频文件为主的原生 SwiftUI App，附带在线魔术课程和练习内容。最低 iOS 17，工程与共享 Scheme 均为 `Tricko`。本文件记录 2026-11-13 的交付和用户确认的约定。后续状态以本项目的代码、配置和新验证记录为准。

## 业务与服务配置

- 业务沿用 Clipo。首页保留课程链接和短码输入，通过 `search-check` 进入可纵向切换的全屏播放器。游客登录、推荐、收藏、离线播放、编辑导出、额度、开屏与激励广告、订阅和恢复购买继续走原有路径。订阅与媒体导出保留服务端权益校验。
- API 为 `https://lvtppgv.tricko.website`，`getV2.name` 为 `Tricko`，取自 `TRICKO_RELEASE_NAME`。Bundle ID 为 `com.trickostudio.videodesk`，由 `Config/Tricko.xcconfig` 定义，并派生游客登录 `source` 和业务 `packageName`。
- AdMob App ID 为 `ca-app-pub-4423220037289714~3524842188`。开屏和激励广告位由 `getV2.adList` 下发，分别对应 Google 的 `adType=1` 和 `adType=5`。公开入口采用 [官网](https://www.tricko.website)、[用户协议](https://www.tricko.website/terms.html) 和 [隐私政策](https://www.tricko.website/privacy.html)。
- Plus 月付商品为 `com.trickostudio.videodesk.plus.monthly`，年付商品为 `com.trickostudio.videodesk.plus.yearly`。会员页展示 StoreKit 返回的本地化价格和账期。
- 播放联调使用当前 API 环境可用的链接或短码，在首页手动输入。接口与广告合同见工具包的 [Clipo 基线](/Users/chengdupengyuyan/.codex/skills/toolkit/references/clipo-baseline.md)。
- 核对后台发布记录时使用 `getV2.name=Tricko` 与工程的 Bundle ID。待确认订单保留原订单的主机和账号归属。

## 本项目的原创界面

- 首页直接从「文件」或「照片」导入视频并进入本地编辑器，也可从最近导入重新打开视频。编辑器提供播放、进度拖动、裁剪、画幅、速度、音频和导出。课程链接、短码及课程浏览入口在首页下方。工具页保留练习日志和魔术手记入口，记录模型在 `Tricko/Core/RoutineJournal.swift`。
- 首页、资料库、工具由根 `TabView` 承载。iOS 26 起使用纯图标 Liquid Glass 底栏，VoiceOver 提供本地化名称。自有页面隐藏状态栏，前景控件按设备安全区布局。首页顶部的个人图标打开账号和设置。全屏课程关闭后回到打开它的页面，下载完成提示的「查看」打开资料库的离线分类。
- **首页与工具**。首页把两种导入方式放在通栏的摄像机照片下方，最近导入以实际视频帧横向排列。工具页的主入口使用剪辑控制器照片，调速、画幅和音频使用独立布局。
- **资料库**。默认显示导入视频，后续分类为导出、收藏和离线。导入和导出用本地视频帧组成封面网格，空库引导从文件或照片导入。顶部的玻璃按钮打开 Plus。实现见 `Tricko/Features/LibraryView.swift`。
- **Plus 会员页**。镜头照片延伸到页首，浅色选中项显示实际金额和账期。导出、编辑预设和免开屏广告权益优先。首页、资料库、账号页及额度和导出入口均可打开。实现见 `Tricko/Features/MembershipView.swift`。
- **Plus 权益**。会员可免开屏广告、无限观看及下载支持离线的课程、导出视频或音频。完整视频编辑器提供两种复盘预设和一份可更新的本地自定义预设。应用预设保留当前视频的裁剪起止点，保存和应用前检查当前账号的 Plus 权益。
- 后续 UI 工作按全局 UI 技能约定使用 `ui-design-reference`、`ui-taste` 和适用的原创素材工作流。iOS 适配按 Duo 约定，保留当前 SwiftUI 和各主题的交互设计。

## 交付时的验证状态

- 已静态核对本地视频入口、三个 Tab、账号入口、练习场景和课程返回路径。
- 待运行验证的事项包括编译、模拟器和真机显示、Duo 布局、正式后台返回、短码播放、广告以及 Apple Sandbox 购买与恢复。按用户约定，默认只做静态核对，编译和测试在用户明确要求时执行。
