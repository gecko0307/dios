import os
import subprocess
import shutil
import tarfile
from pathlib import Path

ROOT = Path(__file__).parent.resolve()

SRC_KERNEL = ROOT / "src" / "kernel"
OBJ = ROOT / "o-elf-x86_64"
OBJ_KERNEL = OBJ / "kernel"
CDROOT = ROOT / "cdroot"
USBSTICK = ROOT / "usbstick"
KERNEL_LINKER_SCRIPT = SRC_KERNEL / "linker.ld"

# Root file system image (ramfs): the contents of the repository folder `rootfs/` are packed
# as they are into cdroot/rootfs.tar. The bootloader loads that as a module and the kernel
# serves it as "/". Put programs in rootfs/bin, config in rootfs/etc, and so on.
ROOTFS = ROOT / "rootfs"
ROOTFS_MAX_NODES = 512      # kernel limit (ramfs.d: RAMFS_MAX_NODES), the root and /mnt included
ROOTFS_NAME_MAX = 63        # kernel limit per path component (RAMFS_NAME_MAX - 1)
ROOTFS_IGNORE = {".gitkeep", ".gitignore", ".DS_Store", "Thumbs.db"}

LDC = shutil.which("ldc2")
NASM = shutil.which("nasm")
LD = shutil.which("ld.lld")
XORRISO = shutil.which("xorriso")

if not LDC:
    raise RuntimeError("ldc2 not found")

if not NASM:
    raise RuntimeError("nasm not found")

if not LD:
    raise RuntimeError("ld.lld not found")

if not XORRISO:
    raise RuntimeError("xorriso not found")

D_FLAGS_KERNEL = [
    "-c",
    "-mtriple=x86_64-none-elf",
    "-release",
    "-nodefaultlib",
    "--boundscheck=off",
    "--disable-red-zone",
    "--use-ctors=0",
    "--fno-exceptions",
    "--nogc",
    "-O0",
    "-I=src/kernel",
    "-code-model=medium",
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

def compile_d(path, src, obj_dir, flags):
    relative = path.relative_to(src)
    output = obj_dir / relative.with_suffix(".o")

    output.parent.mkdir(parents=True, exist_ok=True)

    #if output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
    #    return output

    run([
        LDC, *flags,
        str(path.relative_to(ROOT)),
        f"-of={output.relative_to(ROOT)}",
    ])

    return output

def compile_asm(path, src, obj_dir):
    relative = path.relative_to(src)
    output = obj_dir / relative.with_suffix(".s.o")

    output.parent.mkdir(parents=True, exist_ok=True)

    if output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
        return output

    run([
        NASM, "-f", "elf64",
        "-o", str(output.relative_to(ROOT)),
        str(path.relative_to(ROOT)),
    ])

    return output

def compile_kernel():
    d_files = sorted(SRC_KERNEL.rglob("*.d"))
    asm_files = sorted(SRC_KERNEL.rglob("*.s"))

    objects = []

    for path in d_files:
        objects.append(compile_d(path, SRC_KERNEL, OBJ_KERNEL, D_FLAGS_KERNEL))

    for path in asm_files:
        objects.append(compile_asm(path, SRC_KERNEL, OBJ_KERNEL))

    kernel = CDROOT / "kernel64.bin"
    kernel.parent.mkdir(parents=True, exist_ok=True)

    run([
        LD, *LD_FLAGS_KERNEL,
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

    # The kernel adds the root and creates /mnt itself when the folder has none.
    if len(entries) + 2 > ROOTFS_MAX_NODES:
        raise RuntimeError(f"rootfs: {len(entries)} entries, the kernel takes at most {ROOTFS_MAX_NODES - 2}")

    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as tar:
        for rel, path in entries:     # sorted: a directory always comes before its contents
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

def main():
    compile_kernel()
    build_rootfs()
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

if __name__ == "__main__":
    main()
