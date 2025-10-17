module bootloader.limine;

import ldc.attributes;

extern(C):

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
};

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
};

struct LimineFramebufferResponse
{
    ulong revision;
    ulong framebuffer_count;
    LimineFramebuffer** framebuffers;
}

struct LimineFramebufferRequest
{
    ulong[4] id;
    ulong revision;
    LimineFramebufferResponse* response;
}

@(section(".limine_requests"))
__gshared ulong[3] limine_base_revision;

enum ulong[4] LIMINE_FRAMEBUFFER_REQUEST = [
    0xc7b1dd30df4c8b88,
    0x0a82e883a194f07b,
    0x9d5827dcd881dd75,
    0xa3148604f6fab11b
];

@(section(".limine_requests"))
__gshared LimineFramebufferRequest framebufferRequest = LimineFramebufferRequest(LIMINE_FRAMEBUFFER_REQUEST, 0, null);

@(section(".limine_requests_start"))
__gshared ulong[4] limineRequestsStart;

@(section(".limine_requests_end"))
__gshared ulong[2] limineRequestsEnd;
