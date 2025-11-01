/* Copyright (c) 2024 Torrekie Gen <me@torrekie.dev>
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Library General Public License as published
 * by the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include "libsmc.h"
#include "../common.h"
#include "../iokitextern.h"
#include "../intlextern.h"
#include <dispatch/dispatch.h>
#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFString.h>
#include <string.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#if __has_include(<mach/mach.h>)
#include <mach/mach.h>
#else
typedef unsigned int mach_port_t;
extern mach_port_t mach_task_self_;
#define mach_task_self() mach_task_self_
#endif

#if __has_include(<IOKit/pwr_mgt/IOPM.h>)
#include <IOKit/pwr_mgt/IOPM.h>
#else
enum {
    kIOPSFamilyCodeDisconnected = 0,
    kIOPSFamilyCodeUnsupported  = 0xE00002C7,

    kIOPSFamilyCodeFirewire     = 0xE0008000,

    kIOPSFamilyCodeUSBHost      = 0xE0004000,
    kIOPSFamilyCodeUSBHostSuspended,
    kIOPSFamilyCodeUSBDevice,
    kIOPSFamilyCodeUSBAdapter,
    kIOPSFamilyCodeUSBChargingPortDedicated,
    kIOPSFamilyCodeUSBChargingPortDownstream,
    kIOPSFamilyCodeUSBChargingPort,
    kIOPSFamilyCodeUSBUnknown,
    kIOPSFamilyCodeUSBCBrick,
    kIOPSFamilyCodeUSBCTypeC,
    kIOPSFamilyCodeUSBCPD,
    kIOPSFamilyCodeAC           = 0xE0024000,
    kIOPSFamilyCodeExternal,
    kIOPSFamilyCodeExternal2,
    kIOPSFamilyCodeExternal3,
    kIOPSFamilyCodeExternal4,
    kIOPSFamilyCodeExternal5,
    kIOPSFamilyCodeExternal6,
    kIOPSFamilyCodeExternal7
};
#endif

#define SMC_INIT_CHK(FAIL_RETURN)       \
    IOReturn result = kIOReturnSuccess; \
    if (gConn == 0) result = smc_open();\
    if (result != kIOReturnSuccess)     \
    return FAIL_RETURN

int hasSMC=1;

extern void app_exit(void);

static io_service_t gConn = 0;
gas_gauge_t gGauge = {0};
board_info_t gBoard = {0};

IOReturn smc_open(void) {
	if(!hasSMC)
		goto fail;
    IOReturn result;
    mach_port_t masterPort;
    io_service_t service;
    const char *fail_title = NULL;
    //char message[1024];

    // Init frequently used texts to global string
    init_common_text();

    if (IOMasterPort(MACH_PORT_NULL, &masterPort) != kIOReturnSuccess) {
        DBGLOG(CFSTR("IOMasterPort() failed"));
        fail_title = _C("IOMainPort Open Failed");
        goto fail;
    }

    service = IOServiceGetMatchingService(masterPort, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) {
        fail_title = _C("AppleSMC Unsupported");
        goto fail_unsupported;
    }

    result = IOServiceOpen(service, mach_task_self(), 0, &gConn);
    if (result != kIOReturnSuccess) {
        /* TODO: Check entitlements and explicitly warn which we loss */
        fail_title = _C("AppleSMC Open Failed");
        DBGLOG(CFSTR("IOServiceOpen() failed (%d)"), result);
        goto fail;
    }

    return kIOReturnSuccess;

fail_unsupported:
    hasSMC = 0;
fail:
    // Info will be fetched via IOPMPowerSource if no SMC present
    /*if (is_carbon())
        show_fatal_overlay_async(fail_title, _C("This typically means you did not install Battman with correct entitlements, please reinstall by checking instructions at https://github.com/Torrekie/Battman"));
	return kIOReturnError;
fail_unsupported:
    if (is_carbon()) {
        sprintf(message, _C("Your device (%s) does not support AppleSMC. Battman requires AppleSMC to function properly."), target_type());
        show_fatal_overlay_async(fail_title, message);
    }*/
    return kIOReturnError;
}

IOReturn smc_call(int index, SMCParamStruct *inputStruct,
                         SMCParamStruct *outputStruct) {
    size_t inputSize, outputSize;

    inputSize = sizeof(SMCParamStruct);
    outputSize = sizeof(SMCParamStruct);

    return IOConnectCallStructMethod(gConn, index, inputStruct, inputSize,
                                     outputStruct, &outputSize);
}

static IOReturn smc_get_keyinfo(UInt32 key, SMCKeyInfoData *keyInfo) {
    SMCParamStruct inputStruct={0};
    SMCParamStruct outputStruct;
    IOReturn result;

    inputStruct.key = key;
    inputStruct.param.data8 = kSMCGetKeyInfo;

    result = smc_call(kSMCHandleYPCEvent, &inputStruct, &outputStruct);

    // Important check: dataSize != 0
    // idk why a nonexist key could return kIOReturnSuccess
    if (outputStruct.param.keyInfo.dataSize == 0)
        result = kIOReturnError;
    
    if (result == kIOReturnSuccess) {
        *keyInfo = outputStruct.param.keyInfo;
    }

    return result;
}

IOReturn smc_write_safe(uint32_t key, void *bytes, uint32_t size) {
	SMCParamStruct input={0};
	SMCParamStruct out;
	IOReturn result;
	if((result = smc_get_keyinfo(key, &input.param.keyInfo)))
		return result;
	if(input.param.keyInfo.dataSize>size) {
		DBGLOG(CFSTR("smc_write_safe failed: data too short"));
		return -1;
	}
	input.param.data8=kSMCWriteKey;
	input.key=key;
	memcpy(input.param.bytes,bytes,input.param.keyInfo.dataSize);
	result=smc_call(kSMCHandleYPCEvent, &input,&out);
	if(result != kIOReturnSuccess) {
		DBGLOG(CFSTR("smc_call failed %d"), result);
		return result;
	}
	return kIOReturnSuccess;
}

IOReturn smc_read_safe(uint32_t key, void *bytes, int32_t *size) {
    IOReturn result;
    SMCParamStruct inputStruct={0};
    SMCParamStruct outputStruct;

    inputStruct.key = key;

    result = smc_get_keyinfo(inputStruct.key, &inputStruct.param.keyInfo);
    if (result != kIOReturnSuccess) {
        return result;
    }

	int omit_mismatch_warning=0;
	if(*size<0) {
		*size=-(*size);
		omit_mismatch_warning=1;
	}
	key=htonl(key);
	if(*size<inputStruct.param.keyInfo.dataSize) {
		DBGLOG(CFSTR("smc_read_safe %.4s WARNING: buffer too short: buf len %d; has %d; will truncate"),(char*)&key,*size,inputStruct.param.keyInfo.dataSize);
		//return -1;
	}else if(*size!=inputStruct.param.keyInfo.dataSize) {
		if(!omit_mismatch_warning)
			DBGLOG(CFSTR("smc_read_safe %.4s WARNING: size mismatch: buf len %d; has %d"),(char*)&key,*size,inputStruct.param.keyInfo.dataSize);
		*size=inputStruct.param.keyInfo.dataSize;
	}

    inputStruct.param.data8 = kSMCReadKey;
    
    result = smc_call(kSMCHandleYPCEvent, &inputStruct, &outputStruct);
    if (result != kIOReturnSuccess) {
        DBGLOG(CFSTR("smc_call failed %d"), result);
        return result;
    }

    memcpy(bytes, outputStruct.param.bytes, *size);

    return kIOReturnSuccess;
}

IOReturn smc_read_n(uint32_t key, void *bytes, int32_t size) {
	return smc_read_safe(key,bytes,&size);
}

//IOReturn smc_read(uint32_t key, void *bytes) {
//	// TODO: Deprecate, use safe ones instead.
//	return smc_read_n(key,bytes,-1024);
//}

static float ioft2flt(void *bytes) {
	return (float)*(uint64_t*)bytes / 65536.0f;
}

__attribute__((destructor)) static void smc_close(void) {
    if (gConn != 0)
        IOServiceClose(gConn);
}

const board_info_t *get_board_info(void) {
    static bool retrieved = false;

    /* These info are constants, only retrieve once and set gBoard */
    if (!retrieved) {
        /* RGEN(ui8 ) Generation */
        smc_read_n('RGEN', &gBoard.Generation,1);
        /* RESV(ch8)[16] EmbeddedOSVersion */
        smc_read_n('RESV', &gBoard.EmbeddedOSVersion,16);
        /* RECI(ui64) ChipEcid */
        smc_read_n('RECI', &gBoard.ChipEcid,8);
        /* RCRV(ui32) ChipRev */
        smc_read_n('RCRV', &gBoard.ChipRev, 4);
        /* RBRV(ui32) BoardRev */
        smc_read_n('RBRV', &gBoard.BoardRev, 4);
        /* RBID(ui32) BoardId */
        smc_read_n('RBID', &gBoard.BoardId, 4);
        /* RPlt(ch8)[8] TargetName */
        smc_read_n('RPlt', &gBoard.TargetName,8);

        retrieved = true;
    }

    return &gBoard;
}

/* Fan Control Keys:
 F?Dc(flt ) PercentPWM
 F?Md(ui8 ) Mode
 F?Ac(flt ) CurrentSpeed
 F?Mn(flt ) MinSpeed
 F?Mx(flt ) MaxSpeed
 F?St(ui8 ) Stat?
 F?Tg(flt ) TargetAccess
 FBAD(hex_)[4] BadFanFlags
 FNum(ui8 ) NumFans
 FOFC(ui32) fanInOffStateCnt
 FOff(ui8 ) fanOffModeEnabled
 FRmn(ui16) fanRampRateIgnore
 FRmp(ui16) fanRampLimited
 */
/* TODO: Return arrays */
int get_fan_status(void) {
    SMC_INIT_CHK(0);

    uint8_t fan_num;

    result = smc_read_n('FNum', &fan_num,1);
    /* No hardware fan support, or permission deined */
    if (result != kIOReturnSuccess)
        return 0;

    /* FNum(ui8) == 0, no fans on device */
    if (!fan_num)
        return 0;

    /* If have fans, check 'F*Ac', which is current speed */
    for (int i = 0; i < fan_num; i++) {
        float retval;
        result = smc_read_n('F\0Ac' | ((0x30 + i) << 0x10), &retval, 4);
        /* F*Ac(flt), return 1 if any fan working */
        if (retval > 0.0)
            return 1;
    }

    return 0;
}

#pragma mark - Temperatures

/* Known keys:
 TP?d(ioft): PMU tdev ?
 
 */

float get_temperature(void) {
    SMC_INIT_CHK(-1);

    uint16_t retval;

    result = smc_read_n('B0AT', &retval, 2);
    if (result != kIOReturnSuccess)
        return -1;

    return (float)retval * 0.01f;
}

float *get_temperature_per_cell(void) {
    IOReturn result = kIOReturnSuccess;
    float retval;
    uint8_t ioftret[8];

    int num = batt_cell_num();

    float *cells = malloc(sizeof(float) * num);
    /* TB?T(flt ): Cell ? real-time temperature */
    for (int i = 0; i < num; i++) {
        result = smc_read_n('TB\0T' | ((0x30 + i) << 0x8), &retval,4);
        if (result != kIOReturnSuccess) {
            /* In design, you should able to get temps of all your cells */
            break;
        }
        cells[i] = retval;
    }

    /* TB*T may not exist on mobile devices */
    if (result != kIOReturnSuccess) {
        /* TG?B(ioft): Cell ? existance & real-time temperature */
        for (int i = 0; i < num; i++) {
            result = smc_read_n('TG\0B' | ((0x30 + i) << 0x8), &ioftret, 8);
            if (result != kIOReturnSuccess) {
                /* In design, you should able to get temps of all your cells */
                free(cells);
                return NULL;
            }
            cells[i] = ioft2flt(ioftret);
        }
    }

    return cells;
}

int get_time_to_empty(void) {
    SMC_INIT_CHK(0);

    uint16_t retval = 0, retval_f = 0, retval_e = 0;
    uint8_t charging = 0;

    // TODO: Add this to NSUserDefaults to avoid checks every time
    static SMCKey reliable_TTE = 0;

#if TARGET_OS_EMBEDDED && !TARGET_OS_SIMULATOR
    /* This is weird, why B0TF means TimeToEmpty on Embedded,
     * but TimeToFullCharge on macOS? */
    /* Tested on iPhone 12 mini: B0TF does not exist */
    result = smc_read_n('B0TF', &retval,2);
    if (result == kIOReturnSuccess)
        retval_f = retval;
#endif

    result = smc_read_n('B0TE', &retval,2);
    if (result == kIOReturnSuccess)
        retval_e = retval;

    result = smc_read_n('CHSC', &charging,1);
    if (result != kIOReturnSuccess)
        charging = 0;

    /* Lets do complex condition matching */
    /* 1. Both B0TE and B0TF exists */
    if (retval_f && retval_e) {
        /* Even though B0TE always means TimeToEmpty, we still need to ensure */
        if ((!charging && retval_e == 65535) || (charging && retval_f == 65535)) {
            reliable_TTE = 'B0TF';
            retval = retval_f;
        }
        /* Some devices does not set -1 in any scene, how we handle this? */
        retval = retval_e;
    }
    /* 2. Only B0TF but B0TF means TimeToFull */
    if ((!retval_e && retval_f) && (!charging && retval_f == 65535)) {
        return -1;
    }
    /* 3. Only B0TE but B0TE means TimeToFull */
    if ((retval_e && !retval_f) && (!charging && retval_e == 65535)) {
        return -1;
    }
    /* 4. Ideal scene, which B0TE actually means TimeToEmpty */
    if (retval_e) {
        reliable_TTE = 'B0TE';
    }

    return retval;
}

int estimate_time_to_full() {
    SMC_INIT_CHK(0);

    int16_t current;
    uint16_t fullcap;

    /* B0FC(ui16) FullChargeCapacity (mAh) */
    result = smc_read_n('B0FC', &fullcap,2);
    if (result != kIOReturnSuccess)
        return 0;

    /* B0AC(si16) AverageCurrent (mA) */
    /* TODO: B0IV(si16) InstantAmperage */
    result = smc_read_n('B0AC', &current,2);
    if (result != kIOReturnSuccess)
        return 0;

    /* Not charging */
    if (current < 0)
        return 0;

    /* TimeToFullCharge = FullChargeCapacity (mAh) / AverageCurrent (mA) */
    return (fullcap / current);
}

float get_battery_health(float *design_cap, float *full_cap) {
    SMC_INIT_CHK(0);

    uint16_t fullcap;
    uint16_t designcap;

    /* B0FC(ui16) FullChargeCapacity (mAh) */
    result = smc_read_n('B0FC', &fullcap,2);
    if (result != kIOReturnSuccess)
        return 0;

    /* B0DC(ui16) DesignCapacity (mAh) */
    result = smc_read_n('B0DC', &designcap,2);
    if (result != kIOReturnSuccess)
        return 0;

    if (design_cap) {
        *design_cap = designcap;
    }
    if (full_cap) {
        *full_cap = fullcap;
    }
    /* Health = 100.0f * FullChargeCapacity (mAh) / DesignCapacity (mAh) */
    return (100.0f * fullcap / designcap);
}

bool get_capacity(uint16_t *remaining, uint16_t *full, uint16_t *design) {
    if(!remaining && !full && !design)
        return true;
    
    if (!gConn && smc_open())
        return false;

    int num = batt_cell_num();
    if (num == -1) num = 1;

    uint16_t B0RM, B0FC, B0DC;
    B0RM = B0FC = B0DC = 0;

    /* B0RM(ui16) RemainingCapacity (mAh) */
    IOReturn result = smc_read_n('B0RM', &B0RM, 2);
    if (result != kIOReturnSuccess)
        return false;

    /* B0FC(ui16) FullChargeCapacity (mAh) */
    result = smc_read_n('B0FC', &B0FC, 2);
    if (result != kIOReturnSuccess)
        return false;

    /* B0DC(ui16) DesignCapacity (mAh) */
    result = smc_read_n('B0DC', &B0DC, 2);
    if (result != kIOReturnSuccess)
        return false;

	SMCParamStruct input= {0};
	result = smc_get_keyinfo('B0RM', &input.param.keyInfo);
	if (result == kIOReturnSuccess) {
		uint8_t atrib = input.param.keyInfo.dataAttributes;
		if (atrib & 0x10) {
			/* The known scene where the B0RM endian reversed is when it has attribute 'Function' */
			B0RM = ((B0RM & 0xFF) << 8) | (B0RM >> 8);
		}
	} else {
		// Fallback
		/* B0RM should be read reversed that scene (e.g. 0x760D -> 0x0D76) */
		if (B0RM > (1.1f * B0DC) && (((B0RM & 0xFF) << 8) | (B0RM >> 8)) > 0) {
			B0RM = ((B0RM & 0xFF) << 8) | (B0RM >> 8);
		}
	}

    if (remaining)
        *remaining = B0RM * num;
    if (full)
        *full = B0FC * num;
    if (design)
        *design = B0DC * num;

    return result == kIOReturnSuccess;
}

bool get_gas_gauge(gas_gauge_t *gauge) {
    SMC_INIT_CHK(false);

    // Zero before use
    memset(gauge, 0, sizeof(gas_gauge_t));

    /* TODO: Continue shorten those code */

    /* B0AT(ui16): Temperature */
    smc_read_n('B0AT', &gauge->Temperature,2);

    /* B0AV/BC1V(ui16): Average Voltage */
    smc_read_n('B0AV', &gauge->Voltage,2);
    
    /* B0FI(char[2]): Flags */
    smc_read_n('B0FI', &gauge->Flags,2);
    
    /* B0RM(ui16): RemainingCapacity */
    smc_read_n('B0RM', &gauge->RemainingCapacity,2);
    
    /* B0FC(ui16): FullChargeCapacity */
    smc_read_n('B0FC', &gauge->FullChargeCapacity,2);

    /* B0AC(si16): AverageCurrent */
    smc_read_n('B0AC', &gauge->AverageCurrent,2);

    /* B0TF(ui16): TimeToEmpty */
    smc_read_n('B0TF', &gauge->TimeToEmpty,2);

    /* BQX1(ui16): Qmax */
    smc_read_n('BQX1', &gauge->Qmax,2);

    /* B0AP(si16/si32): AveragePower */
    smc_read_n('B0AP', &gauge->AveragePower,2);

    /* B0OC(si16): OCV_Current */
    smc_read_n('B0OC', &gauge->OCV_Current,2);

    /* B0OV(ui16): OCV_Voltage */
    smc_read_n('B0OV', &gauge->OCV_Voltage,2);

    /* B0CT(ui16): CycleCount */
    smc_read_n('B0CT', &gauge->CycleCount,2);

    /* BRSC(ui16): StateOfCharge */
    smc_read_n('BRSC', &gauge->StateOfCharge,2);

    /* B0TC(si16): TrueRemainingCapacity */
    smc_read_n('B0TC', &gauge->TrueRemainingCapacity,2);

    /* BQCC(si16): PassedCharge */
    smc_read_n('BQCC', &gauge->PassedCharge,2);

    /* BQD1(ui16): DOD0 */
    smc_read_n('BQD1', &gauge->DOD0,2);
    
    /* TODO: BDD1(ui8/ui16): PresentDOD / MinDOD */
    /* ui8 (%), ui16 (mAh) */
    // smc_read_n('BDD1', &gauge->PresentDOD,-2);

    /* B0DC(ui16): DesignCapacity */
    smc_read_n('B0DC', &gauge->DesignCapacity,2);

    /* B0IM(si16): IMAX */
    smc_read_n('B0IM', &gauge->IMAX,2);

    /* B0NC(ui16): NCC */
    smc_read_n('B0NC', &gauge->NCC,2);

    /* B0RS(si16): ResScale */
    smc_read_n('B0RS', &gauge->ResScale,2);

    /* B0MS(ui16): ITMiscStatus */
    smc_read_n('B0MS', &gauge->ITMiscStatus,2);

    /* B0I2(si16): IMAX2 */
    smc_read_n('B0I2', &gauge->IMAX2,2);

    /* B0CI(char[4]): ChemID */
    smc_read_n('B0CI', &gauge->ChemID,4);

    /* B0SR(si16): SimRate */
    smc_read_n('B0SR', &gauge->SimRate,2);

    /* Extensions */

    /* BMDN(ch8*)[32]: DeviceName (MacBooks Only) */
    smc_read_n('BMDN', &gauge->DeviceName,32);

    /* B0CU(ui16): DesignCycleCount (MacBooks Only) */
    smc_read_n('B0CU', &gauge->DesignCycleCount,2);

    /* BMSC(ui8): DailyMaxSoc */
    smc_read_n('BMSC', &gauge->DailyMaxSoc,1);

    /* BNSC(ui8): DailyMinSoc */
    smc_read_n('BNSC', &gauge->DailyMinSoc,1);

    /* BUIC(ui8 ): UI Displayed SoC */
    smc_read_n('BUIC', &gauge->UISoC,1);

    /* B0SC(si8 ): Chemical SoC */
    smc_read_n('B0SC', &gauge->ChemicalSoC,1);

    /* BUPT(hex_)[8]: BMS Uptime */
    smc_read_n('BUPT', &gauge->bmsUpTime,8);
    
    /* B0FD BattData */
    /* BROS MinDOD? */
    /* B0TI */
    /* B0ET */
    /* BCHT ChargingTable */
    /* BVVP PermanentVacVoltageLimit */
    /* BVVM TerminationVoltage */
    /* B0FU ForceUISoC */
    /* BCBL */

    /* BatteryCriticalFlags */
    /* BCFB */
    /* BCFD */
    /* BCFT */
    /* BCFP NeedsPrecharge */
    /* BCFV Voltage */
    return true;
}

/* -1: Unknown */
int batt_cell_num(void) {
    SMC_INIT_CHK(-1);

    int8_t count;
    
    /* BNCB(si8) Number of Battery Cells */
    result = smc_read_n('BNCB', &count,1);
    if (result != kIOReturnSuccess)
        return -1;
    
    return count;
}

/* TODO: */
bool get_cells(cell_info_t cells) {
    return true;
}

bool battery_serial(char *serial) {
    SMC_INIT_CHK(false);

    /* BMSN(ch8*) Battery Serial */
    result = smc_read_n('BMSN', serial,-64);
    if (result != kIOReturnSuccess)
        return false;

    return true;
}

/* Then I found that this was how exactly IOPSCopyExternalPowerAdapterDetails returns */
/*
 SerialString => D?is
 Watts => D?IR * D?VR
 Description => D?DE
 Model => D?ii
 Name => D?in
 PMUConfiguration => CHI?
 Current => D?IR
 FamilyCode => D?FC
 Voltage => D?VR
 FwVersion => D?if
 UsbHvcMenu => D?PM
 AdapterID => D?ii
 UsbHvcHvcIndex => D?PI
 IsWireless => D?FC - kIOPSFamilyCodeExternal < 5
 HwVersion => D?ih
 Manufacturer => D?im
*/
/* Stub macro for PO generation, actual localization shall be done by callers */
#include "not_charging_reason.h"
#define addreason(reason, x) if (code & reason) sprintf(subreason, "%s\n%s", subreason, x);
#define setreason(x) sprintf(subreason, "%s", x);
#define addfault(reason, x) if (code & reason) { fault_reason = true; sprintf(subreason, "%s\n%s", subreason, x); }
const char *not_charging_reason_str(uint64_t code) {
    static char reason[1024];
    static uint8_t gen = 0;
    bool fault_reason = false;
    char subreason[1024];

    memset(reason, 0, sizeof(reason));
    memset(subreason, 0, sizeof(subreason));
    
    /* RGEN(ui8 ) NotChargingReason Generation */
    if (gen == 0 && (smc_read_n('RGEN', &gen,1) != kIOReturnSuccess))
        gen = 3; // x86_chnc

    /* Apple Silicon NotChargingReason */
    if (gen >= 4) {
        if (code == DEVICE_IS_CHARGING) return L_NONE;

        /* Common */
        addreason(NOT_CHARGING_REASON_FULLY_CHARGED, _C("Fully Charged")); // This will be set when FC flag sets
        addreason(NOT_CHARGING_REASON_TEMP_BELOW_MIN_STOP_CHARGING, _C("Too Cold"));
        addreason(NOT_CHARGING_REASON_TEMP_ABOVE_MAX_STOP_CHARGING, _C("Too Hot"));
        addreason(NOT_CHARGING_REASON_TEMP_BELOW_MIN_START_CHARGING, _C("Too Cold To Start"))
        addreason(NOT_CHARGING_REASON_TEMP_ABOVE_MAX_START_CHARGING, _C("Too Hot To Start"));

        /* Presense */
        addreason(NOT_CHARGING_REASON_CHARGE_TIMER_EXPIRED, _C("Charger Wachdog Timeout"));
        addreason(NOT_CHARGING_REASON_BATTERY_NOT_PRESENT, _C("Battery Not Present"));
        addreason(NOT_CHARGING_REASON_VBUS_NOT_PRESENT, _C("VBUS Not Present"));

        addreason(NOT_CHARGING_REASON_HIGH_SOC_HIGH_TEMP_STOP_CHARGING, _C("High SoC High Temp Stopped"));
        addreason(NOT_CHARGING_REASON_CSM_COMMUNICATION_FAILED, _C("Sensor Communication Failed"));

        /* Modes */
        addreason(NOT_CHARGING_REASON_IOAM, _C("Accessory Connecting")); // IOAccessoryManager
        addreason(NOT_CHARGING_REASON_KIOSK_MODE, _C("Kiosk Mode")); // How?
        addreason(NOT_CHARGING_REASON_COREMOTION, _C("CoreMotion")); // How?
        addreason(NOT_CHARGING_REASON_USBPD, _C("USB-PD Connecting")); // This is not 'not charging' ig

        // Internal setbatt tool controlled (not only setbatt can trigger this btw)
        addreason(NOT_CHARGING_REASON_SETBATT, _C("setbatt Controlled"));
        // System controlled
        addreason(NOT_CHARGING_REASON_PREDICTIVECHARGING, _C("Predictive Charging"));
        // Inductive Charging, but I don't have such charger to trigger this
        addreason(NOT_CHARGING_REASON_INDUCTIVE, _C("Wireless Charger Controlled"));
        // Gas Gauge FW Update (May happens with MagSafe chargers, their GG FW is updatable)
        addreason(NOT_CHARGING_REASON_GG_FW_UPDATE, _C("Gas Gauge FW Updating"));
        // Battery does not support inhibit inflow
        // This typically on MacBooks since it controls inflow purely software based
        addreason(NOT_CHARGING_REASON_INHIBIT_INFLOW_BATTERY_NOT_PRESENT, _C("Battery Inhibit Inflow Unsupported"));

        addreason(NOT_CHARGING_REASON_PCTM, _C("PCTM")); // ?
        addreason(NOT_CHARGING_REASON_INHIBIT_CLIENT_ADAPTER, _C("Inhibit Client Adapter"));
        addreason(NOT_CHARGING_REASON_CELL_VOLTAGE_TOO_HIGH, _C("Cell Voltage Too High"));
        addreason(NOT_CHARGING_REASON_BATTERY_NO_CHG_REQ, _C("Battery Not Requesting Charge"));
        addreason(NOT_CHARGING_REASON_WOMBAT, _C("Camera Streaming")); // Continuity Capture / Webcam

        /* System */
        addreason(NOT_CHARGING_REASON_VACTFB, _C("VACTFB")); // ?
        addreason(NOT_CHARGING_REASON_FIELDDIAGS, _C("Field Diagnostics"));
        addreason(NOT_CHARGING_REASON_INHIBIT_INFLOW, _C("Inhibit Inflow"));
        addreason(NOT_CHARGING_REASON_CARRIER_TEST, _C("Carrier Mode Testing"));
    
        /* Faults */
        if (code & NOT_CHARGING_REASON_PERMANENT_FAULT_MASK) {
            addfault(NOT_CHARGING_REASON_VBAT_VFAULT, _C("Vbatt Fault"));
            addfault(NOT_CHARGING_REASON_IBAT_MINFAULT, _C("Ibatt MinFault"));
            addfault(NOT_CHARGING_REASON_CHARGER_COMMUNICATION_FAILED, _C("Charger Communication Failure"));
            addfault(NOT_CHARGING_REASON_CELL_CHECK_FAULT, _C("Cell Check Fault"));
            addreason(NOT_CHARGING_REASON_BATT_CHARGED_TOO_LONG, _C("Charged Too Long"));
            if (!fault_reason) {
                sprintf(reason, "%s\n", _C("Permanent Battery Failure")); // kAsbPermanentFailureKey
            }
        }
    } else if (gen == 3) {
        /* X86 NotChargingReason (BNCR/CHNC) */
        if (code < 0x20) {
            switch (code) {
                case NO_REASON: setreason(L_NONE); break;
                case NO_BATTERY: setreason(_C("No Battery")); break;
                case BAD_BATTERY: setreason(_C("Bad Battery")); break;
                case BATTERY_FC: setreason(_C("Fully Charged")); break;
                case BATTERY_NO_CHG_REQ: setreason(_C("Battery Not Requesting Charge"));
                case AC_INSERT: setreason(_C("Using AC Power"));
                case G3: setreason(_C("G3 Mechanical Off")); break;
                case ADAPTER_DISABLED: setreason(_C("Adapter Disabled")); break;
                case ADAPTER_UNKNOWN: setreason(_C("Unknown Adapter")); break;
                case ADAPTER_NOT_ALLOW_CHARGING: setreason(_C("Adapter Not Allowed")); break;
                case CALIBRATION: setreason(_C("Calibration")); break;
                case B0LI_0: setreason(_C("Charging Disabled")); break;
                case OS_NO_CHG: setreason(_C("OS Charging Disabled")); break;
                case BCLM_REACHED: setreason(_C("Charging Limit Reached")); break;
                case UPSTREAM_NO_CHG: setreason(_C("Upstream Charging Disabled")); break; // ?
                case PM_NO_CHG: setreason(_C("PowerManagement Charging Disabled")); break;
                case TB0T_OVER_50: setreason(_C("Battery Temperature over 50℃")); break;
                case TB0T_OVER_45: setreason(_C("Battery Temperature over 45℃")); break;
                case TEMP_GRADIENT_TOO_HIGH: setreason(_C("Temperature Gradient Too High")); break;
                case TEMP_NOT_ATV_VLD: setreason(_C("TEMP_NOT_ATV_VLD")); break; // ?
                case BATTERY_TCA: setreason(_C("BATTERY_TCA")); break; // ?
                case OW_TDM_LINK_ACTIVE: setreason(_C("OW_TDM_LINK_ACTIVE")); break; // ?
                case CELL_VOLTAGE_TOO_HIGH: setreason(_C("Cell Voltage Too High")); break;
                case OBC_NO_CHG: setreason(_C("Predictive Charging")); break;
                case VACTFB_NO_CHG: setreason(_C("VACTFB_NO_CHG")); break; // ?
                case OBC_NO_INFLOW: setreason(_C("Predictive Charging")); break; // What was the diff with OBC_NO_CHG?
                    
                default: setreason(_C("INVALID_NOT_CHARGING_REASON_VALUE")); break;
            }
        } else {
            sprintf(subreason, "Invalid NotChargingReason");
        }
    } else {
        // Legacy NotChargingReason not parsed (since we don't have any devices)
    }

    /* This is conflicting with NOT_CHARGING_REASON_TEMP_ABOVE_MAX_START_CHARGING, why?
    if (code & 0x10) sprintf(subreason, "%s", _C("Charger Timeout"));
    if (code & 0x20) sprintf(subreason, "%s", _C("Charger Wachdog Timeout"));
     */

    /* This is all possible reasons I could know yet
     * Contributing welcomed.
     */
    if (strlen(subreason) > 0) {
        sprintf(reason, "%s%s(0x%llX)", subreason + (gen == 4), (gen == 4) ? "\n" : " ", code);
    } else {
        sprintf(reason, "(0x%llx)", code);
    }

    DBGLOG(CFSTR("NotChargingReason: %s"), reason);
    return reason;
}

#ifdef _C
#undef _C
#endif
// Stub macro
#define _C(x) x

// TODO: decode all charger status
const char *charger_status_str(uint8_t code[64]) {
    const char *byte2stat = NULL;

    if (code[0] == 0x00) return "None";

    // code[0]: Charger Type I guess, each device has different 1st byte
    // MacBook Pro (13-inch, M1, 2020), Has always 0x8A set
    if (code[0] == 0x8A) {
        switch (code[1]) {
            case 0x6C: byte2stat = "Connecting";
            // 0xB0
            case 0xB4: byte2stat = "Fully Charged";
            case 0xB8: byte2stat = "Stopped";
            case 0xD0: byte2stat = "Disconnected";
            case 0xD4: byte2stat = "Connected";
            case 0xD8: byte2stat = "Charging";
        }
    }
    return byte2stat;
}

const char *get_adapter_family_desc(mach_port_t family) {
    switch (family) {
        case kIOPSFamilyCodeDisconnected:               return _C("Disconnected");
        case kIOPSFamilyCodeUnsupported:                return _C("Unsupported");
        case kIOPSFamilyCodeFirewire:                   return _C("FireWire");
        case kIOPSFamilyCodeUSBHost:                    return _C("USB Host"); // usb host
        case kIOPSFamilyCodeUSBHostSuspended:           return _C("USB SDP");
        case kIOPSFamilyCodeUSBDevice:                  return _C("USB Device");
        case kIOPSFamilyCodeUSBAdapter:                 return _C("USB Adapter");
        case kIOPSFamilyCodeUSBChargingPortDedicated:   return _C("USB DCP"); // usb charger
        case kIOPSFamilyCodeUSBChargingPortDownstream:  return _C("USB CDP");
        case kIOPSFamilyCodeUSBChargingPort:            return _C("USB CP"); // usb charger
        case kIOPSFamilyCodeUSBUnknown:                 return _C("Unknown USB");
        case kIOPSFamilyCodeUSBCBrick:                  return _C("USB-C Brick"); // usb brick
        case kIOPSFamilyCodeUSBCTypeC:                  return _C("USB-C Type-C"); // usb type-c
        case kIOPSFamilyCodeUSBCPD:                     return _C("USB-C PD"); // pd charger
        case kIOPSFamilyCodeAC:                         return _C("AC Power");
        case kIOPSFamilyCodeExternal:                   return _C("Externel Power 1");
        case kIOPSFamilyCodeExternal2:                  return _C("Externel Power 2");
        case kIOPSFamilyCodeExternal3:                  return _C("Externel Power 3"); // baseline arcas
        case kIOPSFamilyCodeExternal4:                  return _C("Externel Power 4");
        case kIOPSFamilyCodeExternal5:                  return _C("Externel Power 5");
        case kIOPSFamilyCodeExternal6:                  return _C("Externel Power 6"); // magsafe chg
        case kIOPSFamilyCodeExternal7:                  return _C("Externel Power 7"); // magsafe acc
    }
    return _C("Unknown");
}

charging_state_t is_charging(mach_port_t *family, device_info_t *info) {
    SMCKey key;
    int8_t charging = 0;
    charging_state_t ret = kIsUnavail;

    SMC_INIT_CHK(ret);
    
    /* AC-W(si8) Known cases */
    /* -1: No Adapter (M Chip) */
    /* 0: No Adapter (A Chip) */
    /* 1: Adapter at USB Port 1 */
    /* 2: Adapter at USB Port 2 */
    /* Consider use 'D*AP' (Adapter Power State) for mobile devices (AppleSMCCharger::_checkConnection) */
    /* Mobile Only:
     1: Wired Charger
     2: Wireless Charger
     */
    result = smc_read_n('AC-W', &charging,1);
    if (result != kIOReturnSuccess)
        return ret;

    if (!charging || charging == -1)
        return kIsNotCharging;

    ret = kIsCharging;

#if TARGET_OS_OSX || TARGET_OS_SIMULATOR
    uint16_t time_to_full;
    /* B0TF(ui16) TimeToFull */
    /* FIXME: determine B0TF/B0TE at runtime */
    result = smc_read_n('B0TF', &time_to_full,2);
    if (result != kIOReturnSuccess)
        return kIsUnavail;

    /* Not charging, but Adapter attached */
    if (time_to_full == (uint16_t)65535)
        ret = kIsPausing;
#endif

    /* kIOPSPowerAdapterFamily */
    if (family != NULL) {
        key = 'D\0FC' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, family, 4);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Family Code: %X"), charging, *family);
    }

    /* Not every charger sets those, no return on err */
    if (info != NULL) {
        /* Zero before use */
        memset(info, 0, sizeof(device_info_t));
        info->port = charging;
        /* D?if(ch8*) USB Port ? Firmware version */
        key = 'D\0if' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, info->firmware, 12);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Firmware Version: %s"), charging, info->firmware);

        /* D?ih(ch8*) USB Port ? Hardware version */
        key = 'D\0ih' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, info->hardware, 12);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Hardware Version: %s"), charging, info->hardware);

        /* D?ii(ch8*) USB Port ? Adapter Model */
        key = 'D\0ii' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, info->adapter, 32);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Adapter Model: %s"), charging, info->adapter);

        /* D?im(ch8*) USB Port ? Vendor */
        key = 'D\0im' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, info->vendor, 32);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Vendor: %s"), charging, info->vendor);

        /* D?in(ch8*) USB Port ? Name */
        key = 'D\0in' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, info->name, 32);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Name: %s"), charging, info->name);

        /* D?is(ch8*) USB Port ? Serial */
        key = 'D\0is' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, info->serial, 32);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Serial: %s"), charging, info->serial);

        /* D?DE(ch8*) USB Port ? Description */
        key = 'D\0DE' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, &info->description, 32);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Description: %s"), charging, info->description);

        /* CHI?(ui32) USB Port ? PMUConfiguration */
        key = 'CHI\0' | ((0x30 + charging) << 0x0);
        result = smc_read_n(key, &info->PMUConfiguration, 4);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, PMUConfiguration: %u"), charging, info->PMUConfiguration);

        /* D?IR(ui16) USB Port ? Charger current rating */
        key = 'D\0IR' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, &info->current, 2);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Current Rating: %u"), charging, info->current);

        /* D?VR(ui16) USB Port ? Charger voltage rating */
        key = 'D\0VR' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, &info->voltage, 2);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Voltage Rating: %u"), charging, info->voltage);

		/* XXX: The VBUS/IBUS should not be here, try to move this when we got a better analytics UI */
		uint8_t ioftret[8];

		/* IQ0u(ioft) IBUS Input current */
		key = 'IQ0u'; // Only one charger can win, so theres only one IBUS
		result = smc_read_n(key, &ioftret, 8);
		if (result == kIOReturnSuccess) {
			info->input_current = ioft2flt(ioftret);
			DBGLOG(CFSTR("Port: %d, IBUS: %f"), charging, info->input_current);
		}

		/* VQ?u(ioft) VBUS Port ? Input voltage */
		key = 'VQ\0u' | ((0x30 + charging - 1) << 0x8);
		result = smc_read_n(key, &ioftret, 8);
		if (result == kIOReturnSuccess) {
			info->input_voltage = ioft2flt(ioftret);
			DBGLOG(CFSTR("Port: %d, VBUS: %f"), charging, info->input_voltage);
		}

        /* D?PM(hex_) USB Port ? HVC Power Modes */
        key = 'D\0PM' | ((0x30 + charging) << 0x10);
        //memset(info->hvc_menu, 0, sizeof(info->hvc_menu));
        result = smc_read_n(key, info->hvc_menu,28);
        if (result == kIOReturnSuccess) {
            DBGLOG(CFSTR("Port: %d, Modes: 0x%X"), charging, info->hvc_menu);
        } else {
            info->hvc_menu[27] = 0xFF; /* We write a special byte for indicating failure */
        }

        /* D?PI(si8 ) USB Port ? Mode Index */
        key = 'D\0PI' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, &info->hvc_index,1);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Index: %d"), charging, info->hvc_index);

        /* Other info */
        /* D?PT(ui8 ) Adapter Type */
        key = 'D\0PT' | ((0x30 + charging) << 0x10);
        result = smc_read_n(key, &info->adap_type, 1);
        if (result == kIOReturnSuccess)
            DBGLOG(CFSTR("Port: %d, Type: %d"), charging, info->adap_type);

        /* D?AR(ui32) Ampere Rating (Mobile Only) */
        /* D?BD(ui32) AdapterID */
        /* D?DB(hex_) debounce */
        /* D?ER(hex_) ErrorFlags */
        /* D?ID(flag) IOAM Inflow Inhibit (Mobile Only) */
        /* D?IG(flag) Ignored (Mobile Only) */
        /* D?NO(ui8 ) Select power source (write only) (Mobile Only) */
        /* D?SD(flag) sharedSource (Mobile Only) */
        /* D?SM(ui32) Socket Model (Mobile Only) */
        /* D?SN(ui8 ) ? */
        /* D1SP(ui8 ) HVC Notification (Mobile Only) */
        /* D?SR(ui16) HVC Request Ready (Mobile Only) */
        /* D?SX(ui8 ) HVC Interrupt Action (Mobile Only) */
        /* D?UD(ui32) SourceID (Mobile Only) */
    }

    return ret;
}

// This is different with device_info_t which returned by is_charging()
bool get_charger_data(charger_data_t *data) {
    IOReturn result = kIOReturnSuccess;

    // No matter if charging or not, get data anyway
    memset(data, 0, sizeof(charger_data_t));
    
    /* CHCC(ui8 ) Charger Capable / Charger External Charge Capable */
    result = smc_read_n('CHCC', &data->ChargerCapable,1);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charger Capable: %u"), data->ChargerCapable);

    /* CHCE(ui8 ) Charger Exist / Charger External Connected */
    result = smc_read_n('CHCE', &data->ChargerExist,1);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charger Exist: %u"), data->ChargerExist);

    /* CHCF(hex_)[1] Charger Flags / Charger External Connected */
    /* CHCR(ui8 ) */

    /* CHBI(ui32) Charging Current */
    result = smc_read_n('CHBI', &data->ChargingCurrent,4);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charging Current: %u"), data->ChargingCurrent);

    /* CHBV(ui32) Charging Voltage */
    result = smc_read_n('CHBV', &data->ChargingVoltage,4);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charging Voltage: %u"), data->ChargingVoltage);

    /* BVVL(ui16) Charger Vac Voltage Limit */
    result = smc_read_n('BVVL', &data->ChargerVacVoltageLimit,2);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charger Vac Voltage Limit: %u"), data->ChargerVacVoltageLimit);

    /* CHFC(ui8 ) */
    /* CHFS(ui32) */

    /* CHNC(hex_)[8] Not Charging Reason */
    result = smc_read_n('CHNC', &data->NotChargingReason,8);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Not Charging Reason: 0x%X"), data->NotChargingReason);

    /* CHSL(hex_)[8] Charger Status ([64] on mobile devices) */
    result = smc_read_n('CHSL', &data->ChargerStatus,-64);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charger Status: 0x%X"), data->ChargerStatus);

    /* CH0D(hex_)[4] Charger ID */
    result = smc_read_n('CH0D', &data->ChargerId,4);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charger ID: 0x%X"), data->ChargerId);

    /* CHAS(ui32) Charger Configuration */
    result = smc_read_n('CHAS', &data->ChargerConfiguration,4);
    if (result == kIOReturnSuccess)
        DBGLOG(CFSTR("Charger Configuration: 0x%X"), data->ChargerConfiguration);
    
    return (data->ChargerExist & 1) != 0;
}

bool get_power_state(power_state_t *power) {
    return true;
}

/* Sadly we still have to get hvc_menu from IOPS, since Macs has no D?PM */
hvc_menu_t *hvc_menu_parse(uint8_t *input, size_t *size) {
    /* Only get 28 bytes */
    uint8_t bytes[28];
    memcpy(bytes, input, 28);

    static hvc_menu_t menu[7];
    memset(menu, 0, sizeof(menu));

    int valid_id = 0;
    int f = 0;
    for (int i = 0; i < 7; i++) {
      f = i * 4;
      if (bytes[f] || bytes[f + 1] || bytes[f + 2] || bytes[f + 3]) {
        menu[valid_id].voltage = bytes[f + 1] << 8 | bytes[f];
        menu[valid_id].current = bytes[f + 3] << 8 | bytes[f + 2];
        valid_id++;
      }
    }

    *size = valid_id;

    return menu;
}

#pragma mark - Iktara Wireless (not always iktara tho)

#include "inductive_status.h"
/* Known charger Keys:
 CHIB(ui8 ): ilim backoff
 CHIE(hex_)[1]: Inflow Inhibit
 CHIF(ui32): ilim flags
 CHIS(ui32): Charger Input State (like D?AP)?
 */
bool accessory_available(void) {
    SMC_INIT_CHK(false);

    static uint8_t count = 0;
    static dispatch_once_t wireless_once;

    /* Constants only do once */
    dispatch_once(&wireless_once, ^{
        /* AY-N(ui8 ) Num Accessory ports */
        if (smc_read_n('AY-N', &count, 1) != kIOReturnSuccess)
            count = 0;
    });

    return (count != 0);
}

int vbus_port(void) {
    SMC_INIT_CHK(0);

    uint32_t st = 0;

    /* VBUS(ui32) Voltage Bus */
    result = smc_read_n('VBUS', &st, 4);
    if (result != kIOReturnSuccess)
        return false;

	return st;
}

bool get_iktara_fw_stat(iktara_fw_t *fw) {
    SMC_INIT_CHK(false);

    uint64_t st = 0;
    
    /* WAFS(hex_) Iktara Firmware Status */
    result = smc_read_n('WAFS', &st,8);
    if (result != kIOReturnSuccess)
        return false;

    if (fw != NULL) {
        memset(fw, 0, sizeof(iktara_fw_t));

        fw->Charging = (st & 0xF000000) == 0xE000000;
        fw->Connected = (st >> 0x0B) & 1;
        fw->FieldPresent = (st >> 0x0A) & 1;
        fw->AppFWRunning = (st >> 0x09) & 1;
        fw->ExceptionState = (st & 0x3F);
        fw->OvpTriggered = (st >> 0x1D) & 1;
        fw->LpmActive = (st >> 0x1C) & 1;
    }

    return true;
}

bool get_iktara_drv_stat(iktara_drv_t *drv) {
    SMC_INIT_CHK(false);

    uint64_t raw = 0;

    /* WADS(hex_) Iktara Driver Status */
    result = smc_read_n('WADS', &raw,8);
    if (result != kIOReturnSuccess)
        return false;

    if (drv != NULL) {
        memset(drv, 0, sizeof(iktara_drv_t));
        // Basic flags
        drv->insuff_power   = (raw & INDUCTIVE_STATUS_INSUFF_POWER)   != 0;
        drv->exception      = (raw & INDUCTIVE_STATUS_EXCEPTION)      != 0;
        drv->verify_failed  = (raw & INDUCTIVE_STATUS_VERIFY_FAILED)  != 0;
        drv->fw_downloaded  = (raw & INDUCTIVE_STATUS_FW_DOWNLOADED)  != 0;

        // Cloak reason (extract bits [4..9])
        drv->cloak_reason   = (uint8_t)((raw & INDUCTIVE_STATUS_CLOAK_REASONS) >> 4);

        // Auth status (extract bits [10..11])
        drv->auth_status    = (uint8_t)((raw & INDUCTIVE_STATUS_AUTH_STATUS) >> INDUCTIVE_STATUS_AUTH_STATUS_SHIFT);

        // CL-status sub-flags
        drv->cl_status.pwr_transident = (raw & INDUCTIVE_STATUS_CL_PWR_TRANSIENT) != 0;
        drv->cl_status.pwr_limited    = (raw & INDUCTIVE_STATUS_CL_PWR_LIMITED)   != 0;
        drv->cl_status.ilim_frozen    = (raw & INDUCTIVE_STATUS_CL_ILIM_FROZEN)   != 0;

        // Other status bits
        drv->status.quiesced     = (raw & INDUCTIVE_STATUS_QUIESCED)       != 0;
        drv->status.ldo_disabled = (raw & INDUCTIVE_STATUS_LDO_DISABLED)   != 0;
        drv->status.on_mat_raw   = (raw & INDUCTIVE_STATUS_ON_MAT_RAW)     != 0;
        drv->status.cl_active    = (raw & INDUCTIVE_STATUS_CL_ACTIVE)      != 0;
        drv->status.hb_failed    = (raw & INDUCTIVE_STATUS_HB_FAILED)      != 0;
        drv->status.coex_limited = (raw & INDUCTIVE_STATUS_COEX_LIMITED)   != 0;
        drv->status.ldo_limited  = (raw & INDUCTIVE_STATUS_LDO_LIMITED)    != 0;
        drv->status.high_temp_disc = (raw & INDUCTIVE_STATUS_HIGH_TEMP_DISC) != 0;
        drv->status.uid_rolled   = (raw & INDUCTIVE_STATUS_UID_ROLLED)     != 0;

        // Driver state (bits [24..31])
        drv->drv_status = (uint8_t)((raw & INDUCTIVE_STATUS_DRV_STATE) >> INDUCTIVE_STATUS_DRV_STATE_SHIFT);

        // VRECT sample (bits [32..39])
        drv->ss_vrect   = (uint16_t)((raw & INDUCTIVE_STATUS_SS_VRECT) >> INDUCTIVE_STATUS_SS_VRECT_SHIFT);

        // EPP 2-phase state (bits [40..43])
        drv->state_2pp  = (uint8_t)((raw & INDUCTIVE_STATUS_2PP_STATE) >> INDUCTIVE_STATUS_2PP_STATE_SHIFT);

        // Load-current modulation (bits [44..47])
        drv->iload_mod  = (uint8_t)((raw & INDUCTIVE_STATUS_ILOAD_MOD) >> INDUCTIVE_STATUS_ILOAD_MOD_SHIFT);

        // Non-cloaking reasons (bits [48..55])
        drv->not_cloaking_reason = (uint16_t)((raw & INDUCTIVE_STATUS_NOT_CLOAKING_REASON) >> INDUCTIVE_STATUS_CLOAK_REASONS_SHIFT);

        // System transition flag (bit 56)
        drv->sys_trans  = (raw & INDUCTIVE_STATUS_SYS_TRANS) != 0;
    }

    return true;
}

bool get_iktara_accessory_array(iktara_accessory_array_t *array) {
	SMC_INIT_CHK(false);

	uint8_t arrayA[12];

	memset(array, 0, sizeof(iktara_accessory_array_t));

	/* AY1A(hex_) Accessory A Array */
	result = smc_read_n('AY1A', &arrayA, 12);
	if (result != kIOReturnSuccess) {
		DBGLOG(CFSTR("Accessory A Array: FAILED %s"), mach_error_string(result));
		/* AY1C(ui8 ): Accessory Charging */
		if (smc_read_n('AY1C', &array->charging, 1) != kIOReturnSuccess) array->charging = -1;

		/* AY1P(ui8 ): Accessory Present */
		if (smc_read_n('AY1P', &array->present, 1) != kIOReturnSuccess) array->present = 0;

		/* AY1S(ui8 ): Accessory SoC */
		if (smc_read_n('AY1S', &array->capacity, 1) != kIOReturnSuccess) array->capacity = -1;

		/* AY1P(ui8 ): Accessory Charging */
		if (smc_read_n('AY1C', &array->charging, 1) != kIOReturnSuccess) array->charging = -1;
	} else {
		/* [0-3 Status] */
		array->status = (uint32_t)arrayA[0] << 0x00 | (uint32_t)arrayA[1] << 0x08 | (uint32_t)arrayA[2] << 0x10 | (uint32_t)arrayA[3] << 0x18;
		/* [4 AY1P] */
		array->present = arrayA[4];
		/* [5 AY1C] */
		array->charging = arrayA[5];
		/* [6 AY1T] */
		array->external_connected = arrayA[6];
		/* [7 AY1S] */
		array->capacity = arrayA[7];
		/* [8-9 VendorID] */
		array->VID = (uint16_t)arrayA[8] << 0x00 | (uint16_t)arrayA[9] << 0x08;
		/* [A-B ProductID] */
		array->PID = (uint16_t)arrayA[10] << 0x00 | (uint16_t)arrayA[11] << 0x08;
	}
	DBGLOG(CFSTR("Accessory A Array: Present %d, Charging %d, Connected %d, Capacity %d, VID %x, PID %x"), array->present, array->charging, array->external_connected, array->capacity, array->VID, array->PID);
	return true;
}

/*
 AP*: Power Out keys
*/
/*
 (<_BCPowerSourceController: 0x28235c900>) Found power source: {
     "Accessory Category" = "Battery Case";
     "Current Capacity" = 15;
     "Is Charging" = 0;
     "Is Present" = 1;
     "Max Capacity" = 100;
     Name = "MagSafe Battery Pack";
     "Power Source ID" = "-1367146496";
     "Power Source State" = "Battery Power";
     "Product ID" = 5017;
     "Show Charging UI" = 0;
     "Transport Type" = "Inductive In-Band";
     Type = "Battery Case";
     "Vendor ID" = 1452;
 }
*/

/* Notes on some guessed keys
 Mobile Only:
    CKRQ(flag): Cloaking Required
    CKST(ui8 ): Cloaking Status
    CKCH(ui8 ): Cloaking remaining time?
 
    WAFC(ui32): (write only, check ui8InductiveFWCtrl) Smart Battery control bit (Enable: 0x10000) | (0x1: quiesce on) | (0x2: quiesce off) | (0x3: FW update) | (0x7: Wireless Cloak) | (0x25: Charge Limit Display) | (0x28: Demo Mode)
    WAFD(hex_): (write only) Wireless data
    WAFB(ui32): Wireless frequency
    WADS(hex_): Inductive status
    BD0E(ui32): DiffAmp
    B0LP(ui16): Lpem Props
 
    B1WI(flt ): Battery 1 Wireless Input Rate (Disabled: 10.0)
 
    GBCM(ui16): GG blockdata related
    GBRW(hex_): GG blockdata related
    GCCM(ui16): GG control related
    GCOP(ui16): GG control related
    GCRW(hex_): GG control related
    GRAD(ui8 ): GG reg related
    GRRD(ui16): GG reg related
    
 
    QQ0u(ioft): iBus accumulator
 
 All:
    AC-N(ui8 ): Adapter count
 
    BAPS(flag): Battery State
    BFS0(ui8 ): Battery Auth Support (0x20: GG Update Support)
    B0FV(hex_): Gas Gauge Firmware Version
    B0Ti(ui32): Charge Limit Rate Index
 
	BMCD(ui16): Battery calibration data

	BSFC(flag): Battery State Fully Charged

    CHSC(ui8 ): Charger Charging-capable
    CHSE(ui8 ): Charger End-of-charge
    CHST(ui8 ): Charge Timeout
    CHPS(ui32): selected powerpath
    CHPP(ui32): powerpath priority
    CHA?(ui32): Powerpath ?
	CHHF(ui8 ): Chargr 
    CHHV(ui64): (write only) USB Input High Voltage
    CHI?(ui32): USB Port ? Input Current Limit / PMUConfiguration
	CH0E(hex_): Charger exception
    CH0I(ui8 ): Battery Connected State 1 << 0
    CH0J(ui8 ): Battery Connected State 1 << 1
    CH0K(ui8 ): Battery Connected State 1 << 2
 
    CIBL(ui32): IBatt target limit

    MBSE(hex_): MachineStateEmbedded
    MBSW(hex_): PmuWakeEvents
    MBSe(hex_): MachineStateEvents
    MST3(ui32): ui32TmTestCase
    MST6(ui64): ui64TmTestCase
    MSTC(ui16): ui16TmTestCase
    MSTD(ui16): ui16TmTestCase2
    MTKN(ui32): ui8Tokens
 
    NESN(hex_): ApcReceiveNotification
    NTAP(flag): ApcNotifyOK
 
    UPOF(hex_): Shutdown data error flags
    UBNC(ui16): Shutdown nominal capacity
    UB0C(ui8 ): (write only) Shutdown data (write 1 to clear)
 
 Conditional:
    VQ0u(ioft): VBUS Voltage
    VP0u VQ0l VQ0B VQ0u VQDD VQHI
 
    DBTE(ui8 ): SMC TGraph Mode
    DCAL(hex_): DispRamUAccess
    DRAM(hex_): DispRam
 
    MEPG(ui8 ): SMC Power Prevent Nap
    MSAL(hex_): Thermal control (Enable: 0x8, Disable: 0x0)
 
    TQ?B(ioft): Charger B Temperature
    TQ?d(ioft): Charger d Temperature
    TQ?j(ioft): Charger j Temperature
 
    WQ0u(ioft): Charger WQ0u Voltage
 
    aDC!(ui32): RawADC
    aDC#(ui32): ADCSensorsCount
    aDCR(ioft):
    aP??(ui32): ADC sensor ??
    aPMX(ui8 ): PmuAmux (write only)
 
    bHLD(ui32): Power Button Hold
    bPHD(flag): PoweredByHoldButton
    bRIN(ui32): ?
    bVDN(ui32): Volume Down Button Hold
    bVUP(ui32): Volume Up Button Hold
 
    gP??(ui32): PMU GPIO keys

    pmFC(hex_): PmuFeatureControl
    rARA(ui32): PmuRailCTL
    rARa rASO rASo
 
    
 */
    
