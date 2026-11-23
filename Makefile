# Eye of the Beholder for MSX-DOS2 + V9990
.DEFAULT_GOAL := all
SJASM ?= sjasm
PYTHON ?= python3
BUILD := build
EN := build/en
VERSION ?= 1.0

export EOB_PC_DIR := $(abspath third_party/dos-es)
ES_INPUTS := $(wildcard third_party/dos-es/*)
EN_INPUTS := $(BUILD)/english.stamp
KYRA_INPUTS := $(wildcard third_party/scummvm/*)
ADLIB_SOURCES := $(shell find tools/adlib_render -type f)
.PHONY: all inputs release manual run run-msx2 run-turbor help clean
LEVELS  = 1 2 3 4 5 6 7 8 9 10 11 12
DATA    = $(foreach l,$(LEVELS),$(BUILD)/LEVEL$(l).V9 $(BUILD)/LEVEL$(l).PAL $(BUILD)/LEVEL$(l).DAT $(BUILD)/LEVEL$(l).SHP $(BUILD)/LEVEL$(l).INF $(BUILD)/LEVEL$(l).LVL) \
          $(BUILD)/vram.inc $(BUILD)/tables.inc $(BUILD)/drawlist.inc $(BUILD)/doortab.inc $(BUILD)/teletab.inc
GLOBAL  = $(BUILD)/UI.V9 $(BUILD)/GLOBAL.SHP $(BUILD)/GLOBAL.DAT $(BUILD)/PARTY.DAT $(BUILD)/fixed.json \
          $(BUILD)/ITEMS.DAT $(BUILD)/ITEMNAME.DAT $(BUILD)/global.json $(BUILD)/gui.inc $(BUILD)/blueicons.inc $(BUILD)/font.inc \
          $(BUILD)/strings.inc $(BUILD)/effectdata.inc $(BUILD)/itemshp.inc $(BUILD)/vgalut.inc $(BUILD)/cursor.inc $(BUILD)/TEXT.DAT
SRCS    = $(wildcard src/*.asm)
INITIAL_SAVE = assets/saves/initial/EOBSAVE.DAT

all: $(BUILD)/sd.stamp

$(BUILD)/rules.inc $(EN)/rules.inc &: tools/gen_rules_tables.py $(BUILD)/eob_tables.json
	$(PYTHON) tools/gen_rules_tables.py

$(GLOBAL) &: tools/conv_global.py tools/conv_level.py tools/eoblib.py $(BUILD)/eob_tables.json $(ES_INPUTS)
	@mkdir -p $(BUILD)
	EOB_LANG=es $(PYTHON) tools/conv_global.py

$(DATA) &: $(GLOBAL) tools/conv_level.py tools/eoblib.py $(BUILD)/eob_tables.json $(ES_INPUTS)
	@mkdir -p $(BUILD)
	for l in $(LEVELS); do EOB_LANG=es $(PYTHON) tools/conv_level.py $$l || exit 1; done

$(BUILD)/adlib_render: $(ADLIB_SOURCES)
	@mkdir -p $(BUILD)
	$(CXX) -O1 -w -include tools/adlib_render/stubs.h -Itools/adlib_render -o $@ tools/adlib_render/main.cpp

$(BUILD)/SFX.DAT $(BUILD)/CGSND.DAT &: $(BUILD)/adlib_render tools/conv_sfx.py tools/eoblib.py $(BUILD)/eob_tables.json $(ES_INPUTS)
	EOB_LANG=es $(PYTHON) tools/conv_sfx.py

CHARGEN = $(BUILD)/CHARGEN.V9 $(BUILD)/CHARGEN.PAL $(BUILD)/chargen.inc
$(CHARGEN) &: $(DATA) tools/conv_chargen.py
	EOB_LANG=es $(PYTHON) tools/conv_chargen.py

$(BUILD)/INTRO.SEQ: $(BUILD)/adlib_render tools/conv_intro.py tools/conv_level.py tools/conv_sfx.py $(BUILD)/eob_tables.json $(ES_INPUTS)
	EOB_LANG=es $(PYTHON) tools/conv_intro.py && touch $@

$(BUILD)/EOB.BIN: $(SRCS) $(DATA) $(GLOBAL) $(CHARGEN) $(BUILD)/SFX.DAT $(BUILD)/INTRO.SEQ $(BUILD)/rules.inc
	cd src && $(SJASM) -s eob.asm ../$@		# also writes build/SCRIPT.OVL...

# English: the same conversion with EOB_LANG=en (pc_en/ has the English
# texts), assembled from a copy of src/ whose ../build/ is build/en/
$(EN)/DATA.OK $(EN)/blueicons.inc $(EN)/cursor.inc &: $(GLOBAL) $(BUILD)/adlib_render $(EN_INPUTS) tools/conv_global.py tools/conv_level.py \
               tools/conv_intro.py tools/conv_chargen.py tools/eoblib.py $(BUILD)/eob_tables.json $(ES_INPUTS)
	@mkdir -p $(EN)
	EOB_LANG=en $(PYTHON) tools/conv_global.py
	for l in $(LEVELS); do EOB_LANG=en $(PYTHON) tools/conv_level.py $$l >/dev/null || exit 1; done
	EOB_LANG=en $(PYTHON) tools/conv_intro.py
	EOB_LANG=en $(PYTHON) tools/conv_chargen.py
	touch $(EN)/DATA.OK

$(EN)/EOB.BIN: $(SRCS) $(EN)/DATA.OK $(EN)/blueicons.inc $(EN)/cursor.inc $(EN)/rules.inc
	rm -rf $(EN)/asm && mkdir -p $(EN)/asm/src && cp src/*.asm $(EN)/asm/src/ && ln -s .. $(EN)/asm/build
	cd $(EN)/asm/src && $(SJASM) -s eob.asm ../build/EOB.BIN

# the launcher and its pictures
$(BUILD)/LOGO.BIN $(BUILD)/COVER.BIN &: tools/conv_opening.py assets/dihalt_logo-b1.png docs/img/opening.png
	@mkdir -p $(BUILD)
	$(PYTHON) tools/conv_opening.py

$(BUILD)/logo_psg.bin: tools/build_logo_psg.py assets/sound/dihalt_psg.vgm
	$(PYTHON) tools/build_logo_psg.py

$(BUILD)/EOB.COM: src/launch.asm $(BUILD)/logo_psg.bin
	# launch.asm names EOB.COM; use a separate basename for its symbols.
	cd src && $(SJASM) -s launch.asm ../$(BUILD)/launch.com


inputs:
	@$(PYTHON) tools/prepare_inputs.py check

$(BUILD)/english.stamp: tools/prepare_inputs.py tools/eoblib.py $(wildcard third_party/dos-en/*) | inputs
	$(PYTHON) tools/prepare_inputs.py english
	@touch $@

$(BUILD)/eob_tables.json: tools/kyradat.py $(KYRA_INPUTS) | inputs
	@mkdir -p $(BUILD)
	$(PYTHON) tools/kyradat.py third_party/scummvm/resource.h third_party/scummvm/kyra.dat $@.tmp
	mv $@.tmp $@

# The global converter counts messages in both editions when laying out data.
$(GLOBAL): $(EN_INPUTS)

$(BUILD)/sd.stamp: $(BUILD)/EOB.COM $(BUILD)/EOB.BIN $(EN)/EOB.BIN $(BUILD)/LOGO.BIN $(BUILD)/COVER.BIN \
                   $(DATA) $(GLOBAL) $(CHARGEN) $(BUILD)/CGSND.DAT $(INITIAL_SAVE) tools/stage_sd.sh
	LEVELS="$(LEVELS)" sh tools/stage_sd.sh
	@touch $@

release: all
	$(PYTHON) tools/package_release.py "$(VERSION)" build/SD/EOB

manual:
	sh tools/build_manual.sh

# If an unpacked release is available, the runner can use it directly.
SD_DIR ?= $(if $(wildcard SD/EOB/EOB.COM),SD/EOB,build/SD/EOB)
run: run-turbor

run-msx2 run-turbor:
	@test -f "$(SD_DIR)/EOB.COM" || $(MAKE) all
	sh tools/run_sd.sh $@ "$(abspath $(SD_DIR))"

help:
	@printf '%s\n' 'make              Build the bilingual game into build/SD/EOB' \
		'make release      Package the game ZIP and both PDFs' \
		'make manual       Rebuild the English and Spanish PDFs' \
		'make run-msx2     Launch the SD payload in openMSX on an MSX2' \
		'make run-turbor   Launch the SD payload in openMSX on a turbo R' \
		'make clean        Remove build outputs and release files'

clean:
	rm -rf $(BUILD)
	rm -f release/Eye-of-the-Beholder-MSX2-V9990-*.zip release/Manual-EN.pdf release/Manual-ES.pdf
