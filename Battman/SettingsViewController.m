#import "ObjCExt/UIScreen+Auto.h"
#import "SettingsViewController.h"
#import "DonationPrompter.h"
#import "CGIconSet/BattmanVectorIcon.h"
#include "common.h"
#include <math.h>
#include <sys/utsname.h>
#import <CoreImage/CoreImage.h>
#import <CoreImage/CIFilterBuiltins.h>

// #import "SerialQRCodeTableViewCell.h"

#include "security/selfcheck.h"

@interface CALayer ()
@property (atomic, assign) BOOL continuousCorners;
@end

@interface UIImage ()
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString*)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#if 0
@interface AADeviceInfo : NSObject
+ (instancetype)currentInfo;
- (NSString *)serialNumber;
@end
#endif

/* You may thought we init artworks in BatteryInfoViewController was a terrible idea
 * but this behavior was explicitly intended. Guess why I decided this. */
extern BOOL artwork_avail;
extern CGImageRef getArtworkImageOf(CFStringRef name);

#if 0
static UIImage *loadSerialNumberQRCodeImage(void) {
	static UIImage *QRCodeImage = nil;
	static dispatch_once_t onceToken;
	if (onceToken != -1)
		dispatch_once(&onceToken, ^{
			NSString *serial = nil;
			if (MGCopyAnswerPtr != nil)
				serial = (__bridge NSString *)MGCopyAnswerPtr(CFSTR("SerialNumber"));
			if (!serial){
				// Hacky
				NSBundle *AppleAccount = [NSBundle bundleWithIdentifier:@"com.apple.AppleAccount"];
				if ([AppleAccount loadAndReturnError:nil]) {
					serial = [[[AppleAccount classNamed:@"AADeviceInfo"] currentInfo] serialNumber];
					[AppleAccount unload];
				}
			}
			if (!serial) return;
			CIFilter<CIQRCodeGenerator> *filter;
			if (@available(iOS 13.0, macOS 10.15, *)) {
				filter = [CIFilter QRCodeGenerator];
				filter.message = [serial dataUsingEncoding:NSISOLatin1StringEncoding];
				filter.correctionLevel = @"H";
			} else {
				filter = (CIFilter<CIQRCodeGenerator> *)[CIFilter filterWithName:@"CIQRCodeGenerator"];
				[filter setValue:[serial dataUsingEncoding:NSISOLatin1StringEncoding] forKey:@"inputMessage"];
				[filter setValue:@"H" forKey:@"inputCorrectionLevel"];
			}
			CIImage *image = filter.outputImage;
			CGRect extent = image.extent;
			image = [image imageByApplyingTransform:CGAffineTransformMakeScale(140.0 / CGRectGetWidth(extent), 140.0 / CGRectGetWidth(extent))];
			CIContext *ctx = [CIContext context];
			CGImageRef cgImage = [ctx createCGImage:image fromRect:image.extent];
			QRCodeImage = [UIImage imageWithCGImage:cgImage];
			CGImageRelease(cgImage);
		});
	
	return QRCodeImage;
}
#endif

@interface LanguageSelectionVC : UITableViewController
@end

enum sections_settings {
	SS_SECT_VERSION,
    SS_SECT_ABOUT,
	SS_SECT_SNS,
#ifdef DEBUG
    SS_SECT_DEBUG,
#endif
    SS_SECT_COUNT
};

#ifdef DEBUG
extern NSMutableAttributedString *redirectedOutput;
extern void (^redirectedOutputListener)(void);
#else
static NSMutableAttributedString *redirectedOutput;
static void (^redirectedOutputListener)(void);
#endif

static BOOL _coolDebugVCPresented = 0;

@interface DebugViewController : UIViewController
@property(nonatomic, readwrite, strong) UITextView *textField;
@end
@implementation DebugViewController

- (NSString *)title {
    return _("Logs");
}

- (void)DebugExportPressed {
    NSString *str = [redirectedOutput string];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[ str ] applicationActivities:nil];
    activityViewController.popoverPresentationController.sourceView = self.navigationController.view;
    [self.navigationController presentViewController:activityViewController animated:YES completion:^{}];
}

- (void)closeCoolDebug {
    if (!_coolDebugVCPresented)
        return;
    _coolDebugVCPresented = 0;
    CGRect myFrame = self.navigationController.view.frame;
    [self.navigationController.view removeFromSuperview];
    self.navigationController.parentViewController.view.frame = CGRectMake(0, 0, myFrame.size.width, myFrame.size.height * 3);
    [self.navigationController removeFromParentViewController];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)viewDidUnload {
    [super viewDidUnload];
    redirectedOutputListener = nil;
}
#pragma clang diagnostic pop

- (void)viewDidLoad {
    [super viewDidLoad];
    if (_coolDebugVCPresented) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(closeCoolDebug)];
    }

    self.view.backgroundColor = [UIColor whiteColor];
    self.textField = [UITextView new];
    self.textField.editable=0;
    self.textField.font = [UIFont fontWithName:@"Courier" size:10];

    self.textField.text = [redirectedOutput string];
    redirectedOutputListener = ^{
      self.textField.text = [redirectedOutput string];
      if (!self.textField.scrollEnabled)
          return;
      // https://stackoverflow.com/questions/952412/uiscrollview-scroll-to-bottom-programmatically
      [self.textField setContentOffset:CGPointMake(0, fmax(self.textField.contentSize.height - self.textField.bounds.size.height + self.textField.contentInset.bottom, -50)) animated:YES];
    };

    [self.view addSubview:self.textField];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.textField.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = 1;
    [self.textField.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = 1;
    [self.textField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = 1;
    [self.textField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = 1;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] init];
    UIButton *export_button;
    if (@available(iOS 13.0, *)) {
        UIImage *export_img = [UIImage systemImageNamed:@"square.and.arrow.up"];
        export_button = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, export_img.size.width, export_img.size.height)];
        [export_button setBackgroundImage:export_img forState:UIControlStateNormal];
    } else {
        export_button = [UIButton buttonWithType:UIButtonTypeSystem];
        [export_button.titleLabel setFont:[UIFont fontWithName:@SFPRO size:22]];
        // U+100202
        [export_button setTitle:@"􀈂" forState:UIControlStateNormal];
        [export_button setFrame:CGRectZero];
    }
    [export_button addTarget:self action:@selector(DebugExportPressed) forControlEvents:UIControlEventTouchUpInside];
    [export_button setShowsTouchWhenHighlighted:YES];

    UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithCustomView:export_button];
    self.navigationItem.rightBarButtonItem = barButton;
}

@end

@implementation SettingsViewController
static NSMutableArray *hided_ip = nil;
static NSMutableArray *sns_avail = nil;

- (NSString *)title {
    return _("More");
}

- (instancetype)init {
    UITabBarItem *tabbarItem = [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemMore tag:1];
    tabbarItem.title = _("More");                            // UITabBarSystemItem cannot change title like this
    [tabbarItem setValue:_("More") forKey:@"internalTitle"]; // This is the correct way (But not accepted by App Store)
    self.tabBarItem = tabbarItem;

	// SNS
	NSArray *sns_list = @[
		@"https://torrekie.com", @"", _("Torrekie's website (zh_CN)"),
		@"twitter://user?screen_name=Torrekie", @"com.atebits.Tweetie2", _("Follow @Torrekie"),
		@"bilibili://space/169414691", @"tv.danmaku.bilianime", _("Subscribe me on Bilibili"),
		@"reddit:///u/Torrekie", @"com.reddit.Reddit", _("Follow u/Torrekie on Reddit"),
	];
	sns_avail = [NSMutableArray new];
	for (int i = 0; i < sns_list.count / 3; i++) {
		NSString *link = sns_list[i * 3];
		if ([UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:link]]) {
			[sns_avail addObject:sns_list[(i * 3)]];
			[sns_avail addObject:sns_list[(i * 3) + 1]];
			[sns_avail addObject:sns_list[(i * 3) + 2]];
		}
	}
	hided_ip = [NSMutableArray new];

#if (LICENSE == LICENSE_NONFREE) && (NONFREE_TYPE == NONFREE_TYPE_HAVOC)
	[hided_ip addObject:[NSIndexPath indexPathForRow:4 inSection:SS_SECT_ABOUT]];
#else
	[self hideRowForBadStatus:@"https://havoc.app/package/battman" indexPath:[NSIndexPath indexPathForRow:4 inSection:SS_SECT_ABOUT]];
#endif

	if (@available(iOS 13.0, *))
		return [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	// [self.tableView registerClass:[SerialQRCodeTableViewCell class] forCellReuseIdentifier:@"QR"];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.tableView beginUpdates];
		[self.tableView reloadRowsAtIndexPaths:hided_ip withRowAnimation:UITableViewRowAnimationAutomatic];
		[self.tableView endUpdates];
	});
}

- (void)hideRowForBadStatus:(NSString *)urlString indexPath:(NSIndexPath *)indexPath {
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) return;

	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
	req.HTTPMethod = @"HEAD";

	__weak typeof(self) weakSelf = self;
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return;

		if (error) {
			// NSLog(@"URL check error: %@", error);
			// Optionally treat network error as "bad":
			// [strongSelf updateHideFlag:YES];
			return;
		}
		
		NSInteger statusCode = 0;
		if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
			statusCode = ((NSHTTPURLResponse *)response).statusCode;
		}

		BOOL shouldHide = (statusCode >= 400);
		if (shouldHide) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([hided_ip indexOfObject:indexPath] == NSNotFound)
					[hided_ip addObject:indexPath];
			});
		}
	}];
	[task resume];
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
	if (section == SS_SECT_VERSION)
		return 2;
	if (section == SS_SECT_ABOUT)
		return 6;
	if (section == SS_SECT_SNS)
		return sns_avail.count / 3;
#ifdef DEBUG
	if (section == SS_SECT_DEBUG)
        return 10;
#endif
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
    return SS_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sect {
	if (sect == SS_SECT_ABOUT)
        return _("About Battman");
#ifdef DEBUG
    if (sect == SS_SECT_DEBUG)
        return _("Debug");
#endif
    return nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == SS_SECT_VERSION) {
		if (indexPath.row == 1) {
			NSString *title = _("Gonna tell us something?");
			NSString *message = _("Found a bug or have an idea? Please choose one way to contact us:\nopen a GitHub Issue (public — great for steps/logs)\nor Send Email (for private info or attachments). We really appreciate your help!");
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

			UIAlertAction *github = [UIAlertAction actionWithTitle:_("Open GitHub Issue") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
				open_url("https://github.com/Torrekie/Battman/issues/new");
			}];
			UIAlertAction *email = [UIAlertAction actionWithTitle:_("Send Email") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
				// Don't use MFMailComposeViewController, this is covering the app UI
				NSString *UDID = nil;
				NSString *version_uname = nil;
				struct utsname uts;
				if (uname(&uts) == 0) {
					// "uname -a" like string, and encoded as url arg
					NSMutableCharacterSet *chars = NSCharacterSet.URLQueryAllowedCharacterSet.mutableCopy;
					[chars removeCharactersInRange:NSMakeRange(':', 1)];
					[chars removeCharactersInRange:NSMakeRange(';', 1)];
					[chars removeCharactersInRange:NSMakeRange('/', 1)];
					version_uname = [[NSString stringWithFormat:@"%s %s %s %s %s", uts.sysname, uts.nodename, uts.release, uts.version, uts.machine] stringByAddingPercentEncodingWithAllowedCharacters:chars];
				}
				if (MGCopyAnswerPtr != nil)
					UDID = (__bridge NSString *)MGCopyAnswerPtr(CFSTR("re6Zb+zwFKJNlkQTUeT+/w"));
				NSString *url = [NSString stringWithFormat:@"mailto:me@torrekie.dev?subject=Battman%%20Support%%20Request&body=Hi%%2C%%0AI%%20need%%20help%%20with%%20the%%20following%%3A%%0A%%0AIf%%20I%%20did%%20not%%20remove%%20this%%20section%%20or%%20add%%20any%%20additional%%20information%%2C%%20please%%20disregard%%20this%%20email.%%0A%%0ADevice%%20Info%%3A%%0ABattman%%20Version%%3A%%20%s%%20(%@)%%0AUUID%%3A%%20%@%%0AOS%%20Version%%3A%%20%@%%0A%%0AThank%%20you.", BATTMAN_VERSION_STRING, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GIT_COMMIT_HASH"], UDID, version_uname];
				open_url(url.UTF8String);
			}];
			
			UIAlertAction *cancel = [UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil];
			
			[alert addAction:github];
			[alert addAction:email];
			[alert addAction:cancel];

			[self presentViewController:alert animated:YES completion:nil];
		}
	}
    if (indexPath.section == SS_SECT_ABOUT) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[CreditViewControllerNew new] animated:YES];
        } else if (indexPath.row == 1) {
            open_url("https://github.com/Torrekie/Battman");
		} else if (indexPath.row == 2) {
			open_url("https://github.com/Torrekie/Battman/wiki");
		} else if (indexPath.row == 3) {
			show_donation(true);
		} else if (indexPath.row == 4) {
			open_url("https://havoc.app/package/battman");
		} else if (indexPath.row == 5) {
			uint8_t a[] = { 104, 12, 0, -4, 3, -57, -11, 0, 53, 5, 10, -16, 12, 3, -14, -54, 57, 0, -56, 33, 10, -1, -24, 23, 31, -62, 29, -29, 10 };
			char *o = malloc('O' - '1');
			if (o) {
				int p = (int)a[0];
				o[0] = (char)p;
				for (size_t i = 1; i < ('N' - '1'); i++)
					o[i] = (char)(p += (int8_t)a[i]);
				o[''] = 0;
			}
			open_url(o);
			free(o);
		}
    }
	if (indexPath.section == SS_SECT_SNS) {
		NSString *nsstr = sns_avail[indexPath.row * 3];
		open_url(nsstr.UTF8String);
	}
#ifdef DEBUG
    if (indexPath.section == SS_SECT_DEBUG) {
        if (indexPath.row == 0) {
            if (_coolDebugVCPresented) {
                show_alert("Cool debug VC", "Already presented", "ok");
                [tv deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }
            [self.navigationController pushViewController:[DebugViewController new] animated:YES];
        } else if (indexPath.row == 1) {
#ifndef USE_GETTEXT
            [self.navigationController pushViewController:[LanguageSelectionVC new] animated:YES];
#else
            show_alert("USE_GETTEXT", "UNIMPLEMENTED YET", "OK");
#endif
        } else if (indexPath.row == 2) {
            app_exit();
        } else if (indexPath.row == 3) {
            if (_coolDebugVCPresented) {
                show_alert("Cool debug VC", "Already presented", "ok");
                [tv deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }
            _coolDebugVCPresented = 1;
            UINavigationController *vc = [[UINavigationController alloc] initWithRootViewController:[DebugViewController new]];
            UITabBarController *tbc = self.tabBarController;
            CGFloat halfHeight = tbc.view.frame.size.height / 3;
            self.tabBarController.view.frame = CGRectMake(0, 0, tbc.view.frame.size.width, halfHeight * 2);
            vc.view.frame = CGRectMake(0, halfHeight * 2, tbc.view.frame.size.width, halfHeight);
            [self.tabBarController.view.superview addSubview:vc.view];
            [self.tabBarController addChildViewController:vc];
            // extern void worker_test(void);
            // worker_test();
        } else if(indexPath.row==4) {
            extern int connect_to_daemon(void);
            int fd = connect_to_daemon();
            if (!fd) {
                show_alert("Daemon", "Failed to connect to daemon", "ok");
                [tv deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }
            dispatch_queue_t queue = dispatch_queue_create("daemonOutputRedirectQueue", NULL);
            dispatch_async(queue, ^{
              char buf[512];
              *buf = 6;
              write(fd, buf, 1);
              while (1) {
                  ssize_t len = read(fd, buf, 512);
                  if (len <= 0) {
                      close(fd);
                      return;
                  }
                  write(1, buf, len);
              }
            });
            show_alert("Done", "Check logs", "ok");
        }else if(indexPath.row==5){
        	show_fatal_overlay_async("Oh no", "Some fatal error occurred :(");
		}else if(indexPath.row==7){
			push_fatal_notif();
		}else if (indexPath.row == 8) {
			extern void jitter_text(void);
			jitter_text();
		} else if (indexPath.row == 9) {
			remove([NSString stringWithFormat:@"%s/token", battman_config_dir()].UTF8String);
			app_exit();
		}
    }
#endif

    [tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (UITableViewCell *)tableView:(id)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // TODO: REUSE (Too few cells to reuse for now so no need at this moment)
	// TODO: Add artwork icons
	UITableViewCell *cell = nil;
#if 0
	if (indexPath.section == SS_SECT_VERSION) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		switch (indexPath.row) {
			case 0: {
				SerialQRCodeTableViewCell *qrCell = [tv dequeueReusableCellWithIdentifier:@"QR"];
				if (!qrCell) qrCell = [[SerialQRCodeTableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"QR"];
				qrCell.selectionStyle = 0;
				qrCell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
				[qrCell setQRCodeImage:loadSerialNumberQRCodeImage()];
				return qrCell;
			}
			default:
				break;
		}
	}
#endif
	if (indexPath.section == SS_SECT_VERSION) {
		if (indexPath.row == 0) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];

			static UIImage *battmanIcon = nil;
			static dispatch_once_t onceToken;
			dispatch_once(&onceToken, ^{
				CGFloat width = ([UIScreen autoScreen].scale == 2.0f) ? 58.0f : 87.0f;
				CGFloat scale = [UIScreen autoScreen].scale;
				CGImageRef src = [BattmanVectorIcon BattmanCGImage];
				CGColorSpaceRef colorSpace = CGImageGetColorSpace(src);
				if (!colorSpace) colorSpace = CGColorSpaceCreateDeviceRGB();
				else CGColorSpaceRetain(colorSpace);
				
				CGContextRef ctx = CGBitmapContextCreate(NULL, width, width, 8, 0, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Little);
				CGColorSpaceRelease(colorSpace);
				if (ctx) {
					CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
					CGContextTranslateCTM(ctx, 0, width);
					CGContextScaleCTM(ctx, 1.0, -1.0);
					CGContextDrawImage(ctx, CGRectMake(0, 0, width, width), src);
					CGImageRef resized = CGBitmapContextCreateImage(ctx);
					CGContextRelease(ctx);
					
					UIImage *img = [UIImage imageWithCGImage:resized scale:scale orientation:UIImageOrientationDown];
					CGImageRelease(resized);
					
					battmanIcon = [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
				}
			});

			cell.imageView.image = battmanIcon;
			cell.textLabel.text = _("Version");
			cell.detailTextLabel.text = [NSString stringWithCString:BATTMAN_VERSION_STRING
#if LICENSE == LICENSE_NONFREE
#if NONFREE_TYPE == NONFREE_TYPE_HAVOC
																	" (Havoc)"
#elif NONFREE_TYPE == NONFREE_TYPE_GITHUB
																	" (GitHub)"
#endif
#else
																	" (Public)"
#endif
														   encoding:NSUTF8StringEncoding];
		} else if (indexPath.row == 1) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.textLabel.text = _("Report Bug");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("Report")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
		}
	}
    if (indexPath.section == SS_SECT_ABOUT) {
		cell = [UITableViewCell new];
		BOOL linkColor = YES;
        if (indexPath.row == 0) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = _("Credit");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("Sponsor")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
			linkColor = NO;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = _("Source Code");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("GitHub")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
		} else if (indexPath.row == 2) {
			cell.textLabel.text = _("Battman Wiki & User Manual");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("Hint")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
		} else if (indexPath.row == 3) {
			cell.textLabel.text = _("Support Us");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("Donate")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
		} else if (indexPath.row == 4) {
			cell.textLabel.text = _("View Battman On Havoc");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("Havoc")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
		} else if (indexPath.row == 5) {
			cell.textLabel.text = _("Join Battman Discord");
			if (artwork_avail) {
				cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("Discord")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
			}
		}
		// Color
		if (linkColor) {
			if (@available(iOS 13.0, *)) {
				cell.textLabel.textColor = [UIColor linkColor];
			} else {
				cell.textLabel.textColor = [UIColor colorWithRed:0 green:(122.0f / 255) blue:1 alpha:1];
			}
		}
    }
	if (indexPath.section == SS_SECT_SNS) {
		cell = [UITableViewCell new];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		NSString *bundleID = sns_avail[(indexPath.row * 3) + 1];
		NSString *label = sns_avail[(indexPath.row) * 3 + 2];
		if (artwork_avail && [bundleID length] == 0) {
			cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf(CFSTR("TorrekieWebLogo")) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
		} else if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
			cell.imageView.image = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen autoScreen].scale];
		cell.textLabel.text = label;
	}
#ifdef DEBUG
    if (indexPath.section == SS_SECT_DEBUG) {
		cell = [UITableViewCell new];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (indexPath.row == 0) {
            cell.textLabel.text = _("Logs (stdout)");
        } else if (indexPath.row == 1) {
            cell.textLabel.text = _("Select language override");
        } else if (indexPath.row == 2) {
            cell.textLabel.text = _("Exit App");
        } else if (indexPath.row == 3) {
            cell.textLabel.text = _("Logs (stdout) (very cool)");
        } else if (indexPath.row == 4) {
            cell.textLabel.text = _("Redirect daemon logs");
        }else if(indexPath.row==5) {
            cell.textLabel.text = _("Show fatal error view");
        }else if(indexPath.row==6) {
			cell.accessoryType = UITableViewCellAccessoryNone;
        	cell.textLabel.text=@"Temp Demo";
        	UIView *accView=[[UIView alloc] initWithFrame:CGRectMake(0,0,250,30)];
        	UISegmentedControl *cur=[[UISegmentedControl alloc] initWithItems:@[@"27.0"]];
        	UISegmentedControl *max=[[UISegmentedControl alloc] initWithItems:@[@"Max",@"29.0"]];
        	UISegmentedControl *avg=[[UISegmentedControl alloc] initWithItems:@[@"Avg",@"22.0"]];
        	max.selectedSegmentIndex=0;
        	avg.selectedSegmentIndex=0;
        	cur.userInteractionEnabled=0;
        	max.userInteractionEnabled=0;
        	avg.userInteractionEnabled=0;
        	[accView addSubview:cur];
        	[accView addSubview:max];
        	[accView addSubview:avg];
        	cur.translatesAutoresizingMaskIntoConstraints=0;
        	avg.translatesAutoresizingMaskIntoConstraints=0;
        	max.translatesAutoresizingMaskIntoConstraints=0;
        	[avg.leadingAnchor constraintEqualToAnchor:accView.leadingAnchor].active=1;
        	//[avg.widthAnchor constraintEqualToAnchor:accView.widthAnchor multiplier:0.4].active=1;
        	[max.leadingAnchor constraintEqualToAnchor:avg.trailingAnchor constant:10].active=1;
        	//[max.trailingAnchor constraintEqualToAnchor:accView.trailingAnchor].active=1;
        	//[max.widthAnchor constraintEqualToAnchor:accView.widthAnchor multiplier:0.4].active=1;
        	[cur.leadingAnchor constraintEqualToAnchor:max.trailingAnchor constant:10].active=1;
        	[cur.trailingAnchor constraintEqualToAnchor:accView.trailingAnchor].active=1;
        	//[cur.widthAnchor constraintEqualToAnchor:accView.widthAnchor multiplier:0.2].active=1;
        	cell.accessoryView=accView;
		} else if(indexPath.row==7) {
			cell.textLabel.text = _("Trigger fatal notify");
		} else if (indexPath.row == 8) {
			cell.textLabel.text = _("Trigger UTF jitter");
		} else if (indexPath.row == 9) {
			cell.textLabel.text = _("Remove token and exit");
		}
    }
#endif
	// Normally you should have a valid cell before reaching here
	if (cell == nil) {
		cell = [UITableViewCell new];
		cell.textLabel.text = @"YOU CAN'T SEE ME";
	}
	for (NSIndexPath *ip in hided_ip) {
		if (ip.section == indexPath.section && ip.row == indexPath.row) {
			cell.alpha = 0.0;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
	}

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	// Smooth corners for icons
	// U think im goin to use the bundle icon huh? No, we are just lookin for default size
	UIImage *tmp = [UIImage _applicationIconImageForBundleIdentifier:[NSBundle.mainBundle bundleIdentifier] format:0 scale:[UIScreen autoScreen].scale];
	if (cell.imageView.image != nil) {
		[cell.imageView.layer setCornerRadius:tmp.size.width * 0.225f];
		if (@available(iOS 13.0, *)) {
			[cell.imageView.layer setCornerCurve:kCACornerCurveContinuous];
		}
		if ([cell.imageView.layer respondsToSelector:@selector(setContinuousCorners:)])
			[cell.imageView.layer setContinuousCorners:YES];
	}
	cell.imageView.clipsToBounds = YES;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	for (NSIndexPath *ip in hided_ip) {
		if (ip.section == indexPath.section && ip.row == indexPath.row) {
			return 0.0f;
		}
	}
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

@end

static NSString *_contrib[] = {
    @"Torrekie",
    @"https://github.com/Torrekie",
    @"Ruphane",
    @"https://github.com/LNSSPsd",
};

// Credit

@implementation CreditViewController

- (NSString *)title {
    return _("Credit");
}

- (instancetype)init {
	if (@available(iOS 13.0, *))
		return [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		return [super initWithStyle:UITableViewStyleGrouped];
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
    return sizeof(_contrib) / (2 * sizeof(NSString *));
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sect {
    return _("Battman Credit");
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    open_url([_contrib[indexPath.row * 2 + 1] UTF8String]);
    [tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (UITableViewCell *)tableView:(id)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [UITableViewCell new];
    cell.textLabel.text = _contrib[indexPath.row * 2];
    if (@available(iOS 13.0, *)) {
        cell.textLabel.textColor = [UIColor linkColor];
    } else {
        cell.textLabel.textColor = [UIColor colorWithRed:0 green:(122.0f / 255) blue:1 alpha:1];
    }

    return cell;
}

+ (NSString *)getTHEPATH {
    extern char *THEPATH;
    return [NSString stringWithUTF8String:THEPATH];
}

+ (NSNumber *)getTHENUM {
    extern NSInteger THENUM;
    return [NSNumber numberWithInteger:THENUM];
}

+ (NSArray *)debugGetBatteryCausesLeakDoNotUseInProduction {
    void *IOPSCopyPowerSourcesByType(int);
    return (__bridge NSArray *)IOPSCopyPowerSourcesByType(1);
}

+ (NSDictionary *)debugGetTemperatureHIDData {
	extern NSDictionary *getTemperatureHIDData(void);
	return getTemperatureHIDData();
}

@end

// Language
#ifdef USE_GETTEXT
static int __unused cond_localize_cnt = 0;
static int cond_localize_language_cnt = 0;
#else
extern int cond_localize_cnt;
extern int cond_localize_language_cnt;
extern CFStringRef **cond_localize_find(const char *str);
#endif
extern void preferred_language_code_clear(void);

@implementation LanguageSelectionVC

- (NSString *)title {
    return _("Language Override");
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
    return cond_localize_language_cnt + 1;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
    return 1;
}

- (UITableViewCell *)tableView:(id)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [UITableViewCell new];
    if (indexPath.row == 0) {
        cell.textLabel.text = _("Clear");
        return cell;
    }
#if !defined(USE_GETTEXT)
    cell.textLabel.text = (__bridge NSString *)(*cond_localize_find("English"))[indexPath.row - 1];
    if (preferred_language_code() + 1 == indexPath.row) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
#endif
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0) {
        remove(lang_cfg_file());
        preferred_language_code_clear();
        [tv reloadData];
        return;
    } else {
        int fd = open_lang_override(O_RDWR | O_CREAT, 0600);
        int n = (int)indexPath.row - 1;
        write(fd, &n, 4);
        close(fd);
        preferred_language_code_clear();
        [tv reloadData];
    }
    [tv deselectRowAtIndexPath:indexPath animated:YES];
}

@end
