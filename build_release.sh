#!/bin/zsh

# Configuration
PROJECT_NAME="NAM Reamp Lab"
SCHEME_NAME="NAM Reamp Lab"
BUILD_DIR="./build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$HOME/Desktop"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

echo "🚀 Starting build for $PROJECT_NAME..."

# Create build directory
mkdir -p "$BUILD_DIR"

# Step 1: Archive
echo "📦 Archiving..."
xcodebuild archive \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

if [ $? -ne 0 ]; then
    echo "❌ Archive failed!"
    exit 1
fi

# Step 2: Create ExportOptions.plist for Development/Copy (since we can't do AppStore/AdHoc easily here)
echo "📝 Creating ExportOptions..."
cat << 'EOP' > "$EXPORT_OPTIONS_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOP

# Note: In a headless environment, 'developer-id' or 'automatic' might fail if no certs are present.
# We can try 'manual' or just copy the .app from the archive if export fails.

# Step 3: Export
echo "Exporting .app..."
# Actually, since this is for a local user, we can just grab the .app from the archive.
APP_PATH=$(find "$ARCHIVE_PATH" -name "*.app" -type d | head -1)

if [ -d "$APP_PATH" ]; then
    echo "✅ Found app at $APP_PATH"
    cp -R "$APP_PATH" "$EXPORT_PATH/"
    echo "🎉 Successfully built and copied to Desktop!"
else
    echo "❌ Could not find .app in archive!"
    exit 1
fi

rm -rf "$BUILD_DIR"
rm build_release.sh
