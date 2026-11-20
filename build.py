import os
import subprocess
import shutil
from pathlib import Path

ROOT = Path(__file__).parent.resolve()

SRC = ROOT / "src"
OBJ = ROOT / "o-elf-x86_64"
CDROOT = ROOT / "cdroot"

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

D_FLAGS = [
    "-c",
    "-I=src",
    "-mtriple=x86_64-none-elf",
    "-release",
    "-nodefaultlib",
    "--boundscheck=off",
    "--disable-red-zone",
    "--use-ctors=0",
    "--fno-exceptions",
    "--nogc",
    "-code-model=medium",
    "-O0",
]

LD_FLAGS = [
    "-m", "elf_x86_64",
    "-T", "linker.ld",
    "-z", "max-page-size=0x1000",
    "-static",
    "--gc-sections",
    "-nostdlib",
]

def run(args):
    args = [str(arg) for arg in args]
    print("+", subprocess.list2cmdline(args))
    subprocess.run(args, cwd=ROOT, check=True)

def compile_d(path):
    relative = path.relative_to(SRC)
    output = OBJ / relative.with_suffix(".o")

    output.parent.mkdir(parents=True, exist_ok=True)

    #if output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
    #    return output

    run([
        LDC, *D_FLAGS,
        str(path.relative_to(ROOT)),
        f"-of={output.relative_to(ROOT)}",
    ])

    return output

def compile_asm(path):
    relative = path.relative_to(SRC)
    output = OBJ / relative.with_suffix(".s.o")

    output.parent.mkdir(parents=True, exist_ok=True)

    if output.exists() and output.stat().st_mtime >= path.stat().st_mtime:
        return output

    run([
        NASM, "-f", "elf64",
        "-o", str(output.relative_to(ROOT)),
        str(path.relative_to(ROOT)),
    ])

    return output

def main():
    d_files = sorted(SRC.rglob("*.d"))
    asm_files = sorted(SRC.rglob("*.s"))

    objects = []

    for path in d_files:
        objects.append(compile_d(path))

    for path in asm_files:
        objects.append(compile_asm(path))

    kernel = CDROOT / "kernel64.bin"
    kernel.parent.mkdir(parents=True, exist_ok=True)

    run([
        LD, *LD_FLAGS,
        "-o", str(kernel.relative_to(ROOT)),
        *[str(obj.relative_to(ROOT)) for obj in objects],
    ])

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
