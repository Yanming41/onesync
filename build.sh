#!/bin/zsh
# 编译并打包成 OneSync.app并签名，装到 ~/Applications
set -e
cd "$(dirname "$0")"
BUNDLE_ID=${BUNDLE_ID:-io.github.onesync}
# 签名身份：优先用环境变量 SIGN_IDENTITY；否则找 scripts/make-signing-cert.sh 生成的「OneSync Local Signing」；都没有就 ad-hoc
SIGN_IDENTITY=${SIGN_IDENTITY:-}
swift build -c release
APP=build/OneSync.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/OneSync $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>OneSync</string>
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundleExecutable</key><string>OneSync</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
S=~/.onesync-signing
if [ -z "$SIGN_IDENTITY" ] && [ -f $S/signing.keychain-db ]; then
  security unlock-keychain -p "$(cat $S/kc.pass)" $S/signing.keychain-db
  SIGN_IDENTITY="OneSync Local Signing"
fi
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force -s "$SIGN_IDENTITY" $APP
else
  echo "warning: ad-hoc 签名，每次重新编译后钥匙串里的密码需要重输（见 README）"
  codesign --force -s - $APP
fi
mkdir -p ~/Applications && rm -rf ~/Applications/OneSync.app && cp -R $APP ~/Applications/
echo "installed ~/Applications/OneSync.app"
