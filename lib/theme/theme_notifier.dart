import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'colors.dart';

// Interná trieda reprezentujúca farebnú paletu (top-level, const konštruktor).
class _Palette {
  final Color text;
  final Color primary;
  final Color background;
  final Color accent;
  const _Palette({required this.text, required this.primary, required this.background, required this.accent});
}

// Mapovanie kľúča témy na paletu farieb (používa definície z colors.dart)
const Map<String, _Palette> _palettes = {
  'blue': _Palette(text: AppColors.text, primary: AppColors.primary, background: AppColors.background, accent: AppColors.accent),
  'red': _Palette(text: AppColorsRed.text, primary: AppColorsRed.primary, background: AppColorsRed.background, accent: AppColorsRed.accent),
  'green': _Palette(text: AppColorsGreen.text, primary: AppColorsGreen.primary, background: AppColorsGreen.background, accent: AppColorsGreen.accent),
  'orange': _Palette(text: AppColorsOrange.text, primary: AppColorsOrange.primary, background: AppColorsOrange.background, accent: AppColorsOrange.accent),
  'turq': _Palette(text: AppColorsTurquise.text, primary: AppColorsTurquise.primary, background: AppColorsTurquise.background, accent: AppColorsTurquise.accent),
};

// Spravuje tému aplikácie — prepína farebné motívy a ukladá výber používateľa.
class ThemeNotifier extends ChangeNotifier {
  static const _kKey = 'app_theme_key';
  ThemeData _theme;
  String _key;

  ThemeNotifier(this._theme, this._key);

  ThemeData get theme => _theme;
  String get key => _key;

  Future<void> setThemeByKey(String k) async {
    // Nastaví tému podľa poskytnutého kľúča, notifikuj odberateľov a ulož vybraný kľúč do SharedPreferences.
    _key = k;
    _theme = _themeFromKey(k);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, k);
  }

  // Vracia ThemeData pre daný názov témy (kľúč), používa palety z _palettes.
  static ThemeData _themeFromKey(String k) {
    final pal = _palettes[k] ?? _palettes['blue']!;
    return _themeFromStaticColors(
      textColor: pal.text,
      primary: pal.primary,
      background: pal.background,
      accent: pal.accent,
    );
  }

  // Vytvorí ThemeData z konkrétnych farieb (text, primary, background, accent).
  static ThemeData _themeFromStaticColors({
    required Color textColor,
    required Color primary,
    required Color background,
    required Color accent,
  }) {
    final base = ThemeData.light();

    return base.copyWith(
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: accent,
        surface: background,
        brightness: Brightness.light,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        iconTheme: IconThemeData(color: textColor),
      ),
      textTheme: base.textTheme.apply(bodyColor: textColor, displayColor: textColor),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: background,
      ),
    );
  }

  // Vytvorí inštanciu ThemeNotifier načítaním uloženého kľúča z prefs.
  static Future<ThemeNotifier> create() async {
    final prefs = await SharedPreferences.getInstance();
    final k = prefs.getString(_kKey) ?? 'blue';
    return ThemeNotifier(_themeFromKey(k), k);
  }
}
