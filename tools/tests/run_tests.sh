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
  check "Plan swap Vanilla $o $e team 1"         "first action = -3096.1, 502.5"  "$LUA" t_vanilla.lua $o $e 1
  check "Plan swap Vanilla $o $e team 102"       "first action = 3096.1, 502.5"   "$LUA" t_vanilla.lua $o $e 102
done; done
# plans of the weapon_pack mod (other FortPos, same starting fort); only if the mod is installed
if [ -d "$WP" ]; then for o in before after; do for e in ToGAF1 ToGWM2; do
  f="mods/weapon_pack/ai/forts/vanilla/mid/fort-t1f1-Template-$e.lua"
  check "Plan swap Vanilla $o weapon_pack $e team 1"   "first action = -3096.1, 502.5" "$LUA" t_vanilla.lua $o $f 1
  check "Plan swap Vanilla $o weapon_pack $e team 102" "first action = 3096.1, 502.5"  "$LUA" t_vanilla.lua $o $f 102
done; done; fi
for o in before after; do
  check "Plan swap VanillaLong $o team 1"        "first action = -3996.1, -447.5" "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 1
  check "Plan swap VanillaLong $o team 102"      "first action = 3996.1, -447.5"  "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 102
done
check "Modules load and are cut out after Load" "^after load: actions=246 expected=246 tagged=0$" "$LUA" t_modules.lua
check "Modules are moved by the transform"     "^module mirrored: 3000.0, 400.0$" "$LUA" t_modules.lua
check "Module waits for its Requires"          "MODULE_WAIT counterbattery trigger=mortar:1,mortar2:1 requires=50 now=9$" "$LUA" t_modules.lua
check "Module wait is logged once"             "^1$" bash -c "\"$LUA\" t_modules.lua | grep -c MODULE_WAIT"
check "Module is inserted at the build index"  "MODULE counterbattery trigger=mortar:1,mortar2:1 at=65 actions=3$" "$LUA" t_modules.lua
check "Module comes before the rest of the plan" "^inserted: bracing armour mortar next=60$" "$LUA" t_modules.lua
check "Index-keyed state moves with the insert" "^shifted: rebuild=true,true frustration=2 devices=4,2 since=45$" "$LUA" t_modules.lua
check "Each module fires once"                 "^anti-air at 3: machinegun, then sniper, total=251$" "$LUA" t_modules.lua
check "Module waits for its After module"      "^goal before anti-air: nil$" "$LUA" t_modules.lua
check "Module fires by time"                   "MODULE goal trigger=time:100 at=69 actions=1$" "$LUA" t_modules.lua
check "Plan file with modules loads in Lua"     "^231 sniper 1 5 sniper$" "$LUA" -e 'dofile("mods/fort-9000/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua") local m = FortModules[1] print(table.concat({ #Fort, m.Name, #m.Actions, m.Requires, m.Actions[1].DeviceSaveName }, " "))'
check "Modular plan loads with time triggers"  "^231 10 sniper 45 heavyartillery artillery$" "$LUA" -e 'dofile("mods/fort-9000/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua") local m = FortModules print(table.concat({ #Fort, #m, m[1].Name, m[1].Trigger.Time, m[4].Name, m[4].Trigger.After }, " "))'
check "Fire control"                           "fired:.11,12,14,15"            "$LUA" t_fire.lua
check "Fire diagnostics: fired"                  "FIRETRY cannon20mm 21 fired=1 code=FIREFAIL_RELOADING m=120 e=1500" "$LUA" t_firewait.lua
check "Fire diagnostics: short of energy"        "FIREWAIT cannon20mm 22 avail=1 ready=0 code=FIREFAIL_NOENERGY queue=0" "$LUA" t_firewait.lua
check "Fire diagnostics: door action pending"    "FIREWAIT sniper 23 avail=1 ready=1 code=- queue=1" "$LUA" t_firewait.lua
check "Fire diagnostics: not available"          "FIREWAIT sniper 24 avail=0" "$LUA" t_firewait.lua
check "Fire diagnostics: declined, ray blocked"  "FIRETRY sniper 25 fired=0 code=- ray=RAY_HIT_STRUCTURE:102:backbracing@3128,70 m=120" "$LUA" t_firewait.lua
check "Fire diagnostics: ray flags as built-in"  "ray flags 7$" "$LUA" t_firewait.lua
check "Fire diagnostics: rate limit"             "^2$" bash -c "\"$LUA\" t_firewait.lua | grep -c 'FIREWAIT sniper 24'"
check "Fire diagnostics: new reason at once"     "FIRETRY cannon20mm 22 fired=0 code=- ray=" "$LUA" t_firewait.lua
check "Machine guns: no offensive fire"          "fired:.11,13,14,15,11,13$"      "$LUA" t_fire_mg.lua
check "Miniguns still fire at the fort"         "minigun offensive.true$"       "$LUA" t_fire_mg.lua
check "Machine guns stay anti-air"               "MG offensive.0.MG during rebuild.0.MG anti-air.0.7" "$LUA" t_fire_mg.lua
check "Smoke fires first, rockets held"          "t1:.22,24$"                    "$LUA" t_smoke.lua
check "Rockets held by the built-in AI too"      "base rocket held:.true$"       "$LUA" t_smoke.lua
check "Rockets fire under smoke"                 "t3:.21,23$"                    "$LUA" t_smoke.lua
check "Rockets held again after the window"      "t12:.24$"                      "$LUA" t_smoke.lua
check "Rockets fire after MaxHold without smoke" "released after hold:.true$"    "$LUA" t_smoke.lua
check "Rockets fire without a smoke launcher"    "no smoke launcher:.21,23,24$"  "$LUA" t_smoke.lua
check "Aggression keeps machine guns at 0"       "after think: MG offensive.0$"  "$LUA" t_fire_mg.lua
check "Safety valve waits when metal is short"   "Rebuild\[59\] =.true"          "$LUA" t_failsafe_poor.lua
check "Safety valve gives up when metal is there" "GAVE_UP action 59"            "$LUA" t_failsafe_rich.lua
check "Rebuild cap stops a device that keeps dying" "REBUILD_CAP action 10 machinegun losses=4 window=180s$" "$LUA" t_rebuildcap.lua
check "Rebuild cap counts losses in a row only"  "^queued: mg=3 turbine=6 mg-slow=4 devices-left=0$" "$LUA" t_rebuildcap.lua
check "Construction is skipped when stuck"      "SKIPPED action 386"            "$LUA" t_skip.lua
check "Tempo + reset for assist AI"              "after assist AI:.3.11.13.10"   "$LUA" t_tempo.lua
check "Build error log"                          "BUILD_ERROR link armour"       "$LUA" t_builderrors.lua
check "Sale tries the strut the other way round" "sold 0 tried 55-58,58-55$"     "$LUA" t_destroy.lua
check "Sale finds the device by its platform"   "sold by id 0 tried 73-76,76-73 id 9$" "$LUA" t_destroy.lua
check "Sale finds the device by its position"   "sold by position 0 id 11$"     "$LUA" t_destroy.lua
check "Failed sale lists the devices"            "BUILD_ERROR destroy scan=3 match=none devices=store@40-41:3000,600,battery@76-73:2900,300,machinegun@90-91:2885,206 1-2 DD_NOTFOUND action=3$" "$LUA" t_destroy.lua
check "Shape snapshot on CS_UNSTABLE"            "SHAPE t=0 why=unstable:cannon mirrored=0 part=1/2 1:0,0 2:0,-4$" "$LUA" t_shape.lua
check "Shape snapshot mirrored back"             "why=minute mirrored=1 part=2/2 10000:-30,12$" "$LUA" t_shape.lua
check "Shape snapshots once per place, capped"   "^shapes=2$"                    "$LUA" t_shape.lua
check "Real stress on CS_UNSTABLE"               "STRESS cannon 501-503 links=4 at=P10000-N504:backbracing:-0.310 P1-P10000:bracing:0.120 top=N504-N505:bracing:0.950 P10000-N504:backbracing:-0.310$" "$LUA" t_stress.lua
check "Stress scan once per place, capped"       "^stress=1 enumerated=4$"       "$LUA" t_stress.lua
check "Probe tries each device, LinkT and strut"  "PROBE END tried=8 placed=6 unstable=2 other=0$" "$LUA" t_probe.lua
check "Probe logs the attempt with stress and sag"  "PROBE TRY 1 sniper 503-501 t=0.20 r=OK s=0.120 sn=0.310 len=100.0 ang=0.0 sag=5,0 v=0,0 dv=0 dn=2 near=battery,store$" "$LUA" t_probe.lua
check "Probe logs devices on the struts"        "PROBE LINK part=2/2 505-501:armour:0.020:battery@0.50,store@0.30$" "$LUA" t_probe.lua
check "Probe START has readable LinkT"          "linkt=0.20,0.80 struts=2" "$LUA" t_probe.lua
check "Probe skips steep struts"                "struts=2 steep=1 attempts=8"   "$LUA" t_probe.lua
check "Probe waits when short of resources"      "PROBE WAIT 1 sniper resources$" "$LUA" t_probe.lua
check "Probe bypasses the build diagnostics"     "^0$"                           sh -c "\"$LUA\" t_probe.lua | grep -c 'BUILD_ERROR\|UNSTABLE cannon'"
check "Probe measures the load with Hold"        "PROBE LOAD 1 cannon 503-501 s=0.300 sn=0.310 top=0.400:504-505 d=0,4,0,0$" "$LUA" t_probe.lua
check "Probe removes devices, AI runs again"     "removed=901,902,903,904,905,906,907 disabled after=false$" "$LUA" t_probe.lua
check "Recorder"                                 "RESULT w="                     "$LUA" t_recorder.lua 1
check "Recorder starts over on a restart"        "^-- restart$" "$LUA" t_restart.lua
check "Recorder writes START restart=1"          "^\[CREC\] f=2 START v=3 restart=1$" "$LUA" t_restart.lua
check "Recorder snapshots after a restart"       "^\[CREC\] f=127 SNAP s=1" "$LUA" t_restart.lua
check "Recorder logs build events"               "LINK s=1 t=1 a=7 b=500 m=bracing pa=-3093.19,205.21 pb=-3100.00,105.00$" "$LUA" t_buildrec.lua 1
check "Recorder logs upgrades"                   "DEV s=2 t=102 i=903 d=minigun a=9 b=8 lt=0.60 .* u=900$" "$LUA" t_buildrec.lua 2
# recorded build -> plan (tools/fortgen/rec_fort.py); needs Python 3 and the game's data/ai and data/maps
PY=""; for p in "py -3" python3 python; do $p --version >/dev/null 2>&1 && { PY="$p"; break; }; done
if [ -n "$PY" ]; then
  for s in 1 2; do "$LUA" t_buildrec.lua $s > rec$s.txt; $PY "$MOD/tools/fortgen/rec_fort.py" --data "$DATA" --log rec$s.txt --out rec$s.lua > conv$s.txt 2>&1; done
  check "Recorded build becomes a plan"          "side 1, 9 actions \(4 built and removed again"  cat conv1.txt
  check "Recorded build has no plan errors"      "^0$"                           sh -c "grep -c 'ERROR' conv1.txt conv2.txt | grep -v ':0$' | wc -l"
  check "Recorded side 2 is mirrored to side 1"  "^same$"                        sh -c "cmp -s rec1.lua rec2.lua && echo same"
  check "Recorded plan loads in Lua"             "^actions 9 first 56 10000$"    "$LUA" -e 'dofile("rec1.lua") print("actions " .. #Fort .. " first " .. Fort[1].OriginalNodeAId .. " " .. Fort[1].OriginalNodeBId)'
  check "Tools read plan modules apart from the plan" "^231 sniper sniper,sniper2,laser,firebeam,cannon,cannon20mm 1 5$" $PY -c "import sys; sys.path.insert(0, sys.argv[1]); from fortplan import parse_plan, parse_modules; m = parse_modules(sys.argv[2])[0]; print(len(parse_plan(sys.argv[2])[1]), m['name'], ','.join(m['types']), m['count'], m['requires'])" "$MOD/tools/fortgen" "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua"
  check "Plan modules pass the building rules"   "module sniper \(1 actions, requires 5\): 0 errors" $PY "$MOD/tools/fortgen/rules.py" "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua"
  "$LUA" t_probe.lua | sed '/PROBE END/q' > probe.txt
  check "Probe parser finds the CS_UNSTABLE split" "unstable if s > 0.260 \(100 %\)" $PY "$MOD/tools/fortgen/probe.py" probe.txt
  check "Probe parser splits by devices nearby"  "devices at its nodes +2 / 2$" $PY "$MOD/tools/fortgen/probe.py" probe.txt
  check "Probe parser lists the refused strut"   "\(100,-100\)-\(0,-100\)  t=0.20,0.80  s=0.400" $PY "$MOD/tools/fortgen/probe.py" probe.txt
else
  echo "SKIP  recorded build -> plan, probe parser (no Python 3)"
fi
rm -rf "$ROOT"; [ $fail = 0 ] && echo "All tests passed." || { echo "There are failures."; exit 1; }
