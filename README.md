# apl-raymarcher
Raymarcher written in dyalog APL, using pixel plotting helpers using rust and nix for build management

### more info at
(https://bolives-hax.github.io/Blog/raymarching-in-dyalog-apl/)

## exporting to png
```bash
nix run github:bolives-hax/apl-raymarcher#pngRunner --no-write-lock-file
# output will we placed in cwd as rendering.png
```

note that you'd need to clone the repo and change the resolution in flake.nix
to use anything but the default resolution.

this could be done using 

```bash
git clone https://github.com/bolives-hax/apl-raymarcher
cd  apl-raymarcher
nix run .#waylandRunner
```

or if you want to build the script that is being run instead to examine it
```bash
  nix build .#waylandRunner
```

## running under wayland
```bash
nix run github:bolives-hax/apl-raymarcher#waylandRunner --no-write-lock-file
```

NOTE: resizing the window after the rendering process started isn't supported for now
and will lead to a crash. As a quick fix there is a 4 second delay before the program
reads in the resolution.

## running under xorg
TODO

## extracting the apl script

TODO (until then using nix build and checking result/ should do the trick
but I will add the raw apl script as a build output
