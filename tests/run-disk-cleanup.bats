#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SCRIPT="$DOTFILES_ROOT/bin/run-disk-cleanup"

# Anything older than the script's 24h staleness cut-off.
OLD_STAMP=202001010000

# Utilities reachable from inside the sandbox: what the script shells out to,
# plus cat for the stubs' own heredocs. Linked into a private directory so PATH
# can stay narrow - this machine ships a real /usr/bin/xcrun and /usr/bin/jq,
# and exposing the whole system bin directory would let a "the tool is missing"
# test quietly drive the real tool against the real machine.
SYS_TOOLS=(awk basename cat df du find grep rm sed sort tail)

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  TEST_TMP="$BATS_TEST_TMPDIR/tmp"
  STUB_BIN="$BATS_TEST_TMPDIR/stubs"
  SYS_BIN="$BATS_TEST_TMPDIR/sysbin"
  mkdir -p "$TEST_HOME" "$TEST_TMP" "$STUB_BIN" "$SYS_BIN"

  local tool
  for tool in "${SYS_TOOLS[@]}"; do
    ln -sf "$(command -v "$tool")" "$SYS_BIN/$tool"
  done
}

# Source the script in library mode and evaluate one snippet against it, with
# HOME, TMPDIR and ANDROID_HOME pointed at the sandbox. bash is invoked by
# absolute path so PATH is free to omit everything the test wants absent.
#   lib <code> [VAR=value...]
lib() {
  local code="$1"
  shift
  run env -i \
    HOME="$TEST_HOME" \
    TMPDIR="$TEST_TMP" \
    ANDROID_HOME="$TEST_HOME/sdk" \
    PATH="$STUB_BIN:$SYS_BIN" \
    "$@" \
    /bin/bash -c '_DISK_CLEANUP_LIB_ONLY=1 source "$0"; eval "$1"' "$SCRIPT" "$code"
}

# stub <name> <body>: drop an executable of that name into the stub dir.
stub() {
  printf '#!/bin/sh\n%s\n' "$2" > "$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# provide <tool>: expose the real tool to the sandboxed PATH.
provide() { ln -sf "$(command -v "$1")" "$SYS_BIN/$1"; }

mkfile_kb() { dd if=/dev/zero of="$1" bs=1024 count="$2" status=none; }

# make_cdk_dir <name> <kb> [stamp]: a cdk.out directory of a known size.
make_cdk_dir() {
  local dir="$TEST_TMP/$1"
  mkdir -p "$dir"
  mkfile_kb "$dir/asset" "$2"
  [[ -n "${3:-}" ]] && touch -t "$3" "$dir"
  return 0
}

make_ndk() {
  mkdir -p "$TEST_HOME/sdk/ndk/$1"
  mkfile_kb "$TEST_HOME/sdk/ndk/$1/payload" "${2:-64}"
}

# xcrun is always called as `simctl <verb> ...`, so the verb is $2:
# `simctl list devices`, `simctl runtime list -j`, `simctl delete unavailable`.
stub_xcrun() {
  stub xcrun "$1"
}

# ─── flags & help ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: run-disk-cleanup"* ]]
}

@test "an unknown flag exits 2 and prints usage to stderr" {
  run --separate-stderr bash "$SCRIPT" --nope
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"Unknown option: --nope"* ]]
  [[ "$stderr" == *"Usage: run-disk-cleanup"* ]]
}

@test "a dry run that finds nothing still exits 0" {
  lib 'DRY_RUN=1 clean_cdk'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing stale"* ]]
}

# ─── human (pure) ──────────────────────────────────────────────────────────

@test "human keeps sub-megabyte values in whole KB" {
  lib 'human 0; human 512; human 1023'
  [ "${lines[0]}" = "0 KB" ]
  [ "${lines[1]}" = "512 KB" ]
  [ "${lines[2]}" = "1023 KB" ]
}

@test "human steps up through MB, GB and TB" {
  lib 'human 1024; human 1048576; human 1073741824'
  [ "${lines[0]}" = "1.0 MB" ]
  [ "${lines[1]}" = "1.0 GB" ]
  [ "${lines[2]}" = "1.0 TB" ]
}

@test "human stops scaling at TB rather than inventing a unit" {
  lib 'human 2147483648'
  [ "$output" = "2.0 TB" ]
}

# ─── size_kb ───────────────────────────────────────────────────────────────

@test "size_kb with no paths is 0 rather than an error" {
  lib 'size_kb'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "size_kb agrees with du -sk on the same paths" {
  make_cdk_dir cdk.outAAA 200
  local expected
  expected=$(du -sk "$TEST_TMP/cdk.outAAA" | awk '{print $1}')

  lib 'size_kb "$TMPDIR/cdk.outAAA"'
  [ "$output" = "$expected" ]
}

@test "size_kb sums across several paths" {
  make_cdk_dir cdk.outAAA 200
  make_cdk_dir cdk.outBBB 300
  local expected
  expected=$(du -sk "$TEST_TMP"/cdk.out* | awk '{s+=$1} END {print s}')

  lib 'size_kb "$TMPDIR"/cdk.out*'
  [ "$output" = "$expected" ]
}

@test "size_kb ignores a path that does not exist" {
  lib 'size_kb "$TMPDIR/absent"'
  [ "$output" = "0" ]
}

# ─── cdk ───────────────────────────────────────────────────────────────────

@test "clean_cdk removes stale cdk.out directories and reports the count" {
  make_cdk_dir cdk.outAAA 200 "$OLD_STAMP"
  make_cdk_dir cdk.outBBB 300 "$OLD_STAMP"

  lib 'clean_cdk'
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 directories"* ]]
  [[ "$output" == *"removed"* ]]
  [ ! -d "$TEST_TMP/cdk.outAAA" ]
  [ ! -d "$TEST_TMP/cdk.outBBB" ]
}

@test "clean_cdk adds what it removed to the running total" {
  make_cdk_dir cdk.outAAA 200 "$OLD_STAMP"
  local expected
  expected=$(du -sk "$TEST_TMP/cdk.outAAA" | awk '{print $1}')

  lib 'clean_cdk > /dev/null; echo "$TOTAL_KB"'
  [ "$output" = "$expected" ]
}

@test "clean_cdk leaves everything in place under a dry run" {
  make_cdk_dir cdk.outAAA 200 "$OLD_STAMP"

  lib 'DRY_RUN=1 clean_cdk'
  [[ "$output" == *"would remove all of them"* ]]
  [ -d "$TEST_TMP/cdk.outAAA" ]
}

@test "clean_cdk counts the bytes it would reclaim in the dry run total" {
  make_cdk_dir cdk.outAAA 200 "$OLD_STAMP"
  local expected
  expected=$(du -sk "$TEST_TMP/cdk.outAAA" | awk '{print $1}')

  lib 'DRY_RUN=1; clean_cdk > /dev/null; echo "$TOTAL_KB"'
  [ "$output" = "$expected" ]
}

@test "clean_cdk spares directories touched inside the staleness window" {
  make_cdk_dir cdk.outFRESH 200

  lib 'clean_cdk'
  [[ "$output" == *"Nothing stale"* ]]
  [ -d "$TEST_TMP/cdk.outFRESH" ]
}

@test "--include-recent takes the fresh directories too" {
  make_cdk_dir cdk.outFRESH 200

  lib 'INCLUDE_RECENT=1 clean_cdk'
  [[ "$output" == *"1 directories"* ]]
  [ ! -d "$TEST_TMP/cdk.outFRESH" ]
}

@test "clean_cdk ignores temp entries that are not cloud assemblies" {
  mkdir -p "$TEST_TMP/something-else"
  touch -t "$OLD_STAMP" "$TEST_TMP/something-else"

  lib 'clean_cdk'
  [ -d "$TEST_TMP/something-else" ]
}

@test "clean_cdk does not descend past the top level of the temp dir" {
  mkdir -p "$TEST_TMP/nested/cdk.outDEEP"
  touch -t "$OLD_STAMP" "$TEST_TMP/nested/cdk.outDEEP"

  lib 'clean_cdk'
  [ -d "$TEST_TMP/nested/cdk.outDEEP" ]
}

# ─── colima disk discovery ─────────────────────────────────────────────────

@test "colima_disk_files finds the single-disk vz layout" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  touch "$TEST_HOME/.colima/_lima/colima/disk"

  lib 'colima_disk_files'
  [[ "$output" == *"/.colima/_lima/colima/disk" ]]
}

@test "colima_disk_files finds both files in the qemu layout" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  touch "$TEST_HOME/.colima/_lima/colima/diffdisk" \
        "$TEST_HOME/.colima/_lima/colima/datadisk"

  lib 'colima_disk_files'
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"diffdisk"* ]]
  [[ "$output" == *"datadisk"* ]]
}

@test "colima_disk_files skips lima's underscore-prefixed state dirs" {
  mkdir -p "$TEST_HOME/.colima/_lima/_disks" "$TEST_HOME/.colima/_lima/colima"
  touch "$TEST_HOME/.colima/_lima/_disks/disk" \
        "$TEST_HOME/.colima/_lima/colima/disk"

  lib 'colima_disk_files'
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" != *"_disks"* ]]
}

@test "colima_disk_files prints nothing when colima has never run" {
  lib 'colima_disk_files'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── docker / colima ───────────────────────────────────────────────────────

@test "clean_docker skips cleanly when colima is not installed" {
  lib 'clean_docker'
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  [[ "$output" == *"colima is not installed"* ]]
}

@test "clean_docker skips cleanly when colima is installed but stopped" {
  stub colima 'exit 1'

  lib 'clean_docker'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Colima is not running"* ]]
}

@test "clean_docker trims even when the prune reclaims nothing" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  mkfile_kb "$TEST_HOME/.colima/_lima/colima/disk" 100
  stub colima 'case "$1" in status) exit 0 ;; ssh) echo "/: 0 B (0 bytes) trimmed" ;; esac'
  stub docker 'echo "Total reclaimed space: 0B"'

  lib 'clean_docker'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total reclaimed space: 0B"* ]]
  [[ "$output" == *"Trimming the guest filesystem"* ]]
  [[ "$output" == *"trimmed"* ]]
}

@test "clean_docker still trims when docker itself is missing" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  touch "$TEST_HOME/.colima/_lima/colima/disk"
  stub colima 'case "$1" in status) exit 0 ;; ssh) echo "trim ran" ;; esac'

  lib 'clean_docker'
  [[ "$output" == *"docker is not installed"* ]]
  [[ "$output" == *"trim ran"* ]]
}

@test "clean_docker reports the disk image size on both sides of the trim" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  mkfile_kb "$TEST_HOME/.colima/_lima/colima/disk" 2048
  stub colima 'case "$1" in status) exit 0 ;; ssh) exit 0 ;; esac'
  stub docker 'exit 0'

  lib 'clean_docker'
  [[ "$output" == *"Disk image before:"* ]]
  [[ "$output" == *"Disk image after:"* ]]
}

@test "clean_docker credits the total with what the trim actually gave back" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  mkfile_kb "$TEST_HOME/.colima/_lima/colima/disk" 4096
  # The trim is what shrinks the host file, so the stub shrinks it.
  stub colima "case \"\$1\" in
    status) exit 0 ;;
    ssh) : > '$TEST_HOME/.colima/_lima/colima/disk' ;;
  esac"
  stub docker 'exit 0'

  lib 'clean_docker > /dev/null; echo "$TOTAL_KB"'
  [ "$output" -gt 0 ]
}

@test "clean_docker prunes nothing and trims nothing in a dry run" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  touch "$TEST_HOME/.colima/_lima/colima/disk"
  stub colima 'case "$1" in status) exit 0 ;; ssh) echo "SHOULD NOT TRIM" ;; esac'
  # Only the prune must stay unrun; the dry run does read `docker system df`.
  stub docker 'case "$2" in prune) echo "SHOULD NOT PRUNE" ;; df) echo "Images: 0B" ;; esac'

  lib 'DRY_RUN=1 clean_docker'
  [[ "$output" != *"SHOULD NOT TRIM"* ]]
  [[ "$output" != *"SHOULD NOT PRUNE"* ]]
  [[ "$output" == *"Images: 0B"* ]]
  [[ "$output" == *"would prune Docker, then fstrim the guest"* ]]
}

@test "the dry run says the trim cannot be estimated and leaves it out" {
  mkdir -p "$TEST_HOME/.colima/_lima/colima"
  touch "$TEST_HOME/.colima/_lima/colima/disk"
  stub colima 'case "$1" in status) exit 0 ;; esac'

  lib 'DRY_RUN=1; clean_docker; echo "TOTAL=$TOTAL_KB"'
  [[ "$output" == *"cannot be estimated"* ]]
  [[ "$output" == *"TOTAL=0"* ]]
}

# ─── ndk ───────────────────────────────────────────────────────────────────

@test "clean_ndk skips when no NDK directory exists" {
  lib 'clean_ndk'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no NDK directory"* ]]
}

@test "clean_ndk keeps the newest version and flags the rest as superseded" {
  make_ndk 28.2.13676358
  make_ndk 30.0.14904198

  lib 'clean_ndk'
  [[ "$output" == *"newest is 30.0.14904198"* ]]
  [[ "$output" == *"28.2.13676358"*"superseded"* ]]
  [[ "$output" == *"30.0.14904198"*"newest, kept"* ]]
}

@test "clean_ndk orders versions numerically, not lexically" {
  make_ndk 9.0.111
  make_ndk 28.2.13676358

  lib 'clean_ndk'
  [[ "$output" == *"newest is 28.2.13676358"* ]]
}

@test "clean_ndk deletes nothing in a dry run" {
  make_ndk 28.2.13676358
  make_ndk 30.0.14904198

  lib 'DRY_RUN=1 clean_ndk'
  [[ "$output" == *"would offer this for deletion"* ]]
  [ -d "$TEST_HOME/sdk/ndk/28.2.13676358" ]
}

@test "a superseded NDK counts as offered, never as reclaimed" {
  make_ndk 28.2.13676358
  make_ndk 30.0.14904198

  lib 'DRY_RUN=1; clean_ndk > /dev/null; echo "TOTAL=$TOTAL_KB OFFERED=$OFFERED_KB"'
  [[ "$output" == *"TOTAL=0"* ]]
  [[ "$output" != *"OFFERED=0"* ]]
}

@test "clean_ndk keeps a superseded version when the prompt cannot be answered" {
  make_ndk 28.2.13676358
  make_ndk 30.0.14904198

  lib 'clean_ndk'
  [[ "$output" == *"no terminal to prompt on"* ]]
  [ -d "$TEST_HOME/sdk/ndk/28.2.13676358" ]
  [ -d "$TEST_HOME/sdk/ndk/30.0.14904198" ]
}

@test "clean_ndk removes a superseded version once the prompt is accepted" {
  make_ndk 28.2.13676358
  make_ndk 30.0.14904198

  lib 'confirm() { :; }; clean_ndk; echo "TOTAL=$TOTAL_KB"'
  [ ! -d "$TEST_HOME/sdk/ndk/28.2.13676358" ]
  [ -d "$TEST_HOME/sdk/ndk/30.0.14904198" ]
  [[ "$output" != *"TOTAL=0"* ]]
}

@test "clean_ndk never offers the only installed version" {
  make_ndk 30.0.14904198

  lib 'confirm() { :; }; clean_ndk'
  [[ "$output" == *"newest, kept"* ]]
  [[ "$output" != *"superseded"* ]]
  [ -d "$TEST_HOME/sdk/ndk/30.0.14904198" ]
}

# ─── derived data ──────────────────────────────────────────────────────────

@test "clean_derived_data skips when the directory is absent" {
  lib 'clean_derived_data'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no DerivedData directory"* ]]
}

@test "clean_derived_data empties the contents but keeps the directory" {
  mkdir -p "$TEST_HOME/Library/Developer/Xcode/DerivedData/Proj-abc/Build"
  mkfile_kb "$TEST_HOME/Library/Developer/Xcode/DerivedData/Proj-abc/Build/o" 128

  lib 'clean_derived_data'
  [[ "$output" == *"emptied"* ]]
  [ -d "$TEST_HOME/Library/Developer/Xcode/DerivedData" ]
  [ ! -e "$TEST_HOME/Library/Developer/Xcode/DerivedData/Proj-abc" ]
}

@test "clean_derived_data clears dotfile entries too" {
  mkdir -p "$TEST_HOME/Library/Developer/Xcode/DerivedData"
  touch "$TEST_HOME/Library/Developer/Xcode/DerivedData/.hidden"

  lib 'clean_derived_data'
  [ ! -e "$TEST_HOME/Library/Developer/Xcode/DerivedData/.hidden" ]
  [ -d "$TEST_HOME/Library/Developer/Xcode/DerivedData" ]
}

@test "clean_derived_data leaves an already-empty directory alone" {
  mkdir -p "$TEST_HOME/Library/Developer/Xcode/DerivedData"

  lib 'clean_derived_data'
  [[ "$output" == *"Already empty"* ]]
  [ -d "$TEST_HOME/Library/Developer/Xcode/DerivedData" ]
}

@test "clean_derived_data deletes nothing in a dry run" {
  mkdir -p "$TEST_HOME/Library/Developer/Xcode/DerivedData/Proj-abc"

  lib 'DRY_RUN=1 clean_derived_data'
  [[ "$output" == *"would empty it"* ]]
  [ -d "$TEST_HOME/Library/Developer/Xcode/DerivedData/Proj-abc" ]
}

# ─── simulators ────────────────────────────────────────────────────────────

DEVICES_NONE='    iPhone 17 (ABC) (Shutdown)'
DEVICES_ONE_UNAVAILABLE='    iPhone 9 (XYZ) (Shutdown) (unavailable, runtime profile not found)'

@test "clean_simulators skips when xcrun is unavailable" {
  lib 'clean_simulators'
  [ "$status" -eq 0 ]
  [[ "$output" == *"xcrun is not available"* ]]
}

@test "clean_simulators reports when there are no unavailable devices" {
  stub_xcrun "case \"\$2\" in list) echo '$DEVICES_NONE' ;; esac"

  lib 'clean_simulators'
  [[ "$output" == *"No unavailable devices"* ]]
}

@test "clean_simulators does not delete devices in a dry run" {
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_ONE_UNAVAILABLE' ;;
    delete) echo 'SHOULD NOT DELETE' ;;
  esac"

  lib 'DRY_RUN=1 clean_simulators'
  [[ "$output" == *"would delete 1 unavailable device"* ]]
  [[ "$output" != *"SHOULD NOT DELETE"* ]]
}

@test "clean_simulators deletes unavailable devices outside a dry run" {
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_ONE_UNAVAILABLE' ;;
    delete) echo 'deleted unavailable' ;;
  esac"

  lib 'clean_simulators'
  [[ "$output" == *"Deleting 1 unavailable device"* ]]
  [[ "$output" == *"deleted unavailable"* ]]
}

@test "clean_simulators skips the runtime listing when jq is missing" {
  stub_xcrun "case \"\$2\" in list) echo '$DEVICES_NONE' ;; esac"

  lib 'clean_simulators'
  [[ "$output" == *"jq is not installed"* ]]
}

@test "clean_simulators reports no runtimes when simctl returns an empty set" {
  provide jq
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_NONE' ;;
    runtime) echo '{}' ;;
  esac"

  lib 'clean_simulators'
  [[ "$output" == *"No runtimes installed"* ]]
}

@test "clean_simulators keeps the newest runtime and flags older ones" {
  provide jq
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_NONE' ;;
    runtime) cat <<'JSON'
{
  \"A\": { \"identifier\": \"A\", \"version\": \"18.0\", \"sizeBytes\": 8000000000, \"deletable\": true },
  \"B\": { \"identifier\": \"B\", \"version\": \"26.5\", \"sizeBytes\": 9000000000, \"deletable\": true }
}
JSON
    ;;
  esac"

  lib 'clean_simulators'
  [[ "$output" == *"newest is 26.5"* ]]
  [[ "$output" == *"18.0"*"superseded"* ]]
  [[ "$output" == *"26.5"*"newest, kept"* ]]
}

@test "clean_simulators orders runtime versions numerically, not lexically" {
  provide jq
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_NONE' ;;
    runtime) cat <<'JSON'
{
  \"A\": { \"identifier\": \"A\", \"version\": \"9.3\", \"sizeBytes\": 1000, \"deletable\": true },
  \"B\": { \"identifier\": \"B\", \"version\": \"18.0\", \"sizeBytes\": 1000, \"deletable\": true }
}
JSON
    ;;
  esac"

  lib 'clean_simulators'
  [[ "$output" == *"newest is 18.0"* ]]
}

@test "a superseded runtime counts as offered, never as reclaimed" {
  provide jq
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_NONE' ;;
    runtime) cat <<'JSON'
{
  \"A\": { \"identifier\": \"A\", \"version\": \"18.0\", \"sizeBytes\": 1048576, \"deletable\": true },
  \"B\": { \"identifier\": \"B\", \"version\": \"26.5\", \"sizeBytes\": 1048576, \"deletable\": true }
}
JSON
    ;;
  esac"

  lib 'DRY_RUN=1; clean_simulators > /dev/null; echo "TOTAL=$TOTAL_KB OFFERED=$OFFERED_KB"'
  [[ "$output" == *"TOTAL=0"* ]]
  [[ "$output" == *"OFFERED=1024"* ]]
}

@test "clean_simulators leaves a runtime simctl calls undeletable alone" {
  provide jq
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_NONE' ;;
    runtime) cat <<'JSON'
{
  \"A\": { \"identifier\": \"A\", \"version\": \"18.0\", \"sizeBytes\": 1000, \"deletable\": false },
  \"B\": { \"identifier\": \"B\", \"version\": \"26.5\", \"sizeBytes\": 1000, \"deletable\": true }
}
JSON
    ;;
  esac"

  lib 'confirm() { :; }; clean_simulators'
  [[ "$output" == *"not deletable"* ]]
}

@test "clean_simulators deletes a superseded runtime once the prompt is accepted" {
  provide jq
  stub_xcrun "case \"\$2\" in
    list) echo '$DEVICES_NONE' ;;
    runtime) if [ \"\$3\" = delete ]; then echo \"deleted \$4\"; else cat <<'JSON'
{
  \"A\": { \"identifier\": \"A\", \"version\": \"18.0\", \"sizeBytes\": 1048576, \"deletable\": true },
  \"B\": { \"identifier\": \"B\", \"version\": \"26.5\", \"sizeBytes\": 1048576, \"deletable\": true }
}
JSON
    fi ;;
  esac"

  lib 'confirm() { :; }; clean_simulators; echo "TOTAL=$TOTAL_KB"'
  [[ "$output" == *"deleted A"* ]]
  [[ "$output" == *"TOTAL=1024"* ]]
}

# ─── totals ────────────────────────────────────────────────────────────────

@test "record accumulates and offer is tracked separately" {
  lib 'record 100; record 50; offer 25; echo "$TOTAL_KB $OFFERED_KB"'
  [ "$output" = "150 25" ]
}

@test "confirm declines rather than blocking when there is no terminal" {
  lib 'confirm "Delete something?" && echo ACCEPTED || echo DECLINED'
  [[ "$output" == *"DECLINED"* ]]
  [[ "$output" != *"ACCEPTED"* ]]
}
