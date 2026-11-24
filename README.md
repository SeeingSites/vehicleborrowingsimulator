# Downtown Rampage — GTA2-style top-down prototype (Godot 4.7.2)

Procedural top-down city with tilted 3D buildings (perspective camera looking straight down),
on-foot player, enterable cars with arcade drift handling, AI traffic, wandering pedestrians,
cash / wanted stars / speed HUD, chasing police, touch controls and a Web (HTML5) export.

## Run
    ./tools/godot --path .                       # play (desktop window)
    ./tools/godot --path . -- --touch            # force on-screen joystick/buttons
    ./tools/godot --path . -e                    # open in the editor
    ./tools/godot --headless --path . --export-release "Web" web_build/index.html
    cd web_build && python3 -m http.server 8060  # then open http://localhost:8060
    ./capture_screenshots.sh                     # scripted offscreen screenshots -> screenshots/

## Controls
- WASD / arrows (or gamepad stick, or the on-screen joystick): walk / drive
- E or Enter (touch: ENTER): enter the nearest car (carjacks traffic) / exit
- Space (touch: DRIFT): handbrake / drift
- Run over pedestrians: +$10 and +1 wanted star. Police spawn at 1+ star (one car per star, max 4)
  and route along the road grid; stop next to a cop and you're BUSTED (−$100, stars cleared).
  Stars decay one every 25 s.

## Layout
- `scripts/game.gd` (autoload): constants, input map, cash/wanted state, touch input
- `scripts/main.gd`: world setup, spawning, enter/exit, police logic, speed-zoom camera, skid marks
- `scripts/city.gd`: 8x8 block grid, sidewalks, buildings with roof clutter, parks, parking lots, markings
- `scripts/car.gd`: one arcade car model used by player, traffic AI and police AI
- `scripts/ped.gd`, `scripts/player.gd`, `scripts/hud.gd`, `scripts/touch.gd`, `scripts/tex.gd`
- `scripts/shots.gd`: scripted scenarios for screenshots (`-- --shot=onfoot|driving|traffic|police`)
