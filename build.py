import argparse
import subprocess
import shutil
import tarfile
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
SRC_KERNEL = ROOT / "src" / "kernel"
SRC_ULIB = ROOT / "src" / "ulib"
OBJ = ROOT / "o-elf-x86_64"
OBJ_KERNEL = OBJ / "kernel"
OBJ_ULIB = OBJ / "ulib"
CDROOT = ROOT / "cdroot"
USBSTICK = ROOT / "usbstick"
KERNEL_LINKER_SCRIPT = SRC_KERNEL / "linker.ld"
ULIB_OUT = ROOT / "rootfs" / "lib" / "libulib.a"

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


def require(**tools):
    """Fail early with a clear message when a needed tool is missing."""
    for name, path in tools.items():
        if not path:
            raise RuntimeError(f"{name} not found")


D_FLAGS_BASE = [
    "-c",
    "-mtriple=x86_64-none-elf",
    "-release",
    "-nodefaultlib",
    "--boundscheck=off",
    "--disable-red-zone",
    "--use-ctors=0",
    "--fno-exceptions",
    "--nogc",
]

D_FLAGS_KERNEL = [
    *D_FLAGS_BASE,
    "-I=src/kernel",
    "-code-model=medium",
]

D_FLAGS_ULIB = [
    *D_FLAGS_BASE,
    "-I=src/ulib",
]

LD_FLAGS_KERNEL = [
    "-m", "elf_x86_64",
    "-T", str(KERNEL_LINKER_SCRIPT.relative_to(ROOT)),
    "-z", "max-page-size=0x1000",
    "-static",
    "--gc-sections",
    "-nostdlib",
]


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


def compile_asm(path, src, obj_dir, incremental=True):
    relative = path.relative_to(src)
    output = obj_dir / relative.with_suffix(".s.o")
    output.parent.mkdir(parents=True, exist_ok=True)
    if incremental and output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
        return output
    run([
        NASM,
        "-f", "elf64",
        "-o", str(output.relative_to(ROOT)),
        str(path.relative_to(ROOT)),
    ])
    return output


def collect_and_compile(src_dir, obj_dir, d_flags, incremental_d=False, incremental_asm=True):
    d_files = sorted(src_dir.rglob("*.d"))
    asm_files = sorted(src_dir.rglob("*.s"))
    objects = []
    for path in d_files:
        objects.append(compile_d(path, src_dir, obj_dir, d_flags, incremental=incremental_d))
    for path in asm_files:
        objects.append(compile_asm(path, src_dir, obj_dir, incremental=incremental_asm))
    return objects


def compile_ulib():
    require(ldc2=LDC, nasm=NASM, **{"llvm-ar": AR})
    objects = collect_and_compile(SRC_ULIB, OBJ_ULIB, D_FLAGS_ULIB, incremental_d=False, incremental_asm=True)
    ULIB_OUT.parent.mkdir(parents=True, exist_ok=True)
    # Удаляем старый архив, чтобы в нём не оставались объектные файлы от удалённых исходников
    if ULIB_OUT.exists():
        ULIB_OUT.unlink()
    run([
        AR,
        "rcs",
        str(ULIB_OUT.relative_to(ROOT)),
        *[str(obj.relative_to(ROOT)) for obj in objects],
    ])


def compile_kernel():
    require(ldc2=LDC, nasm=NASM, **{"ld.lld": LD})
    objects = collect_and_compile(SRC_KERNEL, OBJ_KERNEL, D_FLAGS_KERNEL, incremental_d=False, incremental_asm=True)
    kernel = CDROOT / "kernel64.bin"
    kernel.parent.mkdir(parents=True, exist_ok=True)
    run([
        LD,
        *LD_FLAGS_KERNEL,
        "-o", str(kernel.relative_to(ROOT)),
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


def build_iso():
    require(xorriso=XORRISO)
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
        "-o", "dios64.iso",
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
        default="all",
        help="What to build: 'all' (ulib + kernel + iso, default), 'kernel' (kernel + iso), "
             "'ulib' (only libulib.a), or 'rootfs' (repack rootfs.tar + iso without compiling).",
    )
    parser.add_argument(
        "--no-iso",
        action="store_true",
        help="Skip packing rootfs.tar and building dios64.iso.",
    )
    args = parser.parse_args()

    build_ulib = args.target in ("all", "ulib")
    build_kern = args.target in ("all", "kernel")
    pack_image = (args.target in ("all", "kernel", "rootfs")) and not args.no_iso

    if build_ulib:
        compile_ulib()

    if build_kern:
        compile_kernel()

    if pack_image:
        if not (CDROOT / "kernel64.bin").is_file():
            raise RuntimeError("cdroot/kernel64.bin does not exist yet: build the kernel first")
        build_rootfs()
        build_iso()


if __name__ == "__main__":
    main()
