#!/usr/bin/env python3
"""Windows/macOS Python desktop test UI, not the iOS app. No third-party modules."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox

from data_pipeline import readonly
from query import search


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path, nargs="?", default=Path(__file__).resolve().parents[1] / "sample-data/mcpdict.db")
    parser.add_argument("--smoke-test", action="store_true", help="Create widgets hidden, query 中, assert rendered results, then exit")
    args = parser.parse_args()
    if not args.database.is_file():
        raise SystemExit(f"Database not found: {args.database}")
    root = tk.Tk()
    if args.smoke_test:
        root.withdraw()
    root.title("漢字音典 · Python 查字測試")
    root.geometry("1000x720")
    pool = ThreadPoolExecutor(max_workers=1)
    frame = ttk.Frame(root, padding=16)
    frame.pack(fill="both", expand=True)
    ttk.Label(frame, text="漢字音典", font=("Microsoft YaHei UI", 24)).pack(anchor="w")
    ttk.Label(frame, text="GitHub 字表 → Python 構建 → 離線 SQLite · Windows 測試版").pack(anchor="w", pady=(0, 16))
    bar = ttk.Frame(frame)
    bar.pack(fill="x")
    query = tk.StringVar(value="中")
    entry = ttk.Entry(bar, textvariable=query, width=24)
    entry.pack(side="left", padx=(0, 8))
    mode = ttk.Combobox(bar, values=["漢字", "讀音", "註釋"], state="readonly", width=8)
    mode.current(0)
    mode.pack(side="left", padx=8)
    with closing(readonly(args.database)) as db:
        languages = [row[0] for row in db.execute("SELECT DISTINCT 簡稱 FROM info WHERE 簡稱 != '' ORDER BY 簡稱")]
    language = ttk.Combobox(bar, values=["全部語言"] + languages, width=24)
    language.set("普通話" if "普通話" in languages else "全部語言")
    language.pack(side="left", padx=8)
    status = tk.StringVar(value="漢字可輸入中、心新、𰻞、U+4E2D；讀音請使用資料原始格式。")
    ttk.Label(frame, textvariable=status, wraplength=940).pack(anchor="w", pady=12)
    body = ttk.Frame(frame)
    body.pack(fill="both", expand=True)
    output = tk.Text(body, wrap="word", font=("Microsoft YaHei UI", 12), state="disabled", padx=12, pady=12)
    scrollbar = ttk.Scrollbar(body, command=output.yview)
    output.configure(yscrollcommand=scrollbar.set)
    scrollbar.pack(side="right", fill="y")
    output.pack(fill="both", expand=True)
    active = None
    offset = 0
    request = None
    test_error = None

    def finish(future, more):
        nonlocal active, offset, test_error
        if not future.done():
            root.after(80, finish, future, more)
            return
        active = None
        find_button.configure(state="normal")
        try:
            rows = future.result()
            output.configure(state="normal")
            if not more:
                output.delete("1.0", "end")
                offset = 0
            for row in rows:
                output.insert("end", f'{row["語言"]}  ·  {row["讀音"]}\n{row["字組"]}\n{row["註釋"] or ""}\n\n')
            output.configure(state="disabled")
            offset += len(rows)
            status.set(f"已顯示 {offset} 筆同音字組；未啟用異體字或拼音轉換。")
            more_button.configure(state="normal" if len(rows) == 100 else "disabled")
        except Exception as error:
            if args.smoke_test:
                test_error = error
            else:
                messagebox.showerror("查詢失敗", str(error))
        if args.smoke_test:
            if "zhong1" not in output.get("1.0", "end") or "zhong4" not in output.get("1.0", "end"):
                test_error = test_error or AssertionError("Expected 中 readings in rendered text widget")
            pool.shutdown(wait=True)
            root.destroy()

    def run(more=False):
        nonlocal active, request
        if active is not None:
            return
        if not more:
            request = (query.get(), ["character", "pronunciation", "note"][mode.current()], "" if language.get() == "全部語言" else language.get())
        find_button.configure(state="disabled")
        more_button.configure(state="disabled")
        status.set("查詢中…")
        active = pool.submit(search, args.database, *request, offset if more else 0)
        root.after(80, finish, active, more)

    find_button = ttk.Button(bar, text="查詢", command=run)
    find_button.pack(side="left", padx=8)
    more_button = ttk.Button(frame, text="載入更多", command=lambda: run(True), state="disabled")
    more_button.pack(pady=10)
    entry.bind("<Return>", lambda _: run())
    root.protocol("WM_DELETE_WINDOW", lambda: (pool.shutdown(wait=False, cancel_futures=True), root.destroy()))
    if args.smoke_test:
        root.after(0, run)
    root.mainloop()
    if test_error:
        raise test_error
    if args.smoke_test:
        print("Tkinter UI smoke test passed: 中 -> zhong1 / zhong4")


if __name__ == "__main__":
    main()
