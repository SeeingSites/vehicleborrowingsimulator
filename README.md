# Downtown Rampage — GTA2-style top-down prototype (Godot 4.7.2)

Top-down city (perspective camera looking straight down) built from Kenney's CC0 City Kit buildings,
on-foot player, 8 enterable car types (Kenney Car Kit) with their own arcade handling, AI traffic,
wandering pedestrians, pistol + SMG with pickups and drive-bys, rotating mini-map, cash / wanted stars /
speedometer / ammo HUD, chasing police, touch controls and a Web (HTML5) export. See `CREDITS.md`.

## Run
    ./tools/godot --path .                       # play (desktop window)
    ./tools/godot --path . -- --touch            # force on-screen joystick/buttons
    ./tools/godot --path . -e                    # open in the editor
    ./tools/godot --headless --path . --export-release "Web" web_build/index.html
    cd web_build && python3 -m http.server 8060  # then open http://localhost:8060
    ./capture_screenshots.sh                     # scripted offscreen screenshots -> screenshots/

## Publish on GitHub Pages
The repo ships `.github/workflows/pages.yml`: on every push to `main` (or a manual run) it installs
the pinned Godot 4.7.2 editor plus only the Web export templates (cached between runs), runs the
headless `Web` export into `web_build/`, and deploys it with `actions/upload-pages-artifact` +
`actions/deploy-pages`.

1. Create a GitHub repo and push this project to its `main` branch
   (`git remote add origin git@github.com:<you>/<repo>.git && git push -u origin main`).
2. In the repo: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. Push again (or **Actions → Deploy web build to GitHub Pages → Run workflow**).
   The game appears at `https://<you>.github.io/<repo>/`.

Notes
- The Web preset uses the **single-threaded** template (`variant/thread_support=false`), so it needs no
  SharedArrayBuffer and no COOP/COEP headers (which Pages can't set); no coi-serviceworker is needed.
- All exported paths are relative, so it works under `/<repo>/`. `.nojekyll` is added to the artifact.
- Pages serves `index.wasm` gzip-compressed automatically (~39 MB on disk, ~10 MB over the wire).
- Browsers start audio suspended; a small script in the preset's `html/head_include` resumes it on the
  first tap/click/key press.
- The PWA option is on, so phones can "Add to Home Screen" and play full-screen.

## Controls
- WASD / arrows (or gamepad stick, or the on-screen joystick): walk / drive
- E or Enter (touch: STEAL / ENTER / EXIT / PHONE): steal or enter the nearest car / exit / answer a payphone
- Space (touch: DRIFT): handbrake / drift
- H (touch: HORN): horn
- Esc / P: pause. Progress (cash, multiplier, gang respect, missions done, ammo) is saved automatically.
- Ctrl / F / left click (touch: FIRE): shoot, or punch / mug with no gun. Q / Tab (touch: WPN): next weapon. On foot you shoot where you
  face; in a car it's a forward drive-by. Pistol, SMG and shotgun pickups (spinning boxes on sidewalk corners, also
  shown on the mini-map) give ammo and respawn after 30 s. Shooting peds: +1 star (at most every 2.5 s), killing
  them pays; hitting cars damages them; hitting police adds a star (at most one per second).
- Run over pedestrians: +$10 each and +1 wanted star (at most one star per 2.5 s, so ploughing a crowd is one star,
  not one per body). Police escalate with stars (see Crime systems below).
- Cars have health: they darken and smoke when damaged, catch fire below 15%, then explode
  (blast damages cars, kills pedestrians, can chain; a single crash does at most 60 damage) and leave a wreck. You die if you're in or next to an
  exploding car or get run over: WASTED, then you respawn on foot.
- Traffic lights at every intersection except the four map corners (14 s cycle, all-red clearance). Traffic
  stops on red/yellow, doesn't enter a blocked junction, and left turns yield to oncoming cars.

## Crime systems (v4)
| System | What it does | How to trigger |
|---|---|---|
| Car theft | Parked cars: 1.1 s break-in (player frozen, 50% car alarm that scatters bystanders). Moving cars: driver is pulled out instantly (a cop driver gets out and fights). +1 star if a cop (35 m, line of sight) or a bystander (7 m) sees it, otherwise +$25. Cop cars: +2 stars. | E / touch **STEAL** next to a car (the button reads STEAL / ENTER / EXIT / PHONE) |
| Escalating police | 1-4 stars: 1-4 cop cars, top speed 26 / 30 / 34 m/s at 1 / 2 / 3+ stars (low heat can be outrun). Below 4 stars cop cars tail you and box you in for the arrest instead of ramming; a police bump does at most 20 damage (35 from 4 stars). Cops get out on foot when they catch you and you've stopped (1 cop at 1 star, 2 after). From 3 stars foot cops shoot. 4 stars: roadblocks (2 parked cop cars + cops at the junction ahead, every ~16 s) and cop cars may run you down. 5-6 stars: 1-2 SWAT vans that unload 4 armed SWAT each. | Raise your wanted level |
| Arrest | A cop car next to you while you're on foot/stopped, or a foot cop within 1.8 m, for 1 s = BUSTED. | — |
| Evasion | Stars only decay while no cop can see you (line of sight, 45 m cars / 30 m on foot): one star per 12 s unseen. HUD shows SEEN / EVADING n. | Break line of sight |
| Pay 'n' Spray | Drive in with heat: -$500, wanted cleared, car repaired and the body repainted. No heat: $150 repair. Waits while a cop is watching and sprays as soon as they lose sight. | Blue **R** on the mini-map |
| Busted vs wasted | Busted: fine 10% of cash (min $100), all weapons confiscated, multiplier reset, respawn at the police station. Wasted: $250 hospital bill, keep weapons, multiplier reset, respawn at the hospital. Both fail the active mission. | — |
| Payphone missions | One phone per gang (rings when a job is on offer). Each gang has a starter job and a big job that unlocks at respect 20; at respect <= -25 they hang up. Jobs: steal + deliver a car type to the DROP-OFF, hit a rival gang lieutenant (with bodyguards), timed checkpoint run in any car. Pass: cash, +25 respect (rival gang -15), multiplier +1. Fail (time, busted, wasted, target lost): -5 respect. | Walk to a ☎ and press E / PHONE |
| Gangs and turf | Neon Serpents (west, green), Iron Saints (east, red), Rust Kings (south-middle, orange), 6 members each, turf tinted on the mini-map. Killing a member: -15 with that gang, +5 with the gang that hates them. At respect <= -25 a gang shoots on sight. Respect bars are in the HUD panel (yellow tick = mission unlock). | Walk into their turf |
| Money and multiplier | Every crime pays through a multiplier x1-x5 (+1 per mission or kill frenzy, reset when busted or wasted): ped $10, gang member $25, cop $50, SWAT $100, theft $25, mugging $8-40. | — |
| Mugging | Fire with no gun (fists): knock a pedestrian down and take their cash; +1 star if a cop sees. Hitting someone already down hurts them. | FIRE / Ctrl with FISTS |
| Car crusher | Park on the crusher for 1.2 s: car is crushed for its value x condition (sedan $400 ... sports $1200, cop car $1500). | Yellow **C** on the mini-map |
| Ammu shop | Walk onto a pad: pistol $150 (30), SMG $400 (120), shotgun $600 (16, 6 pellets). Pickups still spawn on corners. | Red **$** on the mini-map |
| Kill frenzy | Skull pickup: 12 kills in 40 s with a free SMG -> $2000 and multiplier +1. Respawns after 90 s. | Red **K** on the mini-map |

Headless checks for all of this: `./tools/godot --headless --fixed-fps 60 --path . -- --test` (prints PASS/FAIL, exit code 1 on
failure, 2 if the checks can't load or time out).

Other rules: a hit job only counts if you make the kill (someone else getting the target fails it); kills from an
explosion count as yours if you shot or rammed the car that blew up; stolen cars you abandon are removed after a minute
out of sight.

## Playthroughs
`scripts/play.gd` plays the game through the normal inputs (virtual-stick vector, E / fire / handbrake) with a small
road-grid autopilot and on-screen captions: `joyride`, `phone_job`, `hit_job`, `five_stars`.

    ./tools/godot --headless --fixed-fps 60 --path . -- --play=hit_job          # dry run: event log + PLAYRESULT
    xvfb-run -a -s "-screen 0 1280x720x24" ./tools/godot --path . --rendering-driver opengl3 \
        --write-movie hit_job.avi --fixed-fps 30 -- --play=hit_job              # record with Movie Maker

## HUD
- Top left: mini-map (player-up, rotates with you; N marker; roads, traffic, flashing police blips, pickups).
- Below it, only in a car: speedometer gauge with km/h and the car type.
- Top centre: wanted stars (moved below the mini-map on portrait screens), SEEN / EVADING, mission objective
  and timer. Top right: cash and multiplier, HP, car health, weapon and ammo, gang respect bars.
- Mini-map also shows gang turf, gang members and foot cops, facilities (R spray, C crusher, $ shop, H hospital,
  P police, ☎ phones, K frenzy) and a flashing ! for the mission target, pinned to the edge when off-map.
- Portrait phones switch the UI to a 720x1280 layout and widen the camera.

## Car types
sedan, sports, hatchback, taxi, SUV, van, truck, police — each with its own length, top speed,
acceleration, turn rate, grip/drift grip and mass (heavier cars take less
crash damage). Traffic and parking lots draw from a weighted mix (`TRAFFIC_MIX` in `scripts/main.gd`; data in
`Car.TYPES`).

## Sound
All audio is synthesised at startup in `scripts/sfx.gd` (engine loop with speed-linked pitch, tyre
skid, two-tone siren, horn, collision thud, pedestrian splat, explosion, pistol, SMG, pickup). No audio assets.

## Traffic simulation (jam metric)
    ./tools/godot --headless --fixed-fps 60 --path . -- --sim=600 --seed=1 --cars=100 [--no-signals]
prints `SIMRESULT {...}` (jam rate = share of traffic cars stationary for 20 s or more, sampled each second
after a 30 s warm-up). `--no-signals` reproduces the v1 traffic AI. Results are in `sim_results/`.

## Layout
- `scripts/game.gd` (autoload): constants, input map, cash/wanted state, touch input
- `scripts/main.gd`: world setup, spawning, enter/exit, police logic, speed-zoom camera, skid marks
- `scripts/city.gd`: 8x8 block grid, sidewalks, buildings with roof clutter, parks, parking lots, markings
- `scripts/car.gd`: arcade car (8 types) used by player, traffic AI and police AI
- `scripts/kit.gd`: loads/caches the Kenney GLB models; `scripts/weapons.gd`: guns, fists, pickups, hitscan
- `scripts/crime.gd`: theft, police escalation, evasion, facilities, missions, gangs, frenzy, busted/wasted
- `scripts/tests.gd`: headless checks (`-- --test`); `scripts/play.gd`: scripted playthroughs (`-- --play=NAME`)
- `scripts/ped.gd`, `scripts/player.gd`, `scripts/hud.gd`, `scripts/touch.gd`, `scripts/tex.gd`
- `scripts/sfx.gd`: procedural sounds; `scripts/sim.gd`: headless traffic simulation
- `scripts/shots.gd`: scripted scenarios for screenshots (`-- --shot=onfoot|driving|traffic|police|signals|damage|explosion|wasted|shooting|driveby|cars|v4_steal|v4_carjack|v4_footcops|v4_roadblock|v4_swat|v4_respray|v4_busted|v4_hospital|v4_phone|v4_gangs|v4_crusher|v4_shop|v4_frenzy|v4_mug`)
- `assets/kenney/`: CC0 models (see `CREDITS.md`)
