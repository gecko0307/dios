module core.vbe;

struct vbe_info
{
    ushort attributes;
    ubyte  window_a, window_b;
    ushort granularity;
    ushort window_size;
    ushort segment_a, segment_b;
    uint   win_func_ptr;
    ushort pitch;
    ushort width;
    ushort height;
    ubyte  w_char, y_char, planes, bpp, banks;
    ubyte  memory_model, bank_size, image_pages;
    ubyte  reserved0;
    ubyte  red_mask, red_position;
    ubyte  green_mask, green_position;
    ubyte  blue_mask, blue_position;
    ubyte  reserved_mask, reserved_position;
    ubyte  direct_color_attributes;
    uint   framebuffer;
    uint   offscreen_mem_off;
    ushort offscreen_mem_size;
    ubyte[206] reserved1;
}
