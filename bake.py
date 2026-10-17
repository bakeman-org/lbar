#!/usr/bin/env python3
"""
打包 ELF 可执行文件及其所有动态库依赖、资源，生成自解压独立运行 bundle。
默认即独立运行（无需主机库），资源文件打包进根目录。
用法：
  ./bake-standalone.py -e qrdock -r zenity -o qrdock.bake
  ./bake-standalone.py -e qrdock -r resource/ -o qrdock.bake   # 资源目录
"""

import argparse
import os
import subprocess
import re
import tempfile
import shutil
import sys

MARKER = "# __BAKE_STANDALONE_MARKER__"


# ========== 依赖收集 ==========
def _parse_ldd_output(text):
    """从 ldd 输出中产出 (name, path) 列表。"""
    result = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        # 标准格式: libname => /path (0x...)
        m = re.match(r'^(\S+)\s+=>\s+(\S+)\s+\([0-9a-fx]+\)$', line)
        if m:
            name, path = m.groups()
            result.append((os.path.basename(name), path))
            continue
        # 动态链接器行: /path/ld-linux.so (0x...)
        m = re.match(r'^(/\S+ld-linux[^\s]*)\s+\([0-9a-fx]+\)$', line)
        if m:
            path = m.group(1)
            result.append((os.path.basename(path), path))
    return result


def collect_dependencies(paths):
    """
    对一组 ELF 路径递归收集所有动态库依赖。
    返回 (ld_linux_path, {libname: libpath})。
    单独对每个路径调用 ldd，以免某个文件失败影响整批。
    """
    depends = {}
    seen = set()
    updates = [os.path.abspath(p) for p in paths]

    while updates:
        p = updates.pop()
        if p in seen:
            continue
        seen.add(p)
        try:
            output = subprocess.check_output(
                ['ldd', p],
                env={'LC_ALL': 'C', 'LANG': 'C', 'LANGUAGE': 'C'},
                stderr=subprocess.DEVNULL
            ).decode()
        except subprocess.CalledProcessError:
            continue

        for name, path in _parse_ldd_output(output):
            if path == 'not found':
                print(f'警告: 找不到依赖 {name} (来自 {os.path.basename(p)})')
                continue
            if name in depends:
                if depends[name] != path:
                    print(f'警告: {name} 存在多条路径: {depends[name]}, {path}')
                continue
            depends[name] = path
            print(f'收集依赖: {name} -> {path}  (来自 {os.path.basename(p)})')
            updates.append(path)

    ld_linux = None
    for name in list(depends.keys()):
        if name.startswith('ld-linux-'):
            ld_linux = depends.pop(name)
            break
    return ld_linux, depends


def _is_elf(path):
    try:
        with open(path, 'rb') as fp:
            return fp.read(4) == b'\x7fELF'
    except OSError:
        return False


# ========== 主函数 ==========
def main():
    parser = argparse.ArgumentParser(
        description="打包可执行文件、所有动态库依赖及资源，生成独立运行自解压bundle"
    )
    parser.add_argument("-e", "--executable", required=True, help="可执行文件路径")
    parser.add_argument("-r", "--resource", action="append", default=[],
                        help="资源文件或目录（可多次指定）")
    parser.add_argument("-o", "--output", help="输出bundle文件名（默认: <exe>.bake）")
    parser.add_argument("--no-compress", action="store_true",
                        help="不使用gzip压缩（默认gzip压缩）")
    args = parser.parse_args()

    exe_path = os.path.abspath(args.executable)
    output_name = args.output or os.path.basename(exe_path) + '.bake'

    temp_dir = tempfile.mkdtemp(prefix='bake_')
    tar_path = None
    try:
        # ---------- 1. 主程序 -> __exe__ ----------
        shutil.copy2(exe_path, os.path.join(temp_dir, '__exe__'))
        os.chmod(os.path.join(temp_dir, '__exe__'), 0o755)

        # ---------- 2. 资源文件（保留目录结构）----------
        # 这样 resource/platforms/libqxcb.so 会保留在 <extract>/platforms/libqxcb.so
        # 目录里的文件放在根目录，子目录结构原样保留。
        for res in args.resource:
            res_abs = os.path.abspath(res)
            if not os.path.exists(res_abs):
                print(f"警告：资源 {res} 不存在，跳过")
                continue
            if os.path.isfile(res_abs):
                shutil.copy2(res_abs, os.path.join(temp_dir, os.path.basename(res_abs)))
            elif os.path.isdir(res_abs):
                for item in sorted(os.listdir(res_abs)):
                    src = os.path.join(res_abs, item)
                    dst = os.path.join(temp_dir, item)
                    if os.path.isdir(src):
                        shutil.copytree(src, dst, dirs_exist_ok=True)
                    else:
                        shutil.copy2(src, dst)
            else:
                print(f"警告：资源 {res} 不是文件或目录，跳过")

        # ---------- 3. 收集依赖 ----------
        # 收集范围：主程序 + 所有资源中的 ELF 文件（主要是 Qt 插件 .so）
        print("=== 收集动态库依赖 ===")
        scan_paths = [exe_path]

        for res in args.resource:
            res_abs = os.path.abspath(res)
            if os.path.isfile(res_abs):
                if _is_elf(res_abs):
                    scan_paths.append(res_abs)
            elif os.path.isdir(res_abs):
                for root, _, files in os.walk(res_abs):
                    for f in files:
                        fpath = os.path.join(root, f)
                        # 插件通常以 .so 结尾，也可能带版本号 .so.6 之类
                        if f.endswith('.so') or '.so.' in f or _is_elf(fpath):
                            scan_paths.append(fpath)

        ld_path, libs = collect_dependencies(scan_paths)
        if not ld_path:
            print("错误：未找到动态链接器，无法独立运行", file=sys.stderr)
            return 1
        print(f"动态链接器: {ld_path}")
        print(f"共收集 {len(libs)} 个动态库")

        # ---------- 4. 复制依赖库（不覆盖资源）----------
        dep_files = [(ld_path, os.path.basename(ld_path))] + \
                    [(path, name) for name, path in libs.items()]
        for src, dst_name in dep_files:
            dst = os.path.join(temp_dir, dst_name)
            if os.path.exists(dst):
                # 已经被资源占用了（比如资源里已经带上了某个库），跳过
                continue
            shutil.copy2(src, dst)
            os.chmod(dst, 0o755)

        # ---------- 5. 打包临时目录为 tar（可选压缩）----------
        compress_flag = '' if args.no_compress else 'z'
        tar_path = tempfile.mktemp(suffix='.tar' + ('' if args.no_compress else '.gz'))
        subprocess.check_call(
            ['tar', '-c' + compress_flag + 'f', tar_path, '-C', temp_dir, '.'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        # ---------- 6. 生成自解压 shell ----------
        SHELL_TEMPLATE = '''#!/bin/bash
set -e

MARKER="{marker}"

get_marker_line() {{
    awk -v m="$MARKER" '$0 == m {{print NR+1; exit}}' "$0"
}}

cleanup() {{ rm -rf "$_extractdir"; }}
_extractdir=$(mktemp -d)
trap cleanup EXIT INT TERM

marker_ln=$(get_marker_line)
tail -n +"$marker_ln" "$0" | sed 's/^#//' | tar -x{compress} - -C "$_extractdir"

# 所有文件可执行（动态链接器、主程序、插件等）
chmod +x "$_extractdir"/* 2>/dev/null || true
find "$_extractdir" -name '*.so' -o -name '*.so.*' 2>/dev/null | xargs -r chmod +x 2>/dev/null || true

# 找到动态链接器
LD=$(ls "$_extractdir"/ld-linux*.so* 2>/dev/null | head -n1)

# 关键：让 Qt 使用 bundle 内的插件，避免加载到系统的插件
# （系统插件链接了系统的 libxkbcommon，与 bundle 里的版本冲突会导致 SIGSEGV）
export QT_PLUGIN_PATH="$_extractdir"
export QT_QPA_PLATFORM_PLUGIN_PATH="$_extractdir/platforms"
export QML2_IMPORT_PATH="$_extractdir/qml"

# 查找路径优先使用 bundle 内的库
if [ -n "$LD" ]; then
    export LD_LIBRARY_PATH="$_extractdir:$LD_LIBRARY_PATH"
    exec -a "$0" "$LD" "$_extractdir/__exe__" "$@"
else
    export LD_LIBRARY_PATH="$_extractdir:$LD_LIBRARY_PATH"
    exec -a "$0" "$_extractdir/__exe__" "$@"
fi
'''
        compress_opt = 'zf' if not args.no_compress else 'xf'
        shell_script = SHELL_TEMPLATE.format(
            marker=MARKER,
            compress=compress_opt
        )

        with open(output_name, 'wb') as fout:
            fout.write(shell_script.encode('utf-8'))
            fout.write(f'\n{MARKER}\n'.encode('utf-8'))
            with open(tar_path, 'rb') as ftar:
                for line in ftar:
                    fout.write(b'#' + line)

        os.chmod(output_name, 0o755)
        print(f"\n生成完成: {output_name}")
        print("独立运行模式（所有依赖已打包），可在任意 Linux 系统上执行")
        if args.no_compress:
            print("未压缩，启动速度最快")
        else:
            print("使用 gzip 压缩（更小体积）")

    except Exception as e:
        print(f"打包失败: {e}", file=sys.stderr)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return 1
    else:
        shutil.rmtree(temp_dir, ignore_errors=True)
    finally:
        if tar_path and os.path.exists(tar_path):
            try:
                os.unlink(tar_path)
            except OSError:
                pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
