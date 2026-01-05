import 'dart:async';
import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'app_locale.dart';
import 'app_theme.dart';
import 'config.dart';
import 'features/device/device_tab_page.dart';
import 'features/about/about_page.dart';
import 'features/map/map_page.dart';
import 'features/profile/profile_page.dart';
import 'features/tracks/tracks_page.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(Config.mapboxAccessToken);
  await AppLocale.init();
  await AppTheme.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: AppLocale.locale,
      builder: (context, locale, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: AppTheme.mode,
          builder: (context, themeMode, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Open-red',
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              themeMode: themeMode,
              darkTheme: ThemeData.dark(),
              home: const MainScreen(),
            );
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  final ValueNotifier<int> _activeTabIndex = ValueNotifier<int>(0);

  final List<Widget?> _tabCache = List<Widget?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
    _activeTabIndex.value = _currentIndex;
  }

  @override
  void dispose() {
    _activeTabIndex.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    final next = index.clamp(0, 4);
    if (next == _currentIndex) return;
    setState(() {
      _currentIndex = next;
      _activeTabIndex.value = next;
    });
  }

  Widget _buildTab(int index) {
    final cached = _tabCache[index];
    if (cached != null) return cached;

    late final Widget built;
    switch (index) {
      case 0:
        built = DeviceTabPage(activeTabIndex: _activeTabIndex, tabIndex: 0);
        break;
      case 1:
        built = TracksPage(
          activeTabIndex: _activeTabIndex,
          tabIndex: 1,
          onRequestTab: _selectTab,
        );
        break;
      case 2:
        built = MapPage(
          activeTabIndex: _activeTabIndex,
          tabIndex: 2,
          measurementType: 'radiation',
        );
        break;
      case 3:
        built = const AboutPage();
        break;
      case 4:
        built = const ProfilePage();
        break;
      default:
        built = const SizedBox.shrink();
        break;
    }

    _tabCache[index] = built;
    return built;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(5, _buildTab),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _selectTab,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.bluetooth),
            label: l10n.navDevice,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.route),
            label: l10n.navTracks,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.map),
            label: l10n.navMap,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.info_outline),
            label: l10n.navAbout,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: l10n.navProfile,
          ),
        ],
      ),
    );
  }
}

