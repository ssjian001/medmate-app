#!/bin/bash
# MedMate 构建脚本: 首次用先跑 setup
set -e
export PATH="$HOME/dev/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/dev/android-sdk"
cd ~/dev/medmate

case "${1:-apk}" in
  setup)
    flutter config --android-sdk "$ANDROID_HOME"
    flutter doctor
    flutter pub get
    ;;
  apk)
    flutter build apk --release
    echo "✓ APK: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  debug)
    flutter build apk --debug
    ;;
esac
