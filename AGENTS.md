# Tricko 项目交接

本项目是原生 SwiftUI 视频播放器，支持本地视频、在线视频链接和短码，并提供剪辑和复盘工具。最低 iOS 17，工程与共享 Scheme 均为 `Tricko`。Duo 布局使用 iOS 27.1 SDK。后续状态以本项目的代码、配置和新验证记录为准。

## 业务与服务配置

- 业务沿用 Clipo。首页保留视频链接和短码输入，通过 `search-check` 进入可纵向切换的全屏播放器。游客登录、推荐、收藏、离线播放、额度、开屏与激励广告、订阅和恢复购买继续走原有路径。订阅权益由服务端校验。视频和音频导出免费，导出在线视频需要下载素材时按现有下载额度处理。
- API 为 `https://lvtppgv.tricko.website`，`getV2.name` 为 `Tricko`，取自 `TRICKO_RELEASE_NAME`。`Config/Tricko.xcconfig` 的打包 Bundle ID 和应用内游客登录 `source` 及业务 `packageName` 均使用 `com.trickostudio.videodesk`。
- AdMob App ID 为 `ca-app-pub-4423220037289714~3524842188`。开屏和激励广告位由 `getV2.adList` 下发，分别对应 Google 的 `adType=1` 和 `adType=5`。公开入口采用 [官网](https://www.tricko.website)、[用户协议](https://www.tricko.website/terms.html) 和 [隐私政策](https://www.tricko.website/privacy.html)。
- Plus 商品 ID 以 `Tricko/Resources/Commerce.json` 为准，月付为 `com.trickostudio.videodesk.plus.monthly`，年付为 `com.trickostudio.videodesk.plus.yearly`。会员页先展示标明币种的美国参考价，确认购买前显示 Apple 商店的实际价格和账期。
- 播放联调使用当前 API 环境可用的链接或短码，在首页手动输入。
- 核对后台发布记录时使用 `getV2.name=Tricko` 和业务包名 `com.trickostudio.videodesk`。待确认订单保留原订单的主机和账号归属。

## 本项目的原创界面

- 首页顶部可输入视频链接或短码，下方可从「文件」或「照片」导入并进入本地编辑器，也可重新打开最近导入的视频。编辑器提供播放、进度拖动、裁剪、画幅、速度、音频和导出。
- 首页、资料库、工具由根 `TabView` 承载。iOS 26 起使用纯图标 Liquid Glass 底栏，VoiceOver 提供本地化名称。自有页面隐藏状态栏，前景控件按设备安全区布局。首页顶部的个人图标打开账号和设置。全屏播放器关闭后回到打开它的页面，下载完成提示的「查看」打开资料库的离线分类。
- **首页与工具**。首页以「播放器」为标题，视频浏览入口使用紧凑的播放图标和文字。最近导入以实际视频帧横向排列。工具页可从文件或照片直接导入，已有导入时，编辑器入口显示最近视频的首帧和文件名，调速、画幅和提取音频也可直接打开这段视频。
- **设置**。首页头像和工具页右上角的设置按钮打开同一页面。Plus、语言、官网和隐私条款位于每日额度与游客账号信息上方。
- **资料库**。默认显示导入视频，后续分类为导出、收藏和离线。导入和导出用本地视频帧组成封面网格，空库引导从文件或照片导入。顶部的玻璃按钮打开 Plus。实现见 `Tricko/Features/LibraryView.swift`。
- **Plus 会员页**。页首直接展示会员状态或可选方案，浅色选中项显示金额和账期。会员权益为免开屏广告、无限观看和下载支持离线的视频。首页、资料库、工具、账号和额度提示均可打开会员页。剩余次数在账号与相关使用场景展示，额度用完可在相应提示中观看激励广告。实现见 `Tricko/Features/MembershipView.swift`。
- **免费编辑功能**。视频和音频均可免费导出。完整视频编辑器提供两种免费复盘预设和一份可更新的本地自定义预设，应用时保留当前视频的裁剪起止点。
- 后续 UI 工作按全局 UI 技能约定使用 `ui-design-reference`、`ui-taste` 和适用的原创素材工作流。iOS 适配按 Duo 约定，保留当前 SwiftUI 和各主题的交互设计。

## 交付时的验证状态

- 已静态核对本地视频入口、三个 Tab、账号入口、本地视频复盘和播放器返回路径。
- 待运行验证的事项包括编译、模拟器和真机显示、Duo 布局、正式后台返回、短码播放、广告以及 Apple Sandbox 购买与恢复。按用户约定，默认只做静态核对，编译和测试在用户明确要求时执行。
