import 'package:flutter/material.dart';

import 'pages/today_page.dart';
import 'services/notify.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notify.instance.init();
  runApp(const MedMateApp());
}

class MedMateApp extends StatefulWidget {
  const MedMateApp({super.key});
  @override
  State<MedMateApp> createState() => _MedMateAppState();
}

class _MedMateAppState extends State<MedMateApp> {
  @override
  void initState() {
    super.initState();
    Notify.onNotificationTap = (payload) {
      // 跳回今日页 (payload 为计划时间)
      navKey.currentState?.pushNamedAndRemoveUntil('/', (_) => false);
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      routes: {'/': (_) => const TodayPage()},
      title: 'MedMate 服药助手',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const TodayPage(),
    );
  }
}

/// 全局 Navigator key: 通知点击后跳转用
final navKey = GlobalKey<NavigatorState>();
