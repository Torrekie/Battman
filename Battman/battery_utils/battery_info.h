#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "../iokitextern.h"

// this isn't enforced
#define BI_MAX_SECTION_NUM 64

#define BI_APPROX_ROWS 64

/* ->content structure:
STRING:
| Bit   | Value
| 0     | isString (=0)
| 0:31  | stringBufferOffset
SPECIAL:
| Bit   | Value
| 1     | isHidden / skipSection
| 2     | isBoolean
| 3     | affectsBatteryView
| 4     | isFloat
| 5     | isForeground / isHiddenInDetails
| 6:12  | unit (7 bit localization) / sectionSeparator if ==0x7f
| 13    | newSection
| 14    | inDetails
| 15    | hasUnit
| 16:31 | 16-bit value
*/

/* ->content structure:
STRING:
| Bit   | Value
| 0     | isString (=0)
| 0:31  | strPointer (char *, guaranteed &1==0)
SPECIAL:
| Bit   | Value
| 0     | isSpecial
| 1     | isHidden / skipSection
| 2     | isBoolean
| 3     | affectsBatteryView
| 4     | isFloat (may be elimated in future)
| 5     | isForeground / isHiddenInDetails
| 6:12  | unit (7 bit localization) / sectionSeparator if ==0x7f
| 13    | newSection
| 14    | newSectionIsHidden
| 30    | inDetails
| 31    | hasUnit
| 32:63 | value (32-bit)
*/

// Bit 1<<0: NotPointer, bc pointer alignments won't allow such bit
// Bit 1<<1:
#define BIN_IS_STRING               0
#define BIN_IS_SPECIAL              (1 << 0)
#define BIN_IS_BOOLEAN              (1 << 2 | BIN_IS_SPECIAL)
#define BIN_AFFECTS_BATTERY_CELL    (1 << 3)
#define BIN_IS_FLOAT                (1 << 4 | BIN_IS_SPECIAL)
#define BIN_IS_FOREGROUND           (1 << 5 | BIN_IS_FLOAT | BIN_AFFECTS_BATTERY_CELL)
#define BIN_IS_BACKGROUND           (0 | BIN_IS_FLOAT | BIN_AFFECTS_BATTERY_CELL)
#define BIN_IS_HIDDEN               (1 << 1)
#define BIN_UNIT_BITMASK            (((1 << 3) - 1) << 6)
#define BIN_HAS_SUBCELLS (1<<10)
#define BIN_IS_SUBCELL (1<<11)
#define BIN_DEF_SUBCELL (BIN_IS_SUBCELL|1<<5)
#define BIN_SECTION					(1 << 13 | BIN_IS_SPECIAL)
#define BIN_SECTION_HIDDEN			(1 << 14)
#define BIN_SECTION_PRIORITY(p) ((p&0xffff)<<16)
#define DEFINE_SECTION(priority)	BIN_SECTION|BIN_SECTION_PRIORITY(priority)
// ^ Use >>6 when retrieving, max 7 bits
#define BIN_DETAILS_SHARED          (1 << 14 | BIN_IS_SPECIAL)
#define BIN_IN_DETAILS              (1 << 14 | BIN_IS_HIDDEN | BIN_IS_SPECIAL)
#define BIN_HAS_UNIT                (1L << 15)

/*#define BIN_UNIT_DEGREE_C           (0x8384e2 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_PERCENT            (0x25 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MAMP               (0x416d << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MAH                (0x68416d << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MVOLT              (0x566d << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MWATT              (0x576d << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MIN                (0x6e696d << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_HOUR               (0x7248 << 6 | BIN_HAS_UNIT)*/

#define BIN_UNIT_DEGREE_C           (0 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_PERCENT            (1 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MAMP               (2 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MAH                (3 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MVOLT              (4 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MWATT              (5 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_MIN                (6 << 6 | BIN_HAS_UNIT)
#define BIN_UNIT_HOUR               (7 << 6 | BIN_HAS_UNIT)

// max 3 bytes unit, conversion:
// e.g. degreeC is e2 84 83 in utf8,
// convert it to little endian, 0x8384e2, and put in the bitmask.

__BEGIN_DECLS

extern const char *bin_unit_strings[];

struct battery_info_node {
    const char *name; // NONNULL
    const char *desc;
    uint32_t content;
};

// struct battery_info_section
// + 0 - prev
// + 8 - next
// +16 - data
// +16+?*sizeof(struct battery_info_node)-NULL terminator

struct battery_info_section;
struct battery_info_section_context {
	uint64_t custom_identifier;
	void (*update)(struct battery_info_section *);
};

struct accessory_info_section_context {
	uint64_t identifier;
	void (*update)(struct battery_info_section *);
	int primary_port;
	io_service_t connect;
};

#if 0
// For example,
// If we have a section for all bluetooth devices connected,
// the context would be something like:

struct bluetooth_section_context {
	uint64_t identifier;
	void (*update)(struct battery_info_section *);
	CFTypeRef someOpaqueBluetoothObject;
};
// where identifier=hash(mac address)

#endif

#define BI_GAS_GAUGE_SECTION_ID 10
#define BI_GAS_GAUGE_IOKIT_ONLY_SECTION_ID 11
#define BI_ADAPTER_SECTION_ID 12
#define BI_ADAPTER_IOKIT_ONLY_SECTION_ID 12
#define BI_ACCESSORY_SECTION_RANGE(i) (i>=420&&i<440)

// For dynamically allocated sections, any section ID will work
// Implement your own hash function to compute the same ID every time
// for a single accessory.

struct battery_info_section {
	struct battery_info_section **self_ref;
	struct battery_info_section *next;
	struct battery_info_section_context *context;
	struct battery_info_node data[];
};

#define SECTION_PRIORITY(sect) (((sect)->data[0].content>>16)&0xffff)

struct battery_info_section *bi_make_section(const char *name, uint64_t context_size);
void bi_destroy_section(struct battery_info_section *sect);
// This function modifies the value without changing the
// definition bits.
void bi_node_change_content_value(struct battery_info_node *node,
                                  int identifier, uint16_t value);
float bi_node_load_float(struct battery_info_node *node);
void bi_node_change_content_value_float(struct battery_info_node *node,
                                        int identifier, float value);
void bi_node_set_hidden(struct battery_info_node *node, int identifier,
                        bool hidden);
char *bi_node_ensure_string(struct battery_info_node *node, int identifier,
                            uint64_t length);
char *bi_node_get_string(struct battery_info_node *node);
void bi_node_free_string(struct battery_info_node *node);
void battery_info_update(struct battery_info_section **head);
int battery_info_get_section_count(struct battery_info_section *head);
struct battery_info_section *battery_info_get_section(struct battery_info_section *head, long section);
//void battery_info_update_iokit_with_data(struct battery_info_node *head, const void *info, bool inDetail);
//void battery_info_update_iokit(struct battery_info_node *head, bool inDetail);
void battery_info_init(struct battery_info_section **);
int battery_info_remove_section(struct battery_info_section *sect);

__END_DECLS
