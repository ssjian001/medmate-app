# MedMate 服药助手

本地优先的 Android 服药记录与提醒应用（Flutter）。

## 功能
- 💊 药物管理：名称/剂量/每日多时间点/备注/颜色标
- ⏰ 今日时间轴：一键打卡、跳过、撤销；过时红色标识
- 🔔 提醒：每日定时通知 + 漏服检测(30min) + 开机重建 + 点击直达 App
- 📅 日历热图：月历绿/橙/红打卡热图 + 单日详情
- 📦 库存管理：打卡自动扣减，余量不足 3 天量提醒补药
- 📊 统计：今日/7天/30天进度环 + 按药物分组依从率
- 📤 CSV 导出：打卡记录分享（Excel 友好 BOM-UTF8）
- 🔐 隐私锁：生物识别/锁屏凭据（local_auth）
- 🌙 深色模式跟随系统

## 技术
Flutter 3.35 · sqflite(本地存储,隐私不上云) · flutter_local_notifications · local_auth

## 构建
```bash
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

## 隐私
所有数据仅存于设备本地 SQLite，无任何网络权限上传。

## License
MIT
