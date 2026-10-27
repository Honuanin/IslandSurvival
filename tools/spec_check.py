#!/usr/bin/env python3
"""工程规格自检：按 孤岛求生-工程规格.json 校验目录、必需文件、.import 元文件、
绝对路径、悬空资源引用与 @trace 需求覆盖，输出 JSON 与 Markdown 报告。

用法：python3 tools/spec_check.py [项目根目录]
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
SPEC = {
    "requiredDirs": ["scenes", "scripts", "assets", "resources", "tests", "docs"],
    "recommendedDirs": ["reports", "export"],
    "requiredFiles": [
        "project.godot",
        "scenes/main/main.tscn",
        "docs/gdd.md",
        "docs/design-freeze.json",
    ],
    "requireImportMeta": True,
    "scanAbsolutePaths": True,
    "scanDanglingRefs": True,
    "refAllowlist": [],
    "requireFrozenDesign": True,
    "traceMarker": "@trace",
}

SKIP_DIRS = {".godot", ".git", "export"}
# 报告产物（截图等）不进游戏包，不做 .import 与引用校验
REPORT_DIRS = {"reports"}
TEXT_EXT = {".gd", ".tscn", ".tres", ".godot", ".cfg", ".md", ".json"}
RES_EXT = {".gd", ".tscn", ".tres", ".otf", ".ttf", ".png", ".svg", ".import",
           ".wav", ".ogg", ".mp3", ".res", ".escn", ".gdshader", ".json"}

problems = []
warnings = []


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def walk_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            yield os.path.join(dirpath, fn)


# ---------- 1. 目录 ----------
for d in SPEC["requiredDirs"]:
    p = os.path.join(ROOT, d)
    if not os.path.isdir(p):
        problems.append({"type": "missing-dir", "target": d, "detail": "必需目录不存在"})
for d in SPEC["recommendedDirs"]:
    p = os.path.join(ROOT, d)
    if not os.path.isdir(p):
        warnings.append({"type": "missing-dir", "target": d, "detail": "推荐目录不存在"})

# ---------- 2. 必需文件 ----------
for f in SPEC["requiredFiles"]:
    p = os.path.join(ROOT, f)
    if not os.path.isfile(p):
        problems.append({"type": "missing-file", "target": f, "detail": "必需文件不存在"})
    elif os.path.getsize(p) == 0:
        problems.append({"type": "empty-file", "target": f, "detail": "必需文件为空"})

# ---------- 3. 设计冻结 ----------
freeze_path = os.path.join(ROOT, "docs/design-freeze.json")
freeze = None
if os.path.isfile(freeze_path):
    try:
        freeze = json.load(open(freeze_path, encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        problems.append({"type": "bad-json", "target": "docs/design-freeze.json",
                         "detail": str(e)})

# ---------- 4. .import 元文件 ----------
if SPEC["requireImportMeta"]:
    for f in walk_files():
        if rel(f).split("/")[0] in REPORT_DIRS:
            continue
        base, ext = os.path.splitext(f)
        if ext in RES_EXT and ext != ".import" and ext != ".gd" and ext != ".tscn" \
                and ext != ".tres" and ext != ".json":
            if not os.path.isfile(f + ".import"):
                problems.append({"type": "missing-import", "target": rel(f),
                                 "detail": "资源缺少 .import 元文件"})

# ---------- 5. 绝对路径 ----------
abs_re = re.compile(r"""(?<![\w.])(/[A-Za-z0-9_.\-]+){2,}""")
if SPEC["scanAbsolutePaths"]:
    for f in walk_files():
        if os.path.splitext(f)[1] not in TEXT_EXT:
            continue
        if rel(f).split("/")[0] in REPORT_DIRS:
            continue
        try:
            txt = open(f, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        for i, line in enumerate(txt.splitlines(), 1):
            # 排除注释里的示例命令与 URL
            if line.strip().startswith("#") or "http" in line:
                continue
            # 去掉 res:// 前缀后再找绝对路径，避免把 res://scenes/x 误判为 /scenes/x
            scan_line = line.replace("res://", "RES_PREFIX").replace("user://", "USER_PREFIX")
            for m in abs_re.finditer(scan_line):
                hit = m.group(0)
                if hit.startswith(("/opt/", "/usr/", "/root/", "/tmp/")):
                    continue  # 构建环境路径，非工程引用
                problems.append({"type": "absolute-path", "target": rel(f),
                                 "detail": "第 %d 行: %s" % (i, hit)})

# ---------- 6. 悬空资源引用 ----------
ref_re = re.compile(r"""["']res://([^"']+)["']""")
exists_cache = {}


def res_exists(res_path):
    if res_path in exists_cache:
        return exists_cache[res_path]
    p = os.path.join(ROOT, res_path)
    ok = os.path.isfile(p) or os.path.isdir(p)
    # Godot 导出时用 .remap，源码里也可能引用 uid:// ——这里只校验 res:// 字面路径
    exists_cache[res_path] = ok
    return ok


if SPEC["scanDanglingRefs"]:
    for f in walk_files():
        if os.path.splitext(f)[1] not in TEXT_EXT:
            continue
        if rel(f).split("/")[0] in REPORT_DIRS:
            continue
        try:
            txt = open(f, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        for res_path in set(ref_re.findall(txt)):
            if res_path in SPEC["refAllowlist"]:
                continue
            # 允许 docs 中的示例路径
            if rel(f).split("/")[0] in ("docs", "reports", "tools"):
                continue
            if not res_exists(res_path):
                problems.append({"type": "dangling-ref", "target": rel(f),
                                 "detail": "引用不存在的 res://" + res_path})

# ---------- 7. @trace 覆盖 ----------
trace_ok = None
if freeze and "items" in freeze:
    ids = [it["id"] for it in freeze["items"]]
    hits = {k: 0 for k in ids}
    marker = SPEC["traceMarker"]
    for f in walk_files():
        if os.path.splitext(f)[1] not in {".gd", ".tscn", ".godot", ".tres"}:
            continue
        txt = open(f, encoding="utf-8").read()
        for m in re.finditer(re.escape(marker) + r"([^\n]*)", txt):
            for tok in m.group(1).split():
                if tok in hits:
                    hits[tok] += 1
    missing = [k for k in ids if hits[k] == 0]
    trace_ok = len(missing) == 0
    for k in missing:
        problems.append({"type": "missing-trace", "target": k,
                         "detail": "需求在源码中无 @trace 标记"})
else:
    warnings.append({"type": "skip", "target": "trace", "detail": "缺少设计冻结文件，跳过覆盖检查"})

# ---------- 8. GDScript 解析 ----------
parse = {"checked": False, "detail": "由 godot --headless --check-only 单独执行"}

report = {
    "project": ROOT,
    "spec": SPEC,
    "ok": len(problems) == 0,
    "problemCount": len(problems),
    "warningCount": len(warnings),
    "problems": problems,
    "warnings": warnings,
    "traceCoverage": trace_ok,
    "parse": parse,
}
os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
with open(os.path.join(ROOT, "reports/spec-check.json"), "w", encoding="utf-8") as fh:
    json.dump(report, fh, ensure_ascii=False, indent=2)

print(json.dumps({k: v for k, v in report.items() if k not in ("spec", "problems", "warnings")},
                 ensure_ascii=False))
for p in problems:
    print("PROBLEM", p["type"], p["target"], p["detail"])
for w in warnings:
    print("WARN   ", w["type"], w["target"], w["detail"])
sys.exit(0 if report["ok"] else 1)
