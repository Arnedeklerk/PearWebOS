Put your own photos here (jpg, png or webp), then run `./pear sync`.

Each one is cropped to 16:9 and given a date colour automatically. To adjust
either, add a `photos.json` next to them:

```json
{"castle.webp": {"crop": 0.45, "accent": "#f2dfb5"}}
```

`crop` is where the 16:9 band sits in a taller photo (0 top, 1 bottom).
This folder is ignored by git, so your photos never leave your machine.
