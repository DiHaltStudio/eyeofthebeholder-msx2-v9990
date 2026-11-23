// main.cpp - renders every sound effect of ADLIB.DAT (AdLib driver v1, as
// EOB1 uses it) into the OPL register writes of each driver tick (72 Hz).
// Usage: adlib_render ADLIB.DAT out.bin
// out.bin: for each of the 120 tracks: u16 ticks, then per tick u8 count
// and count x (u8 register, u8 value); 0 ticks for an empty track. Track 0
// holds the writes of initDriver.
#include "adlib.cpp"
namespace OPL { std::vector<std::pair<int, int>> g_writes; }
using namespace Kyra;

int main(int argc, char **argv) {
	FILE *f = fopen(argv[1], "rb");
	if (!f) return 1;
	std::vector<uint8> file(1 << 16);
	size_t n = fread(file.data(), 1, file.size(), f);
	fclose(f);
	FILE *o = fopen(argv[2], "wb");
	for (int track = 0; track < 120; track++) {
		uint8 id = file[track];
		std::vector<std::vector<std::pair<int, int>>> ticks;
		if (!track) {
			// track 0: what initDriver writes, once at the start
			OPL::g_writes.clear();
			AdLibDriver *d = new AdLibDriver(nullptr, 1);
			d->initDriver();
			ticks.push_back(OPL::g_writes);
			delete d;
		} else if (id != 0xFF) {
			std::vector<uint8> data(file.begin() + 120, file.begin() + n);
			AdLibDriver *d = new AdLibDriver(nullptr, 1);
			d->initDriver();
			d->setSoundData(data.data(), data.size());
			d->setMusicVolume(255);
			d->setSfxVolume(255);
			OPL::g_writes.clear();
			d->startSound(id, 0xFF);
			// until nothing plays (or 20 s)
			int quiet = 0;
			for (int t = 0; t < 72 * (getenv("SECS") ? atoi(getenv("SECS")) : 20) && quiet < 2; t++) {
				OPL::g_writes.clear();
				d->callback();
				ticks.push_back(OPL::g_writes);
				bool any = false;
				for (int c = 0; c < 10; c++)
					any |= d->isChannelPlaying(c);
				quiet = any ? 0 : quiet + 1;
			}
			delete d;
		}
		uint16 nt = ticks.size();
		fwrite(&nt, 2, 1, o);
		for (auto &t : ticks) {
			uint8 c = t.size() > 255 ? 255 : t.size();
			fwrite(&c, 1, 1, o);
			for (int i = 0; i < c; i++) {
				uint8 rv[2] = { (uint8)t[i].first, (uint8)t[i].second };
				fwrite(rv, 2, 1, o);
			}
		}
	}
	fclose(o);
	return 0;
}
