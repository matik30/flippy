import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'colors.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _kKey = 'app_theme_key';
  ThemeData _theme;
  String _key;

  ThemeNotifier(this._theme, this._key);

  ThemeData get theme => _theme;
  String get key => _key;

  Future<void> setThemeByKey(String k) async {
    _key = k;
    _theme = _themeFromKey(k);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, k);
  }

  static ThemeData _themeFromKey(String k) {
    switch (k) {
      case 'red':
        return _themeFromStaticColors(
          textColor: AppColorsRed.text,
          primary: AppColorsRed.primary,
          background: AppColorsRed.background,
          accent: AppColorsRed.accent,
        );
      case 'green':
        return _themeFromStaticColors(
          textColor: AppColorsGreen.text,
          primary: AppColorsGreen.primary,
          background: AppColorsGreen.background,
          accent: AppColorsGreen.accent,
        );
      case 'orange':
        return _themeFromStaticColors(
          textColor: AppColorsOrange.text,
          primary: AppColorsOrange.primary,
          background: AppColorsOrange.background,
          accent: AppColorsOrange.accent,
        );
      case 'turq':
        return _themeFromStaticColors(
          textColor: AppColorsTurquise.text,
          primary: AppColorsTurquise.primary,
          background: AppColorsTurquise.background,
          accent: AppColorsTurquise.accent,
        );
      case 'blue':
      default:
        return _themeFromStaticColors(
          textColor: AppColors.text,
          primary: AppColors.primary,
          background: AppColors.background,
          accent: AppColors.accent,
        );
    }
  }

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

  static Future<ThemeNotifier> create() async {
    final prefs = await SharedPreferences.getInstance();
    final k = prefs.getString(_kKey) ?? 'blue';
    return ThemeNotifier(_themeFromKey(k), k);
  }
}
