import 'package:flutter/material.dart';
import '../../../models/camera_models.dart';
import '../../../models/credentials.dart';
import '../../../services/credential_storage_service.dart';
import '../../../services/alternative_url_generator.dart';
import '../../../services/camera_connection_manager.dart';
import '../../../services/integrated_logging_service.dart';
import '../widgets/port_configuration_widget.dart';

class AddCameraDialogResult {
  final String name;
  final String host;
  final String port;
  final String username;
  final String password;
  final String transport;
  final CameraPortConfiguration portConfiguration;
  final Credentials? credentials;
  final List<AlternativeUrl> alternativeUrls;

  AddCameraDialogResult({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.transport,
    required this.portConfiguration,
    this.credentials,
    this.alternativeUrls = const [],
  });
}

Future<AddCameraDialogResult?> showAddCameraDialog(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final urlController = TextEditingController();
  final portController = TextEditingController(text: '554');
  final userController = TextEditingController();
  final passController = TextEditingController();
  final selectedTransport = ValueNotifier<String>('tcp');
  final testingConnection = ValueNotifier<bool>(false);
  final connectionStatus = ValueNotifier<String>('');
  final alternativeUrls = ValueNotifier<List<AlternativeUrl>>([]);
  
  CameraPortConfiguration portConfiguration = CameraPortConfiguration();
  
  final credentialStorage = CredentialStorageService();
  final urlGenerator = AlternativeUrlGenerator();
  final connectionManager = CameraConnectionManager();
  final loggingService = IntegratedLoggingService();
  
  await credentialStorage.initialize();
  await connectionManager.initialize();
  await loggingService.initialize();

  // Função para testar conexão e gerar URLs alternativas
  Future<void> testConnection() async {
    if (urlController.text.isEmpty || userController.text.isEmpty || passController.text.isEmpty) {
      connectionStatus.value = 'Preencha todos os campos obrigatórios';
      return;
    }

    testingConnection.value = true;
    connectionStatus.value = 'Testando conexão...';

    try {
      final credentials = Credentials(
        username: userController.text,
        password: passController.text,
      );

      // Gerar URLs alternativas
      final urls = urlGenerator.generateAlternativeUrls(
        host: urlController.text,
        username: userController.text,
        password: passController.text,
        transport: selectedTransport.value,
      );
      alternativeUrls.value = urls;

      // Testar conexão com a primeira URL
      final result = await connectionManager.testConnection(
        urls.first.url,
        credentials,
      );

      if (result.isSuccess) {
        connectionStatus.value = 'Conexão bem-sucedida!';
      } else {
        connectionStatus.value = 'Falha na conexão: ${result.error}';
      }
    } catch (e) {
      connectionStatus.value = 'Erro: $e';
    } finally {
      testingConnection.value = false;
    }
  }

  return showDialog<AddCameraDialogResult?>(
    context: context,
    builder: (context) {
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
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Porta (RTSP padrão 554)',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null; // opcional
                    final p = int.tryParse(v.trim());
                    if (p == null || p <= 0 || p > 65535) return 'Porta inválida';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // Seção de Credenciais sempre visível
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade50,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Credenciais de Acesso',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: userController,
                        decoration: const InputDecoration(
                          labelText: 'Usuário *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Usuário é obrigatório';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passController,
                        decoration: const InputDecoration(
                          labelText: 'Senha *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Senha é obrigatória';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: selectedTransport,
                  builder: (context, value, _) {
                    return DropdownButtonFormField<String>(
                      value: value,
                      dropdownColor: const Color(0xFF2A2A2A),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Transporte RTSP',
                        labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                        prefixIcon: Icon(Icons.swap_horiz),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'tcp', child: Text('TCP (Recomendado)')),
                        DropdownMenuItem(value: 'udp', child: Text('UDP')),
                      ],
                      onChanged: (v) { if (v != null) selectedTransport.value = v; },
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Botão de teste de conexão
                ValueListenableBuilder<bool>(
                  valueListenable: testingConnection,
                  builder: (context, testing, child) {
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: testing ? null : testConnection,
                        icon: testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_find),
                        label: Text(testing ? 'Testando...' : 'Testar Conexão'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                // Status da conexão
                ValueListenableBuilder<String>(
                  valueListenable: connectionStatus,
                  builder: (context, status, child) {
                    if (status.isEmpty) return const SizedBox.shrink();
                    
                    final isSuccess = status.contains('bem-sucedida');
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                        border: Border.all(
                          color: isSuccess ? Colors.green : Colors.red,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSuccess ? Icons.check_circle : Icons.error,
                            color: isSuccess ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status,
                              style: TextStyle(
                                color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
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
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                // Criar credenciais se fornecidas
                Credentials? credentials;
                if (userController.text.isNotEmpty && passController.text.isNotEmpty) {
                  credentials = Credentials(
                    username: userController.text,
                    password: passController.text,
                  );
                  
                  // Armazenar credenciais de forma segura
                  await credentialStorage.storeCredentials(
                    '${urlController.text}:${portController.text}',
                    credentials,
                  );
                }
                
                final result = AddCameraDialogResult(
                  name: nameController.text.trim(),
                  host: urlController.text.trim(),
                  port: portController.text.trim(),
                  username: userController.text.trim(),
                  password: passController.text.trim(),
                  transport: selectedTransport.value,
                  portConfiguration: portConfiguration,
                  credentials: credentials,
                  alternativeUrls: alternativeUrls.value,
                );
                Navigator.of(context).pop(result);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
            child: const Text('Adicionar'),
          ),
        ],
      );
    },
  );
}