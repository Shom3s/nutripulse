import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NutriThemeMode { normal, premiumDark }

extension NutriThemeModeX on NutriThemeMode {
  String get storageKey {
    switch (this) {
      case NutriThemeMode.normal:
        return 'normal';
      case NutriThemeMode.premiumDark:
        return 'premiumDark';
    }
  }

  String get title {
    switch (this) {
      case NutriThemeMode.normal:
        return 'Normal Mode';
      case NutriThemeMode.premiumDark:
        return 'Premium Dark';
    }
  }

  String get subtitle {
    switch (this) {
      case NutriThemeMode.normal:
        return 'Current NutriPulse style';
      case NutriThemeMode.premiumDark:
        return 'Sample-style glass dashboard';
    }
  }

  IconData get icon {
    switch (this) {
      case NutriThemeMode.normal:
        return Icons.palette_rounded;
      case NutriThemeMode.premiumDark:
        return Icons.dark_mode_rounded;
    }
  }
}

class NutriPalette {
  final Color bg;
  final Color topGradient;
  final Color bottomGradient;
  final Color card;
  final Color card2;
  final Color text;
  final Color subText;
  final Color lime;
  final Color border;
  final Color navBg;
  final Color navIcon;
  final Color selectedIcon;
  final Color graphBg;
  final Color glow;
  final Brightness brightness;

  const NutriPalette({
    required this.bg,
    required this.topGradient,
    required this.bottomGradient,
    required this.card,
    required this.card2,
    required this.text,
    required this.subText,
    required this.lime,
    required this.border,
    required this.navBg,
    required this.navIcon,
    required this.selectedIcon,
    required this.graphBg,
    required this.glow,
    required this.brightness,
  });

  static const normal = NutriPalette(
    bg: Color(0xFF0F140D),
    topGradient: Color(0xFF2A3A18),
    bottomGradient: Color(0xFF070907),
    card: Color(0xFF1A1F17),
    card2: Color(0xFF23291F),
    text: Colors.white,
    subText: Color(0xFFB7C2A8),
    lime: Color(0xFFD6FF60),
    border: Color(0x26FFFFFF),
    navBg: Color(0xFF121712),
    navIcon: Color(0xFFB7C2A8),
    selectedIcon: Color(0xFF171C12),
    graphBg: Color(0xFF10150D),
    glow: Color(0xFFD6FF60),
    brightness: Brightness.dark,
  );

  static const premiumDark = NutriPalette(
    bg: Color(0xFF050704),
    topGradient: Color(0xFF11170D),
    bottomGradient: Color(0xFF010201),
    card: Color(0xFF10140E),
    card2: Color(0xFF1A2116),
    text: Colors.white,
    subText: Color(0xFFC8D3BD),
    lime: Color(0xFFD6FF28),
    border: Color(0x22FFFFFF),
    navBg: Color(0xE6111510),
    navIcon: Color(0xFFE8EDE2),
    selectedIcon: Color(0xFF10140C),
    graphBg: Color(0xFF070A06),
    glow: Color(0xFFD6FF28),
    brightness: Brightness.dark,
  );
}

class NutriThemeController extends ChangeNotifier {
  static const String prefKey = 'nutripulse_theme_mode';

  NutriThemeMode _mode = NutriThemeMode.normal;

  NutriThemeMode get mode => _mode;

  NutriPalette get palette {
    switch (_mode) {
      case NutriThemeMode.normal:
        return NutriPalette.normal;
      case NutriThemeMode.premiumDark:
        return NutriPalette.premiumDark;
    }
  }

  bool get isPremiumDark => _mode == NutriThemeMode.premiumDark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefKey);

    // Old users may have saved "light" before. Move them safely back to Normal.
    if (saved == NutriThemeMode.premiumDark.storageKey) {
      _mode = NutriThemeMode.premiumDark;
    } else {
      _mode = NutriThemeMode.normal;
      if (saved == 'light') {
        await prefs.setString(prefKey, NutriThemeMode.normal.storageKey);
      }
    }

    notifyListeners();
  }

  Future<void> setMode(NutriThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, mode.storageKey);
  }

  ThemeData materialTheme() {
    final p = palette;
    final scheme = ColorScheme.fromSeed(
      seedColor: p.lime,
      brightness: Brightness.dark,
    ).copyWith(primary: p.lime, surface: p.card, onSurface: p.text);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: p.bg,
      primaryColor: p.lime,
      textTheme: Typography.material2021(
        platform: TargetPlatform.android,
        colorScheme: scheme,
      ).white,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.navBg,
        selectedItemColor: p.lime,
        unselectedItemColor: p.navIcon,
      ),
    );
  }
}

final NutriThemeController nutriThemeController = NutriThemeController();
