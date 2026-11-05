# 漢字音典 iOS 試作

目标是逐步移植汉字音典，先完成稳定的数据与查询闭环。数据直接来自 [osfans/MCPDict](https://github.com/osfans/MCPDict) 的 GitHub 字表，经 Python 构建 SQLite；本工程没有读取、解包或下载 APK。

**这是开发初版，不是已经完成全部功能或通过真机验收的 iOS 成品。** Windows 本地验证 Python；iOS 的编译、模拟器测试交给 GitHub Actions 的 macOS runner。2026-11-05 首次云端检查已全部通过：4 项 Python 测试、iOS 编译及 3 项 XCTest。现在不需要 Apple 付费开发者账号，也没有配置签名、TestFlight 或 App Store 发布。

仓库：[ghehyoein/MCPDict-iOS](https://github.com/ghehyoein/MCPDict-iOS)。[首次通过的完整运行记录](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/41994679817)，对应代码提交 `ac11ed2cb58baeabb5079773d7f544ce18495094`。

## Python 和 Swift 各自负责什么

| 部分 | 语言 | 文件 |
|---|---|---|
| 上游字表解析、规范化、数据库生成 | Python（调用上游脚本） | `tools/data_pipeline.py` |
| 数据完整性校验、SHA-256、版本清单 | Python | `tools/data_pipeline.py` |
| 查询参考实现与命令行 | Python | `tools/query.py` |
| Windows 本地查字测试界面 | Python / Tkinter | `tools/preview.py` |
| 数据测试 | Python unittest | `tools/test_pipeline.py` |
| iPhone 界面、离线 SQLite 读取、下载切换、收藏 | Swift / SwiftUI | `App/` |
| iOS 查询、更新失败保留旧连接测试 | Swift / XCTest | `Tests/` |

Python 负责可复用的数据生产和参考实现；手机内不嵌入 Python 解释器。手机离线使用系统 SQLite，避免第一版引入解释器和额外打包依赖。Python 测试界面用于 Windows 开发，不代表 iOS 界面。

## 已实现的初版功能

- 汉字查询、多字 OR 查询、`U+4E2D` 查询。
- 原始读音与注释的 FTS5 词项查询、单语言筛选、每次加载 100 条。
- 如实显示同音字组，未把每行误认为单个汉字。
- 收藏查询结果快照、个人笔记，独立文件保存；更新词典不覆盖收藏。
- 更新按钮、可选启动检查、下载取消、大小/SHA-256/SQLite/字段/FTS5 验证。
- 下载到新文件，验证后原子更新当前指针；失败保留旧库，成功后保留上一份文件。
- GitHub 自动数据构建及 iOS macOS 编译/模拟器测试工作流。

尚未完成：繁简及异体字自动扩展、完整音韵/拼音转换、形码/部首/笔画查询、字书详情、离线地图、双向矩阵、猜字练习、扩展字体、收藏导入导出、后台下载、百分比进度、旧版本手动回退界面。未宣称与 Android 全功能或全部结果完全一致。

## 现在在 Windows 上试查

安装 Python 3.12 或更新版本（包含 Tcl/Tk）。查询界面只使用标准库，无需安装构建字表的依赖。

在本工程目录打开终端：

```powershell
py -3 tools/preview.py sample-data/mcpdict.db
```

也可以双击 `启动Python查字.cmd`。若本地没有 `sample-data/mcpdict.db`，先从自己的数据 Release 下载 `mcpdict.db`，或按下文构建；可以把数据库路径直接传给脚本。

当前电脑的工程目录已附真实数据库。启动脚本优先使用 `py`，未安装时会尝试此电脑已有的 Python 运行时。仅源码压缩包不含约 484 MB 的数据库；需要保留或另行拷贝 `sample-data/mcpdict.db`。实际测试范围见 `VALIDATION.md`。

命令行查字与测试：

```powershell
py -3 tools/query.py sample-data/mcpdict.db 中 --language 普通話
py -3 tools/query.py sample-data/mcpdict.db zhong1 --mode pronunciation --language 普通話
py -3 -m unittest discover -s tools -p "test_*.py" -v
```

读音必须用数据库原始格式。简体字不一定自动匹配繁体字；没有结果时请尝试原始字形。部分语言使用 IPA。生僻字的显示还取决于系统字体。

## Windows 写代码，GitHub macOS 编译 iOS

1. 在你的 GitHub 账号创建一个代码仓库，将本目录的源码上传。务必包含隐藏目录 `.github/workflows`，不要把大数据库提交到 Git。
2. 打开仓库 **Actions → Check iOS and Python → Run workflow**，或推送代码触发检查。
3. 工作流安装 XcodeGen、生成 Xcode 工程、编译模拟器版本、运行 XCTest，再上传测试报告和模拟器 `.app`。
4. 红色失败时查看失败步骤日志；修改后重新推送。先以持续通过编译和自动测试为目标。

GitHub runner 提供 macOS/Xcode 环境；它不是 Windows 上的交互式 iPhone 模拟器。下载的 `SimulatorApp.zip` 不能直接装到 iPhone，也不能在 Windows 上运行。后续稳定后再接入 Apple 开发者账号和签名。

工作流已在此仓库实际执行并通过，运行页面的 Artifacts 包含测试报告和模拟器应用包。后续代码推送将自动运行检查，也可手动运行。仅文档更新可在提交消息注明 `[skip ci]`，避免重复构建。GitHub Actions 的可用额度和费用遵循账号设置。

相关官方说明：[GitHub 托管 runner](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners)、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

## 配置直接从 GitHub 字表更新

1. 在同一个代码仓库中，打开 **Actions → Build dictionary from GitHub source → Run workflow**。
2. 它锁定上游 `master` 的完整提交 SHA，下载该提交，使用上游 Python `make.py -c -i` 构建，不生成 APK。
3. 全部校验成功后发布不可变的版本数据 Release，再更新 `data-latest` 中的发现清单。若构建失败，原有发布不会被替换。
4. iOS「资料」页填写下面格式的网址（替换为你的用户名与仓库名）：

```text
https://github.com/你的用户名/你的仓库/releases/download/data-latest/manifest.json
```

5. 点击「检查更新」再点「更新资料」。以后无需重装 App 即可更新兼容结构的数据。

当前开发阶段只开放手动构建数据，尚未启用定时发布。待编译和测试稳定后，再配置每天检查上游。同一上游提交不重复构建。手机启动时只检查，下载仍由用户触发。初版前台整库下载，不压缩、不做差分，需预留约两倍新库大小加 100 MB 的空闲空间；旧库另外占用空间。

初版下载器支持可公开访问的 GitHub Releases，没有私有仓库鉴权。请勿把访问令牌写进 App。源码已上传仓库，数据 Release 尚未构建或发布，更新网址目前还不能下载数据。上游代码许可不自动覆盖每一份字表的再分发许可，公开发布数据前应保留并核对上游来源说明。

## 手动使用 Python 构建

以下步骤在本工程根目录执行。首次构建会读取大量表格，可能耗时较长：

```text
git clone https://github.com/osfans/MCPDict.git data-build/upstream
python -m venv .venv
```

激活虚拟环境后运行：

```text
python -m pip install -r tools/requirements-build.txt
python tools/data_pipeline.py --checkout data-build/upstream --repository YOUR_NAME/YOUR_REPO --output dist
```

`YOUR_NAME/YOUR_REPO` 只用于生成真实部署后的 Release 地址，本地打包不会自动上传。输出包括 `mcpdict.db`、`manifest.json`、`validation.json`。清单内的地址只有在对应 Release 发布后才可下载。

构建依赖固定为此次验证的版本；上游新增依赖时需主动更新并重新验证，避免无提示地随依赖发布改变构建结果。上游源码本身按每次构建的提交 SHA 锁定。

## 稳定性与后续顺序

1. 先让 GitHub iOS 编译和测试通过，记录 Xcode 和 runner 版本；当前工作流使用 `macos-latest`，稳定后可固定环境。
2. 扩充 Android 对照样例，验证多音字、异体字、IPA、语言排序；目前只验证明确支持的查询子集。
3. 加入断网、取消、磁盘不足、损坏数据库、App 重启恢复的设备集成测试。
4. 移植 OpenCC 与音韵转换，再加入字书/形码、矩阵、地图和练习。
5. 软件稳定后才处理签名、真机分发和开发者账号。

更新验证的边界：SHA-256 检查传输和文件一致性；清单来自用户配置的 HTTPS GitHub 源，没有额外数字签名。当前没有完整更新故障注入测试，也没有真机性能结论。上游构建可能输出缺失字表或格式警告，生成成功并不代表源资料没有问题。
