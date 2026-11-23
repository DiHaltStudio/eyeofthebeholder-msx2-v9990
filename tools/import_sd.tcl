# Import the SD payload into a bootable Sunrise IDE image.
if {[catch {
    set power off
    ext ide
    set disk [file join $::env(EOB_SETUP) EOB.HDD]
    diskmanipulator create $disk 32M 8M
    hda $disk
    diskmanipulator import hda1 \
        [file join $::env(EOB_BOOT) NEXTOR.SYS] \
        [file join $::env(EOB_BOOT) COMMAND2.COM] \
        [file join $::env(EOB_SETUP) AUTOEXEC.BAT]
    diskmanipulator mkdir hda1 EOB
    diskmanipulator chdir hda1 EOB
    diskmanipulator mkdir hda1 ES
    diskmanipulator mkdir hda1 EN
    set from $::env(EOB_SD)
    diskmanipulator import hda1 {*}[lsort [glob -directory $from -types f *]]
    foreach lang {ES EN} {
        diskmanipulator chdir hda1 /EOB/$lang
        diskmanipulator import hda1 {*}[lsort [glob -directory [file join $from $lang] -types f *]]
    }
} message]} {
    puts stderr $message
    file delete -force -- [file join $::env(EOB_SETUP) EOB.HDD]
}
exit
