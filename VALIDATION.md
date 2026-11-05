# 0.3 地图实现范围（2026-11-05）

- 上游字表目录 3,308 份，其中 3,295 份有有效经纬度；13 份缺少坐标，不放点。
- 经纬度按上游「经度,纬度」解析，检查有限数值与范围；没有自行推测地点或转换坐标基准。
- 无 MapTiler key 时使用 MapKit，有 key 时使用 MapLibre GL JS 5.6.1 + MapTiler Streets v4；API key 由用户在设备设置填写，没有沿用网站的密钥。
- 原生系统地图与 MapLibre 都提供点位聚合；支持一级分区筛选、各级区域关键词、已下载筛选、点位详情、全览和单字读音分布。
- 目录独立缓存；读音图只查已下载表，覆盖全部分页。没有离线底图包，也未移植网站的全部筛选和服务器功能。
- 参考前端的 MIT 许可和渲染库许可证包含在 App/MapWeb。运行时 JS 在 App 内，构建时下载验证固定 SHA-256。
- [最终 CI 42019063409](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42019063409)：7 项 Python 测试、9 项 iOS 测试全部通过，本轮没有跳过联网测试；实际下载普通话约 4.485 秒，WKWebView 地图测试约 9.586 秒。
- 最终应用提交 e0fc3c03def48f6ed5da428d11bb6f7a194c7a53，0.3.0 / build 7；[真机编译 42019063253](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42019063253) 成功。
- IPA 744,735 字节，SHA-256 `470314c979ee33a5dc82ba18de12507404cfc9f6dc77cb6cf106ed44e94e557e`；重新下载后校验一致，地图脚本、样式和许可证完整，无内置字表。
- 中间提交 74373a7 的地图测试通过，但联网字表测试收到 GitHub 限流。随后将 HTTP 429 或 HTTP 403 且 X-RateLimit-Remaining=0 单独分类；CI 仅在该明确外部限流条件下标记联网测试跳过，其余网络或解析错误仍报失败。
- 第一轮提交 647605141843e849273bf216ef1c45c4d1e0eda6：[CI 42017664792](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42017664792) 的 7 项 Python、9 项 XCTest 全部通过。
- 新增地图测试覆盖经纬度顺序和非法坐标拒绝、135 个语言点的完整查询、真实 WKWebView 中 MapLibre 初始化及点位添加/清空。无 key 渲染测试耗时约 3.763 秒。
- 未验证：用户 MapTiler key 的街道瓦片权限、额度和实际网络表现；iPhone 上的手势、密集点位性能及地图视觉布局仍需试用。

# 0.2.0 / build 4 验证（2026-11-05）

- 应用提交：a873c1d21415c5d6bd4d85a463bee3ed4cff3dfb。
- [CI 42012883035](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42012883035)：7 项 Python 测试、6 项 XCTest 全部通过，0 failures，模拟器编译通过。
- 模拟器直接从 osfans/MCPDict 获取上游目录，下载普通话 TSV，验证 Git blob、转换 SQLite，查询“中”只得到“中”的 zhong1 / zhong4。联网测试约 4.839 秒。
- 回归覆盖旧同音字组的单字显示、读音检索仍返回同音字、Unicode 扩展字、坏哈希拒绝、旧数据恢复及删除。
- 本地逐行检查固定上游提交 d88e3bcaff6f17399a33bc3010794ed1c2dd707e 的 3,308 份带元数据 TSV，没有缺失汉字或读音列的记录；这不是所有字表的内容正确性或真机性能验证。
- [真机编译 42012882982](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/42012882982)：arm64 / iPhoneOS，通过打包校验，最低 iOS 17，无内置数据库。
- [下载 build 4](https://github.com/ghehyoein/MCPDict-iOS/releases/tag/iphone-dev-4-a873c1d)：390,885 字节；SHA-256 `6b92d1ecfced826c094b90540e0e39173ad5a6a3873468b4985aec2ecd8c02ac`。公开下载后重新校验一致。
- 图标复用上游 app/src/main/ic_launcher-playstore.png（同一固定提交），macOS 构建时调整到 1024 像素；保留上游许可证。
- 语言页的三种分区和设置外观已编译通过；尚未进行 iPhone 实机布局、外观切换及大批量下载性能验收。IPA 仍需本机签名安装。

以下为历史版本记录，三表目录限制不适用于 0.2。

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

