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

## 续签与限制

AltStore 官方说明：免费账号安装的 App 通常 7 天后过期，需要通过 AltServer 刷新；免费侧载有同时激活数量限制。请在过期前进入 My Apps 使用 Refresh All，并保持电脑 AltServer 可连接。参见 [AltStore 使用与续签说明](https://faq.altstore.io/altstore-classic/your-altstore)。


