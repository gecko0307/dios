module dios.core.pic;

/**
 * The legacy 8259 PIC. We do not use it - the IOAPIC replaces it - but it
 * powers up wired to vectors 0x08-0x0F, which collide with CPU exceptions, and
 * firmware may have left lines unmasked. So: remap it out of the exception
 * range, then mask every line.
 */
import dios.core.port;
import dios.core.idt;

enum ushort PIC1_CMD  = 0x20;
enum ushort PIC1_DATA = 0x21;
enum ushort PIC2_CMD  = 0xA0;
enum ushort PIC2_DATA = 0xA1;

extern(C):

// Old chips need a moment between writes; port 0x80 is the traditional delay.
void picIoWait() @nogc nothrow
{
    kPortWriteByte(0x80, 0);
}

void picDisable() @nogc nothrow
{
    kPortWriteByte(PIC1_CMD, 0x11);  picIoWait();   // ICW1: init, ICW4 follows
    kPortWriteByte(PIC2_CMD, 0x11);  picIoWait();
    kPortWriteByte(PIC1_DATA, cast(ubyte)VEC_PIC_BASE);       picIoWait(); // ICW2: vector offsets
    kPortWriteByte(PIC2_DATA, cast(ubyte)(VEC_PIC_BASE + 8)); picIoWait();
    kPortWriteByte(PIC1_DATA, 4);    picIoWait();   // ICW3: slave on IRQ2
    kPortWriteByte(PIC2_DATA, 2);    picIoWait();   //       slave identity
    kPortWriteByte(PIC1_DATA, 0x01); picIoWait();   // ICW4: 8086 mode
    kPortWriteByte(PIC2_DATA, 0x01); picIoWait();
    kPortWriteByte(PIC1_DATA, 0xFF); // mask everything
    kPortWriteByte(PIC2_DATA, 0xFF);
}
