# Engine notes

The MSX-DOS executable in `src/launch.asm` displays the cover, connects the mouse and launches the selected language executable. Both editions assemble the same Z80 engine against their own generated tables.

The V9990 runs in B2/BP6 mode. The conversion tools prepare wall strips, sprites and interface graphics for rendering and cache placement. The engine uses the MSX VDP for the separate automap display. The assembly is split into the main engine and overlays for the UI, scripts, character creation, magic, effects, automap and introduction.

The SD layout shares common graphics and resource files between editions. Language-specific files stay beside their executable. `ES/EOBSAVE.DAT` and `EN/EOBSAVE.DAT` hold the independent saves.
