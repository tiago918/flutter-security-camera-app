import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';
  static const String _cameraColorsKey = 'camera_colors';
  static const String _accentColorKey = 'accent_color';
  static const String _customThemeKey = 'custom_theme_settings';

  // Singleton instance
  static ThemeService? _instance;
  static ThemeService get instance {
    _instance ??= ThemeService._internal();
    return _instance!;
  }

  ThemeService._internal();

  ThemeMode _themeMode = ThemeMode.system;
  Map<String, Color> _cameraColors = {};
  Color _accentColor = Colors.blue;
  CustomThemeSettings _customSettings = CustomThemeSettings();

  ThemeMode get themeMode => _themeMode;
  Map<String, Color> get cameraColors => Map.unmodifiable(_cameraColors);
  Color get accentColor => _accentColor;
  CustomThemeSettings get customSettings => _customSettings;

  // Predefined camera colors
  static const List<Color> predefinedColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Colors.amber,
    Colors.cyan,
    Colors.lime,
    Colors.deepOrange,
  ];

  // Initialize theme service
  Future<void> initialize() async {
    await _loadThemeMode();
    await _loadCameraColors();
    await _loadAccentColor();
    await _loadCustomSettings();
  }

  // Theme mode management
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _saveThemeMode();
  }

  Future<void> setDarkMode(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _saveThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt(_themeKey) ?? 0;
      _themeMode = ThemeMode.values[modeIndex];
    } catch (e) {
      _themeMode = ThemeMode.system;
    }
  }

  Future<void> _saveThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, _themeMode.index);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  // Camera colors management
  Color getCameraColor(String cameraId) {
    return _cameraColors[cameraId] ?? _getDefaultColorForCamera(cameraId);
  }

  Future<void> setCameraColor(String cameraId, Color color) async {
    _cameraColors[cameraId] = color;
    notifyListeners();
    await _saveCameraColors();
  }

  Future<void> removeCameraColor(String cameraId) async {
    _cameraColors.remove(cameraId);
    notifyListeners();
    await _saveCameraColors();
  }

  Color _getDefaultColorForCamera(String cameraId) {
    final hash = cameraId.hashCode;
    return predefinedColors[hash.abs() % predefinedColors.length];
  }

  Future<void> _loadCameraColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorsJson = prefs.getString(_cameraColorsKey);
      if (colorsJson != null) {
        final Map<String, dynamic> colorsMap = json.decode(colorsJson);
        _cameraColors = colorsMap.map(
          (key, value) => MapEntry(key, Color(value as int)),
        );
      }
    } catch (e) {
      debugPrint('Error loading camera colors: $e');
      _cameraColors = {};
    }
  }

  Future<void> _saveCameraColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorsMap = _cameraColors.map(
        (key, value) => MapEntry(key, value.value),
      );
      await prefs.setString(_cameraColorsKey, json.encode(colorsMap));
    } catch (e) {
      debugPrint('Error saving camera colors: $e');
    }
  }

  // Accent color management
  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    notifyListeners();
    await _saveAccentColor();
  }

  Future<void> _loadAccentColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorValue = prefs.getInt(_accentColorKey);
      if (colorValue != null) {
        _accentColor = Color(colorValue);
      }
    } catch (e) {
      debugPrint('Error loading accent color: $e');
      _accentColor = Colors.blue;
    }
  }

  Future<void> _saveAccentColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_accentColorKey, _accentColor.value);
    } catch (e) {
      debugPrint('Error saving accent color: $e');
    }
  }

  // Custom theme settings
  Future<void> updateCustomSettings(CustomThemeSettings settings) async {
    _customSettings = settings;
    notifyListeners();
    await _saveCustomSettings();
  }

  Future<void> _loadCustomSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_customThemeKey);
      if (settingsJson != null) {
        final Map<String, dynamic> settingsMap = json.decode(settingsJson);
        _customSettings = CustomThemeSettings.fromJson(settingsMap);
      }
    } catch (e) {
      debugPrint('Error loading custom settings: $e');
      _customSettings = CustomThemeSettings();
    }
  }

  Future<void> _saveCustomSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customThemeKey, json.encode(_customSettings.toJson()));
    } catch (e) {
      debugPrint('Error saving custom settings: $e');
    }
  }

  // Theme data generation
  ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accentColor,
        brightness: Brightness.light,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _customSettings.useCustomAppBar 
            ? _customSettings.appBarColor 
            : null,
        foregroundColor: _customSettings.useCustomAppBar 
            ? _customSettings.appBarTextColor 
            : null,
        elevation: _customSettings.appBarElevation,
      ),
      cardTheme: CardThemeData(
        elevation: _customSettings.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_customSettings.borderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_customSettings.borderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_customSettings.borderRadius),
        ),
      ),
    );
  }

  ThemeData getDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accentColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _customSettings.useCustomAppBar 
            ? _customSettings.darkAppBarColor 
            : null,
        foregroundColor: _customSettings.useCustomAppBar 
            ? _customSettings.darkAppBarTextColor 
            : null,
        elevation: _customSettings.appBarElevation,
      ),
      cardTheme: CardThemeData(
        elevation: _customSettings.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_customSettings.borderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_customSettings.borderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_customSettings.borderRadius),
        ),
      ),
    );
  }

  // Utility methods
  bool get isDarkMode {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  // Reset to defaults
  Future<void> resetToDefaults() async {
    _themeMode = ThemeMode.system;
    _cameraColors.clear();
    _accentColor = Colors.blue;
    _customSettings = CustomThemeSettings();
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_themeKey);
    await prefs.remove(_cameraColorsKey);
    await prefs.remove(_accentColorKey);
    await prefs.remove(_customThemeKey);
  }

  // Export/Import settings
  Map<String, dynamic> exportSettings() {
    return {
      'themeMode': _themeMode.index,
      'cameraColors': _cameraColors.map((k, v) => MapEntry(k, v.value)),
      'accentColor': _accentColor.value,
      'customSettings': _customSettings.toJson(),
    };
  }

  Future<void> importSettings(Map<String, dynamic> settings) async {
    try {
      if (settings.containsKey('themeMode')) {
        _themeMode = ThemeMode.values[settings['themeMode']];
      }
      
      if (settings.containsKey('cameraColors')) {
        final Map<String, dynamic> colors = settings['cameraColors'];
        _cameraColors = colors.map((k, v) => MapEntry(k, Color(v)));
      }
      
      if (settings.containsKey('accentColor')) {
        _accentColor = Color(settings['accentColor']);
      }
      
      if (settings.containsKey('customSettings')) {
        _customSettings = CustomThemeSettings.fromJson(settings['customSettings']);
      }
      
      notifyListeners();
      
      // Save all settings
      await _saveThemeMode();
      await _saveCameraColors();
      await _saveAccentColor();
      await _saveCustomSettings();
    } catch (e) {
      debugPrint('Error importing settings: $e');
    }
  }
}

class CustomThemeSettings {
  final bool useCustomAppBar;
  final Color appBarColor;
  final Color appBarTextColor;
  final Color darkAppBarColor;
  final Color darkAppBarTextColor;
  final double appBarElevation;
  final double cardElevation;
  final double borderRadius;
  final bool useGradients;
  final bool useAnimations;

  const CustomThemeSettings({
    this.useCustomAppBar = false,
    this.appBarColor = Colors.blue,
    this.appBarTextColor = Colors.white,
    this.darkAppBarColor = const Color(0xFF1E1E1E),
    this.darkAppBarTextColor = Colors.white,
    this.appBarElevation = 4.0,
    this.cardElevation = 2.0,
    this.borderRadius = 8.0,
    this.useGradients = false,
    this.useAnimations = true,
  });

  CustomThemeSettings copyWith({
    bool? useCustomAppBar,
    Color? appBarColor,
    Color? appBarTextColor,
    Color? darkAppBarColor,
    Color? darkAppBarTextColor,
    double? appBarElevation,
    double? cardElevation,
    double? borderRadius,
    bool? useGradients,
    bool? useAnimations,
  }) {
    return CustomThemeSettings(
      useCustomAppBar: useCustomAppBar ?? this.useCustomAppBar,
      appBarColor: appBarColor ?? this.appBarColor,
      appBarTextColor: appBarTextColor ?? this.appBarTextColor,
      darkAppBarColor: darkAppBarColor ?? this.darkAppBarColor,
      darkAppBarTextColor: darkAppBarTextColor ?? this.darkAppBarTextColor,
      appBarElevation: appBarElevation ?? this.appBarElevation,
      cardElevation: cardElevation ?? this.cardElevation,
      borderRadius: borderRadius ?? this.borderRadius,
      useGradients: useGradients ?? this.useGradients,
      useAnimations: useAnimations ?? this.useAnimations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'useCustomAppBar': useCustomAppBar,
      'appBarColor': appBarColor.value,
      'appBarTextColor': appBarTextColor.value,
      'darkAppBarColor': darkAppBarColor.value,
      'darkAppBarTextColor': darkAppBarTextColor.value,
      'appBarElevation': appBarElevation,
      'cardElevation': cardElevation,
      'borderRadius': borderRadius,
      'useGradients': useGradients,
      'useAnimations': useAnimations,
    };
  }

  factory CustomThemeSettings.fromJson(Map<String, dynamic> json) {
    return CustomThemeSettings(
      useCustomAppBar: json['useCustomAppBar'] ?? false,
      appBarColor: Color(json['appBarColor'] ?? Colors.blue.value),
      appBarTextColor: Color(json['appBarTextColor'] ?? Colors.white.value),
      darkAppBarColor: Color(json['darkAppBarColor'] ?? const Color(0xFF1E1E1E).value),
      darkAppBarTextColor: Color(json['darkAppBarTextColor'] ?? Colors.white.value),
      appBarElevation: (json['appBarElevation'] ?? 4.0).toDouble(),
      cardElevation: (json['cardElevation'] ?? 2.0).toDouble(),
      borderRadius: (json['borderRadius'] ?? 8.0).toDouble(),
      useGradients: json['useGradients'] ?? false,
      useAnimations: json['useAnimations'] ?? true,
    );
  }
}