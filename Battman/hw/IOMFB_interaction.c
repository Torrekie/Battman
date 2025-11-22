//
//  IOMFB_interaction.c
//  Battman
//
//  Created by Torrekie on 2025/6/26.
//

#include "../common.h"
#include "IOMFB_interaction.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <dispatch/dispatch.h>

static CFArrayRef (*IOMobileFramebufferCreateDisplayList)(CFAllocatorRef);
static IOReturn (*IOMobileFramebufferGetMainDisplay)(IOMobileFramebuffer *fb);
static IOReturn (*IOMobileFramebufferOpenByName)(CFStringRef name, IOMobileFramebuffer *fb);
static io_service_t (*IOMobileFramebufferGetServiceObject)(IOMobileFramebuffer fb);
static IOReturn (*IOMobileFramebufferGetBlock)(IOMobileFramebuffer fb, int targetBlock, void *output, ssize_t outputSize, void *input, ssize_t inputSize);

static bool iomfb_capable = false;

#define IOMFB_INIT_CHK(ret)       \
	iomfb_init();                 \
	if (!iomfb_capable) return ret

void iomfb_init(void) {
	static void *handle = NULL;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		handle = dlopen ("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
		if (handle) {
			iomfb_capable = true;
			IOMobileFramebufferCreateDisplayList = dlsym(handle, "IOMobileFramebufferCreateDisplayList");
			IOMobileFramebufferGetMainDisplay = dlsym(handle, "IOMobileFramebufferGetMainDisplay");
			IOMobileFramebufferGetServiceObject = dlsym(handle, "IOMobileFramebufferGetServiceObject");
			IOMobileFramebufferOpenByName = dlsym(handle, "IOMobileFramebufferOpenByName");
			IOMobileFramebufferGetBlock = dlsym(handle, "IOMobileFramebufferGetBlock");
		}
	});
}

double iomfb_primary_screen_temperature(void) {
	IOMFB_INIT_CHK(-1);

	IOReturn ret;
	double temp = -1;
	IOMobileFramebuffer fb;

	ret = IOMobileFramebufferGetMainDisplay(&fb);
	if (ret != kIOReturnSuccess)
		return -1;

	// 0: temperature compensation state [384]
	uint32_t temp_comp[96] = {0};
	ret = IOMobileFramebufferGetBlock(fb, 0, temp_comp, 384, NULL, 0);
	if (ret != kIOReturnSuccess)
		return -1;

	// Q16.16
	if (temp_comp[0] == 3) {
		// version 3
		// temp_comp[91] brightness (nits)
		// temp_comp[92] temperature (c)
		temp = (double)(int)temp_comp[92] * pow(2, -16);
	} else if (temp_comp[0] == 1) {
		// version 1
		// temp_comp[84] temperature (c)
		temp = (double)(int)temp_comp[84] * pow(2, -16);
	} else {
		// Do alert? Can user actually understand what we wanted?
		// consider do a raw dump as log file?
		os_log_error(gLog, "Unknown temp_comp version %d, please report issue at https://github.com/Torrekie/Battman/issues/new", temp_comp[0]);
	}

	return temp;
}
