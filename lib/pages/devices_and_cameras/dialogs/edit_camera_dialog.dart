import 'package:flutter/material.dart';
import 'package:security_camera_app/models/camera_models.dart';
import '../widgets/port_configuration_widget.dart';

class EditCameraDialogResult {
  final String name;
  final String host;
  final String port; // keep as text to allow validation before parsing
  final String username;
  final String password;
  final String transport; // 'tcp' or 'udp'
  final bool acceptSelfSigned;
  final CameraPortConfiguration? portConfiguration;

  EditCameraDialogResult({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.transport,
    required this.acceptSelfSigned,
    required this.portConfiguration,
  });
}

Future<void> showEditCameraDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  required String initialHost,
  required String initialPort,
  required String? initialUsername,
  required String? initialPassword,
  required String initialTransport,
  required bool initialAcceptSelfSigned,
  CameraPortConfiguration? initialPortConfiguration,
  required void Function(EditCameraDialogResult result) onSave,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: initialName);
  final urlController = TextEditingController(text: initialHost);
  final portController = TextEditingController(text: initialPort);
  final userController = TextEditingController(text: initialUsername ?? '');
  final passController = TextEditingController(text: initialPassword ?? '');
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
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Informe um nome';
                      return null;
                    },
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
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Porta (padrão 554)',
                      labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null; // vazio -> usaremos 554
                      final n = int.tryParse(v.trim());
                      if (n == null || n <= 0 || n > 65535) return 'Porta inválida';
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
                    EditCameraDialogResult(
                      name: nameController.text.trim(),
                      host: urlController.text.trim(),
                      port: portController.text.trim().isEmpty ? '554' : portController.text.trim(),
                      username: userController.text.trim(),
                      password: passController.text.trim(),
                      transport: selectedTransport.value,
                      acceptSelfSigned: acceptSelfSigned,
                      portConfiguration: portConfiguration,
                    ),
                  );
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    ),
  );
}