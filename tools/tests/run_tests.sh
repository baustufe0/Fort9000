#!/bin/bash
# FORT 9000 fuer Forts - Testlauf mit echtem Lua 5.1 und nachgebauter Spiel-API.
# Aufruf: bash run_tests.sh <lua5.1-binary> <Forts-data-Ordner>
#   Lua 5.1 bauen (falls noetig):
#     git clone -q --depth 1 --branch 5.1.5 https://github.com/LuaDist/lua.git /tmp/lua51
#     cd /tmp/lua51/src && cp luaconf.h.orig luaconf.h && make -s posix   -> /tmp/lua51/src/lua
# Die Tests erwarten die ausgelieferten Abyss-Plaene (fortplans/Abyss/fort-t1f1-Abyss-2.lua beginnt bei -2120.45,-250).
LUA="${1:-lua5.1}"; DATA="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"; MOD="$(cd "$HERE/../.." && pwd)"
ROOT="$(mktemp -d)"; mkdir -p "$ROOT/mods"; ln -s "$MOD" "$ROOT/mods/fort-9000"; ln -s "$DATA/maps" "$ROOT/maps"; ln -s "$DATA/ai" "$ROOT/ai"
cp "$HERE"/t_*.lua "$ROOT/"; cd "$ROOT"; fail=0
check() { local name="$1" pat="$2"; shift 2; if "$@" 2>&1 | grep -qE "$pat"; then echo "OK    $name"; else echo "FEHLER $name"; "$@" 2>&1 | tail -5; fail=1; fi; }
check "Basis (Zielwahl, Aggression, Ende)"       "MOCK OK"                       "$LUA" t_basis.lua
check "Hilfs-KI wird abgeschaltet"               "ASSIST"                        "$LUA" t_hilfski.lua
for o in before after; do for e in fort-t1f1-Abyss-1.lua fort-t1f1-Abyss-ToGA1.lua; do
  check "Plantausch $o $e Team 1"                "erste Aktion = -2120.4, -250.0" "$LUA" t_plantausch.lua $o $e 1
  check "Plantausch $o $e Team 102"              "erste Aktion = 2120.4, -250.0"  "$LUA" t_plantausch.lua $o $e 102
done; done
for o in before after; do for e in fort-t1f1-Template-1.lua fort-t1f1-Template-2.lua; do
  check "Plantausch Vanilla $o $e Team 1"        "erste Aktion = -2846.2, 204.0"  "$LUA" t_vanilla.lua $o $e 1
  check "Plantausch Vanilla $o $e Team 102"      "erste Aktion = 2846.2, 204.0"   "$LUA" t_vanilla.lua $o $e 102
done; done
for o in before after; do
  check "Plantausch VanillaLong $o Team 1"       "erste Aktion = -3747.2, -746.4" "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 1
  check "Plantausch VanillaLong $o Team 102"     "erste Aktion = 3747.2, -746.4"  "$LUA" t_vanillalong.lua $o fort-t2f1-Template-1.lua 102
done
check "Feuersteuerung"                           "gefeuert:.11,12,14,15"         "$LUA" t_feuer.lua
check "Notbremse wartet bei Metallmangel"        "Rebuild\[59\] =.true"          "$LUA" t_notbremse_arm.lua
check "Notbremse gibt bei Metall auf"            "AUFGEGEBEN Aktion 59"          "$LUA" t_notbremse_reich.lua
check "Weiterbau wird uebersprungen"             "UEBERSPRUNGEN Aktion 386"      "$LUA" t_ueberspringen.lua
check "Tempo + Ruecksetzen fuer Hilfs-KI"        "nach Hilfs-KI:.3.11.13.10"     "$LUA" t_tempo.lua
check "Baufehler-Protokoll"                      "BAUFEHLER Strebe armour"       "$LUA" t_baufehler.lua
check "Recorder"                                 "RESULT w="                     "$LUA" t_recorder.lua 1
rm -rf "$ROOT"; [ $fail = 0 ] && echo "Alle Tests bestanden." || { echo "Es gibt Fehler."; exit 1; }
