# 漢字音典 iOS · 按需下载试验版

数据直接来自 osfans/MCPDict 的 GitHub 字表，经 Python 构建，不读取或提取 APK。当前目标是验证 iPhone 安装、分类目录、独立字表下载和离线查询，并非 Android 版完整复刻。

## 安装到 iPhone

支持 iOS 17+，本次目标为 iPhone 13 / iOS 26。到本仓库 Releases 选择最新 iPhone development build，下载 MCPDict-iPhone-unsigned.ipa。IPA 未签名，须通过 Windows AltServer / AltStore Classic 使用自己的 Apple 账号签名安装，不能在 Safari 下载后直接点开。详见 [INSTALL-IPHONE.md](INSTALL-IPHONE.md)。

## 不内置字表

首次安装没有词典内容。进入「資料」取得小型目录，选中字表后点击「套用選擇」。本试验目录仅有普通話、廣州、杭州三份真实字表，合计约 2 MB；不是上游完整目录，也没有通用汉字/字书基础库。

支持地图集二分区、音典分区、行政区划（省、市、县、镇、村等逐级选择）以及字表名称检索。可以选取一个分类的全部试验字表，也可单独选择某表。分类只是同一字表的不同入口，稳定 ID 去重，不会重复下载。

页面显示需下载大小和将移除的字表数量。取消勾选已下载字表，再套用选择，会移除该表。查询只覆盖已下载字表，收藏和笔记独立保存。确认下载架构后再扩展完整目录和默认内置字表。

## 数据与稳定性

Python data_pipeline.py 使用上游 make.py -i 从固定提交构建整库；build_table_catalog.py 再提取独立 SQLite 字表包，保留同音字组、读音、注释、语言元数据和 FTS5 配置。每份字表记录稳定 ID、分类、来源提交、大小、记录数、SHA-256 和不可变 Release 地址。

iOS 下载并校验所选包，复用相同哈希的已有包，再在临时数据库建立合并查询索引，成功后原子切换本地指针。下载、校验或建立索引失败保留旧数据；成功切换后清理未选择的字表。

当前同时保存独立包和一份合并查询库，磁盘占用大于网络下载量，操作前要求约三倍所选包大小加 30 MB 可用空间。需要保持 App 在前台，显示处理阶段与字表进度，没有后台下载或字节百分比。上游简称变化会成为新字表，改名迁移需后续处理。

[试验目录 catalog.json](https://github.com/ghehyoein/MCPDict-iOS/releases/download/tables-latest/catalog.json)

## GitHub Actions

- Check iOS and Python：Python 测试、工程生成、iOS 编译与模拟器 XCTest。
- Build iPhone IPA for local signing：真机编译，检查 Mach-O 的 arm64/iOS 平台，打包并发布待本地签名 IPA。
- Build dictionary from GitHub source：构建并验证上游整库，发布清单和源数据诊断。
- Publish experimental downloadable tables：从已验证整库提取三份独立字表，发布包和目录。

代码推送会运行 iOS 检查，App 或真机打包文件变化会生成新的真机包。数据和目录工作流支持手动运行，也在各自构建文件变更时运行，尚未启用每天定时更新。上游更新后，先手动运行整库流程，成功后运行字表目录流程。

首次基础版本的 [成功记录](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/41994679817)。后续按需下载版本以 Actions 对应提交为准。实际验证范围见 [VALIDATION.md](VALIDATION.md)。

## Python 优先

Python 负责数据构建、字表拆分、目录清单、参考查询、Windows 测试界面、图标生成、IPA 验证和打包。Swift 负责 iPhone 原生界面、SQLite 查询、下载与数据切换。手机内不嵌入 Python 解释器。

Windows 安装 Python 3.12+ 后可运行：

```powershell
py -3 -m unittest discover -s tools -p "test_*.py" -v
py -3 tools/preview.py sample-data/mcpdict.db
```

Windows 界面是独立的完整开发快照查字工具，不代表 iOS 的下载界面。本地工程目录附有快照，Git 仓库不提交大型数据库。

手动构建完整数据（在 Python 虚拟环境中）：

```text
git clone https://github.com/osfans/MCPDict.git data-build/upstream
python -m pip install -r tools/requirements-build.txt
python tools/data_pipeline.py --checkout data-build/upstream --repository ghehyoein/MCPDict-iOS --output dist
```

上游构建可能报告源文件缺失或格式警告，生成成功不代表资料无误。字表来源和许可需要独立核对，上游 MIT 代码许可证不自动覆盖全部数据。

## 功能边界

基础汉字、多字、Unicode、原始读音与注释查询、语言筛选、分页、收藏、笔记和按需字表管理已写入。

尚未移植：繁简/异体字、复杂音韵/拼音转换、形码/部首/笔画、字书详情、矩阵、离线地图、猜字/猜方言、扩展字体、收藏导入导出。行政分类是字表选择入口，不是离线地图。

真机签名、安装和使用效果仍需在你的 iPhone 上确认。当前是开发测试包，不是 App Store 或 TestFlight 成品。
