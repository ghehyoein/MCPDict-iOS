# 音典内部 TestFlight

正式 GitHub Release 的标签决定内部测试的版本、源代码和字表快照。工作流核验标签所指提交、IPA 的 SHA-256、应用标识和构建号，重新签名编译并以 TestFlight Internal Only 上传。正式 App Store 版本的审核和发布选项由 App Store Connect 单独管理。

从 main 手动运行 [Sync GitHub release to internal TestFlight](https://github.com/ghehyoein/MCPDict-iOS/actions/workflows/internal-testflight.yml) 可同步当前最新 Release。通过原有手动工作流发布新版 GitHub IPA 后，成功结束的发布任务也会触发同步，仅当最新 Release 标签对应其提交及运行号时上传。TestFlight 版本沿用 GitHub Release，构建号为「Release 的原构建号.同步运行序号.本次尝试序号」。

Apple 处理完成并通过出口合规检查后，已配置的内部测试 组会收到新版。用受邀账号在 iPhone 的 TestFlight 中接受邀请、安装，可打开自动更新。每个测试构建有效期最长 90 天。
