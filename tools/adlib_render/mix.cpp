// Independent oracle: run the original AdLib driver with simultaneous cues.
// Usage: adlib_mix SOUND.DAT schedule.txt states.bin
// Schedule: number of 72Hz ticks, then pairs of tick and SOUND.DAT track.
// Output per tick: u16 active driver channels, then 256 OPL register values.
#include "adlib.cpp"
namespace OPL { std::vector<std::pair<int, int>> g_writes; }
using namespace Kyra;
int main(int argc, char **argv) {
	if (argc != 4) return 2;
	FILE *f = fopen(argv[1], "rb");
	if (!f) return 2;
	std::vector<uint8> data(65536);
	size_t size = fread(data.data(), 1, data.size(), f);
	fclose(f);
	if (size <= 120) return 2;
	FILE *schedule = fopen(argv[2], "r");
	if (!schedule) return 2;
	int total, tick, track;
	if (fscanf(schedule, "%d", &total) != 1 || total < 1 || total > 17280) return 2;
	std::vector<std::pair<int, int>> cues;
	while (fscanf(schedule, "%d%d", &tick, &track) == 2) {
		if (tick < 0 || tick >= total || track < 1 || track >= 120 || data[track] == 255) return 2;
		cues.emplace_back(tick, track);
	}
	fclose(schedule);
	AdLibDriver driver(nullptr, 1);
	driver.initDriver();
	uint8 regs[256] = {};
	for (auto [r, v] : OPL::g_writes) regs[r] = v;
	driver.setSoundData(data.data() + 120, size - 120);
	driver.setMusicVolume(255);
	driver.setSfxVolume(255);
	FILE *out = fopen(argv[3], "wb");
	if (!out) return 2;
	for (int t = 0; t < total; ++t) {
		for (auto [at, sound] : cues) if (at == t) driver.startSound(data[sound], 255);
		OPL::g_writes.clear();
		driver.callback();
		for (auto [r, v] : OPL::g_writes) regs[r] = v;
		uint16 active = 0;
		for (int c = 0; c < 10; ++c) if (driver.isChannelPlaying(c)) active |= 1 << c;
		uint8 mask[2] = {uint8(active), uint8(active >> 8)};
		fwrite(mask, 2, 1, out);
		fwrite(regs, sizeof(regs), 1, out);
	}
	fclose(out);
}
