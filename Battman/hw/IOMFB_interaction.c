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
static IOReturn (*IOMobileFramebufferGetMainDisplay)(IOMobileFramebufferRef *fb);
static IOReturn (*IOMobileFramebufferOpenByName)(CFStringRef name, IOMobileFramebufferRef *fb);
static io_service_t (*IOMobileFramebufferGetServiceObject)(IOMobileFramebufferRef fb);
static IOReturn (*IOMobileFramebufferGetBlock)(IOMobileFramebufferRef fb, int targetBlock, void *output, ssize_t outputSize, void *input, ssize_t inputSize);

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
	IOMobileFramebufferRef fb;

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

const char *iomfb_primary_screen_panel_id(void) {
	IOMFB_INIT_CHK(NULL);
	
	IOReturn ret;
	io_service_t service = MACH_PORT_NULL;
	IOMobileFramebufferRef fb;
	static char panel_id[512] = {0};

	if (panel_id[0] != 0) {
		os_log_debug(gLog, "Panel_ID cached: %s", panel_id);
		return (const char *)panel_id;
	}

	ret = IOMobileFramebufferGetMainDisplay(&fb);
	if (ret != kIOReturnSuccess) {
		os_log_error(gLog, "IOMobileFramebufferGetMainDisplay failed: 0x%x", ret);
		return NULL;
	}
	
	if (!fb) {
		os_log_error(gLog, "IOMobileFramebufferRef is NULL");
		return NULL;
	}
	
	os_log_debug(gLog, "Got IOMobileFramebufferRef: %p", fb);
	
	service = IOMobileFramebufferGetServiceObject(fb);
	if (!service) {
		os_log_error(gLog, "IOMobileFramebufferGetServiceObject returned NULL service");
		return NULL;
	}
	
	os_log_debug(gLog, "Got service object: 0x%x", service);

	CFTypeRef buffer = IORegistryEntryCreateCFProperty(service, CFSTR("Panel_ID"), kCFAllocatorDefault, 0);
	if (!buffer) {
		os_log_error(gLog, "IORegistryEntryCreateCFProperty for Panel_ID returned NULL");
		return NULL;
	}
	
	CFTypeID typeID = CFGetTypeID(buffer);
	os_log_debug(gLog, "Panel_ID property type: %lu (CFString=%lu, CFData=%lu)", 
		typeID, CFStringGetTypeID(), CFDataGetTypeID());
	
	const char *result = NULL;
	if (typeID == CFStringGetTypeID()) {
		CFStringRef strRef = (CFStringRef)buffer;
		CFIndex length = CFStringGetLength(strRef);
		os_log_debug(gLog, "CFString length: %ld characters", length);
		
		// Try to get raw description
		CFStringRef description = CFCopyDescription(strRef);
		if (description) {
			char desc[512] = {0};
			if (CFStringGetCString(description, desc, sizeof(desc), kCFStringEncodingUTF8)) {
				os_log_debug(gLog, "CFString description: %s", desc);
			}
			CFRelease(description);
		}
		
		// Try UTF-8 first
		if (CFStringGetCString(strRef, panel_id, sizeof(panel_id), kCFStringEncodingUTF8)) {
			os_log_debug(gLog, "Panel_ID string retrieved (UTF-8), length: %zu", strlen(panel_id));
			if (strlen(panel_id) != 0) {
				os_log_info(gLog, "Panel_ID: %s", panel_id);
				result = panel_id;
			} else {
				os_log_error(gLog, "Panel_ID string is empty");
			}
		} else {
			os_log_error(gLog, "CFStringGetCString failed with UTF-8, trying ASCII...");
			
			// Try ASCII encoding
			if (CFStringGetCString(strRef, panel_id, sizeof(panel_id), kCFStringEncodingASCII)) {
				os_log_info(gLog, "Panel_ID retrieved with ASCII: %s", panel_id);
				result = panel_id;
			} else {
				os_log_error(gLog, "ASCII encoding also failed, trying raw bytes...");
				
				// Try to get raw bytes as hex
				const char *cstr = CFStringGetCStringPtr(strRef, kCFStringEncodingUTF8);
				if (cstr) {
					os_log_info(gLog, "Got C string pointer: %s", cstr);
					strncpy(panel_id, cstr, sizeof(panel_id) - 1);
					result = panel_id;
				} else {
					// Last resort: get as external representation (UTF-8 data)
					CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, strRef, kCFStringEncodingUTF8, 0);
					if (data) {
						CFIndex dataLen = CFDataGetLength(data);
						os_log_debug(gLog, "External representation length: %ld bytes", dataLen);
						if (dataLen > 0 && dataLen < sizeof(panel_id)) {
							const UInt8 *bytes = CFDataGetBytePtr(data);
							memcpy(panel_id, bytes, dataLen);
							panel_id[dataLen] = '\0';
							
							// Log first 32 bytes as hex for debugging
							char hexbuf[128] = {0};
							CFIndex hexLen = dataLen < 32 ? dataLen : 32;
							for (CFIndex i = 0; i < hexLen; i++) {
								snprintf(hexbuf + (i * 3), sizeof(hexbuf) - (i * 3), "%02x ", bytes[i]);
							}
							os_log_debug(gLog, "Panel_ID hex (first %ld bytes): %s", hexLen, hexbuf);
							
							// Store as UTF-8 string (supports Unicode like U+02C7 ˇ)
							os_log_info(gLog, "Panel_ID retrieved (%ld UTF-8 bytes): %s", dataLen, panel_id);
							result = panel_id;
						} else {
							os_log_error(gLog, "Panel_ID data too large (%ld bytes) for buffer (%zu bytes)", dataLen, sizeof(panel_id));
						}
						CFRelease(data);
					} else {
						os_log_error(gLog, "All string extraction methods failed");
					}
				}
			}
		}
	} else if (typeID == CFDataGetTypeID()) {
		os_log_error(gLog, "Panel_ID is CFData type, not CFString. Data length: %ld", CFDataGetLength((CFDataRef)buffer));
	} else {
		os_log_error(gLog, "Panel_ID has unexpected type");
	}
	
	CFRelease(buffer);
	return result;
}
