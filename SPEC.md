# FORT 9000 – Spezifikation

FORT 9000 ist eine Mod für das Spiel **Forts** (Steam), die die eingebaute KI erweitert, Partien aufzeichnet und aus den Aufzeichnungen die KI-Parameter automatisch nachtrainiert.

Anzeigename im Spiel: *FORT 9000 (KI + Recorder)* · Ordner: `data/mods/fort-9000`

---

## 1. Ziele

- Eine stärkere, anpassungsfähigere Computergegnerin als die eingebaute Forts-KI.
- Die Spielweise soll sich aus echten Partien verbessern (Training), nicht nur durch Handarbeit.
- Eigene Bauvarianten je Karte, damit die KI nicht immer dieselbe Festung baut.
- Alles deterministisch: Replays und Multiplayer dürfen nicht auseinanderlaufen.

## 2. Features

### 2.1 Adaptive Zielwahl
Die Prioritätslisten der eingebauten KI (`HeavyArmsPriorities`, `SmallArmsPriorities`) werden alle `ThinkInterval` Sekunden neu sortiert.
Punktzahl je Gerätetyp = Grundwert (`Strategy.TargetValue`) + Bedrohungsbonus.
Die Bedrohung steigt, wenn eine gegnerische Waffe schießt (`ThreatPerShot`), uns trifft (`ThreatPerHit`) oder den Reaktor trifft (`ThreatPerReactorHit`), und zerfällt laufend (`ThreatDecay`). Der Bonus sättigt: `ThreatWeight · T / (T + ThreatHalf)`. Wird eine Waffe des Gegners zerstört, sinkt ihre Bedrohung auf 70 %.

### 2.2 Aggression nach Spielphase und Wirtschaft
- Phasen: Early (< `EarlySeconds`), Mid, Late (ab `LateSeconds`) mit je eigenem Faktor.
- Viel Metall (`RichMetal`) → Faktor × `RichBoost`; wenig Metall/Energie (`PoorMetal`, `PoorEnergy`) → Faktor × `PoorFactor`.
- Wirkt auf `OffensiveFireProbability` (Maschinengewehre sind über `AggressionExclude` ausgenommen).

### 2.3 Luftabwehr nach Beschussdruck
Zählt gegnerische Schüsse mit Mörsern und Raketen (`IndirectThreatTypes`). Je mehr, desto stärker wird `AntiAirFireProbability` angehoben (bis `AntiAirBoostMax`).

### 2.4 Feuersteuerung
Die eingebaute KI feuert nur in Baupausen und höchstens eine Waffe pro Durchlauf. FORT 9000 setzt `HardThreshold = 0` (immer angriffsbereit), erhöht die Feuerwahrscheinlichkeit beim Bauen (`RebuildFireFactor`) und feuert in einem eigenen Takt (`Fire.Interval`) bis zu `WeaponsPerTick` bereite Waffen reihum.

### 2.5 Bautempo nach Schwierigkeit
Takt (`UpdatePeriod`) und Reparaturzeit (`RepairPeriod`) werden zwischen Easy / Normal / Hard linear interpoliert. Bau- und Pausenzeiten sind einstellbar.

### 2.6 Notbremsen beim Bauen
- **Wiederaufbau aufgeben:** hängt eine vorgemerkte Wiederaufbau-Aktion länger als `RebuildGiveUpSeconds`, wird sie verworfen. Wartet die KI nur auf Metall, läuft die Uhr nicht.
- **Aktion überspringen:** hängt der normale Weiterbau trotz genug Metall (`BuildSkipMinMetal`) länger als `BuildSkipSeconds`, wird die Aktion übersprungen.

### 2.7 Eigene Bauplan-Varianten je Karte
- Pläne liegen in `fortplans/<Karte>/` (Forts entfernt fremde Dateien aus `data/maps`).
- Karte wird über den Dateinamen oder über die Signatur des Spielplans (Position + Aktionszahl, ggf. Reaktorzahl) erkannt.
- Pro Partie wird deterministisch ein Plan gewählt (Spielzufall bzw. `teamId`) und in die Koordinaten des Spielplans verschoben; das Spiel spiegelt/verschiebt ihn danach wie gewohnt.
- `"original"` in der Planliste behält den Plan des Spiels.
- Unterstützte Karten: **Abyss**, **Vanilla** (Mid-Festung, gilt auch für Penguin, Caverns, …), **VanillaLong** (2v2, obere Plattform).
- Kartenbezogene Strategie-Überschreibungen (`Maps[<Karte>].Strategy`), z. B. langsamerer Start auf weiten Karten.

### 2.8 Fehlersuche
Bau-Funktionen (`CreateLink`, `CreateNode`, `CreateDeviceWithFlags`, `CreateGroundDevice`, `UpgradeDevice`) werden eingehängt; fehlgeschlagene Versuche landen mit Fehlercode als `BAUFEHLER` im Log (je Fall einmal, max. 200).

### 2.9 Hilfs-KI-Modus
Übernimmt ein Spieler die KI als Luftabwehr-Assistent, schaltet sich FORT 9000 ab und stellt alle geänderten Werte wieder her.

### 2.10 Recorder
`script.lua` läuft in jeder Partie und in Replays, verändert nichts am Spiel und schreibt mit Präfix `[CREC]` ins Forts-Log:

| Zeile | Inhalt |
|---|---|
| `START v=2` | Beginn |
| `SNAP s=… m=… e=… dev=… shots=…` | alle 125 Frames: Metall, Energie, Geräte und Schüsse je Seite |
| `BUILT` / `LOST` | Gerät fertig / zerstört |
| `RESULT w=…` | Sieger |

### 2.11 Training
`tools/train.py` sammelt die Logs, lernt daraus und schreibt `ai/strategy.lua` neu (vorherige Version: `strategy_previous.lua`).
Gelernt wird jedes Mal von den Startwerten aus, mehrfaches Ausführen verschiebt also nichts. Nur neue Partien ändern das Ergebnis.
Gelernt werden `TargetValue` (Heavy/Small) und `Aggression` (Early/Mid/Late). Mit `--strength` (0..1) wird begrenzt, wie weit die Werte von den Startwerten abweichen.

### 2.12 Festungs-Generator
`tools/fortgen/` erzeugt Bauplan-Varianten (`gen_fort.py`), rechnet Pläne zwischen Koordinatensystemen um (`mid_to_long.py`) und rendert sie zur Prüfung als Bild (`render_all.py`, `view.py`).

---

## 3. Architektur

```
fort-9000/
├── mod.lua                 Mod-Manifest
├── displayname.lua         Anzeigename (EN/DE)
├── script.lua              Recorder (Mod-Script, läuft immer)
├── ai/
│   ├── ai.lua              KI-Erweiterung (läuft NACH data/ai/ai.lua)
│   ├── strategy.lua        trainierte Parameter (von train.py erzeugt)
│   ├── strategy_previous.lua   Vorversion
│   └── fortplans.lua       Karten, Planlisten, Karten-Strategien
├── fortplans/<Karte>/      eigene Bauplan-Varianten
└── tools/
    ├── train.py / train.bat    Sammeln + Training
    ├── fortgen/                Plan-Generator und Werkzeuge
    ├── tests/                  Lua-Tests (run_tests.sh)
    ├── logs/                   archivierte Partie-Logs (nicht im Repo)
    └── _alt/                   Sicherungen (nicht im Repo)
```

### 3.1 Ladereihenfolge und Erweiterungsprinzip
Forts führt `ai/ai.lua` des Mods **nach** der eingebauten KI aus. Die Mod überschreibt keine Dateien, sondern **umhüllt** Funktionen der eingebauten KI (`Load`, `OffsetFort`, `MirrorFort`, `OnWeaponFired`, `OnDeviceHit`, `OnDeviceDestroyed`, `OnGameResult`, `EnableHumanAssist`): die Originalfunktion wird gesichert, aufgerufen und um eigene Logik ergänzt.

### 3.2 Ablauf in der KI

```
Initialisierung (dofile erlaubt)
  ├─ strategy.lua laden, fehlende Werte mit Defaults füllen
  ├─ fortplans.lua laden
  └─ alle eigenen und Originalpläne vorladen
Spielstart
  ├─ OffsetFort / MirrorFort / Load → CAI_TrySwapPlan (einmalig):
  │     Karte erkennen → Karten-Strategie mergen → Plan wählen → verschieben → einsetzen
  ├─ Load → CAI_Init, Tempo, Feuer, Bau-Logging, Denkschleife starten
Laufend
  ├─ CAI_Think (alle ThinkInterval s): Bedrohung zerfällt, Notbremsen, Ziele, Aggression, Luftabwehr
  ├─ CAI_FireTick (alle Fire.Interval s): reihum Waffen feuern
  └─ Ereignisse: OnWeaponFired / OnDeviceHit / OnDeviceDestroyed → Bedrohung, Statistik
Spielende
  └─ OnGameResult → [CAI] END mit kills / lost / enemyShots
```

### 3.3 Trainingskreislauf

```
Partie spielen ──► users/<id>/log.txt ([CREC] + [CAI])
      ▲                      │ train.py collect (Archiv in tools/logs/)
      │                      ▼
strategy.lua  ◄── train.py train (liest alle Logs, lernt von Startwerten aus)
```

Forts überschreibt `log.txt` bei jedem Start – deshalb nach jeder Spielsitzung `train.bat` ausführen.

### 3.4 Wichtige Entwurfsregeln
- **Determinismus:** keine Uhrzeit, kein `math.random`. Zufall nur über `GetRandomInteger`, sonst Fallback auf `teamId`.
- **Fehlertoleranz:** jede eigene Logik läuft in `pcall`; ein Fehler darf die Partie nicht abbrechen, sondern wird mit `[CAI] FEHLER …` geloggt.
- **Konfiguration statt Code:** Verhalten steuern `strategy.lua` (gelernt) und `fortplans.lua` (manuell); `fortplans.lua` wird vom Training nie verändert.
- **Logging:** Entscheidungen mit `[CAI]`, Aufzeichnung mit `[CREC]`.

## 4. Konfigurationsreferenz

**`strategy.lua`** (Auszug): `ThinkInterval`, `ThreatWeight/Half/Decay/PerShot/PerHit/PerReactorHit`, `EarlySeconds`, `LateSeconds`, `Aggression{Early,Mid,Late}`, `AggressionExclude`, `RichMetal/RichBoost`, `PoorMetal/PoorEnergy/PoorFactor`, `IndirectThreatTypes`, `AntiAirThreatShots`, `AntiAirBoostMax`, `RebuildGiveUpSeconds`, `BuildSkipSeconds`, `BuildSkipMinMetal`, `Fire{…}`, `Tempo{…}`, `TargetValue{Heavy,Small}`.

**`fortplans.lua`:** je Karte `Originals`, `OriginalsDir`, `ReactorsPerSide`, `Plans`, `Strategy`; global `Force` (Plan erzwingen, zum Testen).

## 5. Installation und Benutzung

1. Ordner `fort-9000` nach `<Steam>/steamapps/common/Forts/data/mods/` kopieren.
2. Im Spiel die Mod *FORT 9000 (KI + Recorder)* aktivieren.
3. Partien spielen oder Replays abspielen.
4. `tools/train.bat` ausführen (benötigt Python 3) – aktualisiert `ai/strategy.lua`.
5. Tests: `tools/tests/run_tests.sh` (Lua, über `LuaPlusC.exe`).

## 6. Bekannte Einschränkungen

- Pläne nur für Abyss, Vanilla und VanillaLong.
- Training lernt aus wenigen Partien (aktuell 11); `--strength` begrenzt die Abweichung.
- Annahme von 25 Frames pro Sekunde für die Spielphasen im Training.
