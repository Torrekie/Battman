//
//  dcp.c
//  Battman
//
//  Created by Torrekie on 2025/11/13.
//

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include "../common.h"
#include "../hw/IOMFB_interaction.h"

static int is_dcp = -1;

bool dcp_backlight(void) {
	io_service_t service;
	if (is_dcp == -1) {
		/* IOService:/AppleARMPE/arm-io@XXXXXXX/AppleXXXX/dcp@XXXXXX */
		service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceNameMatching("dcp"));
		if (service) {
#ifdef DEBUG
			/* Only call IORegistryEntryGetPath when DEBUG */
			char path[PATH_MAX];
			kern_return_t result = IORegistryEntryGetPath(service, kIOServicePlane, path);
			if (result != KERN_SUCCESS) DBGLOG(CFSTR("Failed to get DCP path (%s)"), mach_error_string(result));
			DBGLOG(CFSTR("Found DCP: %s"), path);
#endif
			is_dcp = 1;
			IOObjectRelease(service);
			return true;
		}
	}
	
	return (is_dcp == 1);
}
