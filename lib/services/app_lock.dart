/// 隐私锁: 启动时生物识别/PIN（local_auth）
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class AppLock {
  AppLock._();
  static final AppLock instance = AppLock._();
  final _auth = LocalAuthentication();
  bool _unlocked = false; // 本次运行已解锁则不再烦

  Future<void> ensureUnlocked() async {
    if (_unlocked) return;
    try {
      final can = await _auth.getAvailableBiometrics();
      final canCheck = await _auth.isDeviceSupported();
      if (canCheck && can.isNotEmpty) {
        _unlocked = await _auth.authenticate(
          localizedReason: '解锁 MedMate 查看服药记录',
          options: const AuthenticationOptions(
              biometricOnly: false, stickyAuth: true),
        );
      } else {
        _unlocked = true; // 设备无锁屏凭据 → 不拦截（可后续加 PIN）
      }
    } on PlatformException {
      _unlocked = true; // 认证器异常别把用户锁在门外
    }
  }

  void markUnlocked() => _unlocked = true;
}
