import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'screens/stats_screen.dart';
import 'services/shopping_monitor_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ShoppingMonitorService.instance.init();
  runApp(const SugarControlApp());
}

class SugarControlApp extends StatelessWidget {
  const SugarControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '糖迹',
      theme: buildAppTheme(),
      home: const _RootNav(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _RootNav extends StatefulWidget {
  const _RootNav();

  @override
  State<_RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<_RootNav> {
  int _index = 0;
  // Increment to trigger a data refresh on the stats screen
  final _statsRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _statsRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ChatScreen(),
          StatsScreen(refreshNotifier: _statsRefresh),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) {
          setState(() => _index = i);
          // Refresh stats data every time user taps the stats tab
          if (i == 1) _statsRefresh.value++;
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: '问一问',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: '摄入统计',
          ),
        ],
      ),
    );
  }
}
