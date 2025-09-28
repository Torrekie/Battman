#import "ChargingLimitViewController.h"
#import "SliderTableViewCell.h"
#import "PickerAccessoryView.h"
#include "common.h"
#include "intlextern.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sqlite3.h>
#include <sys/errno.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

typedef enum {
	CL_SECTION_GRAPH,
	CL_SECTION_MAIN,
	CL_SECTION_COUNT
} CLSect;

typedef enum {
	CL_GRAPH_ROW,
	CL_GRAPH_COUNT,
} CLRowGraph;

typedef enum {
	CL_MAIN_CYCLEMODE,
	CL_MAIN_LIMITLABEL,
	CL_MAIN_LIMIT,
	CL_MAIN_RESUMELABEL,
	CL_MAIN_RESUME,
	CL_MAIN_DISCHGMODE,
	CL_MAIN_OBCSWITCH,
	CL_MAIN_PIDLABEL,
	CL_MAIN_DAEMONSWITCH,
	CL_MAIN_COUNT,
} CLRowMain;

int connect_to_daemon(void) {
	struct sockaddr_un sockaddr;
	memset(&sockaddr, 0, sizeof(sockaddr));
	sockaddr.sun_family = AF_UNIX;

	NSString *home = NSHomeDirectory();
	if (!home) {
		// HOW
		return 0;
	}

	const char *home_fs = [home fileSystemRepresentation];
	char socket_path[sizeof(sockaddr.sun_path)];
	int needed = snprintf(socket_path, sizeof(socket_path), "%s/Library/dsck", home_fs);
	if (needed < 0 || needed >= (int)sizeof(socket_path)) {
		char errstr[1024];
		snprintf(errstr, sizeof(errstr), "%s\n%s\n%s", L_ERR, "Socket path is too long for sockaddr_un.sun_path.", L_OK);
		show_alert(L_ERR, errstr, L_OK);
		return 0;
	}
	
	strncpy(sockaddr.sun_path, socket_path, sizeof(sockaddr.sun_path));
	size_t addrlen = offsetof(struct sockaddr_un, sun_path) + strlen(sockaddr.sun_path) + 1;
	sockaddr.sun_len = (unsigned char)addrlen;

	int sock = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sock == -1) {
		/*
		char errstr[1024];
		snprintf(errstr, sizeof(errstr), "%s\n%s: %s", _C("Failed to create socket"), L_ERR, strerror(errno));
		show_alert(L_ERR, errstr, L_OK);
		 */
		return 0;
	}
	
	if (connect(sock, (struct sockaddr *)&sockaddr, (socklen_t)addrlen) == -1) {
		/*
		char errstr[1024];
		snprintf(errstr, sizeof(errstr), "%s\n%s\n%s: %s", _C("Failed to connect to daemon at"), sockaddr.sun_path, L_ERR, strerror(errno));
		show_alert(L_ERR, errstr, L_OK);
		close(sock);
		 */
		// No alert bc we need to retry
		return 0;
	}
	
	char cmd = 2;
	if (write(sock, &cmd, 1) != 1) {
		NSLog(@"Failed to write ping to daemon: %s", strerror(errno));
		show_alert(L_FAILED, "Failed to write to daemon.", L_OK);
		close(sock);
		return 0;
	}
	if (read(sock, &cmd, 1) != 1 || cmd != 2) {
		NSLog(@"Failed to ping daemon: %s", strerror(errno));
		show_alert(L_FAILED, "The daemon may not be working properly.", L_OK);
		close(sock);
		return 0;
	}

	NSLog(@"Connected to daemon and received ping!");
	return sock;
}

static void changeLabelColorsInternal(UIView *view, UIColor *color) {
	if (!view)
		return;

	if ([view isKindOfClass:[UILabel class]]) {
		UILabel *label  = (UILabel *)view;
		label.textColor = color;
	}

	for (UIView *subview in view.subviews) {
		changeLabelColorsInternal(subview, color);
	}
}

static void changeLabelColors(UIView *inputView, UIColor *color) {
	if (!inputView || !color)
		return;

	if ([NSThread isMainThread]) {
		changeLabelColorsInternal(inputView, color);
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			changeLabelColorsInternal(inputView, color);
		});
	}
}

static int _cl_sql_pt_cb(void *arr_ref, int cnt, char **texts, char **names) {
	NSMutableArray    *arr = (__bridge NSMutableArray *)arr_ref;
	NSDate            *dt;
	NSNumber          *val;
	NSNumberFormatter *formatter = [NSNumberFormatter new];
	for (int i = 0; i < cnt; i++) {
		if (!strcmp(names[i], "timestamp")) {
			dt = [NSDate dateWithTimeIntervalSince1970:[[formatter numberFromString:[NSString stringWithUTF8String:texts[i]]] doubleValue]];
		} else if (!strcmp(names[i], "Level")) {
			val = [formatter numberFromString:[NSString stringWithUTF8String:texts[i]]];
		}
	}
	[arr addObject:[NSArray arrayWithObjects:dt, val, NULL]];
	return 0;
}

@interface __some_random_defs_111 : NSObject
- (void)setGraphArray:(NSArray *)arr;
- (void)setLabelColor:(UIColor *)color;
- (UIView *)graphView;
@end
extern const char *container_system_group_path_for_identifier(int, const char *, BOOL *);

@interface ChargingLimitViewController ()
@property (nonatomic, copy) NSArray *drainModes;
@end

@implementation ChargingLimitViewController

- (NSString *)title {
	return _("Charging Limit");
}

- (instancetype)init {
	if (@available(iOS 13.0, *)) {
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	} else {
		self = [super initWithStyle:UITableViewStyleGrouped];
	}
	NSBundle *PLBundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/BatteryUsageUI.bundle"];
	if (PLBundle) {
		// TODO: Implement our own GraphView
		PSGraphViewTableCell = [PLBundle classNamed:@"PSGraphViewTableCell"];
		if (PSGraphViewTableCell)
			load_graph = container_system_group_path_for_identifier(0, "systemgroup.com.apple.powerlog", NULL);
	}

	self.drainModes = @[
		_("Discharge, Keep A/C"),
		_("Block A/C")
	];

	[self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"clhighthr"];
	[self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"cllowthr"];

	char  buf[1024];
	char *end = stpcpy(stpcpy(buf, getenv("HOME")), "/Library/daemon");
	strcpy(end, ".run");
	int drfd = open(buf, O_RDONLY);
	if (drfd != -1) {
		int pid;
		if (read(drfd, &pid, 4) == 4) {
			if (kill(pid, 0) == 0 || errno != ESRCH) {
				daemon_pid = pid;
			}
		}
		close(drfd);
	}

	strcpy(end, "_settings");
	int fd = open(buf, O_RDWR | O_CREAT, 0644);
	if (fd == -1) {
		NSLog(@"open %s: Error - %s", buf, strerror(errno));
		show_alert(L_ERR, _C("Failed to open daemon settings file"), L_OK);
		vals = NULL;
		return self;
	}
	// See daemon.c for vals struct, we are doing bad practice here
	char _vals[3];
	if (read(fd, _vals, 3) != 2) {
		NSLog(@"Writing initial values to daemon_settings");
		_vals[0] = -1;
		_vals[1] = -1;
		_vals[2] = 0;
		lseek(fd, 0, SEEK_SET);
		write(fd, _vals, 3);
	}
	lseek(fd, 0, SEEK_SET);
	vals = mmap(NULL, 3, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if ((long long)vals == -1) {
		NSLog(@"mmap: Error - %s", strerror(errno));
		show_alert(L_ERR, _C("File mapping failed"), L_OK);
		vals = NULL;
		close(fd);
		return self;
	}
	close(fd);
	if (daemon_pid) {
		NSLog(@"Daemon likely valid, trying to connect");
		[self connectToDaemon];
	}
	return self;
}

- (void)connectToDaemon {
	if (daemon_fd)
		return;
	daemon_fd = connect_to_daemon();
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sect {
	CLSect section = (CLSect)sect;
	switch (section) {
		case CL_SECTION_GRAPH:
			return load_graph ? _("7-Day Battery Level") : nil;
		case CL_SECTION_MAIN:
			return _("Charging Limit (Experimental)");
		default:
			break;
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)sect {
	CLSect section = (CLSect)sect;
	switch (section) {
		case CL_SECTION_GRAPH:
			return load_graph ? _("The system logs battery charge–level changes for the past 7 days. If this graph is empty, the power-log service may not be running correctly.") : nil;
		case CL_SECTION_MAIN:
			return _("Charging Limit uses a background service to monitor your battery's charge level and automatically adjust charging behavior.");
		default:
			break;
	}
	return nil;
}

- (void)dealloc {
	if (!vals)
		return;
	const char endconnectioncmd = 5;
	if (daemon_fd) {
		write(daemon_fd, &endconnectioncmd, 1);
		close(daemon_fd);
	}
	munmap(vals, 3);
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)sect {
	CLSect section = (CLSect)sect;
	switch (section) {
		case CL_SECTION_GRAPH:
			return CL_GRAPH_COUNT;
		case CL_SECTION_MAIN:
			return CL_MAIN_COUNT;
		default:
			break;
	}
	return 0;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
	return CL_SECTION_COUNT;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == CL_SECTION_MAIN && indexPath.row == CL_MAIN_DAEMONSWITCH) {
		if (vals[1] < vals[0]) {
			show_alert(_C("Invalid Setup"), _C("Limit Value should be bigger than Resume Value"), L_OK);
			return;
		}
		if (daemon_pid) {
			NSLog(@"Daemon is likely active, requesting stop");
			if (!daemon_fd) {
				show_alert(L_ERR, _C("Unable to connect to the daemon."), L_OK);
				[tv deselectRowAtIndexPath:indexPath animated:YES];
				return;
			}
			char stop_cmd = 3;
			write(daemon_fd, &stop_cmd, 1);
			if (read(daemon_fd, &stop_cmd, 1) == 1 && stop_cmd == 3) {
				NSLog(@"Daemon returned 3 - stopped");
				daemon_pid = 0;
				close(daemon_fd);
				daemon_fd = 0;
			}
			[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
		} else {
			extern int battman_run_daemon(void);
			daemon_pid = battman_run_daemon();
			for (int i = 0; i < 30; i++) {
				usleep(50000);
				[self connectToDaemon];
				if (daemon_fd) {
					DBGLOG(@"%@: Got Daemon fd: %d", indexPath, daemon_fd);
					break;
				} else if (i == 29) {
					if (errno != 0) {
						char *errmsg = calloc(256, sizeof(char));
						sprintf(errmsg, "%s\n%s: %s", _C("Unable to connect to the daemon."), L_ERR, strerror(errno));
						show_alert(L_FAILED, errmsg, L_OK);
						free(errmsg);
					} else {
						show_alert(L_FAILED, _C("Couldn't start the daemon — it isn’t responding."), L_OK);
					}
				}
			}
			[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
		}
	}
	[tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)cltypechanged:(UISegmentedControl *)segCon {
	vals[0] = segCon.selectedSegmentIndex ? 0 : -1;
	[self daemonRedecide];
	/* Refreshing the whole tableview causes animation lost */
	NSIndexPath *resumeIndexLabel  = [NSIndexPath indexPathForRow:CL_MAIN_RESUMELABEL inSection:CL_SECTION_MAIN];
	NSIndexPath *resumeIndexSlider = [NSIndexPath indexPathForRow:CL_MAIN_RESUME inSection:CL_SECTION_MAIN];
	[self.tableView reloadRowsAtIndexPaths:@[resumeIndexLabel, resumeIndexSlider] withRowAnimation:UITableViewRowAnimationFade];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (load_graph && indexPath.section == CL_SECTION_GRAPH) {
		return 150;
	}
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	if (previousTraitCollection)
		[super traitCollectionDidChange:previousTraitCollection];
	[self viewDidAppear:YES];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (load_graph) {
		NSIndexPath *ip = [NSIndexPath indexPathForRow:CL_GRAPH_ROW inSection:CL_SECTION_GRAPH];
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
		if ([cell isKindOfClass:[PSGraphViewTableCell class]]) {
			UIView *graph = [(id)cell graphView];
		
			if (@available(iOS 13.0, *)) {
				changeLabelColors(cell, [UIColor labelColor]);
				@try {
					[(id)graph setLabelColor:[UIColor labelColor]];
				} @catch (NSException *exception) {
					os_log_error(gLog, "ChargingLimit: Failed to setLabelColor for graphView");
				}
			}

			[graph setNeedsLayout];
			[graph layoutSubviews];
			[graph setNeedsDisplay];
		}
	}
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell;
	CLSect section = (CLSect)indexPath.section;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	switch (section) {
		case CL_SECTION_GRAPH: {
			if (!load_graph) {
				cell                      = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				cell.textLabel.text       = _("7-Day Battery Level");
				cell.detailTextLabel.text = _("Unavailable");
				return cell;
			}
			const char *pl_container_path = load_graph;
			char        sqlpath[PATH_MAX];
			sprintf(sqlpath, "%s/Library/BatteryLife/CurrentPowerlog.PLSQL", pl_container_path);
			sqlite3 *p_db;
			int      err = sqlite3_open_v2(sqlpath, &p_db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
			if (err != SQLITE_OK) {
				// macOS/Simulator
				err = sqlite3_open_v2("/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL", &p_db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
			}
			if (err != SQLITE_OK) {
				cell                      = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				cell.textLabel.text       = _("7-Day Battery Level");
				cell.detailTextLabel.text = [NSString stringWithUTF8String:sqlite3_errmsg(p_db)];
				sqlite3_close_v2(p_db);
				return cell;
			}
			time_t cur_time = time(NULL);
			sprintf(sqlpath, "SELECT * FROM PLBatteryAgent_EventBackward_BatteryUI WHERE timestamp BETWEEN %ld AND %ld ORDER BY timestamp", cur_time - 3600 * 24 * 7, cur_time);
			char           *errmsg;
			NSMutableArray *arr = [NSMutableArray array];
			err                 = sqlite3_exec(p_db, sqlpath, _cl_sql_pt_cb, (__bridge void *)arr, &errmsg);
			if (err != SQLITE_OK) {
				cell                      = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				cell.textLabel.text       = _("7-Day Battery Level");
				cell.detailTextLabel.text = [NSString stringWithUTF8String:errmsg];
				sqlite3_free(errmsg);
				sqlite3_close_v2(p_db);
				return cell;
			}
			sqlite3_close_v2(p_db);
			id            graphCell     = [PSGraphViewTableCell new];
			NSArray      *modelGraphArr = arr;
			UIScrollView *view          = [(id)graphCell scrollView];
			view.autoresizingMask       = UIViewAutoresizingFlexibleWidth;
			
			[(id)graphCell setGraphArray:modelGraphArr];
			
			return graphCell;
		}
		case CL_SECTION_MAIN: {
			CLRowMain row = (CLRowMain)indexPath.row;
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
			switch (row) {
				case CL_MAIN_CYCLEMODE: {
					cell.textLabel.text = _("When limit is reached");
					NSArray *items;
					if (@available(iOS 13.0, *)) {
						// XXX: Consider use dynamic check
						if (@available(iOS 14.0, *)) {
							items = @[[UIImage systemImageNamed:@"pause.rectangle"], [UIImage systemImageNamed:@"arrow.rectanglepath"]];
						} else {
							// Sadly arrow.rectanglepath is iOS 14+
							items = @[[UIImage systemImageNamed:@"pause.circle"], [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]];
						}
					} else {
						// pause.rectangle U+10029B
						// arrow.rectanglepath U+1008C1
						items = @[@"􀊛", @"􀣁"];
					}
					UISegmentedControl *segCon = [[UISegmentedControl alloc] initWithItems:items];
					if (@available(iOS 13.0, *)) {
						// Handle something?
					} else {
						[segCon setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIFont fontWithName:@SFPRO size:12.0], NSFontAttributeName, nil] forState:UIControlStateNormal];
					}
					
					if (vals[0] == -1) {
						segCon.selectedSegmentIndex = 0;
					} else {
						segCon.selectedSegmentIndex = 1;
					}
					[segCon addTarget:self action:@selector(cltypechanged:) forControlEvents:UIControlEventValueChanged];
					cell.accessoryView = segCon;
					break;
				}
				case CL_MAIN_LIMITLABEL: {
					cell.textLabel.text = _("Limit charging at (%)");
					break;
				}
				case CL_MAIN_LIMIT: {
					SliderTableViewCell *scell = [tv dequeueReusableCellWithIdentifier:@"clhighthr" forIndexPath:indexPath];
					if (!scell) {
						scell = [[SliderTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"clhighthr"];
					}
					scell.slider.minimumValue = 1;
					scell.slider.maximumValue = 100;
					scell.slider.enabled      = 1;
					scell.textField.enabled   = 1;
					scell.delegate            = (id)self;
					if (vals[1] == -1) {
						scell.slider.value   = 100;
						scell.textField.text = @"100";
					} else {
						scell.slider.value   = (float)vals[1];
						scell.textField.text = [NSString stringWithFormat:@"%d", (int)vals[1]];
					}
					return scell;
				}
				case CL_MAIN_RESUMELABEL: {
					if (vals[0] == -1)
						cell.textLabel.enabled = NO;
					cell.textLabel.text = _("Resume charging at (%)");
					break;
				}
				case CL_MAIN_RESUME: {
					SliderTableViewCell *scell = [tv dequeueReusableCellWithIdentifier:@"cllowthr" forIndexPath:indexPath];
					if (!scell) {
						scell = [[SliderTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cllowthr"];
					}
					scell.slider.minimumValue = 0;
					scell.slider.maximumValue = 100;
					scell.delegate            = (id)self;
					if (vals[0] == -1) {
						scell.slider.enabled                   = NO;
						scell.slider.userInteractionEnabled    = NO;
						scell.slider.value                     = 0;
						scell.textField.enabled                = 0;
						scell.textField.userInteractionEnabled = 0;
						scell.textField.text                   = @"0";
					} else {
						scell.slider.enabled                   = 1;
						scell.slider.userInteractionEnabled    = 1;
						scell.slider.value                     = (float)vals[0];
						scell.textField.enabled                = 1;
						scell.textField.userInteractionEnabled = 1;
						scell.textField.text                   = [NSString stringWithFormat:@"%d", (int)vals[0]];
					}
					return scell;
				}
				case CL_MAIN_DISCHGMODE: {
					cell.textLabel.text = _("Drain Mode");
					PickerAccessoryView *picker = [[PickerAccessoryView alloc] initWithFrame:CGRectZero font:nil options:self.drainModes];
					[picker addTarget:self action:@selector(drainModeChanged:)];
					[picker selectAutomaticRow:BIT_GET(vals[2], 0) animated:YES];
					cell.accessoryView = picker;
					cell.clipsToBounds = YES;
					break;
				}
				case CL_MAIN_OBCSWITCH: {
					cell.textLabel.text = _("Override OBC On Cycle");
					UISwitch *cswitch = [UISwitch new];
					cswitch.on = BIT_GET(vals[2], 1);
					cell.detailTextLabel.text = cswitch.on ? _("OBC will turn off") : _("OBC will not be affected");
					[cswitch addTarget:self action:@selector(overrideOBCChanged:) forControlEvents:UIControlEventValueChanged];
					cell.accessoryView = cswitch;
					break;
				}
				case CL_MAIN_PIDLABEL: {
					if (daemon_pid) {
						DBGLOG(@"%@: Got Daemon PID: %d", indexPath, daemon_pid);
						cell.textLabel.text = [NSString stringWithFormat:@"%@ (%@: %d)", _("Daemon is active"), _("PID"), daemon_pid];
					} else {
						cell.textLabel.text = _("Daemon is inactive");
					}
					break;
				}
				case CL_MAIN_DAEMONSWITCH: {
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					if (daemon_pid) {
						cell.textLabel.text = _("Stop Daemon (Disable Charging Limit)");
					} else {
						cell.textLabel.text = _("Start Daemon (Enforce Charging Limit)");
					}
					if (@available(iOS 13.0, *)) {
						cell.textLabel.textColor = [UIColor linkColor];
					} else {
						cell.textLabel.textColor = [UIColor colorWithRed:0 green:(122.0f / 255) blue:1 alpha:1];
					}
					break;
				}
				case CL_MAIN_COUNT: {
					break;
				}
			}
		}
		default:
			break;
	}

	return cell;
}

#pragma mark - SliderTableViewCell Delegate

- (void)sliderTableViewCellDidBeginChanging:(SliderTableViewCell *)cell {
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	NSIndexPath *curr = [self.tableView indexPathForCell:cell];
	if (curr.section == CL_SECTION_MAIN) {
		NSIndexPath *oppo = [NSIndexPath indexPathForRow:curr.row - (isHighThr ? -2 : 2) inSection:curr.section];
		if (vals[0] != -1) {
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.userInteractionEnabled = NO;
		}
	}

	os_log_error(gLog, "sliderTableViewCellDidBeginChanging: unexpected call at indexPath %ld:%ld", curr.section, curr.row);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value {
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	int8_t rounded = (int8_t)lroundf(value);
	NSIndexPath *ip = [self.tableView indexPathForCell:cell];
	if (ip.section == CL_SECTION_MAIN) {
		if ((isHighThr && value < vals[0]) || (!isHighThr && value > vals[1])) {
			vals[!isHighThr] = rounded + (isHighThr ? -1 : 1);
			vals[!isHighThr] = MIN(MAX(vals[!isHighThr], 0), 100);

			// XXX: Improve readability
			NSIndexPath *oppo = [NSIndexPath indexPathForRow:[self.tableView indexPathForCell:cell].row - (isHighThr ? -2 : 2) inSection:[self.tableView indexPathForCell:cell].section];
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.slider.value = vals[!isHighThr];
			oppocell.textField.text = [NSString stringWithFormat:@"%d", vals[!isHighThr]];
		}
		
		vals[isHighThr] = rounded;
		cell.slider.value = rounded;
		cell.textField.text = [NSString stringWithFormat:@"%d", rounded];
		return;
	}

	os_log_error(gLog, "sliderTableViewCell:didChangeValue: unexpected call at indexPath %ld:%ld", ip.section, ip.row);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didEndChangingValue:(float)value {
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	NSIndexPath *curr = [self.tableView indexPathForCell:cell];
	if (curr.section == CL_SECTION_MAIN) {
		NSIndexPath *oppo = [NSIndexPath indexPathForRow:curr.row - (isHighThr ? -2 : 2) inSection:curr.section];

		if (vals[0] != -1) {
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.userInteractionEnabled = YES;
		}

		[self daemonRedecide];
	}

	os_log_error(gLog, "sliderTableViewCell:didEndChangingValue: unexpected call at indexPath %ld:%ld", curr.section, curr.row);
}


- (void)daemonRedecide {
	// Do msync after vals[] changes
	if (msync(vals, sizeof(vals), MS_SYNC) == -1) {
		os_log_error(gLog, "msync failed: %s", strerror(errno));
	}
	const char redecidecmd = 4;
	write(daemon_fd, &redecidecmd, 1);
}

- (void)drainModeChanged:(PickerAccessoryView *)sender {
	NSInteger row = [sender selectedRowInComponent:0];
	NSInteger opt = row % sender.options.count;
	DBGLOG(@"Value %ld: %@", opt, sender.options[opt]);
	/* Currently we only have 2 drain modes so this is a binary stored at bit 0
	 * This has to be changed once we have more than 2 */
	BIT_SET(vals[2], 0, (opt & 1));
	[self daemonRedecide];
}

- (void)overrideOBCChanged:(UISwitch *)sender {
	BIT_SET(vals[2], 1, sender.on);
	[self daemonRedecide];
	/* Im lazy, so hardcode here */
	NSIndexPath *ip = [NSIndexPath indexPathForRow:CL_MAIN_OBCSWITCH inSection:CL_SECTION_MAIN];
	[self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
