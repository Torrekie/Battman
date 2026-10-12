// Minimal arm64/iOS MH_EXECUTE fixture for release-pipeline integration tests.
// It is never installed or shipped. Strict tests opt into the host-shape marker
// table; ordinary engineering fixtures remain intentionally minimal.

#ifndef BATTMAN_FIXTURE_CHANNEL
#define BATTMAN_FIXTURE_CHANNEL "public"
#endif
__attribute__((used, section("__TEXT,__btchannel")))
static const char battman_fixture_channel[] = BATTMAN_FIXTURE_CHANNEL;

#if defined(BATTMAN_STRICT_HOST_FIXTURE)
__attribute__((used)) static const char *const battman_strict_host_markers[] = {
	"com.torrekie.battman.analytics.live",
	"com.torrekie.battman.analytics.capacity",
	"com.torrekie.battman.analytics.cells",
	"com.torrekie.battman.analytics.session",
	"com.torrekie.battman.analytics.discharge",
	"com.torrekie.battman.analytics.events",
	"com.torrekie.battman.analytics.path",
	"com.torrekie.battman.analytics.dwell",
	"com.torrekie.battman.analytics.compare",
	"com.torrekie.battman.analytics.rhythm",
	"com.torrekie.battman.analytics.card.v1",
	"BattmanPluginEntryPointV1",
	"BTPluginImportDidFinishNotification",
};
#endif

int main(void) {
	#if defined(BATTMAN_STRICT_HOST_FIXTURE)
	return battman_strict_host_markers[0][0] == '\0';
	#else
	return 0;
	#endif
}
