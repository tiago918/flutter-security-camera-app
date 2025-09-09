import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/theme_service.dart';
import 'services/camera_service.dart';
import 'services/notification_service.dart';
import 'services/ptz_service.dart';
import 'services/motion_detection_service.dart';
import 'services/night_mode_service.dart';
import 'services/recording_service.dart';
import 'services/logging_service.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart';
import 'pages/devices_and_cameras_page.dart';
import 'pages/access_control_page.dart';
import 'pages/security_settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize FVP first - CRITICAL for video playback
    fvp.registerWith();
    
    // Initialize logging service
    await LoggingService.instance.initialize();
    LoggingService.instance.info('App iniciado - Inicializando serviços');
    LoggingService.instance.info('FVP registrado com sucesso');
    
    // Initialize SharedPreferences
    await SharedPreferences.getInstance();
    LoggingService.instance.info('SharedPreferences inicializado');
    
    // Inicializar serviços
    // CameraService será inicializado quando necessário
    
    // Initialize notification service
    NotificationService.instance.initialize();
    LoggingService.instance.info('NotificationService inicializado');
    
    LoggingService.instance.info('Todos os serviços inicializados com sucesso');
    runApp(const SecurityCameraApp());
  } catch (e) {
    LoggingService.instance.error('Erro na inicialização: $e');
    debugPrint('Initialization error: $e');
    runApp(const SecurityCameraApp());
  }
}

class SecurityCameraApp extends StatelessWidget {
  const SecurityCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ThemeService.instance..initialize()),
        Provider.value(value: CameraService()),
        Provider.value(value: NotificationService.instance),
        Provider.value(value: PTZService()),
        Provider.value(value: MotionDetectionService()),
        Provider.value(value: NightModeService()),
        Provider.value(value: RecordingService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'Security Camera App',
            debugShowCheckedModeBanner: false,
            theme: themeService.getLightTheme(),
            darkTheme: themeService.getDarkTheme(),
            themeMode: themeService.themeMode,
            home: const AppMainScreen(),
          );
        },
      ),
    );
  }
}

class AppMainScreen extends StatefulWidget {
  const AppMainScreen({super.key});

  @override
  State<AppMainScreen> createState() => _AppMainScreenState();
}

class _AppMainScreenState extends State<AppMainScreen> {
  int _selectedIndex = 0;
  bool _isAuthenticated = false;

  final List<Widget> _screens = const [
    DevicesAndCamerasScreen(), // Página de câmeras como principal
    AccessControlScreen(),
    SettingsScreen(), // Nova tela de configurações
  ];
  
  @override
  void initState() {
    super.initState();
    // Authentication check can be added here if needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Câmeras',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.security),
                if (!_isAuthenticated)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Acesso',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Configurações',
          ),
        ],
      ),
    );
  }
}
