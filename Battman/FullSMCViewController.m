#import "ObjCExt/UIScreen+Auto.h"
#import "FullSMCViewController.h"
#include "battery_utils/libsmc.h"
#include "common.h"
#include "intlextern.h"

@interface SMCWriteViewController : UIViewController {
    uint8_t *buffer;
    char type[4];
    char key[4];
    int length;
    UITextView *hexConversionView;
    UITextField *userInputView;
    UILabel *keyLabel;
    NSArray<UISegmentedControl *> *allTypeControls;
    int endian;
}

// TODO: Implement shim UIKit instead change colors every sources
@property (nonatomic, strong) UIColor *systemRedColor;

- (instancetype)initWithKey:(struct smc_key *)skey;
@end

static void hton_with_type(void *bytes, int type) {
    if (type == '1') { // 16
        uint16_t *val = (uint16_t *)bytes;
        *val = htons(*val);
    } else if (type == '3') { // 32
        uint32_t *val = (uint32_t *)bytes;
        *val = htonl(*val);
    } else { // 64
        uint32_t *val = (uint32_t *)bytes;
        *(uint64_t *)bytes = ((uint64_t)htonl(*val) << 32LL) | (uint64_t)htonl(val[1]);
    }
}

static NSString *valueForSMCBuffer(uint8_t *bytes, int size, char *ptype, int mode) {
    NSString *text;
    if (*ptype == 'h') {
        // hex_
        if (size > 8) {
            text = [NSString stringWithFormat:_("(partial) %016llX..."), *(uint64_t *)bytes];
        } else {
            text = [NSString stringWithFormat:@"%0*llX", size << 1, *(uint64_t *)bytes];
        }
    } else if (ptype[3] == '*') {
        if (*ptype == 'u') {
            // ui8\*
            NSMutableArray *arr = [NSMutableArray array];
            for (int i = 0; i < size; i++) {
                [arr addObject:[NSString stringWithFormat:@"%u", bytes[i]]];
            }
            text = [arr componentsJoinedByString:@","];
        } else if (*ptype == 'c') {
            // ch8\*
            text = [NSString stringWithUTF8String:(const char *)bytes];
            /*NSMutableArray *arr=[NSMutableArray array];
            for(int i=0;i<size;i++) {
                    [arr addObject:[NSString stringWithFormat:@"%d",(int)bytes[i]]];
            }
            text=[arr componentsJoinedByString:@","];*/
        } else {
            text = _("Unknown array");
        }
    } else if (*ptype == 'u') {
        // ui.{2}
        if (mode && ptype[2] != '8')
            hton_with_type(bytes, ptype[2]);
        uint64_t val = *(uint64_t *)bytes;
        text = [NSString stringWithFormat:@"%llu", val];
    } else if (*ptype == 's') {
        // si.{2}
        if (mode && ptype[2] != '8')
            hton_with_type(bytes, ptype[2]);
        int64_t val = *(int64_t *)bytes;
        if (ptype[2] == '8')
            text = [NSString stringWithFormat:@"%d", (int)(char)val];
        else if (ptype[2] == '1')
            text = [NSString stringWithFormat:@"%hd", (short)val];
        else if (ptype[2] == '3')
            text = [NSString stringWithFormat:@"%d", (int)val];
        else
            text = [NSString stringWithFormat:@"%lld", val];
    } else if (*ptype == 'f' && ptype[2] == 't') {
        // flt
        if (mode)
            hton_with_type(bytes, '3');
        text = [NSString stringWithFormat:@"%0.3f", *(float *)bytes];
    } else if (*ptype == 'f') {
        // flag
        NSMutableString *ft = [NSMutableString stringWithCapacity:8 * size];
        for (int i = size - 1; i >= 0; i--) {
            for (int b = 7; b >= 0; b--) {
                [ft appendString:(bytes[i] & (1 << b)) ? @"1" : @"0"];
            }
        }
        text = ft;
    } else if (*ptype == 'i') {
        // ioft
        if (mode)
            hton_with_type(bytes, '6');
        text = [NSString stringWithFormat:@"%0.3f", (float)*(uint64_t *)bytes / 65536.0f];
    } else {
        text = [NSString stringWithFormat:_("(Unknown type) %0*llX"), size << 1, *(uint64_t *)bytes];
    }
    return text;
}

static NSString *valueForSMCBufferSafe(uint8_t *bytes, int size, char *ptype, int mode) {
    uint8_t newbytes[120] = {0};
    memcpy(newbytes, bytes, size);
    return valueForSMCBuffer(newbytes, size, ptype, mode);
}

@implementation FullSMCViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    SMCParamStruct input = {0};
    SMCParamStruct output;
    input.param.data8 = kSMCGetKeyCount;
    smc_call(kSMCHandleYPCEvent, &input, &output);
    NSLog(@"SMC Count=%d", htonl(output.param.data32));
    numKeys = htonl(output.param.data32);
    input.param.data8 = kSMCGetKeyFromIndex;
    allkeys = malloc(sizeof(struct smc_key) * numKeys);
    for (int i = 0; i < numKeys; i++) {
        input.param.data32 = i;
        smc_call(kSMCHandleYPCEvent, &input, &output);
        // output.key=htonl(output.key);
        // NSLog(@"SMC[%d]=%.4s",i,(char*)&output.key);
        allkeys[i].key = output.key;
    }
    input.param.data32 = 0;
    input.param.data8 = kSMCGetKeyInfo;
    for (int i = 0; i < numKeys; i++) {
        input.key = allkeys[i].key;
        smc_call(kSMCHandleYPCEvent, &input, &output);
        // int type=htonl(output.param.keyInfo.dataType);
        // NSLog(@"type=%.4s",(char*)&type);
        allkeys[i].dataSize = output.param.keyInfo.dataSize;
        allkeys[i].dataType = output.param.keyInfo.dataType;
    }
    UISegmentedControl *endiannessControl = [[UISegmentedControl alloc] initWithItems:@[ @"Little Endian", @"Big Endian" ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:endiannessControl];
    endiannessControl.selectedSegmentIndex = 0;
    [endiannessControl addTarget:self action:@selector(endiannessChanged:) forControlEvents:UIControlEventValueChanged];
    return self;
}

- (void)endiannessChanged:(UISegmentedControl *)ec {
    mode = (int)ec.selectedSegmentIndex;
    [self.tableView reloadData];
}

- (void)dealloc {
    free(allkeys);
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
    return 2;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 1) {
        UIAlertController *keyInput = [UIAlertController alertControllerWithTitle:_("Jump to") message:_("Enter the key below.") preferredStyle:UIAlertControllerStyleAlert];
        [keyInput addTextFieldWithConfigurationHandler:nil];
        [keyInput addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [keyInput addAction:[UIAlertAction actionWithTitle:_("Jump") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *key = keyInput.textFields.firstObject.text;
            if (key.length != 4) {
                show_alert(_C("Jump to"), _C("Invalid key"), L_OK);
                return;
            }
            uint32_t vkey = htonl(*(uint32_t *)[key UTF8String]);
            for (int i = 0; i < self->numKeys; i++) {
                if (self->allkeys[i].key == vkey) {
                    NSIndexPath *targetIp = [NSIndexPath indexPathForRow:i inSection:1];
                    //[tv scrollToRowAtIndexPath:targetIp atScrollPosition:UITableViewScrollPositionMiddle animated:1];
                    [tv selectRowAtIndexPath:targetIp animated:1 scrollPosition:UITableViewScrollPositionMiddle];
                    return;
                }
            }
            show_alert(_C("Jump to"), _C("Key not found"), L_OK);
        }]];
        [self presentViewController:keyInput animated:1 completion:nil];
    }
    if (indexPath.section == 1)
        [self.navigationController pushViewController:[[SMCWriteViewController alloc] initWithKey:allkeys + indexPath.row] animated:1];
    [tv deselectRowAtIndexPath:indexPath animated:1];
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)sect {
    if (sect == 0)
        return 2;
    return numKeys;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *simpleCell = [UITableViewCell new];
        if (indexPath.row == 0) {
            simpleCell.textLabel.text = _("Click a row to edit");
            simpleCell.textLabel.enabled = 0;
        } else {
            simpleCell.textLabel.text = _("Jump to key");
            if (@available(iOS 13.0, *)) {
                simpleCell.textLabel.textColor = [UIColor linkColor];
            } else {
                simpleCell.textLabel.textColor = [UIColor colorWithRed:0 green:(122.0f / 255) blue:1 alpha:1];
            }
        }
        return simpleCell;
    }
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"regularSMCItemCell"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"regularSMCItemCell"];
    SMCParamStruct smcstr = {0};
    struct smc_key *curkey = allkeys + indexPath.row;
    smcstr.key = curkey->key;
    smcstr.param.keyInfo.dataSize = curkey->dataSize;
    smcstr.param.data8 = kSMCReadKey;
    smc_call(kSMCHandleYPCEvent, &smcstr, &smcstr);
    unsigned int type = htonl(curkey->dataType);
    unsigned int key = htonl(curkey->key);
    cell.textLabel.text = [NSString stringWithFormat:@"%.4s(%u) %.4s", (char *)&type, curkey->dataSize, (char *)&key];
    if (smcstr.param.status) {
        cell.detailTextLabel.text = _("(Unable to read)");
        cell.detailTextLabel.enabled = 0;
    } else {
        char *ptype = (char *)&type;
        cell.detailTextLabel.text = valueForSMCBuffer(smcstr.param.bytes, curkey->dataSize, ptype, mode);
        cell.detailTextLabel.enabled = 1;
    }
    return cell;
}

@end

static const char *smctypes[] = {
    "ui8\0",
    "si8\0",
    "ui8*",
    "ch8*", // ASCII
    "ui16",
    "si16",
    "ui32",
    "si32",
    "ui64",
    "si64",
    "flt\0", // 32-bit single-precision IEEE float
    "ioft", // 64-bit unsigned fixed-point value (with 48.16 precision)
    "hex_", // binary data, sometimes numbers
    "flag", // Boolean
    NULL};

static int smctype_to_length(int type) {
    switch (type) {
    case 0:
    case 1:
        return 1;
    case 2:
    case 3:
    case 12:
    case 13:
        return -1; // undefined length
    case 4:
    case 5:
        return 2;
    case 6:
    case 7:
    case 10:
        return 4;
    case 8:
    case 9:
    case 11:
        return 8;
    }
    return -1;
}

@implementation SMCWriteViewController

- (instancetype)initWithKey:(struct smc_key *)skey {
    SMCParamStruct smcstr = {0};
    smcstr.key = skey->key;
    smcstr.param.keyInfo.dataSize = skey->dataSize;
    smcstr.param.data8 = kSMCReadKey;
    smc_call(kSMCHandleYPCEvent, &smcstr, &smcstr);
    *(uint32_t *)type = htonl(skey->dataType);
    *(uint32_t *)key = htonl(skey->key);
    length = skey->dataSize;
    buffer = malloc(length);
    memcpy(buffer, smcstr.param.bytes, length);
    return self;
}

- (void)dealloc {
    free(buffer);
}

- (NSString *)title {
    return _("Write to SMC");
}

- (void)refreshTypeControls {
    int cursel = 0;
    for (const char **i = smctypes; *i != NULL; i++) {
        if (*(uint32_t *)*i == *(uint32_t *)type) {
            cursel = (int)(i - smctypes);
            break;
        }
    }
    for (int i = 0; i < allTypeControls.count; i++) {
        if (i != cursel / 7) {
            allTypeControls[i].selectedSegmentIndex = UISegmentedControlNoSegment;
        } else {
            allTypeControls[i].selectedSegmentIndex = cursel % 7;
        }
    }
    keyLabel.text = [NSString stringWithFormat:@"%.4s(%d byte(s)) %.4s", type, length, key];
    userInputView.text = valueForSMCBufferSafe(buffer, length, type, endian);
}

- (void)typeSelected:(UISegmentedControl *)control {
    int desiredType = (int)(control.selectedSegmentIndex + [allTypeControls indexOfObject:control] * 7);
    UIAlertController *warningController = [UIAlertController alertControllerWithTitle:_("Type Change") message:[NSString stringWithFormat:_("Are you sure you want to interpret the item \"%.4s\" as type \"%.4s\"? This may cause undefined behavior."), key, smctypes[desiredType]] preferredStyle:UIAlertControllerStyleAlert];
    [warningController addAction:[UIAlertAction actionWithTitle:_("Proceed") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        int newlength = smctype_to_length(desiredType);
        if (newlength == -1)
        newlength = self->length;
        if (newlength != self->length) {
            UIAlertController *secondWarning = [UIAlertController alertControllerWithTitle:_("Are you 100% sure?") message:[NSString stringWithFormat:_("The type \"%.4s\" you requested is %d bytes long, which doesn't match the current length of %d bytes. Only continue if you're certain of the consequences. Proceed?"), smctypes[desiredType], newlength, self->length] preferredStyle:UIAlertControllerStyleAlert];
            [secondWarning addAction:[UIAlertAction actionWithTitle:_("Proceed") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                if (newlength > self->length) {
                    uint8_t *newbuffer = calloc(newlength, 1);
                    memcpy(newbuffer, self->buffer, self->length);
                    free(self->buffer);
                    self->buffer = newbuffer;
                }
                self->length = newlength;
                memcpy(&self->type, smctypes[desiredType], 4);
                [self refreshTypeControls];
                [self makeHexRepresentation];
            }]];
            [secondWarning addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [self refreshTypeControls];
            }]];
            [self presentViewController:secondWarning animated:1 completion:nil];
            return;
        }
        memcpy(&self->type, smctypes[desiredType], 4);
        [self refreshTypeControls];
    }]];
    [warningController addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self refreshTypeControls];
    }]];
    [self presentViewController:warningController animated:1 completion:nil];
}

- (void)remakeUserInput {
    userInputView.text = valueForSMCBufferSafe(buffer, length, type, endian);
}

- (void)endiannessChanged:(UISegmentedControl *)control {
    endian = (int)control.selectedSegmentIndex;
    [self remakeUserInput];
}

- (void)makeHexRepresentation {
    NSMutableString *str = [NSMutableString stringWithCapacity:length * 4];
    for (int i = 0; i < length; i++) {
        [str appendFormat:@"%02X ", (uint32_t)buffer[i]];
        if ((i + 1) % 12 == 0)
            [str appendString:@"\n"];
    }
    hexConversionView.text = str;
}

- (void)remakeBuffer {
    uint8_t maxBuffer[120] = {0};
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    if (*type == 'c') {
        NSString *input = userInputView.text;
        memcpy(maxBuffer, input.UTF8String, input.length);
        memcpy(buffer, maxBuffer, length);
        [self makeHexRepresentation];
        [self remakeUserInput];
        return;
    } else if (type[3] == '*' && *type == 'u') {
        NSArray *components = [userInputView.text componentsSeparatedByString:@","];
        if (length != components.count) {
            show_alert(_C("Array"), _C("Element count mismatch."), L_OK);
            [self remakeUserInput];
            return;
        }
        for (int i = 0; i < length; i++) {
            NSNumber *cur = [formatter numberFromString:components[i]];
            int cv = [cur intValue];
            if (cv > 255 || cv < -128) {
                show_alert(_C("Array"), _C("Invalid value detected."), L_OK);
                [self remakeUserInput];
                return;
            }
            maxBuffer[i] = (uint8_t)cv;
        }
        memcpy(buffer, maxBuffer, length);
        [self makeHexRepresentation];
        [self remakeUserInput];
        return;
    } else if (type[3] == 'g') {
        NSString *input = userInputView.text;
        if (input.length > length * 8) {
            show_alert(_C("Flags Editor"), _C("Data too long"), L_OK);
            [self remakeUserInput];
            return;
        }
        uint8_t curbyte = 0;
        uint8_t curoff = 0;
        uint8_t *pbuf = maxBuffer;
        for (int i = (int)input.length - 1; i >= 0; i--) {
            unsigned short c = [input characterAtIndex:i];
            if (c == '1') {
                curbyte |= (1 << curoff);
            } else if (c != '0') {
                show_alert(_C("Flags Editor"), _C("Invalid flag value found"), L_OK);
                [self remakeUserInput];
                return;
            }
            curoff++;
            if (curoff == 8) {
                curoff = 0;
                *pbuf = curbyte;
                curbyte = 0;
                pbuf++;
            }
        }
        if (curoff != 0)
            *pbuf = curbyte;
        memcpy(buffer, maxBuffer, length);
        [self makeHexRepresentation];
        [self remakeUserInput];
        return;
    } else if (*type == 'h') {
        [self remakeUserInput];
        show_alert(_C("Hex Editing"), _C("Please use the hex editor below instead."), L_OK);
        return;
    }
    NSNumber *num = [formatter numberFromString:userInputView.text];
    if (!num)
        return;
    if (*type == 's' || *type == 'u') {
        int64_t sv = [num longLongValue];
        if (!endian || type[2] == '8')
            *(int64_t *)maxBuffer = sv;
        else {
            if (type[2] == '1') {
                *(uint16_t *)maxBuffer = htons((uint16_t)sv);
            } else if (type[2] == '3') {
                *(uint32_t *)maxBuffer = htonl((uint32_t)sv);
            } else {
                uint32_t *psv = (uint32_t *)&sv;
                *(uint64_t *)maxBuffer = ((uint64_t)htonl(*psv) << 32LL) | (uint64_t)htonl(psv[1]);
            }
        }
    } else if (*type == 'f') {
        *(float *)maxBuffer = [num floatValue];
        if (endian)
            *(uint32_t *)maxBuffer = htonl(*(uint32_t *)maxBuffer);
    } else if (*type == 'i') {
        uint64_t sv = [num doubleValue] * 65536.0;
        if (endian) {
            uint32_t *psv = (uint32_t *)&sv;
            *(uint64_t *)maxBuffer = ((uint64_t)htonl(*psv) << 32LL) | (uint64_t)htonl(psv[1]);
        } else {
            *(uint64_t *)maxBuffer = sv;
        }
    }
    memcpy(buffer, maxBuffer, length);
    [self makeHexRepresentation];
    [self remakeUserInput];
}

- (void)endEditing {
    if (hexConversionView.isFirstResponder) {
        NSArray *allhex = [[hexConversionView.text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] componentsSeparatedByString:@" "];
        NSMutableArray *fallhex = [NSMutableArray array];
        for (NSString *i in allhex) {
            if (i.length)
                [fallhex addObject:i];
        }
        if (fallhex.count != length) {
            show_alert(_C("Hex Editor"), _C("Data length mismatch"), L_OK);
            [self makeHexRepresentation];
            [self.view endEditing:1];
            return;
        }
        uint8_t tmpbuf[120];
        for (int i = 0; i < length; i++) {
            errno = 0;
            tmpbuf[i] = (uint8_t)strtoul([fallhex[i] UTF8String], NULL, 16);
            if (errno != 0) {
                show_alert(_C("Hex Editor"), _C("Invalid value detected"), L_OK);
                [self makeHexRepresentation];
                [self.view endEditing:1];
                return;
            }
        }
        memcpy(buffer, tmpbuf, length);
        [self makeHexRepresentation];
        [self.view endEditing:1];
        [self remakeUserInput];
        return;
    }
    if (!userInputView.editing)
        return;
    [self.view endEditing:1];
    [self remakeBuffer];
}

- (void)refetchSMCData {
    SMCParamStruct smcstr = {0};
    smcstr.key = htonl(*(uint32_t *)key);
    smcstr.param.keyInfo.dataSize = length;
    smcstr.param.data8 = kSMCReadKey;
    smc_call(kSMCHandleYPCEvent, &smcstr, &smcstr);
    free(buffer);
    buffer = malloc(length);
    memcpy(buffer, smcstr.param.bytes, length);
    [self remakeUserInput];
    [self makeHexRepresentation];
}

- (void)writeSMCData {
    UIAlertController *warningAlert = [UIAlertController alertControllerWithTitle:_("Disclaimer") message:[NSString stringWithFormat:@"%@\n%@\n%@", _("Please read the entire message."), _("Writing to the SMC can be harmful. If unexpected behavior occurs, the developers offer NO WARRANTY to the fullest extent permitted by law."), _("Make sure you understand what you're doing before continuing.")] preferredStyle:UIAlertControllerStyleAlert];
    [warningAlert addAction:[UIAlertAction actionWithTitle:_("I understand, write to SMC NOW") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SMCParamStruct smcstr = {0};
        smcstr.key = htonl(*(uint32_t *)self->key);
        smcstr.param.keyInfo.dataSize = self->length;
        smcstr.param.data8 = kSMCWriteKey;
        memcpy(smcstr.param.bytes, self->buffer, self->length);
        smc_call(kSMCHandleYPCEvent, &smcstr, &smcstr);
        // TODO: Show error result
        if (smcstr.param.result != 0 || smcstr.param.status != 0) {
            show_alert(_C("AppleSMC"), _C("Failed to write to SMC."), L_OK);
            return;
        }
        [self refetchSMCData];
    }]];
    [warningAlert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:warningAlert animated:1 completion:nil];
}

- (void)updateColors {
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        [self setSystemRedColor:[UIColor systemRedColor]];
        return;
    }

    if (@available(iOS 12.0, *)) {
        // We already have a non published darkmode in iOS 12, some tweaks may be able to enforce it
        if ([(id)UIScreen.autoScreen.traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark) {
            self.view.backgroundColor = [UIColor blackColor];
            [self setSystemRedColor:[UIColor colorWithRed:1 green:(69.0f / 255) blue:(58.0f / 255) alpha:1]];
            return;
        }
    }

    self.view.backgroundColor = [UIColor whiteColor];
    [self setSystemRedColor:[UIColor colorWithRed:1 green:(59.0f / 255) blue:(48.0f / 255) alpha:1]];
}

- (void)loadView {
    [super loadView];
    UIView *view = self.view;
    [view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(endEditing)]];

    // Set bgcolor
    [self updateColors];

    keyLabel = [UILabel new];
    keyLabel.text = [NSString stringWithFormat:_("%.4s(%d byte(s)) %.4s"), type, length, key];
    [view addSubview:keyLabel];
    keyLabel.translatesAutoresizingMaskIntoConstraints = 0;
    [keyLabel.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:40].active = 1;
    [keyLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [keyLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    NSMutableArray *alltypes = [NSMutableArray array];
    NSMutableArray *allcontrols = [NSMutableArray array];
    UIView *lastControl = keyLabel;
    for (const char **i = smctypes; *i != NULL; i++) {
        // if(*(uint32_t*)*i==*(uint32_t*)type)
        //	selIndex=alltypes.count;
        [alltypes addObject:[[NSString alloc] initWithBytesNoCopy:(void *)*i length:4 encoding:NSUTF8StringEncoding freeWhenDone:0]];
        if (alltypes.count == 7 || !*(i + 1)) {
            UISegmentedControl *typeControl = [[UISegmentedControl alloc] initWithItems:alltypes];
            // if(selIndex!=-1)
            //	typeControl.selectedSegmentIndex=selIndex;
            [view addSubview:typeControl];
            typeControl.translatesAutoresizingMaskIntoConstraints = 0;
            [typeControl.topAnchor constraintEqualToAnchor:lastControl.bottomAnchor constant:20].active = 1;
            [typeControl.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
            [typeControl.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
            [typeControl addTarget:self action:@selector(typeSelected:) forControlEvents:UIControlEventValueChanged];
            lastControl = typeControl;
            [allcontrols addObject:typeControl];
            [alltypes removeAllObjects];
        }
    }
    allTypeControls = allcontrols;
    UISegmentedControl *endiannessControl = [[UISegmentedControl alloc] initWithItems:@[ @"Little Endian", @"Big Endian" ]];
    endiannessControl.selectedSegmentIndex = 0;
    [view addSubview:endiannessControl];
    endiannessControl.translatesAutoresizingMaskIntoConstraints = 0;
    [endiannessControl.topAnchor constraintEqualToAnchor:lastControl.bottomAnchor constant:50].active = 1;
    [endiannessControl.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [endiannessControl.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    [endiannessControl addTarget:self action:@selector(endiannessChanged:) forControlEvents:UIControlEventValueChanged];
    userInputView = [UITextField new];
    [view addSubview:userInputView];
    userInputView.translatesAutoresizingMaskIntoConstraints = 0;
    [userInputView.topAnchor constraintEqualToAnchor:endiannessControl.bottomAnchor constant:30].active = 1;
    [userInputView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [userInputView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    //[userInputView.heightAnchor constraintEqualToConstant:80].active=1;
    userInputView.text = valueForSMCBufferSafe(buffer, length, type, endian);
    userInputView.borderStyle = UITextBorderStyleRoundedRect;
    UILabel *hexDumpLabel = [UILabel new];
    hexDumpLabel.text = _("Hex Dump");
    hexDumpLabel.translatesAutoresizingMaskIntoConstraints = 0;
    [view addSubview:hexDumpLabel];
    [hexDumpLabel.topAnchor constraintEqualToAnchor:userInputView.bottomAnchor constant:40].active = 1;
    [hexDumpLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [hexDumpLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    hexConversionView = [UITextView new];
    hexConversionView.layer.cornerRadius = 8;
    hexConversionView.layer.borderWidth = 1;
    hexConversionView.layer.borderColor = [[UIColor grayColor] CGColor];
    hexConversionView.translatesAutoresizingMaskIntoConstraints = 0;
    [view addSubview:hexConversionView];
    [hexConversionView.topAnchor constraintEqualToAnchor:hexDumpLabel.bottomAnchor constant:20].active = 1;
    [hexConversionView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [hexConversionView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    [hexConversionView.heightAnchor constraintEqualToConstant:140].active = 1;
    // hexConversionView.editable=0;
    UILabel *noteLabel = [UILabel new];
    noteLabel.text = _("No data is sent to the SMC until you click \"Write to SMC.\"");
    noteLabel.translatesAutoresizingMaskIntoConstraints = 0;
    [view addSubview:noteLabel];
    [noteLabel.topAnchor constraintEqualToAnchor:hexConversionView.bottomAnchor constant:10].active = 1;
    [noteLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [noteLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    noteLabel.numberOfLines = 0;
    UIButton *readButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [readButton setTitle:_("Refetch Data") forState:UIControlStateNormal];
    readButton.translatesAutoresizingMaskIntoConstraints = 0;
    [view addSubview:readButton];
    [readButton.topAnchor constraintEqualToAnchor:noteLabel.bottomAnchor constant:30].active = 1;
    [readButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20].active = 1;
    [readButton addTarget:self action:@selector(refetchSMCData) forControlEvents:UIControlEventTouchUpInside];
    UIButton *writeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [writeButton setTitle:_("Write to SMC") forState:UIControlStateNormal];
    writeButton.translatesAutoresizingMaskIntoConstraints = 0;
    writeButton.tintColor = [self systemRedColor];
    [view addSubview:writeButton];
    [writeButton.topAnchor constraintEqualToAnchor:noteLabel.bottomAnchor constant:30].active = 1;
    [writeButton.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20].active = 1;
    [writeButton addTarget:self action:@selector(writeSMCData) forControlEvents:UIControlEventTouchUpInside];
    [self makeHexRepresentation];
    [self refreshTypeControls];
}

@end
