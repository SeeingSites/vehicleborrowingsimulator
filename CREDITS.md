# Credits

## Third-party art (CC0 1.0, public domain)
- **City Kit (Commercial) 2.1** by Kenney (www.kenney.nl), CC0 1.0 Universal.
  https://kenney.nl/assets/city-kit-commercial
  Used for every building and skyscraper (`assets/kenney/city/`: `building-a`…`building-n`,
  `building-skyscraper-a`…`e`, shared `Textures/colormap.png`). Licence file: `assets/kenney/city/License.txt`.
- **Car Kit 3.1** by Kenney (www.kenney.nl), CC0 1.0 Universal.
  https://kenney.nl/assets/car-kit
  Used for all vehicles (`assets/kenney/cars/`: sedan, sedan-sports, hatchback-sports, taxi, suv, van,
  delivery, police, plus truck/ambulance kept for later). Licence file: `assets/kenney/cars/License.txt`.

CC0 needs no attribution; Kenney is credited here anyway (thank you!).

## Generated in this project
Roads, sidewalks, markings, crossings, parks, parking lots, traffic lights, street lamps, pedestrians,
the player, weapon pickups, tracers / muzzle flashes / sparks, smoke, fire and explosions are generated
procedurally at runtime in GDScript (`scripts/tex.gd`, `scripts/city.gd`, `scripts/ped.gd`,
`scripts/weapons.gd`, `scripts/crime.gd`, `scripts/main.gd`), including the v4 garages, pads, payphones, signs and skull.
Gang names (Neon Serpents, Iron Saints, Rust Kings) are original to this project. All sound effects (engine, skid, siren, horn, thud, splat,
explosion, pistol, SMG, shotgun, punch, car alarm, phone ring, cash chime, spray, crusher) are synthesised at runtime in `scripts/sfx.gd`. No audio assets are used.

- Engine: Godot Engine 4.7.2-stable (MIT licence), https://godotengine.org
- Font: Godot's built-in default font.
