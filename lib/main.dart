import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'pages/devices_and_cameras_page.dart';
import 'pages/access_control_page.dart';
import 'pages/security_settings_page.dart';

import 'services/auth_service.dart';
import 'services/onvif_playback_service.dart';

import 'dart:io' show Platform;

void main() async {
  // Garante que os canais de plataforma estejam prontos antes de registrar o plugin
  WidgetsFlutterBinding.ensureInitialized();

  // Registrar o fvp ANTES de qualquer VideoPlayerController ser criado
  try {
    if (Platform.isAndroid) {
      fvp.registerWith(options: {
        // lowLatency removido para evitar o caminho de áudio OpenSL ES de baixa latência (gera o warning SL_RESULT_FEATURE_UNSUPPORTED)
        'fastSeek': true,
      });
    }
  } catch (e) {
    // Não deixar que uma exceção aqui impeça o app de continuar
    // Você poderá verificar logs depois para ajustar as opções do player
    // ignore: avoid_print
    print('fvp.registerWith falhou: $e');
  }

  // Inicializa preferências do PlaybackService (HTTPS autoassinado)
  await OnvifPlaybackService.initFromPrefs();

  // Sobe a UI depois do registro do fvp
  runApp(const SecurityCameraApp());
}

class SecurityCameraApp extends StatelessWidget {
  const SecurityCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Security Camera App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        primaryColor: const Color(0xFF2D2D2D),
        cardColor: const Color(0xFF2D2D2D),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isAuthenticated = false;

  final List<Widget> _screens = const [
    DevicesAndCamerasScreen(),
    AccessControlScreen(),
    SecuritySettingsScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }
  
  Future<void> _checkAuthStatus() async {
    final isAuth = await AuthService.instance.isAuthenticated();
    setState(() {
      _isAuthenticated = isAuth;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.security, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              '',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const Spacer(),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
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
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.settings),
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
            label: 'Configurações',
          ),
        ],
      ),
    );
  }
}
