// Minimal arm64/iOS MH_EXECUTE fixture for release-pipeline integration tests.
// It is never installed or shipped. Strict tests opt into the host-shape marker
// table; ordinary engineering fixtures remain intentionally minimal.

#if defined(BATTMAN_STRICT_HOST_FIXTURE)
__attribute__((used)) static const char *const battman_strict_host_markers[] = {
	"com.torrekie.battman.analytics.battery.summary",
	"com.torrekie.battman.analytics.temperature.average",
	"com.torrekie.battman.analytics.power.average",
	"com.torrekie.battman.analytics.cycle.summary",
	"com.torrekie.battman.analytics.capacity.remaining",
	"com.torrekie.battman.analytics.charging-limit",
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
