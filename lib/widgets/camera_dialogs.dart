import 'package:flutter/material.dart';
import '../models/camera_models.dart';
import '../widgets/port_configuration_widget.dart';

class CameraDialogs {
  /// Mostra diálogo para adicionar nova câmera
  static Future<void> showAddCameraDialog(
    BuildContext context, {
    required Function(String name, String host, String port, String username, String password, String transport, bool acceptSelfSigned, CameraPortConfiguration? portConfiguration) onSave,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final portController = TextEditingController(text: '554');
    final userController = TextEditingController();
    final passController = TextEditingController();
    final selectedTransport = ValueNotifier<String>('tcp');
    bool acceptSelfSigned = false;
    CameraPortConfiguration? portConfiguration;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Adicionar câmera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome da câmera',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'IP ou domínio',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Informe o IP ou domínio';
                        final input = v.trim();
                        final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                        final hostRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
                        if (ipRegex.hasMatch(input) || hostRegex.hasMatch(input)) return null;
                        return 'Informe um IP (ex: 192.168.1.100) ou domínio válido';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: portController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Porta RTSP',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final port = int.tryParse(v.trim());
                        if (port == null || port < 1 || port > 65535) {
                          return 'Porta deve estar entre 1 e 65535';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: userController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Usuário (opcional)',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Senha (opcional)',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: selectedTransport,
                      builder: (context, transport, child) {
                        return DropdownButtonFormField<String>(
                          value: transport,
                          style: const TextStyle(color: Colors.white),
                          dropdownColor: const Color(0xFF2A2A2A),
                          decoration: const InputDecoration(
                            labelText: 'Transporte RTSP',
                            labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                            DropdownMenuItem(value: 'udp', child: Text('UDP')),
                          ],
                          onChanged: (value) {
                            if (value != null) selectedTransport.value = value;
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    PortConfigurationWidget(
                      host: urlController.text.trim(),
                      username: userController.text.trim(),
                      password: passController.text.trim(),
                      initialConfiguration: portConfiguration,
                      onConfigurationChanged: (config) {
                        portConfiguration = config;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Aceitar certificados HTTPS autoassinados', style: TextStyle(color: Colors.white)),
                      value: acceptSelfSigned,
                      onChanged: (value) {
                        setState(() {
                          acceptSelfSigned = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    onSave(
                      nameController.text.trim(),
                      urlController.text.trim(),
                      portController.text.trim(),
                      userController.text.trim(),
                      passController.text.trim(),
                      selectedTransport.value,
                      acceptSelfSigned,
                      portConfiguration,
                    );
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('Adicionar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Mostra diálogo para editar câmera existente
  static Future<void> showEditCameraDialog(
    BuildContext context, {
    required String title,
    required String initialName,
    required String initialHost,
    required String initialPort,
    required String initialUsername,
    required String initialPassword,
    required String initialTransport,
    required bool initialAcceptSelfSigned,
    CameraPortConfiguration? initialPortConfiguration,
    required Function(EditCameraResult result) onSave,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: initialName);
    final urlController = TextEditingController(text: initialHost);
    final portController = TextEditingController(text: initialPort);
    final userController = TextEditingController(text: initialUsername);
    final passController = TextEditingController(text: initialPassword);
    final selectedTransport = ValueNotifier<String>(initialTransport);
    bool acceptSelfSigned = initialAcceptSelfSigned;
    CameraPortConfiguration? portConfiguration = initialPortConfiguration;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome da câmera',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'IP ou domínio',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Informe o IP ou domínio';
                        final input = v.trim();
                        final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                        final hostRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
                        if (ipRegex.hasMatch(input) || hostRegex.hasMatch(input)) return null;
                        return 'Informe um IP (ex: 192.168.1.100) ou domínio válido';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: userController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Usuário (opcional)',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Senha (opcional)',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: selectedTransport,
                      builder: (context, transport, child) {
                        return DropdownButtonFormField<String>(
                          value: transport,
                          style: const TextStyle(color: Colors.white),
                          dropdownColor: const Color(0xFF2A2A2A),
                          decoration: const InputDecoration(
                            labelText: 'Transporte RTSP',
                            labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                            DropdownMenuItem(value: 'udp', child: Text('UDP')),
                          ],
                          onChanged: (value) {
                            if (value != null) selectedTransport.value = value;
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    PortConfigurationWidget(
                      host: urlController.text.trim(),
                      username: userController.text.trim(),
                      password: passController.text.trim(),
                      initialConfiguration: portConfiguration,
                      onConfigurationChanged: (config) {
                        portConfiguration = config;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Aceitar certificados HTTPS autoassinados', style: TextStyle(color: Colors.white)),
                      value: acceptSelfSigned,
                      onChanged: (value) {
                        setState(() {
                          acceptSelfSigned = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    onSave(EditCameraResult(
                      name: nameController.text.trim(),
                      host: urlController.text.trim(),
                      port: portController.text.trim(),
                      username: userController.text.trim(),
                      password: passController.text.trim(),
                      transport: selectedTransport.value,
                      acceptSelfSigned: acceptSelfSigned,
                      portConfiguration: portConfiguration,
                    ));
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Mostra diálogo para credenciais ONVIF
  static Future<OnvifCredentials?> showOnvifCredentialsDialog(
    BuildContext context,
    String deviceName,
  ) async {
    final userController = TextEditingController();
    final passController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return await showDialog<OnvifCredentials?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Credenciais para $deviceName',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Este dispositivo requer autenticação. Informe as credenciais:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: userController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Usuário',
                  labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o usuário' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a senha' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(OnvifCredentials(
                  username: userController.text.trim(),
                  password: passController.text.trim(),
                ));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Conectar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// Mostra diálogo de informações
  static Future<void> showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  /// Mostra diálogo de configurações
  static Future<void> showSettingsDialog(
    BuildContext context, {
    required bool backgroundOnvifDetection,
    required Function(bool) onBackgroundDetectionChanged,
    required VoidCallback onForceCapabilitiesDetection,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Configurações',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Detecção ONVIF em segundo plano',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Detecta automaticamente dispositivos ONVIF na rede',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  value: backgroundOnvifDetection,
                  onChanged: (value) {
                    setState(() {
                      onBackgroundDetectionChanged(value);
                    });
                  },
                  activeColor: const Color(0xFF4CAF50),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onForceCapabilitiesDetection();
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Re-detectar Capacidades ONVIF',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use esta opção se as funcionalidades de gravação não estão aparecendo nas câmeras.',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

/// Classe para resultado da edição de câmera
class EditCameraResult {
  final String name;
  final String host;
  final String port;
  final String username;
  final String password;
  final String transport;
  final bool acceptSelfSigned;
  final CameraPortConfiguration? portConfiguration;

  EditCameraResult({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.transport,
    required this.acceptSelfSigned,
    this.portConfiguration,
  });
}

/// Classe para credenciais ONVIF
class OnvifCredentials {
  final String username;
  final String password;

  OnvifCredentials({
    required this.username,
    required this.password,
  });
}