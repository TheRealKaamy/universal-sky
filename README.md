# Universal Sky Plugin
Dynamic Sky for Godot Engine 4.5
---------------------------------------------

<img width="1911" height="973" alt="univsky1" src="https://github.com/user-attachments/assets/4a419f61-bb58-4b91-873d-429dd4a8f62f" />

---------------------------------------------

## Status:
> 0.2 Alpha 
---------------------------------------------

## Features:
---------------------------------------------
### Rendering:
- Forward.
- Mobile.
- Compatibility.

### Standard Sky:
- Rayleigh and mie scattering.
- Night scattering.
- Artistic control.
- Moon and moon phases.
- Deep space.
- Stars field scintillation.
- Simple dynamic clouds.
- Clouds panorama(static clouds).
- Incrementally ray-marched volumetric clouds (Forward+).
- Sun eclipses

### Planetary:
- Day and night cycle.
- Simple sun and moon position.
- Realistic sun and moon positions.
- Datetime with basic gregorian calendar.
- Realistic deep space rotation.

## Volumetric Clouds


Volumetric clouds use compute shaders and require the Forward+ renderer. See `example/volumetric_clouds.tscn` for a configured example.

The quality preset changes only view and light ray samples:

| Preset | View samples | Light samples |
| --- | ---: | ---: |
| Performance | 64 | 3 |
| Balanced | 96 | 4 |
| High | 128 | 6 |
| Ultra | 160 | 8 |

Texture resolution and `frames_to_update` remain independent. Lower "update frame" values provide faster visual updates, while higher values reduce the per-frame GPU cost. `weather_skip_threshold` and `density_skip_threshold` are lossless at zero. Raising them trades tenuous cloud detail for faster rendering.

## Screenshots

#### Night
![Night Screenshot](docs/screenshots/volumetric-midnight.png)

#### Day
![Day Screenshot](docs/screenshots/volumetric-day.png)

#### Sunrise
![Sunrise Screenshot](docs/screenshots/volumetric-sunrise.png)

### Credits

Based on [Clay John’s volumetric cloud demo v2](https://github.com/clayjohn/godot-volumetric-cloud-demo-v2), released under the MIT license. The original license notice is included in [`LICENSES/volumetric-clouds-MIT.txt`](LICENSES/volumetric-clouds-MIT.txt).
