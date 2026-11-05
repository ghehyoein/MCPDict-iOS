# 首次验证记录

## 按需下载试验版追加验证（2026-11-05）

- 真机 IPA：[构建 42000102179](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42000102179) 成功，代码提交 `1e2509a92fd35b4ac1142cf1704f7d261858d123`，build 2。arm64 / iPhoneOS，最低 iOS 17，212,768 字节，包内不含 `.db`。SHA-256：`bd53a2ff9c5874a310191c2d43e382d78bb3ac9f114d76cbc50f40d7b948a13b`。未签名，需本地 AltStore 签名。
- 七项 Python 测试通过：另覆盖字表独立拆分、分类元数据、哈希以及拒绝误打包模拟器二进制。
- [运行 42000812068](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42000812068) 对提交 `da0734a969aa6a34f004a8bc076d13608c34c7bc` 完成五项 iOS 测试，0 failures。该提交只追加测试，应用代码与上述 IPA 一致。
- 其中真实联网测试由 iOS 模拟器读取已公开目录、下载普通话字表、校验和建立索引，查询中得到 `zhong1`、`zhong4`，耗时约 15 秒（不含模拟器启动）。其余测试覆盖下载校验失败保留旧库、重启恢复、移除和基础查询。
- 三份公开字表均已从 Windows 下载并验证大小、SHA-256、SQLite quick_check、记录数和单一语言内容。普通話：1,699,840 字节 / 1,613 组；廣州：217,088 字节 / 1,651 组；杭州：233,472 字节 / 1,497 组。记录数是读音字组数，并非汉字数。
- 起初仓库私有导致公开下载 404，用户改为公开后已验证成功。一次普通话 CDN 下载超时重试后恢复；模拟器实际 URLSession 下载最终通过。
- 当前仅发布这三份试验字表，三种分区是对这三份字表的不同选择入口。没有默认内置字表，也没有完整目录或汉字/字书基础库。
- 尚需用户完成：Windows AltServer / AltStore 配置、Apple 账号本地签名、iPhone 13 / iOS 26 安装和实机使用。没有宣称真机安装成功。

以下是前期整库与基础版本的历史记录，不能将整库记录数视为当前试验目录的收录范围。

日期：2026-11-05。环境：Windows，Python 3.12，依赖版本见 `tools/requirements-build.txt`。

## 已实际通过

- 从 GitHub 克隆 `osfans/MCPDict`，固定提交 `d88e3bcaff6f17399a33bc3010794ed1c2dd707e`。
- 调用上游 Python `tools/make.py` 构建数据库，耗时约 528 秒；没有读取用户 APK，也没有下载 APK。
- 数据库大小：483,934,208 字节。SHA-256：`e05acb632fc5511ebf719970be3653fba61bf834f7c950607de7daa564b584ad`。
- SQLite `PRAGMA quick_check` 返回 `ok`，必要字段存在，FTS5 查询成功。
- `mcpdict`：101,999 条；`langs`：4,840,844 条；`info`：3,314 条。`info` 还包括分类与字书条目，不等于独立方言点数。
- 普通话查询：中 → `zhong4`、`zhong1`；國 → `guo2`；𰻞 → `biang2`；`U+4E2D` 与中一致。
- 4 项 Python 自动测试通过，覆盖同音字组、语言精确筛选、SQL/FTS 字面量转义、多字/Unicode、分页、清单大小与哈希、缺失字段拒绝。
- Python 全部源码通过 `compileall`。
- 隐藏窗口的 Tkinter 集成测试通过：创建真实控件、异步查真实数据库、确认结果文本同时出现 `zhong1` 和 `zhong4`。

## 资料限制

上游构建输出了「未找到 揚州同音字表.xlsx」「未找到 阳朔新嵅洲村白话.xlsx」等警告，以及部分字表字数过少、格式提示。完整输出保存在 `sample-data/upstream-build.log`；这份数据库是该提交实际可构建出的开发快照，不代表缺失资料已补齐。

本地首次构建使用 `make.py`；云端自动发布按上游流程使用 `make.py -c -i`，会启用同音字检查和额外输出，排序及哈希可能不同。二者都从 GitHub 字表生成；不把本地哈希作为后续云端构建必须相同的条件。

## GitHub macOS 实际验证

2026-11-05，在 [运行 41994679817](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/41994679817) 中，对提交 `ac11ed2cb58baeabb5079773d7f544ce18495094` 验证：

- 4 项 Python 自动测试通过。
- XcodeGen 工程生成通过，Xcode 26.6 模拟器编译 `BUILD SUCCEEDED`。
- 3 项 XCTest 全部通过，0 failures：查询契约、更新激活失败保留旧连接、拒绝不兼容清单。
- `TEST SUCCEEDED`，测试报告和模拟器应用包均已作为 Actions artifacts 上传。
- 第一轮发现数据更新页面的 SwiftUI Section 初始化写法错误，修正后运行以上完整检查通过。

## 尚未实际验证

- iOS 真机速度、内存、布局、长时间下载与断网恢复。
- 整库下载在真实 iPhone 上的使用；当前已经验证的是上述按字表下载的模拟器流程。
- 与 Android 的全功能结果一致性；当前只实现声明的基础查询子集。

因此此交付是可继续开发的初版工程与已验证的 Python 数据基础，不是已经验证稳定的完整 iOS 应用。
