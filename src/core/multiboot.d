module core.multiboot;

extern(C):

/* How many bytes from the start of the file we search for the header. */
const MULTIBOOT_SEARCH = 8192;

/* The magic field should contain this. */
const MULTIBOOT_HEADER_MAGIC = 0x1BADB002;

/* This should be in %eax. */
const MULTIBOOT_BOOTLOADER_MAGIC = 0x2BADB002;

/* The bits in the required part of flags field we don't support. */
const MULTIBOOT_UNSUPPORTED = 0x0000fffc;

/* Alignment of multiboot modules. */
const MULTIBOOT_MOD_ALIGN = 0x00001000;

/* Alignment of the multiboot info structure. */
const MULTIBOOT_INFO_ALIGN = 0x00000004;

/* Flags set in the 'flags' member of the multiboot header. */

/* Align all boot modules on i386 page (4KB) boundaries. */
const MULTIBOOT_PAGE_ALIGN = 0x00000001;

/* Must pass memory information to OS. */
const MULTIBOOT_MEMORY_INFO = 0x00000002;

/* Must pass video information to OS. */
const MULTIBOOT_VIDEO_MODE = 0x00000004;

/* This flag indicates the use of the address fields in the header. */
const MULTIBOOT_AOUT_KLUDGE = 0x00010000;

/* Flags to be set in the 'flags' member of the multiboot info structure. */

/* is there basic lower/upper memory information? */
const MULTIBOOT_INFO_MEMORY = 0x00000001;
/* is there a boot device set? */
const MULTIBOOT_INFO_BOOTDEV = 0x00000002;
/* is the command-line defined? */
const MULTIBOOT_INFO_CMDLINE = 0x00000004;
/* are there modules to do something with? */
const MULTIBOOT_INFO_MODS = 0x00000008;

/* These next two are mutually exclusive */

/* is there a symbol table loaded? */
const MULTIBOOT_INFO_AOUT_SYMS = 0x00000010;
/* is there an ELF section header table? */
const MULTIBOOT_INFO_ELF_SHDR = 0X00000020;

/* is there a full memory map? */
const MULTIBOOT_INFO_MEM_MAP = 0x00000040;

/* Is there drive info? */
const MULTIBOOT_INFO_DRIVE_INFO = 0x00000080;

/* Is there a config table? */
const MULTIBOOT_INFO_CONFIG_TABLE = 0x00000100;

/* Is there a boot loader name? */
const MULTIBOOT_INFO_BOOT_LOADER_NAME = 0x00000200;

/* Is there a APM table? */
const MULTIBOOT_INFO_APM_TABLE = 0x00000400;

/* Is there video information? */
const MULTIBOOT_INFO_VIDEO_INFO = 0x00000800;

struct multiboot_header
{
  align(1):
    /* Must be MULTIBOOT_MAGIC - see above. */
    uint magic;
     
    /* Feature flags. */
    uint flags;
     
    /* The above fields plus this one must equal 0 mod 2^32. */
    uint checksum;
     
    /* These are only valid if MULTIBOOT_AOUT_KLUDGE is set. */
    uint header_addr;
    uint load_addr;
    uint load_end_addr;
    uint bss_end_addr;
    uint entry_addr;
     
    /* These are only valid if MULTIBOOT_VIDEO_MODE is set. */
    uint mode_type;
    uint width;
    uint height;
    uint depth;
}

/* The symbol table for a.out. */
struct multiboot_aout_symbol_table
{
  align(1):
    uint tabsize;
    uint strsize;
    uint addr;
    uint reserved;
}

alias multiboot_aout_symbol_table multiboot_aout_symbol_table_t;
     
/* The section header table for ELF. */
struct multiboot_elf_section_header_table
{
  align(1):
    uint num;
    uint size;
    uint addr;
    uint shndx;
}

alias multiboot_elf_section_header_table multiboot_elf_section_header_table_t;

struct multiboot_info
{
  align(1):
    /* Multiboot info version number */
    uint flags;
     
    /* Available memory from BIOS */
    uint mem_lower;
    uint mem_upper;
     
    /* "root" partition */
    uint boot_device;
     
    /* Kernel command line */
    uint cmdline;
     
    /* Boot-Module list */
    uint mods_count;
    uint mods_addr;
     
    union
    {
        multiboot_aout_symbol_table aout_sym;
        multiboot_elf_section_header_table elf_sec;
    };
     
    /* Memory Mapping buffer */
    uint mmap_length;
    uint mmap_addr;
     
    /* Drive Info buffer */
    uint drives_length;
    uint drives_addr;
     
    /* ROM configuration table */
    uint config_table;
     
    /* Boot Loader Name */
    uint boot_loader_name;
     
    /* APM table */
    uint apm_table;
     
    /* Video */
    uint vbe_control_info;
    uint vbe_mode_info;
    ushort vbe_mode;
    ushort vbe_interface_seg;
    ushort vbe_interface_off;
    ushort vbe_interface_len;
}

alias multiboot_info multiboot_info_t;

const MULTIBOOT_MEMORY_AVAILABLE = 1;
const MULTIBOOT_MEMORY_RESERVED = 2;

// TODO: make union (addr, len)
struct multiboot_mmap_entry
{
  align(1):
    uint size;
    uint addr_low, addr_high; //addr;
    uint length_low, length_high; //len;
    uint type;
}

alias multiboot_mmap_entry multiboot_memory_map_t;

struct multiboot_mod_list
{
  align(1):
    /* the memory used goes from bytes 'mod_start' to 'mod_end-1' inclusive */
    uint mod_start;
    uint mod_end;
     
    /* Module command line */
    uint cmdline;
     
    /* padding to take it to 16 bytes (must be zero) */
    uint pad;
}

alias multiboot_mod_list multiboot_module_t;

uint checkFlag(T)(uint flags, T bit) 
{
    return ((flags) & (1 << (bit)));
}
