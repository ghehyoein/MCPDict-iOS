# 漢字音典 iOS · 按需下载试验版

数据直接来自 osfans/MCPDict 的 GitHub 规范化字表，在 iPhone 本地建立查询索引，不读取或提取 APK。当前目标是验证 iPhone 安装、分类目录、独立字表下载和离线查询，并非 Android 版完整复刻。

当前版本 0.2：复用安卓图标；汉字查询只显示所查字；查询语言列表支持三种分区；底部设置可选浅色、深色或跟随系统。实际验证以对应提交的 Actions 和 VALIDATION.md 为准。

## 安装到 iPhone

支持 iOS 17+，本次目标为 iPhone 13 / iOS 26。到本仓库 Releases 选择最新 iPhone development build，下载 MCPDict-iPhone-unsigned.ipa。IPA 未签名，须通过 Windows AltServer / AltStore Classic 使用自己的 Apple 账号签名安装，不能在 Safari 下载后直接点开。详见 [INSTALL-IPHONE.md](INSTALL-IPHONE.md)。

## 不内置字表

首次安装没有词典内容。进入「資料」取得小型目录，选中字表后点击「套用選擇」。目录直接读取安卓上游 master 的 tools/tables/output/_詳情.json 与 Git 文件清单。本次提交包含 3,308 份有元数据的 TSV 字表；不包含通用汉字/字书基础库。

支持地图集二分区、音典分区、行政区划（省、市、县、镇、村等逐级选择）以及字表名称检索。可以选取一个分类的全部字表，也可单独选择某表。分类只是同一字表的不同入口，稳定 ID 去重，不会重复下载。

页面显示需下载大小和将移除的字表数量。取消勾选已下载字表，再套用选择，会移除该表。查询只覆盖已下载字表，收藏和笔记独立保存。查询页的语言选择也有相同分区入口，仅展示已下载字表。默认内置字表仍留待后续加入。

## 数据与稳定性

App 每次检查更新先读取上游 master 最新提交，再从同一固定提交取得目录和所选 TSV；不会混用更新前后的版本。下载直接访问 raw.githubusercontent.com/osfans/MCPDict，不依赖本仓库发布字表包。上游原始 data 文件需要先由上游生成 output；App 跟随已提交的 output，不在手机运行上游 Python 转换器。

「資料 → 更新 → 檢查上游目錄」检查最新目录；「更新全部已下載字表」重新检查并更新已安装数据。更新按需触发，不是后台推送。GitHub 限流或网络不可用时显示错误，现有字表继续离线可用。

下载校验 Git blob SHA-1 与文件大小，解析 TSV 后建立临时 SQLite 索引，再原子切换本地指针。缓存以字表内容哈希识别，内容未变则复用；下载、解析或索引失败保留旧数据。兼容旧试验版的 SQLite 安装索引，首次更新会转为上游 TSV。

当前同时保存独立字表数据库和合并查询库，占用大于原始 TSV；操作前保守检查约十二倍所选原始字表大小加 30 MB 空间。下载需保持 App 在前台，有字表级进度和取消，没有后台下载或字节百分比。上游简称变化视为新字表；一键更新遇到已移除字表会要求用户手动确认选择。

## GitHub Actions

- Check iOS and Python：Python 测试、工程生成、iOS 编译与模拟器 XCTest。
- Build iPhone IPA for local signing：真机编译，检查 Mach-O 的 arm64/iOS 平台，打包并发布待本地签名 IPA。
- Build dictionary from GitHub source：构建并验证上游整库，发布清单和源数据诊断。
- Publish experimental downloadable tables：从已验证整库提取三份独立字表，发布包和目录。

代码推送会运行 iOS 检查，App 或真机打包文件变化会生成新的真机包。数据和目录工作流支持手动运行，也在各自构建文件变更时运行，尚未启用每天定时更新。旧整库与三表目录工作流保留作开发工具；当前 App 更新直接连接上游，无需运行这些工作流。

首次基础版本的 [成功记录](https://github.com/ghehyoein/MCPDict-iOS/actions/runs/41994679817)。后续按需下载版本以 Actions 对应提交为准。实际验证范围见 [VALIDATION.md](VALIDATION.md)。

## Python 优先

Python 负责数据构建、字表拆分、目录清单、参考查询、Windows 测试界面、安卓图标资源准备、IPA 验证和打包。Swift 负责 iPhone 原生界面、SQLite 查询、下载与数据切换。手机内不嵌入 Python 解释器。

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
