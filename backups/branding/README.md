# Logo backup

Documentation checked on 2026-09-20. This directory records historical branding
backups; it is not the source of the current generated application icons.

`2026-09-07-before-logo-replacement.zip` contains the 49 original branding
files, including SVG sources, platform icons, launch images, TV banners,
HTML previews, the Flutter logo widget, and both export scripts.

The ZIP is a local historical artifact covered by the repository's `*.zip`
ignore rule, so it may not exist in a clean clone. Its absence does not prevent
building the application. The 49-file count describes that original archive,
not the current repository resource count.

Paths inside the archive are relative to the repository root. Extract to a
temporary directory first and restore only the files you need. These assets
are archived outside `assets/` so they are not bundled with the application.

The current source is `assets/branding/starflow_logo_source.png`, copied
unchanged from `ChatGPT Image 2026年9月7日 20_58_28.png`. This later replacement
did not create an additional backup; the original archive remains unchanged.

The separate current iOS dark-icon source is
`assets/branding/starflow_ios_dark_icon_source.png`. Both paths are relative to
the repository root. Use [the shared generator](../../tool/generate_brand_assets.py)
to update platform exports; the old Swift entry point delegates to this Python
script. Python with Pillow and Microsoft Edge for the TV banner are required.

Do not restore this whole archive over unrelated code changes. Brand HTML
previews are not the source for current app-icon pixels; the PNG masters are.
Native launch screens currently show only a dark background, while the Flutter
startup page uses the generated launch logo. See the
[iOS launch resource notes](../../ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md)
and [root branding guide](../../README.md#品牌资源).

This documentation update did not extract, create or replace a backup archive
and did not regenerate any image assets.
