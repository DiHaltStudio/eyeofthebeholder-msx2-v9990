# gfx9000_autovideo.tcl - Switches openMSX's video output to the GFX9000
# when a program turns its display on (DISP bit of R#8) and switches it back to
# the MSX VDP when it turns it off. It only acts on changes, so it does not
# prevent choosing another output by hand.
# Usage: openmsx -script tools/gfx9000_autovideo.tcl, or copy it to
# share/scripts/ in the openMSX user directory so it is always loaded
# (also in openMSX instances launched from other tools).
namespace eval gfx9000_autovideo {
  variable last 0
  proc regs {} {
    foreach d [debug list] {
      if {[string match "*GFX9000 regs" $d]} { return $d }
    }
    return ""
  }
  proc poll {} {
    variable last
    set d [regs]
    if {$d ne ""} {
      set on [expr {([debug read $d 8] & 0x80) != 0}]
      if {$on && !$last} { catch {set ::videosource GFX9000} }
      if {!$on && $last} { catch {set ::videosource MSX} }
      set last $on
    }
    after time 0.25 [namespace code poll]
  }
  after time 0.5 [namespace code poll]
}
