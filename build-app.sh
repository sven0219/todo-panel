#!/bin/bash
# 构建并打包 TodoPanel.app（菜单栏应用，无 Dock 图标）
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/TodoPanel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/TodoPanel "$APP/Contents/MacOS/TodoPanel"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>TodoPanel</string>
	<key>CFBundleIdentifier</key>
	<string>com.todopanel.app</string>
	<key>CFBundleName</key>
	<string>TodoPanel</string>
	<key>CFBundleDisplayName</key>
	<string>TodoPanel</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.7</string>
	<key>CFBundleVersion</key>
	<string>7</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true

echo "打包完成: $APP"
