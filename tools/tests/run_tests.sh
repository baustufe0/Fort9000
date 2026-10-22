#!/bin/bash
# FORT 9000 for Forts - test run with real Lua 5.1 and a mocked game API.
# Usage: bash run_tests.sh <lua5.1-binary> <Forts-data-folder>
#   Build Lua 5.1 (if necessary):
#     git clone -q --depth 1 --branch 5.1.5 https://github.com/LuaDist/lua.git /tmp/lua51
#     cd /tmp/lua51/src && cp luaconf.h.orig luaconf.h && make -s posix   -> /tmp/lua51/src/lua
# The tests expect the shipped Abyss plans (fortplans/Abyss/fort-t1f1-Abyss-2.lua starts at -2120.45,-250).
LUA="${1:-lua5.1}"; DATA="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"; MOD="$(cd "$HERE/../.." && pwd)"
ROOT="$(mktemp -d)"; mkdir -p "$ROOT/mods"; ln -s "$MOD" "$ROOT/mods/fort-9000"; ln -s "$DATA/maps" "$ROOT/maps"; ln -s "$DATA/ai" "$ROOT/ai"
WP="$DATA/mods/weapon_pack"; [ -d "$WP" ] && ln -s "$WP" "$ROOT/mods/weapon_pack"
cp "$HERE"/t_*.lua "$ROOT/"; cd "$ROOT"; fail=0
check() { local name="$1" pat="$2"; shift 2; if "$@" 2>&1 | grep -qE "$pat"; then echo "OK    $name"; else echo "FAIL  $name"; "$@" 2>&1 | tail -5; fail=1; fi; }
check "Basic (targeting, aggression, end)"       "MOCK OK"                       "$LUA" t_basic.lua
check "Assist AI is switched off"                "ASSIST"                        "$LUA" t_assist.lua
for o in before after; do for e in fort-t1f1-Abyss-1.lua fort-t1f1-Abyss-ToGA1.lua; do
  check "Plan swap $o $e team 1"                 "first action = -2120.4, -250.0" "$LUA" t_plan_swap.lua $o $e 1
  check "Plan swap $o $e team 102"               "first action = 2120.4, -250.0"  "$LUA" t_plan_swap.lua $o $e 102
done; done
for o in before after; do for e in fort-t1f1-Template-1.lua fort-t1f1-Template-2.lua; do
  check "Plan swap Vanilla $o $e team 1"         "first action = -3029.4, 700.0"  "$LUA" t_vanilla.lua $o $e 1
  check "Plan swap Vanilla $o $e team 102"       "first action = 3029.4, 700.0"   "$LUA" t_vanilla.lua $o $e 102
done; done
# plans of the weapon_pack mod (other FortPos, same starting fort); only if the mod is installed
if [ -d "$WP" ]; then for o in before after; do for e in ToGAF1 ToGWM2; do
  f="mods/weapon_pack/ai/forts/vanilla/mid/fort-t1f1-Template-$e.lua"
  check "Plan swap Vanilla $o weapon_pack $e team 1"   "first action = -3029.4, 700.0" "$LUA" t_vanilla.lua $o $f 1
  check "Plan swap Vanilla $o weapon_pack $e team 102" "first action = 3029.4, 700.0"  "$LUA" t_vanilla.lua $o $f 102
done; done; fi
for o in before after; do
  check "Plan swap VanillaLong $o team 1"        "first action = -3929.4, -250.0" "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 1
  check "Plan swap VanillaLong $o team 102"      "first action = 3929.4, -250.0"  "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 102
done
check "Fire control"                             "fired:.11,12,14,15"            "$LUA" t_fire.lua
check "Safety valve waits when metal is short"   "Rebuild\[59\] =.true"          "$LUA" t_failsafe_poor.lua
check "Safety valve gives up when metal is there" "GAVE_UP action 59"            "$LUA" t_failsafe_rich.lua
check "Construction is skipped when stuck"       "SKIPPED action 386"            "$LUA" t_skip.lua
check "Tempo + reset for assist AI"              "after assist AI:.3.11.13.10"   "$LUA" t_tempo.lua
check "Build error log"                          "BUILD_ERROR link armour"       "$LUA" t_builderrors.lua
check "Recorder"                                 "RESULT w="                     "$LUA" t_recorder.lua 1
rm -rf "$ROOT"; [ $fail = 0 ] && echo "All tests passed." || { echo "There are failures."; exit 1; }
