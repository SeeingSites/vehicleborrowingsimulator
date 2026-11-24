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
- E or Enter (touch: ENTER): enter the nearest car (carjacks traffic) / exit
- Space (touch: DRIFT): handbrake / drift
- H (touch: HORN): horn
- Ctrl / F / left click (touch: FIRE): shoot. Q / Tab (touch: WPN): next weapon. On foot you shoot where you
  face; in a car it's a forward drive-by. Pistol and SMG pickups (spinning boxes on sidewalk corners, also
  shown on the mini-map) give ammo and respawn after 30 s. Shooting peds: +$10 and +1 star; hitting cars
  damages them; hitting police always adds a star.
- Run over pedestrians: +$10 and +1 wanted star. Police spawn at 1+ star (one car per star, max 4)
  and route along the road grid; stop next to a cop and you're BUSTED (−$100, stars cleared).
  Stars decay one every 25 s.
- Cars have health: they darken and smoke when damaged, catch fire below 15%, then explode
  (blast damages cars, kills pedestrians, can chain) and leave a wreck. You die if you're in or next to an
  exploding car or get run over: WASTED, then you respawn on foot.
- Traffic lights at every intersection except the four map corners (14 s cycle, all-red clearance). Traffic
  stops on red/yellow, doesn't enter a blocked junction, and left turns yield to oncoming cars.

## HUD
- Top left: mini-map (player-up, rotates with you; N marker; roads, traffic, flashing police blips, pickups).
- Below it, only in a car: speedometer gauge with km/h and the car type.
- Top centre: wanted stars (moved below the mini-map on portrait screens). Top right: cash, HP, car health,
  weapon and ammo.
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
- `scripts/kit.gd`: loads/caches the Kenney GLB models; `scripts/weapons.gd`: guns, pickups, hitscan
- `scripts/ped.gd`, `scripts/player.gd`, `scripts/hud.gd`, `scripts/touch.gd`, `scripts/tex.gd`
- `scripts/sfx.gd`: procedural sounds; `scripts/sim.gd`: headless traffic simulation
- `scripts/shots.gd`: scripted scenarios for screenshots (`-- --shot=onfoot|driving|traffic|police|signals|damage|explosion|wasted|shooting|driveby|cars`)
- `assets/kenney/`: CC0 models (see `CREDITS.md`)
