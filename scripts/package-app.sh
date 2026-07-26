#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
build_dir="$repo_root/.build"
app_dir="$build_dir/CodexMic.app"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
staging_app="$staging_dir/CodexMic.app"
contents_dir="$staging_app/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

cd "$repo_root"
swift build --disable-sandbox

if [[ -d "$app_dir" ]]; then
  rm -rf "$app_dir"
fi
mkdir -p "$macos_dir" "$resources_dir"
cp -X "$build_dir/debug/CodexMic" "$macos_dir/CodexMic"
cp -X "$repo_root/support/Info.plist" "$contents_dir/Info.plist"
cp -X "$repo_root/support/codex-micro-lighting-service.js" "$resources_dir/"
xattr -cr "$staging_app"
codesign --force --deep --sign - "$staging_app"
codesign --verify --deep --strict "$staging_app"
ditto --norsrc "$staging_app" "$app_dir"
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
