# run.sh changes the process working directory. Restore it before any test
# sources relative paths or writes screenshots, and before disk-build commands.
cd $::env(EOB_PROJECT_DIR)
