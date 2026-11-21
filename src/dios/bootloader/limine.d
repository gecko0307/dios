module dios.bootloader.limine;

import ldc.attributes;

extern(C):

struct LimineUUID
{
    uint a;
    ushort b;
    ushort c;
    ubyte[8] d;
};

enum LIMINE_MEDIA_TYPE_GENERIC = 0;
enum LIMINE_MEDIA_TYPE_OPTICAL = 1;
enum LIMINE_MEDIA_TYPE_TFTP = 2;

struct LimineFile
{
    ulong revision;
    void* address;
    ulong size;
    char* path;
    char* cmdline;
    uint media_type;
    uint unused;
    uint tftp_ip;
    uint tftp_port;
    uint partition_index;
    uint mbr_disk_id;
    LimineUUID gpt_disk_uuid;
    LimineUUID gpt_part_uuid;
    LimineUUID part_uuid;
}

struct LimineVideoMode
{
    ulong pitch;
    ulong width;
    ulong height;
    ushort bpp;
    ubyte memory_model;
    ubyte red_mask_size;
    ubyte red_mask_shift;
    ubyte green_mask_size;
    ubyte green_mask_shift;
    ubyte blue_mask_size;
    ubyte blue_mask_shift;
}

struct LimineFramebuffer
{
    void* address;
    ulong width;
    ulong height;
    ulong pitch;
    ushort bpp;
    ubyte memory_model;
    ubyte red_mask_size;
    ubyte red_mask_shift;
    ubyte green_mask_size;
    ubyte green_mask_shift;
    ubyte blue_mask_size;
    ubyte blue_mask_shift;
    ubyte[7] unused;
    ulong edid_size;
    void* edid;
    // Response revision 1
    ulong mode_count;
    LimineVideoMode** modes;
}

struct LimineFramebufferResponse
{
    ulong revision;
    ulong framebuffer_count;
    LimineFramebuffer** framebuffers;
}

enum LIMINE_MEMMAP_USABLE = 0;
enum LIMINE_MEMMAP_RESERVED = 1;
enum LIMINE_MEMMAP_ACPI_RECLAIMABLE = 2;
enum LIMINE_MEMMAP_ACPI_NVS = 3;
enum LIMINE_MEMMAP_BAD_MEMORY = 4;
enum LIMINE_MEMMAP_BOOTLOADER_RECLAIMABLE = 5;
enum LIMINE_MEMMAP_KERNEL_AND_MODULES = 6;
enum LIMINE_MEMMAP_FRAMEBUFFER = 7;

struct LimineMemmapEntry
{
    ulong base;
    ulong length;
    ulong type;
}

struct LimineMemmapResponse
{
    ulong revision;
    ulong entry_count;
    LimineMemmapEntry** entries;
}

struct LimineFramebufferRequest
{
    ulong[4] id;
    ulong revision;
    LimineFramebufferResponse* response;
}

struct LimineMemmapRequest
{
    ulong[4] id;
    ulong revision;
    LimineMemmapResponse* response;
}

enum LIMINE_COMMON_MAGIC1 = 0xc7b1dd30df4c8b88;
enum LIMINE_COMMON_MAGIC2 = 0x0a82e883a194f07b;

enum ulong[4] LIMINE_MEMMAP_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0x67cf3d9d378a806f,
    0xe304acdfc50c3c62
];

enum ulong[4] LIMINE_FRAMEBUFFER_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0x9d5827dcd881dd75,
    0xa3148604f6fab11b
];

enum ulong[4] LIMINE_KERNEL_FILE_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0xad97e90e83f1ed67,
    0x31eb5d1c5ff23b69
];

struct LimineKernelFileResponse
{
    ulong revision;
    LimineFile* kernel_file;
}

struct LimineKernelFileRequest
{
    ulong[4] id;
    ulong revision;
    LimineKernelFileResponse* response;
}

enum ulong[4] LIMINE_HHDM_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0x48dcf1cb8ad2b852,
    0x63984e959a98244b
];

struct LimineHHDMResponse
{
    ulong revision;
    ulong offset;
};

struct LimineHHDMRequest
{
    ulong[4] id;
    ulong revision;
    LimineHHDMResponse* response;
};

enum ulong[4] LIMINE_KERNEL_ADDRESS_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0x71ba76863cc55f63,
    0xb2644a48c516a487
];

struct LimineKernelAddressResponse
{
    ulong revision;
    ulong physical_base;
    ulong virtual_base;
};

struct LimineKernelAddressRequest
{
    ulong[4] id;
    ulong revision;
    LimineKernelAddressResponse* response;
};

enum ulong[4] LIMINE_RSDP_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0xc5e77b6b397e7b43,
    0x27637845accdcf3c
];

struct LimineRsdpResponse
{
    ulong revision;
    void* address;   // physical with base revision 3, HHDM-virtual before: acpi.d accepts both
};

struct LimineRsdpRequest
{
    ulong[4] id;
    ulong revision;
    LimineRsdpResponse* response;
};

enum ulong[4] LIMINE_MODULE_REQUEST = [
    LIMINE_COMMON_MAGIC1,
    LIMINE_COMMON_MAGIC2,
    0x3e7e279702be32af,
    0xca1c4f3bd1280cee
];

struct LimineModuleResponse
{
    ulong revision;
    ulong module_count;
    LimineFile** modules;
}

struct LimineModuleRequest
{
    ulong[4] id;
    ulong revision;
    LimineModuleResponse* response;
};

// Base revision tag. The bootloader looks for these exact magic values; with
// zeros here it silently falls back to revision 0 (identity map of the first
// 4 GiB, which hid the fact that the kernel dereferenced physical addresses).
// The bootloader sets limine_base_revision[2] to 0 if it accepts revision 3.
@(section(".limine_requests"))
__gshared ulong[3] limine_base_revision = [0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3];

bool limineBaseRevisionSupported() @nogc nothrow
{
    return limine_base_revision[2] == 0;
}

@(section(".limine_requests"))
__gshared LimineKernelFileRequest kernelFileRequest = LimineKernelFileRequest(LIMINE_KERNEL_FILE_REQUEST, 0, null);

@(section(".limine_requests"))
__gshared LimineFramebufferRequest framebufferRequest = LimineFramebufferRequest(LIMINE_FRAMEBUFFER_REQUEST, 0, null);

@(section(".limine_requests"))
__gshared LimineMemmapRequest memmapRequest = LimineMemmapRequest(LIMINE_MEMMAP_REQUEST, 0, null);

@(section(".limine_requests"))
__gshared LimineHHDMRequest hhdmRequest = LimineHHDMRequest(LIMINE_HHDM_REQUEST, 0, null);

@(section(".limine_requests"))
__gshared LimineKernelAddressRequest kernelAddressRequest = LimineKernelAddressRequest(LIMINE_KERNEL_ADDRESS_REQUEST, 0, null);

@(section(".limine_requests"))
__gshared LimineRsdpRequest rsdpRequest = LimineRsdpRequest(LIMINE_RSDP_REQUEST, 0, null);

@(section(".limine_requests"))
__gshared LimineModuleRequest moduleRequest = LimineModuleRequest(LIMINE_MODULE_REQUEST, 0, null);

@(section(".limine_requests_start"))
__gshared ulong[4] limineRequestsStart = [0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9];

@(section(".limine_requests_end"))
__gshared ulong[2] limineRequestsEnd = [0xadc0e0531bb10d03, 0x9572709f31764c62];
