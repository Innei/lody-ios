# Aqua

`Aqua.icon` is an alternate iOS Icon Composer icon. Its transparent character
foreground comes from the supplied `Weixin Image_20260920210657_818_478.png`;
Icon Composer supplies the background, lighting, shadow and Liquid Glass effects.
Open the package in Icon Composer to edit it. `withLodyIcons.js` registers it with
Xcode; the primary icon remains `assets/icon.png`.

The foreground was extracted with the built-in imagegen tool using this prompt:

> Use case: background-extraction. Edit target: provided square blue-haired
> character image. Remove only the black background and make it genuinely
> transparent (PNG alpha), including black gaps beside hair. Preserve the exact
> original illustration, face, colors, hair silhouette, scale and square cropping;
> do not redraw or invent details, do not add shadows, glass effects, borders or
> text. This will be the foreground layer in Apple Icon Composer; glass rendering
> happens there. Output 1024x1024 transparent PNG.

The generated foreground is 1254 × 1254; its Composer layer scale fits it to the
1024 pt canvas. The `.icon` package is the source asset, not a flattened preview.

## Settings previews

The app-icon grid and Settings thumbnail share `AppIconPreview-*` image sets in
LodyKit's `Icons.xcassets`. Aqua previews include the actual Composer background,
lighting and glass, with separate Default and Dark renditions. Regenerate them
after editing `Aqua.icon` (from the repository root):

```sh
icon_tool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
preview_dir=apps/mobile/modules/lody-kit/ios/Icons.xcassets
"$icon_tool" apps/mobile/assets/icons/Aqua.icon --export-image --output-file "$preview_dir/AppIconPreview-Aqua.imageset/default.png" --platform iOS --rendition Default --width 256 --height 256 --scale 1
"$icon_tool" apps/mobile/assets/icons/Aqua.icon --export-image --output-file "$preview_dir/AppIconPreview-Aqua.imageset/dark.png" --platform iOS --rendition Dark --width 256 --height 256 --scale 1
cp apps/mobile/assets/icon.png "$preview_dir/AppIconPreview-default.imageset/default.png"
```
