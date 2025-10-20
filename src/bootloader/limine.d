module bootloader.limine;

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
    /* Response revision 1 */
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

enum LIMINE_HHDM_REQUEST = [
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

enum LIMINE_KERNEL_ADDRESS_REQUEST = [
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

@(section(".limine_requests"))
__gshared ulong[3] limine_base_revision;

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

@(section(".limine_requests_start"))
__gshared ulong[4] limineRequestsStart;

@(section(".limine_requests_end"))
__gshared ulong[2] limineRequestsEnd;
