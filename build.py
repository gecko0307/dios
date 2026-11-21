import os
import subprocess
import shutil
from pathlib import Path

ROOT = Path(__file__).parent.resolve()

SRC_KERNEL = ROOT / "src" / "kernel"
SRC_USER = ROOT / "src" / "user"
OBJ = ROOT / "o-elf-x86_64"
OBJ_KERNEL = OBJ / "kernel"
OBJ_USER = OBJ / "user"
CDROOT = ROOT / "cdroot"

# User-space layout (src/user):
#   object.d, ulib.d, ulib.s   runtime shared by every program
#   user.ld                    linker script for programs
#   anything else *.d          one program each -> cdroot/<name>.elf
USER_RUNTIME = {"object.d", "ulib.d", "ulib.s"}
USER_LINKER_SCRIPT = SRC_USER / "user.ld"

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

D_FLAGS_COMMON = [
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
]

D_FLAGS_KERNEL = [
    *D_FLAGS_COMMON,
    "-I=src/kernel",
    "-code-model=medium",
]

# User programs live low in the address space (0x400000), so the default
# (small) code model is right; the kernel's "medium" model is for its high half.
D_FLAGS_USER = [
    *D_FLAGS_COMMON,
    "-I=src/user",
]

LD_FLAGS_KERNEL = [
    "-m", "elf_x86_64",
    "-T", "linker.ld",
    "-z", "max-page-size=0x1000",
    "-static",
    "--gc-sections",
    "-nostdlib",
]

LD_FLAGS_USER = [
    "-m", "elf_x86_64",
    "-T", str(USER_LINKER_SCRIPT.relative_to(ROOT)),
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

def compile_userspace():
    """Build every program in src/user into cdroot/<name>.elf. Returns the program names."""
    if not SRC_USER.is_dir():
        return []

    output = CDROOT / "user"
    output.mkdir(parents=True, exist_ok=True)

    # The runtime is compiled once and linked into every program.
    runtime = []
    for name in sorted(USER_RUNTIME):
        path = SRC_USER / name
        if not path.exists():
            raise RuntimeError(f"user runtime file missing: {path.relative_to(ROOT)}")
        if path.suffix == ".d":
            runtime.append(compile_d(path, SRC_USER, OBJ_USER, D_FLAGS_USER))
        else:
            runtime.append(compile_asm(path, SRC_USER, OBJ_USER))

    programs = [p for p in sorted(SRC_USER.glob("*.d")) if p.name not in USER_RUNTIME]

    names = []
    for path in programs:
        obj = compile_d(path, SRC_USER, OBJ_USER, D_FLAGS_USER)
        elf = output / f"{path.stem}.elf"
        run([
            LD, *LD_FLAGS_USER,
            "-o", str(elf.relative_to(ROOT)),
            *[str(o.relative_to(ROOT)) for o in runtime],
            str(obj.relative_to(ROOT)),
        ])
        names.append(path.stem)

    return names

def check_boot_modules(programs):
    """The kernel only sees programs that limine.conf lists as modules."""
    conf = CDROOT / "limine.conf"
    if not programs or not conf.exists():
        return

    text = conf.read_text(errors="replace")
    missing = [name for name in programs if f"{name}.elf" not in text]
    if missing:
        print()
        print("WARNING: not listed in cdroot/limine.conf (the kernel will not see them):")
        for name in missing:
            print(f"    module_path: boot():/{name}.elf")
        print()

def main():
    compile_kernel()
    programs = compile_userspace()
    check_boot_modules(programs)

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
