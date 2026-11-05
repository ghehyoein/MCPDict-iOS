# 首次验证记录

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

## 尚未实际验证

- Swift 在 Xcode 中的编译；已准备 GitHub macOS 编译工作流，尚未部署运行。
- 3 项 XCTest（查询契约、更新激活失败保留旧连接、拒绝不兼容清单）；已编写并接入 CI，尚未运行。
- iOS 真机速度、内存、布局、长时间下载与断网恢复。
- GitHub Release 实际发布、App 从已发布地址下载并完成切换。
- 与 Android 的全功能结果一致性；当前只实现声明的基础查询子集。

因此此交付是可继续开发的初版工程与已验证的 Python 数据基础，不是已经验证稳定的完整 iOS 应用。
