import argparse
import ast
import re
import subprocess
import shutil
import tarfile
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

ROOT = Path(__file__).parent.resolve()
DEFAULT_CONFIG_PATH = ROOT / "build.toml"

SRC_KERNEL = ROOT / "src" / "kernel"
SRC_ULIB = ROOT / "src" / "ulib"
OBJ = ROOT / "o-elf-x86_64"
OBJ_KERNEL = OBJ / "kernel"
OBJ_ULIB = OBJ / "ulib"
CDROOT = ROOT / "cdroot"
USBSTICK = ROOT / "usbstick"
KERNEL_LINKER_SCRIPT = SRC_KERNEL / "linker.ld"

# Root file system image (ramfs)
ROOTFS = ROOT / "rootfs"
ROOTFS_MAX_NODES = 512  # kernel limit (ramfs.d: RAMFS_MAX_NODES), the root and /mnt included
ROOTFS_NAME_MAX = 63    # kernel limit per path component (RAMFS_NAME_MAX - 1)
ROOTFS_IGNORE = {".gitkeep", ".gitignore", ".DS_Store", "Thumbs.db"}

LDC = shutil.which("ldc2")
NASM = shutil.which("nasm")
LD = shutil.which("ld.lld")
AR = shutil.which("llvm-ar")
XORRISO = shutil.which("xorriso")

DEFAULT_CONFIG = {
    "build": {
        "default_target": "all",  # "all" | "kernel" | "ulib" | "rootfs"
        "pack_iso": True,
        "debug": False,
        "ulib_out": "rootfs/lib/libulib.a",
        "kernel_out": "cdroot/kernel64.bin",
        "iso_out": "dios64.iso",
    },
    "flags": {
        "d_base": [
            "-c",
            "-mtriple=x86_64-none-elf",
            "-nodefaultlib",
            "--boundscheck=off",
            "--disable-red-zone",
            "--use-ctors=0",
            "--fno-exceptions",
            "--nogc",
        ],
        "d_release": ["-release"],
        "d_debug": ["-O0", "-g"],
        "d_kernel": ["-I=src/kernel", "-code-model=medium"],
        "d_ulib": ["-I=src/ulib"],
        "ld_kernel": [
            "-m", "elf_x86_64",
            "-z", "max-page-size=0x1000",
            "-static",
            "--gc-sections",
            "-nostdlib",
        ],
        "nasm": ["-f", "elf64"],
    },
}


def _strip_toml_comment(line: str) -> str:
    in_quotes = False
    quote_char = ""
    escaped = False
    out = []
    for ch in line:
        if escaped:
            out.append(ch)
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            out.append(ch)
            continue
        if in_quotes:
            if ch == quote_char:
                in_quotes = False
            out.append(ch)
        else:
            if ch in ('"', "'"):
                in_quotes = True
                quote_char = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
    return "".join(out).strip()


def _parse_simple_toml(text: str) -> dict:
    """Fallback TOML parser for Python < 3.11 (supports [sections], strings, bools, ints, arrays)."""
    data = {}
    current_section = data
    pending_key = None
    pending_buf = []

    for raw_line in text.splitlines():
        line = _strip_toml_comment(raw_line)
        if not line:
            continue

        if pending_key is not None:
            pending_buf.append(line)
            joined = " ".join(pending_buf)
            if joined.count("[") <= joined.count("]"):
                current_section[pending_key] = _parse_toml_value(joined)
                pending_key = None
                pending_buf = []
            continue

        section_match = re.match(r"^\[([A-Za-z0-9_.-]+)\]$", line)
        if section_match:
            sec_name = section_match.group(1)
            data.setdefault(sec_name, {})
            current_section = data[sec_name]
            continue

        if "=" not in line:
            raise RuntimeError(f"Invalid line in TOML config: {raw_line}")

        key, val_str = line.split("=", 1)
        key = key.strip()
        val_str = val_str.strip()

        if val_str.startswith("[") and val_str.count("[") > val_str.count("]"):
            pending_key = key
            pending_buf = [val_str]
        else:
            current_section[key] = _parse_toml_value(val_str)

    if pending_key is not None:
        raise RuntimeError(f"Unclosed array for key '{pending_key}' in TOML config")

    return data


def _parse_toml_value(val_str: str):
    if val_str == "true":
        return True
    if val_str == "false":
        return False
    try:
        return ast.literal_eval(val_str)
    except Exception as exc:
        raise RuntimeError(f"Cannot parse TOML value: {val_str}") from exc


def load_config(config_path: Path) -> dict:
    cfg = {
        "build": DEFAULT_CONFIG["build"].copy(),
        "flags": {k: list(v) for k, v in DEFAULT_CONFIG["flags"].items()},
    }

    if not config_path.exists():
        return cfg

    if tomllib is not None:
        with open(config_path, "rb") as f:
            user_cfg = tomllib.load(f)
    else:
        with open(config_path, "r", encoding="utf-8") as f:
            user_cfg = _parse_simple_toml(f.read())

    build_section = user_cfg.get("build", user_cfg)
    for key in cfg["build"]:
        if key in build_section:
            cfg["build"][key] = build_section[key]

    flags_section = user_cfg.get("flags", {})
    for key in cfg["flags"]:
        if key in flags_section:
            val = flags_section[key]
            if not isinstance(val, list):
                raise RuntimeError(f"Config error: [flags].{key} must be a list of strings")
            cfg["flags"][key] = [str(x) for x in val]

    valid_targets = {"all", "kernel", "ulib", "rootfs"}
    if cfg["build"]["default_target"] not in valid_targets:
        raise RuntimeError(
            f"Invalid default_target '{cfg['build']['default_target']}' in {config_path}. "
            f"Expected one of: {', '.join(sorted(valid_targets))}"
        )

    return cfg

def build_flag_sets(cfg: dict) -> dict:
    flags = cfg["flags"]
    is_debug = bool(cfg["build"]["debug"])
    mode_flags = flags["d_debug"] if is_debug else flags["d_release"]

    return {
        "d_kernel": [*flags["d_base"], *mode_flags, *flags["d_kernel"]],
        "d_ulib": [*flags["d_base"], *mode_flags, *flags["d_ulib"]],
        "ld_kernel": [
            "-T", str(KERNEL_LINKER_SCRIPT.relative_to(ROOT)),
            *flags["ld_kernel"],
        ],
        "nasm": flags["nasm"],
    }


def require(**tools):
    """Fail early with a clear message when a needed tool is missing."""
    for name, path in tools.items():
        if not path:
            raise RuntimeError(f"{name} not found")


def run(args):
    args = [str(arg) for arg in args]
    print("+", subprocess.list2cmdline(args))
    subprocess.run(args, cwd=ROOT, check=True)


def compile_d(path, src, obj_dir, flags, incremental=False):
    relative = path.relative_to(src)
    output = obj_dir / relative.with_suffix(".o")
    output.parent.mkdir(parents=True, exist_ok=True)
    if incremental and output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
        return output
    run([
        LDC,
        *flags,
        str(path.relative_to(ROOT)),
        f"-of={output.relative_to(ROOT)}",
    ])
    return output


def compile_asm(path, src, obj_dir, nasm_flags, incremental=True):
    relative = path.relative_to(src)
    output = obj_dir / relative.with_suffix(".s.o")
    output.parent.mkdir(parents=True, exist_ok=True)
    if incremental and output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
        return output
    run([
        NASM,
        *nasm_flags,
        "-o", str(output.relative_to(ROOT)),
        str(path.relative_to(ROOT)),
    ])
    return output


def collect_and_compile(src_dir, obj_dir, d_flags, nasm_flags, incremental_d=False, incremental_asm=True):
    if not src_dir.is_dir():
        raise RuntimeError(f"Source directory not found: {src_dir}")
    d_files = sorted(src_dir.rglob("*.d"))
    asm_files = sorted(src_dir.rglob("*.s"))
    objects = []
    for path in d_files:
        objects.append(compile_d(path, src_dir, obj_dir, d_flags, incremental=incremental_d))
    for path in asm_files:
        objects.append(compile_asm(path, src_dir, obj_dir, nasm_flags, incremental=incremental_asm))
    return objects


def compile_ulib(ulib_out: Path, flag_sets: dict):
    require(ldc2=LDC, nasm=NASM, **{"llvm-ar": AR})
    objects = collect_and_compile(
        SRC_ULIB, OBJ_ULIB, flag_sets["d_ulib"], flag_sets["nasm"],
        incremental_d=False, incremental_asm=True
    )
    ulib_out.parent.mkdir(parents=True, exist_ok=True)
    if ulib_out.exists():
        ulib_out.unlink()
    run([
        AR,
        "rcs",
        str(ulib_out.relative_to(ROOT)),
        *[str(obj.relative_to(ROOT)) for obj in objects],
    ])


def compile_kernel(kernel_out: Path, flag_sets: dict):
    require(ldc2=LDC, nasm=NASM, **{"ld.lld": LD})
    objects = collect_and_compile(
        SRC_KERNEL, OBJ_KERNEL, flag_sets["d_kernel"], flag_sets["nasm"],
        incremental_d=False, incremental_asm=True
    )
    kernel_out.parent.mkdir(parents=True, exist_ok=True)
    run([
        LD,
        *flag_sets["ld_kernel"],
        "-o", str(kernel_out.relative_to(ROOT)),
        *[str(obj.relative_to(ROOT)) for obj in objects],
    ])


def build_rootfs():
    """Pack the folder rootfs/ into cdroot/rootfs.tar (plain ustar, read by src/kernel/dios/core/ramfs.d)."""
    if not ROOTFS.is_dir():
        raise RuntimeError(f"rootfs folder not found: {ROOTFS}")
    out = CDROOT / "rootfs.tar"
    out.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    for path in sorted(ROOTFS.rglob("*")):
        if path.name in ROOTFS_IGNORE:
            continue
        rel = path.relative_to(ROOTFS).as_posix()
        if path.is_symlink():
            raise RuntimeError(f"rootfs: symbolic links are not supported: {rel}")
        if not (path.is_dir() or path.is_file()):
            continue
        if len(rel) > 100 or any(len(part) > ROOTFS_NAME_MAX for part in rel.split("/")):
            raise RuntimeError(f"rootfs: path too long (max 100 characters, {ROOTFS_NAME_MAX} per name): {rel}")
        entries.append((rel, path))

    if len(entries) + 2 > ROOTFS_MAX_NODES:
        raise RuntimeError(f"rootfs: {len(entries)} entries, the kernel takes at most {ROOTFS_MAX_NODES - 2}")

    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as tar:
        for rel, path in entries:
            info = tarfile.TarInfo(rel)
            info.mtime = int(path.stat().st_mtime)
            if path.is_dir():
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                tar.addfile(info)
            else:
                info.size = path.stat().st_size
                info.mode = 0o755 if rel.startswith("bin/") else 0o644
                with open(path, "rb") as f:
                    tar.addfile(info, f)
    print(f"rootfs: {out.relative_to(ROOT)} from {ROOTFS.relative_to(ROOT)}/ "
          f"({len(entries)} entries, {out.stat().st_size} bytes)")


def build_iso(iso_out: Path):
    require(xorriso=XORRISO)
    iso_out.parent.mkdir(parents=True, exist_ok=True)
    run([
        XORRISO,
        "-as", "mkisofs",
        "-r",
        "-b", "limine/limine-bios-cd.bin",
        "-no-emul-boot",
        "-boot-load-size", "4",
        "-boot-info-table",
        "-eltorito-alt-boot",
        "-e", "limine/limine-uefi-cd.bin",
        "-no-emul-boot",
        "--efi-boot-part",
        "--efi-boot-image",
        "--protective-msdos-label",
        "-o", str(iso_out.relative_to(ROOT)),
        "./cdroot",
    ])


def main():
    parser = argparse.ArgumentParser(
        description="Build the DIOS kernel, ulib runtime, root file system image and ISO."
    )
    parser.add_argument(
        "target",
        nargs="?",
        choices=["all", "kernel", "ulib", "rootfs"],
        default=None,
        help="What to build (overrides build.toml): 'all', 'kernel', 'ulib', or 'rootfs'.",
    )
    parser.add_argument(
        "-c", "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help="Path to TOML config file (default: build.toml).",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Use debug compiler flags (overrides build.debug in config).",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="Use release compiler flags (overrides build.debug in config).",
    )
    parser.add_argument(
        "--no-iso",
        action="store_true",
        help="Skip packing rootfs.tar and building ISO.",
    )
    parser.add_argument(
        "--iso",
        action="store_true",
        help="Force packing rootfs.tar and building ISO even if disabled in config.",
    )
    args = parser.parse_args()
    cfg = load_config(args.config.resolve())
    build_cfg = cfg["build"]
    
    if args.debug:
        build_cfg["debug"] = True
    elif args.release:
        build_cfg["debug"] = False
    
    flag_sets = build_flag_sets(cfg)
    
    target = args.target or build_cfg["default_target"]
    ulib_out = (ROOT / build_cfg["ulib_out"]).resolve()
    kernel_out = (ROOT / build_cfg["kernel_out"]).resolve()
    iso_out = (ROOT / build_cfg["iso_out"]).resolve()
    
    if args.no_iso:
        should_pack_iso = False
    elif args.iso:
        should_pack_iso = True
    else:
        should_pack_iso = bool(build_cfg["pack_iso"])
    
    build_ulib = target in ("all", "ulib")
    build_kern = target in ("all", "kernel")
    pack_image = (target in ("all", "kernel", "rootfs")) and should_pack_iso
    
    if build_ulib:
        compile_ulib(ulib_out, flag_sets)
    
    if build_kern:
        compile_kernel(kernel_out, flag_sets)
    
    if pack_image:
        if not kernel_out.is_file():
            raise RuntimeError(f"{kernel_out.relative_to(ROOT)} does not exist yet: build the kernel first")
        build_rootfs()
        build_iso(iso_out)

if __name__ == "__main__":
    main()