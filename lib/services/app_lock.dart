/// 隐私锁: 启动时生物识别/PIN（local_auth）
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class AppLock {
  AppLock._();
  static final AppLock instance = AppLock._();
  final _auth = LocalAuthentication();
  bool _unlocked = false; // 本次运行已解锁则不再烦

  /// 返回 true = 已解锁可看数据; false = 认证失败/取消, 调用方应挡住数据
  Future<bool> ensureUnlocked() async {
    if (_unlocked) return true;
    try {
      // 只看 isDeviceSupported: getAvailableBiometrics 只列已录入的生物特征,
      // 只设了 PIN/图案锁的设备会被误判成"无凭据"而绕过隐私锁
      if (!await _auth.isDeviceSupported()) {
        _unlocked = true; // 设备无锁屏凭据 → 不拦截（可后续加 PIN）
        return true;
      }
      _unlocked = await _auth.authenticate(
        localizedReason: '解锁 MedMate 查看服药记录',
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true),
      );
      return _unlocked;
    } on PlatformException {
      _unlocked = true; // 认证器异常别把用户锁在门外
      return true;
    }
  }

  void markUnlocked() => _unlocked = true;
}
