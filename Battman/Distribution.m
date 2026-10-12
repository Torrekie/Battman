// The channel marker is compiled with the same definitions as the application.
// Packaging reads this Mach-O section instead of inferring a channel from a name.
#import "common.h"

#if LICENSE == LICENSE_NONFREE && NONFREE_TYPE == NONFREE_TYPE_HAVOC
#if !__has_include("nonfree-havoc.m")
#error The Havoc target requires its private authorization implementation.
#endif
#include "nonfree-havoc.m"
#define BT_DISTRIBUTION "havoc"
#elif LICENSE == LICENSE_NONFREE && NONFREE_TYPE == NONFREE_TYPE_GITHUB
#define BT_DISTRIBUTION "github"
#else
#define BT_DISTRIBUTION "public"
#endif

__attribute__((used, section("__TEXT,__btchannel")))
static const char BTDistributionChannel[] = BT_DISTRIBUTION;
