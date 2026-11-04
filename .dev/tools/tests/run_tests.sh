#!/bin/bash
# FORT 9000 for Forts - test run with real Lua 5.1 and a mocked game API.
# Usage: bash run_tests.sh <lua5.1-binary> <Forts-data-folder>
#   Build Lua 5.1 (if necessary):
#     git clone -q --depth 1 --branch 5.1.5 https://github.com/LuaDist/lua.git /tmp/lua51
#     cd /tmp/lua51/src && cp luaconf.h.orig luaconf.h && make -s posix   -> /tmp/lua51/src/lua
# The tests expect the shipped Abyss plans (fortplans/Abyss/fort-t1f1-Abyss-2.lua starts at -2000.99,304.82, the workshop strut).
LUA="${1:-lua5.1}"; DATA="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"; MOD="$(cd "$HERE/../../.." && pwd)"
ROOT="$(mktemp -d)"; mkdir -p "$ROOT/mods"; ln -s "$MOD" "$ROOT/mods/fort9000dev"; ln -s "$DATA/maps" "$ROOT/maps"; ln -s "$DATA/ai" "$ROOT/ai"
WP="$DATA/mods/weapon_pack"; [ -d "$WP" ] && ln -s "$WP" "$ROOT/mods/weapon_pack"
cp "$HERE"/t_*.lua "$ROOT/"; cd "$ROOT"; fail=0
check() { local name="$1" pat="$2"; shift 2; if "$@" 2>&1 | grep -qE "$pat"; then echo "OK    $name"; else echo "FAIL  $name"; "$@" 2>&1 | tail -5; fail=1; fi; }
check "Basic (targeting, aggression, end)"       "MOCK OK"                       "$LUA" t_basic.lua
check "Assist AI is switched off"                "ASSIST"                        "$LUA" t_assist.lua
for o in before after; do for e in fort-t1f1-Abyss-1.lua fort-t1f1-Abyss-ToGA1.lua; do
  check "Plan swap $o $e team 1"                 "first action = -2095.5, -94.4"  "$LUA" t_plan_swap.lua $o $e 1
  check "Plan swap $o $e team 102"               "first action = 2095.5, -94.4"   "$LUA" t_plan_swap.lua $o $e 102
done; done
for o in before after; do for e in fort-t1f1-Template-1.lua fort-t1f1-Template-2.lua; do
  check "Plan swap Vanilla $o $e team 1"         "first action = -2895.4, 505.4"  "$LUA" t_vanilla.lua $o $e 1
  check "Plan swap Vanilla $o $e team 102"       "first action = 2895.4, 505.4"   "$LUA" t_vanilla.lua $o $e 102
done; done
# plans of the weapon_pack mod (other FortPos, same starting fort); only if the mod is installed
if [ -d "$WP" ]; then for o in before after; do for e in ToGAF1 ToGWM2; do
  f="mods/weapon_pack/ai/forts/vanilla/mid/fort-t1f1-Template-$e.lua"
  check "Plan swap Vanilla $o weapon_pack $e team 1"   "first action = -2895.4, 505.4" "$LUA" t_vanilla.lua $o $f 1
  check "Plan swap Vanilla $o weapon_pack $e team 102" "first action = 2895.4, 505.4"  "$LUA" t_vanilla.lua $o $f 102
done; done; fi
for o in before after; do
  check "Plan swap VanillaLong $o team 1"        "first action = -3795.[45], -444.6" "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 1
  check "Plan swap VanillaLong $o team 102"      "first action = 3795.[45], -444.6"  "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 102
done
# 2v6 Vanilla: the same game plans, told apart by where the fort stands (FortPositions); the hub comes first
MID=ai/forts/vanilla/mid/fort-t1f1-Template-1.lua; LONG=ai/forts/vanilla/long/fort-t2f1-Template-1.lua
for o in before after; do
  check "2v6 $o: mid plan at (4700,-900) team 102" "PLAN map=Vanilla2v6 file=fort-t1f1-Vanilla2v6-1.lua .* fort=4700,-900" "$LUA" t_vanilla2v6.lua $o $MID 102 4700 -900
  check "2v6 $o: mid plan, first action in place"  "first action rel = 4.[56], -194.6"  "$LUA" t_vanilla2v6.lua $o $MID 102 7400 -4000
  check "2v6 $o: mid plan at (-3800,-300) team 1"  "PLAN map=Vanilla2v6 file=.* fort=-3800,-300" "$LUA" t_vanilla2v6.lua $o $MID 1 -3800 -300
  check "2v6 $o: long plan at (3800,100) team 102" "PLAN map=Vanilla2v6Long file=fort-t2f3-Vanilla2v6Long-1.lua" "$LUA" t_vanilla2v6.lua $o $LONG 102 3800 100
  check "2v6 $o: long plan, first action in place" "first action rel = 4.[56], -194.6"  "$LUA" t_vanilla2v6.lua $o $LONG 102 3800 100
  check "2v6 $o: Vanilla's own fort stays Vanilla" "PLAN map=Vanilla file=.* fort=2900,700" "$LUA" t_vanilla2v6.lua $o $MID 102 2900 700
  check "2v6 $o: Vanilla 2v2 upper fort stays VanillaLong" "PLAN map=VanillaLong file=" "$LUA" t_vanilla2v6.lua $o $LONG 102 3800 -250
done
# Stalactites: the shared hanging plans (any of the three), told apart by where the fort stands; the first action is the
# starting fort's front post node (-2502, -1199), 151 below the fort's position
HANG=ai/forts/hanging/long/fort-t1f1-TemplateHang
for o in before after; do
  check "Stalactites $o: 1v1 fort team 1"          "PLAN map=Stalactites file=fort-t1f1-Stalactites-1.lua .* fort=-2500,-1350" "$LUA" t_vanilla2v6.lua $o $HANG-1.lua 1 -2500 -1350
  check "Stalactites $o: first action in place"    "first action rel = -1.9, 151.4" "$LUA" t_vanilla2v6.lua $o $HANG-2.lua 102 2500 -1350
  check "Stalactites $o: 2v2 fort 2 team 102"      "PLAN map=Stalactites file=.* fort=4100,-150" "$LUA" t_vanilla2v6.lua $o $HANG-3.lua 102 4100 -150
  check "Stalactites $o: other hanging forts keep the game's plan" "PLAN file=original reason=unknown-game-plan" "$LUA" t_vanilla2v6.lua $o $HANG-1.lua 1 -3000 500
done
# weapon_pack's hanging plans (the first Stalactites match got ToGHngA1); only if the mod is installed
if [ -d "$WP" ]; then for o in before after; do for e in ToGA1 ToGHngA1 ToGW1; do
  check "Stalactites $o: weapon_pack $e team 102"  "PLAN map=Stalactites .* fort=2500,-1350" "$LUA" t_vanilla2v6.lua $o mods/weapon_pack/ai/forts/hanging/long/fort-t1f1-TemplateHang-$e.lua 102 2500 -1350
  check "Stalactites $o: weapon_pack $e in place"   "first action rel = -1.9, 151.4" "$LUA" t_vanilla2v6.lua $o mods/weapon_pack/ai/forts/hanging/long/fort-t1f1-TemplateHang-$e.lua 1 -4100 -150
done; done; fi
check "Modules load and are cut out after Load" "^after load: actions=232 expected=232 tagged=0$" "$LUA" t_modules.lua
check "Modules are moved by the transform"     "^module mirrored: 3000.0, 400.0$" "$LUA" t_modules.lua
check "Module waits for its Requires"          "MODULE_WAIT counterbattery trigger=mortar:1,mortar2:1 requires=50 now=9$" "$LUA" t_modules.lua
check "Module wait is logged once"             "^1$" bash -c "\"$LUA\" t_modules.lua | grep -c MODULE_WAIT"
check "Module is inserted at the build index"  "MODULE counterbattery trigger=mortar:1,mortar2:1 at=65 actions=3$" "$LUA" t_modules.lua
check "Module comes before the rest of the plan" "^inserted: bracing armour mortar next=60$" "$LUA" t_modules.lua
check "Index-keyed state moves with the insert" "^shifted: rebuild=true,true frustration=2 devices=4,2 since=45$" "$LUA" t_modules.lua
check "Each module fires once"                 "^anti-air at 3: machinegun, then sniper, total=237$" "$LUA" t_modules.lua
check "Module waits for its After module"      "^goal before anti-air: nil$" "$LUA" t_modules.lua
check "Module fires by time"                   "MODULE goal trigger=time:100 at=69 actions=1$" "$LUA" t_modules.lua
check "Plan file with modules loads in Lua"     "^217 sniper 1 18 sniper$" "$LUA" -e 'dofile("mods/fort9000dev/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua") local m = FortModules[1] print(table.concat({ #Fort, m.Name, #m.Actions, m.Requires, m.Actions[1].DeviceSaveName }, " "))'
check "Modular plan loads with time triggers"  "^217 10 sniper 45 heavyartillery artillery$" "$LUA" -e 'dofile("mods/fort9000dev/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua") local m = FortModules print(table.concat({ #Fort, #m, m[1].Name, m[1].Trigger.Time, m[4].Name, m[4].Trigger.After }, " "))'
check "Surplus: not while the plan is built"    "^building: nil,nil$" "$LUA" t_surplus.lua
check "Surplus: not while a rebuild is queued"  "^rebuilding: nil,nil$" "$LUA" t_surplus.lua
check "Surplus: not below the thresholds"       "^short of energy: nil,nil$" "$LUA" t_surplus.lua
check "Surplus: not before Seconds"             "^after 15 s: nil,nil$" "$LUA" t_surplus.lua
check "Surplus module fires"                    "MODULE firebeam trigger=surplus:m=1200,e=9000 at=233 actions=1$" "$LUA" t_surplus.lua
check "Surplus: After module waits for the build" "^firebeam building: true,nil$" "$LUA" t_surplus.lua
check "Surplus: a dip restarts the clock"       "^after the dip: true,nil$" "$LUA" t_surplus.lua
check "Surplus: second module fires"            "^laser: true,true laser$" "$LUA" t_surplus.lua
check "Repeated inserts: rebuilds stay on their actions"  "^rebuild: 3 of 3, 0 wrong$" "$LUA" t_insert_repeat.lua
check "Repeated inserts: frustration stays on its actions" "^frustration: 2 of 2, 0 wrong$" "$LUA" t_insert_repeat.lua
check "Repeated inserts: rebuild clocks stay on their actions" "^since: 3 of 3, 0 wrong$" "$LUA" t_insert_repeat.lua
check "Repeated inserts: devices stay on their actions" "^devices: 3, 0 wrong$" "$LUA" t_insert_repeat.lua
check "Repeated inserts: later modules go in front"  "^order: m3 m3 m5 m5 m5 m5 m5 m4 m4 m4 m4 m3 m2 m2 m1 k60 k61$" "$LUA" t_insert_repeat.lua
check "Engine probe: material over an existing strut" "EPROBE MATERIAL 11-12 bracing->armour result=0:CS_SUCCESS now=armour linked=true m=500->500$" "$LUA" t_engineprobe.lua
check "Engine probe: reclaim falls back to the next device" "EPROBE RECLAIM machinegun id=2 result=0 success=true cost=m=50,e=300 rate=m=2.5,e=30 m=500$" "$LUA" t_engineprobe.lua
check "Engine probe: reclaim metal by frame"   "EPROBE RECLAIM series m0=500 end=525 deleted@2 deltas=0,0,25,0,0$" "$LUA" t_engineprobe.lua
check "Engine probe: own strut hits by type"   "EPROBE LINKHIT t=20 hits=cannon:2/200,mortar:1/40 broken=1:1$" "$LUA" t_engineprobe.lua
check "Engine probe: first hit logged once"    "^1$" bash -c "\"$LUA\" t_engineprobe.lua | grep -c 'LINKHIT first'"
check "Vanilla-5 loads with its surplus module" "^216 1 firebeam 500 3500 20$" "$LUA" -e 'dofile("mods/fort9000dev/fortplans/Vanilla/fort-t1f1-Vanilla-5.lua") local m = FortModules print(table.concat({ #Fort, #m, m[1].Name, m[1].Trigger.Surplus.Metal, m[1].Trigger.Surplus.Energy, m[1].Trigger.Surplus.Seconds }, " "))'
check "Bastion loads with sockets and zones"   "^246 7 B1 sniper -3100 5 Z0 M1\+M2 mortar$" "$LUA" -e 'dofile("mods/fort9000dev/fortplans/Vanilla/fort-t1f1-Vanilla-8.lua") local s, z, m = FortSockets, FortZones, FortModules[1] print(table.concat({ #Fort, #s, s[3].Name, s[3].Default, s[3].Cell.x, #z, z[1].Name, m.Socket, m.Loadout }, " "))'
check "Sockets: listed with their loadouts"     "SOCKETS A0:machinegun A1:machinegun B1:sniper/cannon20mm/laser/firebeam/machinegun B2:.* M1:mortar/machinegun M2:mortar$" "$LUA" t_sockets.lua
check "Sockets: one loss keeps the weapon"      "SOCKET B1 lost sniper losses=1$" "$LUA" t_sockets.lua
check "Sockets: no machine gun for a sniper"   "^after two losses: sniper rebuild=true$" "$LUA" t_sockets.lua
check "Sockets: swap to a loadout whose tech stands" "^with munitions: cannon20mm$" "$LUA" t_sockets.lua
check "Sockets: tech under construction does not count" "^factory building: sniper$" "$LUA" t_sockets.lua
check "Sockets: the posture's preferred loadout" "^factory built: laser$" "$LUA" t_sockets.lua
check "Sockets: machine gun under AntiAir"     "^anti-air: machinegun$" "$LUA" t_sockets.lua
check "Sockets: an old loss is forgotten"       "^late loss: machinegun losses=1$" "$LUA" t_sockets.lua
check "Modules: Repeat and Cooldown"            "^again inserted 3 times$" "$LUA" t_sockets.lua
check "Modules: a repeat is logged"             "MODULE again trigger=time:5 at=[0-9]+ actions=1 repeat=2$" "$LUA" t_sockets.lua
check "Upgrade: nothing without the tech"        "^no tech: sniper sold=0$" "$LUA" t_upgrade.lua
check "Upgrade: B2 first, sold and rebuilt as a laser" "^factory: B2=laser rebuild=true B1=sniper sold=1$" "$LUA" t_upgrade.lua
check "Upgrade: the sale is logged"              "SOCKET B2 sell sniper->laser action=[0-9]+ result=-8 " "$LUA" t_upgrade.lua
check "Upgrade: not while poor"                  "^poor: B1=sniper$" "$LUA" t_upgrade.lua
check "Upgrade: B1 later, another weapon"        "^later: B1=firebeam B2=laser sold=2$" "$LUA" t_upgrade.lua
check "Upgrade: a mix with the munitions plant"  "^mix: B1=cannon20mm$" "$LUA" t_upgrade.lua
check "Upgrade: nothing dearer than the storage"   "^storage 900: B2=cannon20mm B1=sniper$" "$LUA" t_upgrade.lua
check "Upgrade: a firebeam is replaced later"     "^firebeam replaced: B1=cannon20mm$" "$LUA" t_upgrade.lua
check "Refill: not at once (a rebuild may be due)" "^short empty: rebuild=nil$" "$LUA" t_upgrade.lua
check "Refill: an empty socket gets a new try"   "^refill: rebuild=true B2=cannon20mm$" "$LUA" t_upgrade.lua
check "Sniper sight: no fire through structure"  "^blocked by structure: true true ap hitpoints=600 chance=1$" "$LUA" t_sniper.lua
check "Sniper sight: a free line"                "^open: sniper y200 ap y200$" "$LUA" t_sniper.lua
check "Sniper sight: AP through one door only"   "^one door: sniper hold ap y200$" "$LUA" t_sniper.lua
check "Sniper sight: not through two doors"      "^two doors: sniper hold ap hold$" "$LUA" t_sniper.lua
check "Sniper sight: a door above the centre"    "^door over the centre: sniper y185$" "$LUA" t_sniper.lua
check "Front strip: listed in the plan"           "^list: 3$" "$LUA" t_strip.lua
check "Front strip: not while metal is there"     "^metal there: armour armour armour$" "$LUA" t_strip.lua
check "Front strip: as many as the metal needs"   "^one step: bracing bracing armour m=210$" "$LUA" t_strip.lua
check "Front strip: all three while short"        "^short: bracing bracing bracing$" "$LUA" t_strip.lua
check "Front strip: back only with plenty"        "^not yet back: bracing bracing bracing$" "$LUA" t_strip.lua
check "Front strip: armour again, a door stays"   "^plenty: armour door armour$" "$LUA" t_strip.lua
check "Front strip: once per strut"               "^once per strut: armour door armour$" "$LUA" t_strip.lua
check "Front strip: logged with the metal"        "STRIP -2844.7,309.73--2892.17,411.07 armour->bracing result=-15 m=50->130 t=15$" "$LUA" t_strip.lua
check "Sniper sight: another device is no target" "^sandbags in the way: sniper hold$" "$LUA" t_sniper.lua
check "Sniper sight: counted"                    "^counts: seen=3 pierced=1 hold=4$" "$LUA" t_sniper.lua
check "Zones: nodes mapped by planned position" "^zone of 901: Z0, of 903: Z1, of 950: nil$" "$LUA" t_zones.lua
check "Zones: enemy hits count, own do not"     "^totals: Z0=300 Z1=70$" "$LUA" t_zones.lua
check "Zones: pressure decays and is logged"    "ZONES t=5 Z0:270/300 Z1:63/70 \(pressure/total\)$" "$LUA" t_zones.lua
check "Zones: damage fires the zone module"     "MODULE Z0face trigger=zone:Z0=300 at=[0-9]+ actions=6$" "$LUA" t_zones.lua
check "Zones: lost struts count, deletes do not" "^after breaks: Z0=800$" "$LUA" t_zones.lua
check "Zones: a second module at its own damage" "MODULE Z0prow trigger=zone:Z0=800 at=[0-9]+ actions=5$" "$LUA" t_zones.lua
check "Zones: again after the cooldown"         "MODULE Z0face trigger=zone:Z0=1000 at=[0-9]+ actions=6 repeat=1$" "$LUA" t_zones.lua
check "Posture: starts with Pressure"           "POSTURE -->Pressure t=5 scores=Pressure:3$" "$LUA" t_posture.lua
check "Posture: holds 30 s before a switch"     "^at 10 s: Pressure$" "$LUA" t_posture.lua
check "Posture: enemy mortars -> AntiArtillery" "POSTURE Pressure->AntiArtillery t=35 " "$LUA" t_posture.lua
check "Posture: boosts its targets"             "^heavy targets: cannon,mortar,mine$" "$LUA" t_posture.lua
check "Posture: zone pressure -> Siege"         "POSTURE AntiArtillery->Siege t=65 " "$LUA" t_posture.lua
check "Posture: triggers its module"            "MODULE munitions trigger=posture:Siege at=[0-9]+ actions=3$" "$LUA" t_posture.lua
check "Posture: preferred loadout on a swap"    "SOCKET B1 sniper->laser action=[0-9]+ swaps=1 posture=Siege$" "$LUA" t_posture.lua
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
check "Retire: idle sniper sold, not rebuilt"   "sold: 31@50 devices31=nil devices33=9$" "$LUA" t_retire.lua
check "Retire: read from the plan file"          "RETIRE-CONFIG sniper2:90,sniper:90" "$LUA" t_plan_swap.lua after fort-t1f1-Abyss-1.lua 1
check "Retire: log line"                         "RETIRE sniper 31 idle=20 shots=0 result=0" "$LUA" t_retire.lua
check "Retire: shots of the built-in AI count"  "sold: 31@50 " "$LUA" t_retire.lua
check "Miniguns still fire at the fort"         "minigun offensive.true$"       "$LUA" t_fire_mg.lua
check "Machine guns stay anti-air"               "MG offensive.0.MG during rebuild.0.MG anti-air.0.7" "$LUA" t_fire_mg.lua
check "Smoke fires first, rockets held"          "t1:.22,24$"                    "$LUA" t_smoke.lua
check "Rockets held by the built-in AI too"      "base rocket held:.true$"       "$LUA" t_smoke.lua
check "Rockets fire under smoke"                 "t3:.21,23,24$"                 "$LUA" t_smoke.lua
check "Smoke waits without energy for rockets"   "^400 energy:.$"                "$LUA" t_smokecost.lua
check "Smoke wait is logged"                     "SMOKE_WAIT energy rockets=1$"  "$LUA" t_smokecost.lua
check "Smoke fires when rockets can follow"      "^600 energy:.22$"              "$LUA" t_smokecost.lua
check "No smoke while the rockets reload"        "^rocket reloading:.false$"     "$LUA" t_smokecost.lua
check "Flak fires at the fort without threats"   "^no threats: flak offensive=0.4" "$LUA" t_flakhold.lua
check "Flak holds for anti-air against mortars"  "^mortars: flak offensive=0 rebuild=0 anti-air=0.9" "$LUA" t_flakhold.lua
check "Flak hold is logged"                      "FLAK_HOLD on threats=mortar:2$" "$LUA" t_flakhold.lua
check "Flak fires again when threats are gone"   "^mortars gone: flak offensive=0.6 rebuild=0.5" "$LUA" t_flakhold.lua
check "Machine guns stay off the fort"           "machinegun offensive=0$"       "$LUA" t_flakhold.lua
check "Rockets held again after the window"      "t12:.24$"                      "$LUA" t_smoke.lua
check "Rockets fire after MaxHold without smoke" "released after hold:.true$"    "$LUA" t_smoke.lua
check "Rockets fire without a smoke launcher"    "no smoke launcher:.21,23,24$"  "$LUA" t_smoke.lua
check "Smoke cover shots are logged"            "SMOKETRY smokebomb 22 fired=1"  "$LUA" t_smoke.lua
check "Held rockets are logged"                 "FIREHOLD rocket 21 fired=0"     "$LUA" t_smoke.lua
check "Volley: firebeam waits for its partner"   "^partner reloading:.33$"       "$LUA" t_volley.lua
check "Volley: built-in AI's shot held too"      "^base firebeam held:.true$"    "$LUA" t_volley.lua
check "Volley: both fire as one group"           "^both ready:.31:31\+32,33$"    "$LUA" t_volley.lua
check "Volley is logged"                         "VOLLEY 2 leader=31 ids=31,32 fired=2$" "$LUA" t_volley.lua
check "Volley waits for energy for all"          "VOLLEY_HOLD ready=2/2 energy=0$" "$LUA" t_volley.lua
check "Volley: alone after MaxHold"              "^alone after hold:.(2[01])$"   "$LUA" t_volley.lua
check "Volley: one built firebeam fires alone"   "^partner under construction:.31$" "$LUA" t_volley.lua
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
check "Recorder 2v2 sums the teams of a side"     "SNAP s=2 t=102,202 m=1300 e=6000 dev=mine:1,reactor:2 shots= tm=102:600:3000,202:700:3000$" "$LUA" t_recorder2v2.lua
check "Recorder 1v1 snapshot unchanged"           "SNAP s=1 t=1 m=600 e=3000 dev=reactor:1 shots=$" "$LUA" t_recorder2v2.lua
check "Recorder starts over on a restart"        "^-- restart$" "$LUA" t_restart.lua
check "Recorder writes START restart=1"          "^\[CREC\] f=2 START v=4 restart=1$" "$LUA" t_restart.lua
check "Recorder snapshots after a restart"       "^\[CREC\] f=127 SNAP s=1" "$LUA" t_restart.lua
check "Recorder logs build events"               "LINK s=1 t=1 a=7 b=500 m=bracing pa=-3093.19,205.21 pb=-3100.00,105.00$" "$LUA" t_buildrec.lua 1
check "Recorder logs upgrades"                   "DEV s=2 t=102 i=903 d=minigun a=9 b=8 lt=0.60 .* u=900$" "$LUA" t_buildrec.lua 2
# recorded build -> plan (.dev/tools/fortgen/rec_fort.py); needs Python 3 and the game's data/ai and data/maps
PY=""; for p in "py -3" python3 python; do $p --version >/dev/null 2>&1 && { PY="$p"; break; }; done
if [ -n "$PY" ]; then
  for s in 1 2; do "$LUA" t_buildrec.lua $s > rec$s.txt; $PY "$MOD/.dev/tools/fortgen/rec_fort.py" --data "$DATA" --log rec$s.txt --out rec$s.lua > conv$s.txt 2>&1; done
  check "Recorded build becomes a plan"          "side 1, 10 actions \(7 built and removed again"  cat conv1.txt
  check "Recorded build has no plan errors"      "^0$"                           sh -c "grep -c 'ERROR' conv1.txt conv2.txt | grep -v ':0$' | wc -l"
  check "Recorded side 2 is mirrored to side 1"  "^same$"                        sh -c "cmp -s rec1.lua rec2.lua && echo same"
  check "Recorded plan loads in Lua"             "^actions 10 first 56 10000$"    "$LUA" -e 'dofile("rec1.lua") print("actions " .. #Fort .. " first " .. Fort[1].OriginalNodeAId .. " " .. Fort[1].OriginalNodeBId)'
  check "Tools read plan modules apart from the plan" "^217 sniper sniper,sniper2,laser,firebeam,cannon,cannon20mm 1 18$" $PY -c "import sys; sys.path.insert(0, sys.argv[1]); from fortplan import parse_plan, parse_modules; m = parse_modules(sys.argv[2])[0]; print(len(parse_plan(sys.argv[2])[1]), m['name'], ','.join(m['types']), m['count'], m['requires'])" "$MOD/.dev/tools/fortgen" "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua"
  check "Plan modules pass the building rules"   "module sniper \(1 actions, requires 18\): 0 errors" $PY "$MOD/.dev/tools/fortgen/rules.py" "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-6.lua"
  check "Bastion and its modules pass the rules"  "module sniper2 \(1 actions, requires [0-9]+\): 0 errors" $PY "$MOD/.dev/tools/fortgen/rules.py" "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-8.lua"
  check "Physics: Bastion stands in its build order" "fort-t1f1-Vanilla-8.lua: (STANDS|WEAK)" $PY "$MOD/.dev/tools/fortgen/physics.py" check "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-8.lua"
  # published copy as a Workshop subscriber has it: only under mods/<PublishedFileId>/ (multiplayer desync, 28.10.2026)
  ID="$(sed -n 's/.*PublishedFileId *= *"\([0-9]*\)".*/\1/p' "$MOD/.dev/publishedfileid.lua" 2>/dev/null)"
  if [ -n "$ID" ]; then
    $PY "$MOD/.dev/tools/publish.py" --target "$ROOT/pub/fort9000" > pub.txt 2>&1
  fi
  if [ -n "$ID" ] && [ ! -f "$ROOT/pub/fort9000/ai/ai.lua" ]; then
    # publish.py refuses a dev mod with test switches on (Force, Probe, EngineProbe), e.g. on a test branch
    echo "SKIP  published copy (publish.py refused: $(grep -m1 'fortplans.lua' pub.txt))"
  elif [ -n "$ID" ]; then
    ln -s "$ROOT/pub/fort9000" "$ROOT/mods/$ID"
    check "Published AI looks in the Workshop folder first" "^local CAI_ModDirs = \{ \"mods/$ID/\", \"mods/fort9000/\" \}$" grep "^local CAI_ModDirs" "$ROOT/pub/fort9000/ai/ai.lua"
    # the maps come in pairs() order: one check per map
    for m in "Abyss:3/2" "Vanilla:5/[24]" "VanillaLong:4/1" "Vanilla2v6:4/[24]" "Vanilla2v6Long:4/1"; do
      check "Subscriber's copy loads plans and strategy ($m)" "PLAN-PRELOAD (.* )?$m( |$)" env CAI_TEST_MOD="mods/$ID/ai/ai.lua" "$LUA" t_plan_swap.lua after fort-t1f1-Abyss-1.lua 1
    done
    check "Subscriber's copy swaps the plan"       "first action = -2095.5, -94.4" env CAI_TEST_MOD="mods/$ID/ai/ai.lua" "$LUA" t_plan_swap.lua after fort-t1f1-Abyss-1.lua 1
  else
    echo "SKIP  published copy (no .dev/publishedfileid.lua)"
  fi
  "$LUA" t_probe.lua | sed '/PROBE END/q' > probe.txt
  check "Probe parser finds the CS_UNSTABLE split" "unstable if s > 0.260 \(100 %\)" $PY "$MOD/.dev/tools/fortgen/probe.py" probe.txt
  check "Probe parser splits by devices nearby"  "devices at its nodes +2 / 2$" $PY "$MOD/.dev/tools/fortgen/probe.py" probe.txt
  check "Probe parser lists the refused strut"   "\(100,-100\)-\(0,-100\)  t=0.20,0.80  s=0.400" $PY "$MOD/.dev/tools/fortgen/probe.py" probe.txt
  # static physics check (.dev/tools/fortgen/physics.py, .dev/docs/physics.md)
  $PY "$MOD/.dev/tools/fortgen/physics.py" selftest > phys.txt 2>&1
  check "Physics: a braced cell stands"          "^braced cell: converged=True mechanism=\[\] broken=0" cat phys.txt
  check "Physics: an unbraced cell folds"        "^unbraced cell: mechanism=\[3\]$" cat phys.txt
  check "Physics: a short overhang holds"        "200-long overhang: converged=True broken=0" cat phys.txt
  check "Physics: a long overhang breaks"        "600-long overhang: converged=[A-Za-z]* broken=[1-9][0-9]* tip sag [0-9]{3}" cat phys.txt
  # map files (.dev/tools/fortgen/spr.py, fwe.py, .dev/docs/map-files.md); need the game's data/maps
  check "Map .spr: Abyss starting fort"          "team 1: 31 nodes \(9 foundations\), 69 struts, devices \['reactor 291-294@0.52', 'machinegun 292-293@0.35'\]" $PY "$MOD/.dev/tools/fortgen/spr.py" Abyss
  check "Map .spr: Vanilla starting fort"        "team 1: 19 nodes \(4 foundations\), 36 struts" $PY "$MOD/.dev/tools/fortgen/spr.py" Vanilla
  check "Map .fwe: Abyss terrain"                "version 20, gravity 981, .* 15 blocks, 3 views" $PY "$MOD/.dev/tools/fortgen/fwe.py" Abyss
  check "Tech hidden when placed (Abyss, Vanilla, 2v6)" "^tech not hidden: 0$" $PY -c "import sys, glob; sys.path.insert(0, sys.argv[1]); import gen_fort, rules; from fortplan import parse_plan, node_positions; n = 0
for f in glob.glob(sys.argv[2] + '/fortplans/*/*.lua'):
    d = f.replace(chr(92), '/').split('/')[-2]
    if d not in ('Abyss', 'Vanilla', 'Vanilla2v6'): continue
    a = parse_plan(f)[1]; m = gen_fort.MAPS[d].get('spr_map', d)
    w = rules.tech_hidden(a, gen_fort.start_fort(m, node_positions(a))); n += len(w); [print(f, x) for x in w]
print('tech not hidden: %d' % n)" "$MOD/.dev/tools/fortgen" "$MOD"
  check "Physics: Vanilla-5's long brace refused" "REFUSED action [0-9]* link: 47-40 length 21[89]" $PY "$MOD/.dev/tools/fortgen/physics.py" check "$MOD/fortplans/Vanilla/fort-t1f1-Vanilla-5.lua"
  # a foundation created along the rock from a neighbouring foundation is refused (CS_OBSTRUCTION, Stalactites-3,
  # 01.11.2026), and so is one on an edge not decorated "foundations" (the rock lip over the mine pocket): every new
  # node on the rock of a Stalactites plan is created straight up from the node below it, on a "foundations" edge
  check "Stalactites foundations from below, on foundation edges" "^bad foundations: 0$" $PY -c "import sys, glob, re, math; sys.path.insert(0, sys.argv[1]); import fwe
edges = [(v[k][:2], v[(k + 1) % len(v)][:2], v[k][2]) for b in fwe.read(sys.argv[3])['blocks'] if b['id'] >= 0 or b['id'] == -1 for v in [b['vertices']] for k in range(len(v))]
def near(p, a, b):
    L = math.dist(a, b); t = max(0, min(1, ((p[0] - a[0]) * (b[0] - a[0]) + (p[1] - a[1]) * (b[1] - a[1])) / (L * L or 1)))
    return math.dist(p, (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
n = 0
for f in glob.glob(sys.argv[2] + '/fortplans/Stalactites/*.lua'):
    for line in open(f):
        if line.startswith('{ Type = CREATE_NODE'):
            a, b = [(float(x), float(y)) for x, y in re.findall(r'x = (-?[\d.]+), y = (-?[\d.]+)', line)][:2]
            on = [d for p, q, d in edges if near(b, p, q) <= 1.5]
            if on and (not (abs(a[0] - b[0]) < 2 and a[1] > b[1]) or 'foundations' not in on): n += 1; print(f, b, 'from', a, on)
print('bad foundations: %d' % n)" "$MOD/.dev/tools/fortgen" "$MOD" "$DATA/maps/Stalactites 1v1/Stalactites 1v1.fwe"
  # a player cuts a hanging fort off the rock (Stalactites-3, 01.11.2026: the starting fort's bottom storey was cut and
  # everything below fell): with every foreground strut through any storey removed, each plan still hangs on its
  # background bracing (gen_hang.py cut, physics.py)
  check "Stalactites plans survive a cut through any storey" "^cut test: 0 falls$" $PY "$MOD/.dev/tools/fortgen/gen_hang.py" cut "$MOD"/fortplans/Stalactites/fort-t1f1-Stalactites-*.lua
else
  echo "SKIP  recorded build -> plan, probe parser (no Python 3)"
fi
rm -rf "$ROOT"; [ $fail = 0 ] && echo "All tests passed." || { echo "There are failures."; exit 1; }
