//
//  accessory.h
//  Battman
//
//  Created by Torrekie on 2025/5/17.
//

#ifndef accessory_h
#define accessory_h

#include <stdio.h>
#include "IOAccessoryManager.h"

#define VID_APPLE 0x05AC
#define VID_UGREEN 0x2B89

typedef struct accessory_info {
	char serial[32];
	char vendor[256];
	char name[256];
	char model[256];
	char fwVer[256];
	char hwVer[256];
	char PPID[256];
} accessory_info_t;

typedef struct accessory_powermode {
	AccessoryPowermode mode;
	AccessoryPowermode active;
	size_t supported_cnt;
	AccessoryPowermode supported[kIOAMPowermodeCount];
	unsigned long supported_lim[kIOAMPowermodeCount];
} accessory_powermode_t;

typedef struct accessory_sleeppower {
	bool supported;
	bool enabled;
	int limit;
} accessory_sleeppower_t;

typedef struct accessory_usb_connstat {
	int type;
	int published_type;
	bool active;
} accessory_usb_connstat_t;

typedef struct accessory_usb_ilim {
	int limit;
	int base;
	int offset;
	int max;
} accessory_usb_ilim_t;

__BEGIN_DECLS

const char *acc_id_string(int accid);
const char *acc_port_type_string(int pt);
const char *manf_id_string(int manf);
const char *apple_prod_id_string(int prod);
void acc_powermode_string(AccessoryPowermode powermode, char **pbuf,
    size_t *remaining);
void acc_powermode_string_supported(accessory_powermode_t mode, char **pbuf,
    size_t *remaining);
void acc_powermode_details_string(accessory_powermode_t mode, char *pbuf,
    size_t capacity);
void acc_usb_ilim_string_multiline(accessory_usb_ilim_t ilim,char*);
const char *acc_usb_connstat_string(int usb_connstat);
void acc_inductive_mode_string(int mode,char*);

io_connect_t acc_open_with_port(int port);

int get_accid(io_connect_t connect);
bool get_acc_battery_pack_mode(io_connect_t connect);
int get_acc_allowed_features(io_connect_t connect);
int get_acc_port_type(io_connect_t connect);
accessory_info_t get_acc_info(io_connect_t connect);
accessory_powermode_t get_acc_powermode(io_connect_t connect);
accessory_sleeppower_t get_acc_sleeppower(io_connect_t connect);
bool get_acc_supervised(io_connect_t connect);
bool get_acc_supervised_transport_restricted(io_connect_t connect);
int get_acc_type(io_connect_t connect);
IOReturn get_acc_digitalid(io_connect_t connect, void *digitalID);
IOReturn get_acc_usb_connstat(io_connect_t connect, accessory_usb_connstat_t *connstat);
IOReturn get_acc_usb_voltage(io_connect_t connect, int *voltage);
IOReturn get_acc_usb_ilim(io_connect_t connect, accessory_usb_ilim_t *ilim);
IOReturn get_acc_idsn(io_connect_t connect, long long *buf);
IOReturn get_acc_msn(io_connect_t connect, void *buf);
int get_acc_inductive_fw_mode(io_connect_t connect);
int get_acc_inductive_region_code(io_connect_t connect);
bool get_acc_inductive_timeout(io_connect_t connect);

__END_DECLS

#endif /* accessory_h */
