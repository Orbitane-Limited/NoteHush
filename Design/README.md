# NoteHush artwork

The original icon depicts a text page, an insertion point and three tabs in muted teal and warm white. It uses hand-authored geometric shapes; no Microsoft artwork, third-party icons, fonts or generated app screenshots are embedded.

`scripts/render_icon.swift` is the geometry/color source of truth. It uses offscreen Core Graphics and ImageIO to generate [the vector master](NoteHushIcon.svg) and every macOS AppIcon asset slot. Run it from the repository root:

```sh
swift scripts/render_icon.swift
```

The current icon uses an asset catalog so the deployment target remains macOS 14. Its transparent outer padding and enclosed shape are the flattened macOS treatment. Apple currently accepts [asset catalogs or Icon Composer](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon). A native layered Icon Composer rendition can be prepared from the original vector shapes after visual testing on supported systems; the asset-catalog build is not evidence of testing all Liquid Glass appearance variants.

Source artwork is 1024 × 1024. Generated PNG slots cover 16, 32, 128, 256 and 512 points, each at 1× and 2×. The largest PNG is 1024 × 1024; colors are explicitly sRGB. The checked-in files are compiled by Xcode as the app's `AppIcon` resource. The renderer is authoring tooling and is not linked into NoteHush.

Review the compiled icon in Dock, Finder, About, light/dark appearance and reduced-transparency modes on the supported OS versions before completing issue #15. Generating or inspecting the artwork alone does not satisfy those runtime checks.
