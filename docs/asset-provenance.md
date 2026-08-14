# Asset provenance

The following files come from the read-only Rowan PWA repository. They are
project-owned artwork included for product continuity; ownership/licensing
should still be confirmed before public distribution.

| Native path | Original PWA path |
|---|---|
| `kyndyn/Resources/Companions/spark.png` | `backend/static/img/companions/spark.png` |
| `kyndyn/Resources/Companions/orbit.png` | `backend/static/img/companions/orbit.png` |
| `kyndyn/Resources/Companions/pixel.png` | `backend/static/img/companions/pixel.png` |
| `kyndyn/Resources/Companions/comet.png` | `backend/static/img/companions/comet.png` |
| `kyndyn/Resources/Companions/bop.png` | `backend/static/img/companions/bop.png` |
| `kyndyn/Resources/Companions/penguin.png` | `data/uploads/companions/builtin_penguin.png` |
| `kyndyn/Resources/Companions/bee.png` | `data/uploads/companions/builtin_bee.png` |
| `kyndyn/Resources/Companions/cactus.png` | `data/uploads/companions/builtin_cactus.png` |
| `kyndyn/Resources/Companions/cloud.png` | `data/uploads/companions/builtin_cloud.png` |
| `kyndyn/Resources/Companions/dino.png` | `data/uploads/companions/builtin_dino.png` |
| `kyndyn/Resources/Backgrounds/meadow.png` | `backend/static/img/backgrounds/meadow.png` |
| `kyndyn/Resources/Backgrounds/bedroom.png` | `backend/static/img/backgrounds/bedroom.png` |
| `kyndyn/Resources/Backgrounds/background-cloud.png` | `backend/static/img/backgrounds/cloud.png` |
| `kyndyn/Resources/Backgrounds/aquarium.png` | `backend/static/img/backgrounds/aquarium.png` |
| `kyndyn/Resources/Backgrounds/arcade.png` | `backend/static/img/backgrounds/arcade.png` |

The five `builtin_*.png` companion files are generic app catalog assets, not
household uploads. Their solid chroma backgrounds were removed locally for
native transparency; their artwork was otherwise retained. No household JSON,
user-uploaded artwork, backups, names, or private runtime data was copied.

The app icon at
`kyndyn/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` was
provided directly by the project owner during Development CloudKit Validation
0.5. The native copy is mechanically flattened to an opaque 1024×1024 PNG for
Apple asset-catalog compliance; the supplied source file is not committed.

The alternate app icons and their matching in-app previews were also supplied
directly by the project owner. Their committed asset-catalog copies were
mechanically resized to Apple-compliant 1024×1024 icon sources and 512×512
device-local previews. No private household content is present in these assets.

The launch-screen wordmark at
`kyndyn/Resources/Assets.xcassets/KyndynSplash.imageset/KyndynSplash.png` was
provided directly by the project owner for Build 5 and is committed unchanged.
