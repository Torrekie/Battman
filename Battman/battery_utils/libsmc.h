#ifndef __libsmc_h__
#define __libsmc_h__

#include <CoreFoundation/CFBase.h>
#include <stdio.h>
#include <stdint.h>

#if !defined(__arm64__) && !defined(__aarch64__) && !defined(__arm64e__)
#error Current SMC implementation is arm64 only! \
       Please file an issue if you would like to contribute!
#endif

extern int hasSMC;

/* SMC operations */
typedef CF_ENUM(UInt8, SMCIndex) {
    /* the user client method name constants */
    kSMCUserClientOpen,
    kSMCUserClientClose,
    kSMCHandleYPCEvent,

    kSMCPlaceholder1, /* *** LEGACY SUPPORT placeholder */
    kSMCNumberOfMethods,

    /* other constants not mapped to individual methods */
    kSMCReadKey,
    kSMCWriteKey,
    kSMCGetKeyCount,
    kSMCGetKeyFromIndex,
    kSMCGetKeyInfo,

    kSMCFireInterrupt,
    kSMCGetPLimits,
    kSMCGetVers,
    kSMCPlaceholder2, /* *** LEGACY SUPPORT placeholder */

    kSMCReadStatus,
    kSMCReadResult,

    kSMCVariableCommand
};

// AppleSMCSensorDispatcher
typedef CF_ENUM(UInt8, SMCSensorIndex) {
	kSMCGetSMCSensorCount,
	kSMCGetSMCSensor4CC,
	kSMCGetSMCSensorData,
	kSMCSetSMCSensorData
};

typedef uint32_t SMCKey;
typedef uint32_t SMCDataType;
typedef uint8_t SMCDataAttributes;

/* a struct to hold the SMC version */
typedef struct SMCVersion {
    unsigned char major;
    unsigned char minor;
    unsigned char build;
    //unsigned char reserved; // padding for alignment
    unsigned short release;
} SMCVersion;

typedef struct SMCPLimitData {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

/* a struct to hold the key info data */
typedef struct SMCKeyInfoData {
    uint32_t dataSize;
    SMCDataType dataType;
    SMCDataAttributes dataAttributes;
} SMCKeyInfoData;

/* the struct passed back and forth between the kext and UC */
/* sizeof(SMCParamStruct) should be 168 or 80, depending on whether uses
 * bytes[32] or bytes[120] */
typedef struct SMCParamStruct {
    SMCKey key;
    struct SMCParam {
        SMCVersion vers;
        SMCPLimitData pLimitData;
        SMCKeyInfoData keyInfo;

        uint8_t result;
        uint8_t status;

        uint8_t data8;
        uint32_t data32;
        unsigned char bytes[120];
    } param;
} SMCParamStruct;

/* libsmc.c */

typedef struct gas_gauge {
    uint16_t Temperature;           /* Celsius */
    uint16_t Voltage;               /* mV */
    uint16_t Flags;                 /* hex_[2] */
    uint16_t RemainingCapacity;     /* mAh */
    uint16_t FullChargeCapacity;    /* mAh */
    int16_t AverageCurrent;         /* mA */
    uint16_t TimeToEmpty;           /* min */
    uint16_t Qmax;                  /* mAh */
    int16_t AveragePower;           /* mW */
    int16_t OCV_Current;            /* mA */
    uint16_t OCV_Voltage;           /* mV */
    uint16_t CycleCount;
    uint16_t StateOfCharge;         /* % */
    int16_t TrueRemainingCapacity;  /* mAh */
    int16_t PassedCharge;           /* mAh */
    uint16_t DOD0;                  /* raw 0-16384 */
    uint16_t PresentDOD;            /* %/mAh */
    uint16_t DesignCapacity;        /* mAh */
    int16_t IMAX;                   /* mA */
    uint16_t NCC;
    int16_t ResScale;
    uint16_t ITMiscStatus;          /* Impedance Track™, this should be parseable but we don't know how */
    int16_t IMAX2;                  /* mA */
    uint32_t ChemID;                /* hex_[4] */
    int16_t SimRate;                /* Hr */

    /* Extensions */
    char DeviceName[32];
    uint8_t DailyMaxSoc;           /* % */
    uint8_t DailyMinSoc;           /* % */
    uint16_t DesignCycleCount;
    uint8_t UISoC;                  /* % */
    int8_t ChemicalSoC;             /* % */
    uint64_t bmsUpTime;             /* sec */
} gas_gauge_t;

typedef struct device_info {
    int8_t port;
    char firmware[12];
    char hardware[12];
    char adapter[32];
    char vendor[32];
    char name[32];
    char serial[32];
    char description[32];
    uint32_t PMUConfiguration;
    uint16_t current;
    uint16_t voltage;
	float input_current;
	float input_voltage;
    /* HVC (High Voltage Charging) */
    uint8_t hvc_menu[28]; /* hex_[28], 4 bit each hvc, max 7 hvc */
    int8_t hvc_index;
    /* Others */
    uint8_t adap_type;
} device_info_t;

typedef struct cell_info {
    int64_t CurrentAccumulator; /* BC?A */
    uint16_t Voltage;           /* BC?V */
    uint16_t Qmax;              /* BQX? */
    uint16_t DOD0;              /* BQD?, raw 0-16384 */
    uint16_t PresentDOD;        /* BDD? */
    uint16_t WoM;               /* BMW? */
    uint8_t RaTableRaw[32];     /* B0R? */
} cell_info_t;

typedef struct lifetime_data {
    uint8_t ArrayA[32];                         /* BL0A */
    uint8_t ArrayB[32];                         /* BL0B */
    uint8_t CycleCountLastQmax;                 /* BLCC (Embedded Only) */
    uint16_t FlashWriteCount;                   /* BLCF (Conditional) */
    int16_t HighAverageCurrentLastRun;          /* BLCH (Conditional) */
    int16_t LowAverageCurrentLastRun;           /* BLCL (Conditional) */
    uint16_t ResistanceUpdatedDisabledCount;    /* BLCR (Conditional) */
    int16_t MinDeltaVoltage;                    /* BLDM (Conditional) */
    int16_t MaxDeltaVoltage;                    /* BLDX (Conditional) */
    int16_t MinFCC;                             /* BLFM (Conditional) */
    int16_t MaxFCC;                             /* BLFX (Conditional) */
    int16_t MaxChargeCurrent;                   /* BLIC */
    int16_t MaxDishargeCurrent;                 /* BLID */
    int16_t MinPackVoltage;                     /* BLPM */
    int16_t MaxPackVoltage;                     /* BLPX */
    int16_t MaxOverChargedCapacity;             /* BLQC (Conditional) */
    int16_t MaxOverDischargedCapacity;          /* BLQD (Conditional) */
    int16_t MinQmax;                            /* BLQM (Conditional) */
    int16_t MaxQmax;                            /* BLQX (Conditional) */
    uint16_t MinRa08;                           /* BLRM (Conditional) */
    uint16_t MaxRa08;                           /* BLRX (Conditional) */
    int8_t AverageTemperature;                  /* BLTA */
    int16_t MinTemperature;                     /* BLTM */
    uint32_t TotalOperatingTime;                /* BLTO */
    int32_t TemperatureSamples;                 /* BLTS */
    int16_t MaxTemperature;                     /* BLTX */
    uint8_t RdisCnt;                            /* BLCR (Conditional) */
    int16_t NCCMin;                             /* BLNM (Conditional) */
    int16_t NCCMax;                             /* BLNX (Conditional) */
    uint16_t MinRa8;                            /* BLRO (Conditional) */
    uint16_t MaxRa8;                            /* BLRN (Conditional) */
    uint8_t ResetCnt;                           /* BLRC (Conditional) */
    uint16_t QmaxUpdSucCnt;                     /* BLQN (Conditional) */
    uint16_t QmaxUpdFailCnt;                    /* BLQO (Conditional) */
    uint32_t TimeAtHighSoc[10];                 /* BLTP (Min 16, Max 40) */
    uint64_t SafetyFaultCounter[4];             /* BLSC (Conditional) */
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    uint64_t LowVoltageRes;                     /* BLTV (Conditional) */
    uint64_t FlashEraseCounter;                 /* BFLE (Conditional) */
    uint64_t FlashFailureCounter;               /* BFLF (Conditional) */
    uint64_t LtOcvRestCnt;                      /* BLSD (Conditional) */
    uint64_t LtQmaxUpdCnt;                      /* BLSE (Conditional) */
    uint64_t LtOcvRestCntHsp;                   /* BLSF (Conditional) */
    uint64_t LtQmaxUpdCntHsp;                   /* BLSG (Conditional) */
} lifetime_data_t;

typedef struct shutdown_data {
    uint8_t UiSoc;                      /* UBUI */
    int16_t Temperature;                /* UBAT */
    uint16_t Voltage;                   /* UBAV */
    uint16_t PrevVoltage;               /* UBPV */
    uint16_t NominalChargeCapacity;     /* UBNC */
    uint16_t PrevNominalChargeCapacity; /* UBPN */
    uint16_t FullChargeCapacity;        /* UBFC */
    uint16_t PrevFullChargeCapacity;    /* UBPF */
    uint16_t RemainingCapacity;         /* UBPM */
    uint16_t PrevRemainingCapacity;     /* UBPR */
    int16_t AverageCurrent;             /* UBAC */
    int16_t PrevAverageCurrent;         /* UBPI */
    uint16_t RSS;                       /* UBSS */
    uint16_t DOD0;                      /* UBD0, raw 0-16384 */
    int16_t PresentDOD;                 /* UBDD */
    int16_t PassedCharge;               /* UBPC */
    uint16_t CycleCount;                /* UBCT */
    int16_t ResScale;                   /* UBRS */
    uint8_t CycleCountLastQmax;         /* UBCC */
    uint16_t MaxRa08;                   /* UBRX */
    uint8_t TimeAbove95;                /* UBTP */
    uint8_t RaTableRaw[32];             /* UBRA */
    int16_t MaxDischargeCurrent;        /* UBID */
    int16_t Qstart;                     /* UBQS */
    uint8_t DLog[64];                   /* UBDL */
    uint8_t UnexpectedRestart;          /* UPOR */
    uint64_t RestartTimestamp;          /* UB0T */
    uint8_t DataError;                  /* UPOF */
    int16_t FilteredCurrent;            /* UBIS */
    uint16_t LpemMode;                  /* UBLP */
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    uint16_t SocAlarm;                  /* UBSA */
    uint16_t DataSoc1vcut;              /* UBSB */
    uint16_t SocSoc2;                   /* UBSU */
    uint16_t ShutdownVoltage;           /* UBSV */
    uint16_t ShutdownSoc;               /* UBSW */
    uint16_t DataSwRemCap;              /* UBSX */
    uint16_t SwFcc;                     /* UBSY */
    uint16_t SocfThres;                 /* UBSZ */
} shutdown_data_t;

typedef struct carrier_mode {
    uint32_t status;        /* CHTE (bootarg: carrier-mode) */
    uint32_t high_voltage;  /* CHTU (bootarg: max-charge-voltage/carrier-max-limit) */
    uint32_t low_voltage;   /* CHTL (bootarg: min-charge-voltage/carrier-min-limit) */
	uint32_t test_mode;     /* CHTM */
} carrier_mode_t;

/* This is not "Single App Mode", possibly enabled on Demo devices but cannot verify */
typedef struct kiosk_mode {
    /* CHKD */
    /* CHKG */
    /* CHKH */
    /* CHKK */
    uint8_t mode;               /* CHKM (bootarg: kiosk-mode) */
    uint16_t FullVoltage;       /* CHKL (bootarg: kiosk-mode-voltage) */
    uint32_t HighSocSecs;       /* CHKO */
    uint8_t HighSocDays;        /* CHKP */
    /* CHKQ */
    /* CHKR */
    /* CHKS */
    /* CHKT */
    /* CHKU */
    uint8_t LastHighSocHours;   /* CHKV */
    /* CHKW */
} kiosk_mode_t;

typedef struct charger_data {
    uint32_t ChargerConfiguration;      /* CHAS */
    uint32_t ChargingCurrent;           /* CHBI / B0VI */
    uint32_t ChargingVoltage;           /* CHBV */
    uint16_t ChargerVacVoltageLimit;    /* BVVL */
    uint64_t NotChargingReason;         /* BNCR / CHNC */
    uint8_t ChargerStatus[64];          /* CHSL */
    uint32_t ChargerId;                 /* CH0D */
    uint8_t ChargerCapable;             /* CHCC */
    uint8_t ChargerExist;               /* CHCE */
    /* Charging Limits: CHA? CHI? CHP? */
    /* Inflow Inhibit: CH0R */
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    uint16_t TimeThermallyLimited;      /* CHTC */
} charger_data_t;

typedef struct lpem_data {
    uint16_t Mode;          /* B0LP */
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    uint32_t Fcc;           /* SBOF */
    uint32_t Soc;           /* SBOP */
    uint32_t RemCap;        /* SBOR */
    uint32_t SocfThresh;    /* SBOT */
    uint32_t AlgoStatus;    /* SBST */
} lpem_data_t;

typedef struct ocv_data {
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    uint32_t Count;         /* OBOF */
    uint32_t Ocv;           /* OBOO */
    uint32_t RaDisq;        /* OBOR */
    uint32_t QmaxDisq;      /* OBOQ */
    uint32_t TimeSinceOcv;  /* OBTO */
} ocv_data_t;

typedef struct shallow_discharge_data {
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    uint32_t Levels;    /* BSDC */
    uint32_t Score;     /* BSDS */
    uint32_t Flag;      /* BSDF */
} shallow_discharge_data_t;

typedef struct battery_data {
    uint16_t StateOfCharge;                 /* BRSC */
    int16_t ResScale;                       /* B0RS */
    float AdapterPower;                     /* PDTR */
    float SystemPower;                      /* PSTR */
    uint32_t PMUConfigured;                 /* CHGI */
    char mfgData[32];                       /* BMDA */
    char ManfDate[7];                       /* BMDT */
    int64_t PackCurrentAccumulator;         /* BAAC */
    uint64_t PackCurrentAccumulatorCount;   /* BACC */
    uint64_t CellCurrentAccumulatorCount;   /* BCCA */
    uint16_t RSS;                           /* B0SS */
    int16_t RSSFiltered;                    /* BRSS */
    uint32_t ChemID;                        /* B0CI */
    uint32_t AlgoChemID;                    /* B0CJ */
    int16_t ISS;                            /* BISS */
    uint32_t CSMStatus;                     /* BCST */
    uint16_t MaxCapacity;                   /* B0CM */
    uint16_t HealthMetric;                  /* B0HM */
    uint16_t ChemicalWRa;                   /* BR0C */
    uint64_t Flags;                         /* B0FG */
    uint16_t WRa;                           /* BR0W */
    uint16_t Ra00;                          /* BR00 */
    uint16_t Ra01;                          /* BR01 */
    uint16_t Ra02;                          /* BR02 */
    uint16_t Ra03;                          /* BR03 */
    uint16_t Ra04;                          /* BR04 */
    uint16_t Ra05;                          /* BR05 */
    uint16_t Ra06;                          /* BR06 */
    uint16_t Ra07;                          /* BR07 */
    uint16_t Ra08;                          /* BR08 */
    uint16_t Ra09;                          /* BR09 */
    uint16_t Ra10;                          /* BR10 */
    uint16_t Ra11;                          /* BR11 */
    uint16_t Ra12;                          /* BR12 */
    uint16_t Ra13;                          /* BR13 */
    uint16_t Ra14;                          /* BR14 */
    uint32_t GaugeResetCounter;             /* GGRC */
    int16_t soc1Voltage;                    /* B0S1 */
    uint16_t DailyMaxSoc;                   /* BMSC */
    uint16_t DailyMinSoc;                   /* BNSC */
    uint32_t UUID;                          /* B0ID */
    uint8_t GaugeResetData[32];             /* BLRD */
    uint16_t GaugeResetDataFirmware;        /* BLRF */
    uint16_t GaugeResetDataHardware;        /* BLRH */
    uint16_t GaugeResetDataSoftware;        /* BLRS */
    uint16_t GaugeResetDataWatchDog;        /* BLRW */
    uint16_t QmaxDisqReason;                /* B0QD */
    int16_t ChargeAccum;                    /* B0CH */
    int16_t SimRate;                        /* B0SR */
    int16_t FilteredCurrent;                /* B0IF */
    int16_t FilteredCurrentRc3;             /* BI03 */
    int16_t FilteredCurrentRc4;             /* BI04 */
    uint8_t iMaxAndSocSmoothTable[32];      /* B0IS */
    int16_t PassedCharge;                   /* BQCC */
    int16_t Qstart;                         /* B0QS */
    uint8_t BatteryState[16];               /* BAST */
    uint16_t ITMiscStatus;                  /* B0MS */
    uint16_t GaugeFlagRaw;                  /* B0FI */
    uint16_t FccComp1;                      /* BFC1 */
    uint16_t FccComp2;                      /* BFC2 */
    uint8_t WatchdogDebugDump[32];          /* B0WD */
    /* GaugeDataFlashWriteCnt BFWC */
    uint16_t SocAlarm;                      /* B0SA */
    int16_t DynamicSoc1Vcut;                /* B0VC */
    uint64_t AlgoTemperature;               /* TG0A */
    uint64_t VirtualTemperature;            /* TG0V */
    /* DODatEOC BDDE */
} battery_data_t;

typedef struct gg_data_flash_update {
    /* The following keys were not seen in my pre 2021 devices, need contributors */
    /*
     Status BFUE
     Error BFUF
     Phase BFUG
     ErrorPhase BFUH
     SubclassId BFUI
     Block BFUJ
     */
} gg_data_flash_update_t;

typedef struct hvc_menu {
    uint16_t current;
    uint16_t voltage;
} hvc_menu_t;

typedef enum {
    kIsUnavail = -1,    /* Error Occured */
    kIsNotCharging = 0, /* Not charging */
    kIsCharging,        /* Charging */
    kIsPausing,         /* AC connected, not charging */
} charging_state_t;

typedef struct power_state {
    float AdapterPower;
    float SystemPower;
} power_state_t;

typedef struct board_info {
    uint8_t Generation;         /* RGEN */
    char EmbeddedOSVersion[16]; /* RESV */
    uint64_t ChipEcid;          /* RECI */
    uint32_t ChipRev;           /* RCRV */
    uint32_t ChipId;            /* RCID */
    uint32_t BoardRev;          /* RBRV */
    uint32_t BoardId;           /* RBID */
    char TargetName[8];         /* RPlt */
} board_info_t;

typedef struct iktara_fw {
    bool Charging;              /* (WAFS & 0xF000000) == 0xE000000 */
    bool Connected;             /* (WAFS >> 0x0B) & 1 */
    bool FieldPresent;          /* (WAFS >> 0x0A) & 1 */
    bool AppFWRunning;          /* (WAFS >> 0x09) & 1 */
    uint16_t ExceptionState;    /* (WAFS & 0x3F) */
    bool OvpTriggered;          /* (WAFS >> 0x1D) & 1 */
    bool LpmActive;             /* (WAFS >> 0x1C) & 1 */
} iktara_fw_t;

typedef struct iktara_drv {
    bool insuff_power;
    bool exception;
    bool verify_failed;
    bool fw_downloaded;
    uint8_t cloak_reason;
    uint8_t auth_status;
    struct {
        bool pwr_transident;
        bool pwr_limited;
        bool ilim_frozen;
    } cl_status;
    struct {
        bool quiesced;
        bool ldo_disabled;
        bool on_mat_raw;
        bool cl_active;
        bool hb_failed;
        bool coex_limited;
        bool ldo_limited;
        bool high_temp_disc;
        bool uid_rolled;
    } status;
    uint8_t drv_status;
    uint16_t ss_vrect;
    uint8_t state_2pp;
    uint8_t iload_mod;
    uint16_t not_cloaking_reason;
    bool sys_trans;
} iktara_drv_t;

typedef struct iktara_accessory_array {
	uint32_t status;
	int8_t present;
	int8_t charging;
	int8_t capacity;
	int8_t external_connected;
	uint16_t VID;
	uint16_t PID;
} iktara_accessory_array_t;

typedef struct inductive_param {
    uint32_t FwMode;            /* WASM */
    uint16_t RectifierVoltage;  /* WAVR */
    int16_t RectifierCurrent;   /* WAIR */
    int16_t VoltageTarget;      /* WATV */
    uint16_t PowerTarget;       /* WATP */
    uint32_t TxPowerBudget;     /* WAPB */
    uint32_t TxGain1;           /* WAG1 */
    uint32_t TxGain2;           /* WAG2 */
    uint32_t TxVersion;         /* WAVN */
    uint32_t Frequency;         /* WARF */
    uint16_t RxVoltage;         /* WARV */
    int16_t RxCurrent;          /* WARI */
    int16_t RxPower;            /* WARP */
    uint8_t PromotionState2PP;  /* WAPS */
    uint32_t SignalStrenth;     /* WASS */
    uint32_t NotCloakReason;    /* WANC */
    uint32_t CloakReason;       /* WACM */
    uint32_t ModDepth;          /* WAMD */
    uint8_t HighFreq;           /* WAHF */
    /* OVPCount WAOC */
    /* WAFS -> iktara_fw_t */
    /* WADS -> iktara_drv_t */
} inductive_param_t;

__BEGIN_DECLS

extern gas_gauge_t gGauge;
extern board_info_t gBoard;

const board_info_t *get_board_info(void);
int get_fan_status(void);
float get_temperature(void);
int get_time_to_empty(charging_state_t charging_state);
int estimate_time_to_full(void);
float get_battery_health(float *design_cap, float *full_cap);
bool get_capacity(uint16_t *remaining, uint16_t *full, uint16_t *design);
int batt_cell_num(void);
bool get_gas_gauge(gas_gauge_t *gauge);
typedef unsigned int mach_port_t;
charging_state_t is_charging(mach_port_t *family, device_info_t *info);
float *get_temperature_per_cell(void);
bool battery_serial(char *serial);
hvc_menu_t *hvc_menu_parse(uint8_t *input, size_t *size);
const char *get_adapter_family_desc(mach_port_t family);
bool get_charger_data(charger_data_t *data);
const char *not_charging_reason_str(uint64_t code);

int smc_open(void);
int smc_write_safe(uint32_t key, void *bytes, uint32_t size);
int smc_read_n(uint32_t key, void *bytes, int32_t size);
int smc_call(int index, SMCParamStruct *inputStruct,SMCParamStruct *outputStruct);

bool accessory_available(void);
int vbus_port(void);
bool get_iktara_fw_stat(iktara_fw_t *fw);
bool get_iktara_drv_stat(iktara_drv_t *drv);
bool get_iktara_accessory_array(iktara_accessory_array_t *array);

__END_DECLS

#endif
