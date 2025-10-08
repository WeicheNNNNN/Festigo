import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'starred_festivals.dart';
import 'local_festivals.dart';
import 'list_festivals.dart';
import 'custom_organizer.dart';
import 'user_timetable.dart';
import 'settings_screen.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://kxgpxtnhdtkgcqvebtlf.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt4Z3B4dG5oZHRrZ2NxdmVidGxmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk5MjI0NzYsImV4cCI6MjA3NTQ5ODQ3Nn0.5yde3mqDyNiJUCe_XrEYYEZJbxDqaEssiT9ciw6BL34',
  );
  runApp(const MusicFestApp());
}

class MusicFestApp extends StatelessWidget {
  const MusicFestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '音樂祭時間表',
      theme: ThemeData(
        primaryColor: const Color.fromARGB(255, 40, 60, 70),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 40, 60, 70),
        ),
      ),
      home: const MainNavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final Map<String, dynamic>? initialTimetableFestival;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.initialTimetableFestival,
  });
  final int initialIndex;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late int _currentIndex;
  // ignore: unused_field
  bool _unlockedOrganizer = false;

  final List<Widget> _pages = const [
    FestivalListScreen(),
    StarredFestivalsScreen(),
    LocalFestivalsScreen(),
    CustomOrganizerScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // 若開機指定要顯示某個音樂祭時間表
    if (widget.initialTimetableFestival != null) {
      Future.microtask(() {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => UserTimetableScreen(
                  festival: widget.initialTimetableFestival!,
                ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      setState(() => _unlockedOrganizer = false);
    }
  }

  void _onTabTapped(int index) async {
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 主內容頁面
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _pages,
          ),

          // 浮動 BottomNavigationBar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white,
              child: BottomNavigationBar(
                backgroundColor: const Color.fromARGB(255, 40, 60, 70),
                currentIndex: _currentIndex,
                onTap: _onTabTapped,
                type: BottomNavigationBarType.fixed,
                selectedFontSize: 12,
                selectedIconTheme: const IconThemeData(size: 38),
                selectedItemColor: const Color.fromARGB(255, 231, 190, 123),
                unselectedFontSize: 12,
                unselectedIconTheme: const IconThemeData(size: 28),
                unselectedItemColor: const Color.fromARGB(150, 231, 190, 123),

                showSelectedLabels: false,
                showUnselectedLabels: false,

                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.star),
                    label: '已加星號',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.list_alt_outlined),
                    label: '自定義清單',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.edit),
                    label: '自定義模式',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings),
                    label: '設定',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
