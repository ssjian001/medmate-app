#!/bin/bash
# MedMate 构建与发布脚本
# 用法: ./build.sh [apk|debug|setup|install|release vX.Y.Z "说明"]
set -e
export PATH="$HOME/dev/flutter/bin:$HOME/dev/android-sdk/platform-tools:$PATH"
export ANDROID_HOME="$HOME/dev/android-sdk"
export JAVA_HOME="$HOME/tools/jdk-21.0.12.1+1"
cd ~/dev/medmate

do_setup() {
  flutter config --android-sdk "$ANDROID_HOME"
  flutter doctor
  flutter pub get
}

do_apk() {
  flutter build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk MedMate_latest.apk
  echo "✓ APK: MedMate_latest.apk"
}

do_release() {
  [ -z "$1" ] && { echo "用法: ./build.sh release vX.Y.Z \"说明\""; exit 1; }
  local TAG="$1"; shift
  local NOTES="${1:-MedMate $TAG}"
  flutter build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk "MedMate_${TAG}.apk"
  gh release create "$TAG" "MedMate_${TAG}.apk" \
    --title "MedMate $TAG" --notes "$NOTES" \
    && echo "✓ 发布: https://github.com/ssjian001/medmate-app/releases/tag/$TAG"
}

case "${1:-apk}" in
  setup)   do_setup ;;
  apk)     do_apk ;;
  debug)   flutter build apk --debug ;;
  install) do_apk && adb install -r MedMate_latest.apk ;;
  release) shift; do_release "$@" ;;
  *) echo "用法: ./build.sh [apk|debug|setup|install|release vX.Y.Z \"说明\"]" ;;
esac
