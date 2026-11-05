# iPhone 安装：Windows 免费测试路线

支持 iOS 17 及更新版本。**IPA 未签名，必须经你电脑上的 AltServer / AltStore Classic 使用你的 Apple 账号重新签名安装。Safari 下载文件后直接点击不会完成安装。** 当前不是 App Store 或 TestFlight 版本。

## Windows 首次准备

1. 按 [AltStore Classic Windows 官方说明](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 安装其要求的 Apple iTunes、iCloud 和 AltServer。请通过官方页面的下载链接获取，所需版本以官方文档为准。
2. 用数据线连接 iPhone，解锁并选择信任电脑。在 iTunes 中确认能识别手机，并开启 Wi-Fi 同步。
3. 运行 AltServer，在 Windows 系统托盘选择 Install AltStore → 你的 iPhone。
4. Apple 账号、密码和验证操作只在你自己的 AltServer/Apple 登录界面完成；不要发送到聊天或存入 GitHub。
5. 手机上按提示信任开发者，在「设置 → 隐私与安全性 → 开发者模式」开启并完成系统要求的重启确认。

## 安装汉字音典

1. 在 iPhone Safari 打开 [本仓库 Releases](https://github.com/ghehyoein/MCPDict-iOS/releases)，找到最新的 **iPhone development build**，展开 Assets，下载 `MCPDict-iPhone-unsigned.ipa` 到「文件」App。不要下载模拟器 ZIP 或数据数据库作为安装包。
2. 保持 Windows AltServer 运行，并让手机和电脑连接同一可信网络；首次可继续连接数据线。
3. 在 AltStore Classic 的 **My Apps** 页面点击 **+**，选中刚下载的 IPA，等待签名和安装。
4. 打开「汉字音典」，进入「字表」取得上游目录。可按地图集二分区、音典分区、行政区划或语言点选择，再点击「字表下載」。本试验版没有内置字表，目录直接来自安卓项目 GitHub，当前约 3,308 份。请保持 App 在前台，完成后可离线查询。
5. 测试「中」和语言「普通話」，应能看到对应的两个读音；显示格式由声调设置决定。测试「输」会出现「输」「輸」字形选项。

勾选已下载字表后点击「字表移除」才会移除；「字表下載」只下载或更新选中项，保留其他已下载字表。取消下载会保存此前完整下载并校验的字表，请等待索引保存完成。收藏独立保存。查询只覆盖已下载字表，同一字表在不同分类中选择只下载一份。独立数据库和合并索引的磁盘占用大于原始下载文件；暂不包含通用汉字/字书基础库。

在「設定 → 顯示語言」可切换简体中文与繁體中文；界面会立即更新，字表原始汉字、读音和注释不改写。查询结果和字表列表中的语言点名称均可点开查看完整档案。

## 续签与限制

AltStore 官方说明：免费账号安装的 App 通常 7 天后过期，需要通过 AltServer 刷新；免费侧载有同时激活数量限制。请在过期前进入 My Apps 使用 Refresh All，并保持电脑 AltServer 可连接。参见 [AltStore 使用与续签说明](https://faq.altstore.io/altstore-classic/your-altstore)。

这一步不要求加入 Apple 付费开发者计划，但仍需有效 Apple 账号、成功的本地签名以及手机上的信任/开发者模式。请使用同一账号和应用标识覆盖更新以保留数据；不要先删除 App，删除会移除本地收藏。

## 验证范围

云端验证真机编译、Mach-O arm64 与 iOS 设备平台、IPA 布局，并输出 SHA-256。设备签名、安装和真实手机上的运行效果，仍需在你的 iPhone 完成后确认。当前 App 直接获取安卓项目上游目录与字表，不依赖本仓库的数据发布工作流。
