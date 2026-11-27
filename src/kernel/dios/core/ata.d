module dios.core.ata;

// ATA command opcodes

// General
enum ubyte ATA_CMD_NOP                  = 0x00;
enum ubyte ATA_CMD_DATA_SET_MANAGEMENT  = 0x06;
enum ubyte ATA_CMD_DEVICE_RESET         = 0x08;
enum ubyte ATA_CMD_IDENTIFY_DEVICE      = 0xEC;
enum ubyte ATA_CMD_IDENTIFY_PACKET      = 0xA1;
enum ubyte ATA_CMD_SET_FEATURES         = 0xEF;

// PIO read
enum ubyte ATA_CMD_READ_SECTORS         = 0x20;
enum ubyte ATA_CMD_READ_SECTORS_EXT     = 0x24;
enum ubyte ATA_CMD_READ_MULTIPLE        = 0xC4;
enum ubyte ATA_CMD_READ_MULTIPLE_EXT    = 0x29;

// DMA read
enum ubyte ATA_CMD_READ_DMA             = 0xC8;
enum ubyte ATA_CMD_READ_DMA_EXT         = 0x25;

// PIO write
enum ubyte ATA_CMD_WRITE_SECTORS        = 0x30;
enum ubyte ATA_CMD_WRITE_SECTORS_EXT    = 0x34;
enum ubyte ATA_CMD_WRITE_MULTIPLE       = 0xC5;
enum ubyte ATA_CMD_WRITE_MULTIPLE_EXT   = 0x39;

// DMA write
enum ubyte ATA_CMD_WRITE_DMA            = 0xCA;
enum ubyte ATA_CMD_WRITE_DMA_EXT        = 0x35;
enum ubyte ATA_CMD_WRITE_DMA_FUA_EXT    = 0x3D;

// Verify
enum ubyte ATA_CMD_VERIFY               = 0x40;
enum ubyte ATA_CMD_VERIFY_EXT           = 0x42;

// Cache
enum ubyte ATA_CMD_FLUSH_CACHE          = 0xE7;
enum ubyte ATA_CMD_FLUSH_CACHE_EXT      = 0xEA;

// Queued DMA (NCQ)
enum ubyte ATA_CMD_READ_FPDMA_QUEUED    = 0x60;
enum ubyte ATA_CMD_WRITE_FPDMA_QUEUED   = 0x61;

// Logs
enum ubyte ATA_CMD_READ_LOG_EXT         = 0x2F;
enum ubyte ATA_CMD_WRITE_LOG_EXT        = 0x3F;

// Power management
enum ubyte ATA_CMD_CHECK_POWER_MODE     = 0xE5;
enum ubyte ATA_CMD_STANDBY_IMMEDIATE    = 0xE0;
enum ubyte ATA_CMD_IDLE_IMMEDIATE       = 0xE1;
enum ubyte ATA_CMD_STANDBY              = 0xE2;
enum ubyte ATA_CMD_IDLE                 = 0xE3;
enum ubyte ATA_CMD_SLEEP                = 0xE6;

// Buffer
enum ubyte ATA_CMD_READ_BUFFER          = 0xE4;
enum ubyte ATA_CMD_WRITE_BUFFER         = 0xE8;

// SMART
enum ubyte ATA_CMD_SMART                = 0xB0;

// Device configuration
enum ubyte ATA_CMD_DOWNLOAD_MICROCODE   = 0x92;

// Device register flags
enum ubyte ATA_DEVICE_LBA               = 0x40;
