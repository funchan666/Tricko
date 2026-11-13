# Tricko 项目交接

本项目是魔术教学视频 App。使用原生 SwiftUI，最低 iOS 17，工程与共享 Scheme 均为 `Tricko`。本文件记录 2026-11-13 的交付和用户确认的约定。后续状态以本项目的代码、配置和新验证记录为准。

## 业务与测试约定

- 业务沿用 Clipo。首页保留课程链接和短码输入，通过 `search-check` 进入可纵向切换的全屏播放器。游客登录、推荐、收藏、离线播放、编辑导出、额度、开屏与激励广告、订阅和恢复购买继续走原有路径。订阅与媒体导出保留服务端权益校验。
- 当前是测试配置。API 为 `https://devapi.io-jp.com`，`getV2.name` 为 `Tricko`，取自 `TRICKO_RELEASE_NAME`。Bundle ID 为 `im.seex.lobo`，游客登录 `source` 和业务 `packageName` 同源。五包共用测试 BID，同一设备依次安装。
- 广告使用 Clipo 的 Google 官方演示 App ID 和开屏、激励广告位。测试版开屏与游客登录并行预载，冷启动最多等待五秒，展示前核对当前账户权益。官网、用户协议、隐私政策使用 HTTPS 占位链接。测试商品为月付 `coins_1.99` USD 9.99、年付 `conis_4.99` USD 99.99。会员页展示 StoreKit 返回的本地化价格和账期。
- 播放联调用 Clipo 的原测试短码，在首页手动输入。短码和广告配置见工具包的 [Clipo 基线](/Users/chengdupengyuyan/.codex/skills/toolkit/references/clipo-baseline.md) 第 1、5 节。Clipo 源工程位于 `/Users/chengdupengyuyan/Fun/Clipo`。
- 用户确认本项目测试通过后，再收集尚未提供的正式 BID、API 域名、广告 App ID 和广告位、官网、用户协议和隐私政策。切换时 Bundle ID、登录 `source` 与业务 `packageName` 一起使用正式 BID，`getV2.name` 继续用 `Tricko`。核对正式月年商品与后台订单映射。

## 本项目的原创界面

- 首页、发现的加载及空状态、练习、资料库和 Plus 使用各自的原创摄影风格上半屏背景。练习日志和魔术手记沿用各自的主题素材作页首背景。首页可看全屏课程、输入链接或短码，也可选择镜前、镜头或观众排练。记录模型在 `Tricko/Core/RoutineJournal.swift`。
- 首页、发现、练习、资料库由根 `TabView` 承载。iOS 26 起使用纯图标 Liquid Glass 底栏，VoiceOver 保留本地化名称。自有页面隐藏状态栏，前景控件按设备安全区布局。首页顶部的个人图标打开账号和设置。全屏课程关闭后回到首页，下载完成提示的「查看」打开资料库的离线分类。
- **资料库**。深色分类索引显示收藏、离线、导入、导出数量，下方是 Plus 入口和当前分类的内容。实现见 `Tricko/Features/LibraryView.swift`。
- **Plus 会员页**。上半屏背景为打开的纸牌木盒，下面并列对齐套餐名、实际金额和账期，选中项以金边标示。首页、资料库、账号页及额度和导出入口均可打开。实现见 `Tricko/Features/MembershipView.swift`，新图在 `Assets.xcassets/Illustrations/PlusBackdrop.imageset`。
- 后续 UI 工作按全局 UI 技能约定使用 `ui-design-reference`、`ui-taste` 和适用的原创素材工作流。iOS 适配按 Duo 约定，保留当前 SwiftUI 和各主题的交互设计。

## 交付时的验证状态

- 已静态核对新版首页、四个 Tab 的入口、账号入口、练习场景和课程返回路径。此前核对过资料库与会员页的语法和接线。
- 待运行验证的事项包括编译、模拟器和真机显示、Duo 布局、测试后台返回、短码播放、广告以及 Apple Sandbox 购买与恢复。按用户约定，默认只做静态核对，编译和测试在用户明确要求时执行。
