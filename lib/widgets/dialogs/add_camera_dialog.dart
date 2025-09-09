import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../models/camera_models.dart' as models;
import '../../models/camera_model.dart';
import '../../services/camera_service.dart';
import '../../models/camera_status.dart';
import '../../models/stream_config.dart';

class AddCameraDialog extends StatefulWidget {
  const AddCameraDialog({super.key});

  @override
  State<AddCameraDialog> createState() => _AddCameraDialogState();
}

class _AddCameraDialogState extends State<AddCameraDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '554');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathController = TextEditingController(text: '/stream1');
  
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _addCamera() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('DEBUG: Iniciando adição de câmera manual');
      
      final String name = _nameController.text.trim();
      final String ip = _ipController.text.trim();
      final String portStr = _portController.text.trim();
      final String username = _usernameController.text.trim();
      final String password = _passwordController.text.trim();
      String path = _pathController.text.trim();
      
      // Se o caminho estiver vazio, usar um padrão
      if (path.isEmpty) {
        path = '/cam/realmonitor?channel=1&subtype=0';
      }
      
      final int port = int.parse(portStr);
      
      print('DEBUG: Construindo URL RTSP com:');
      print('  IP: $ip');
      print('  Porta: $port');
      print('  Usuário: ${username.isNotEmpty ? username : "(vazio)"}');
       print('  Senha: ${password.isNotEmpty ? "***" : "(vazio)"}');
      print('  Caminho: $path');
      
      // Construir URL RTSP
      String streamUrl;
      if (username.isNotEmpty && password.isNotEmpty) {
        streamUrl = 'rtsp://$username:$password@$ip:$port$path';
      } else {
        streamUrl = 'rtsp://$ip:$port$path';
      }
      
      print('DEBUG: URL RTSP construída: $streamUrl');
      
      // Criar CameraData (usado pelo sistema de persistência)
       final cameraData = models.CameraData(
         id: DateTime.now().millisecondsSinceEpoch,
         name: name,
         isLive: false,
         statusColor: const Color(0xFF888888),
         uniqueColor: Color(models.CameraData.generateUniqueColor(DateTime.now().millisecondsSinceEpoch)),
         icon: Icons.videocam_outlined,
         streamUrl: streamUrl,
         username: username.isNotEmpty ? username : null,
         password: password.isNotEmpty ? password : null,
         port: port,
         transport: 'tcp',
         acceptSelfSigned: false,
         host: ip,
       );
      
      // Criar CameraModel para o CameraService
      final cameraModel = CameraModel(
        id: cameraData.id.toString(),
        name: name,
        type: CameraType.ip,
        ipAddress: ip,
        port: port,
        username: username.isNotEmpty ? username : null,
        password: password.isNotEmpty ? password : null,
        rtspPath: path,
        isSecure: false,
        status: CameraStatus.offline,
        capabilities: const CameraCapabilities(),
        streamConfig: StreamConfig(
          videoCodec: VideoCodec.h264,
          resolution: '1920x1080',
          bitrate: 2000000,
          frameRate: 25,
        ),
        settings: const CameraSettings(),
      );
      
      // Adicionar ao CameraService
      await CameraService.instance.addCamera(cameraModel);
      
      // Também salvar usando SharedPreferences para compatibilidade
      final prefs = await SharedPreferences.getInstance();
      final existingCameras = prefs.getString('cameras');
      List<Map<String, dynamic>> camerasList = [];
      
      if (existingCameras != null) {
        final List<dynamic> decoded = json.decode(existingCameras);
        camerasList = decoded.cast<Map<String, dynamic>>();
      }
      
      camerasList.add(cameraData.toJson());
      await prefs.setString('cameras', json.encode(camerasList));
      
      print('DEBUG: Câmera salva no CameraService e SharedPreferences');
      print('DEBUG: Total de câmeras salvas: ${camerasList.length}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Câmera adicionada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      print('ERRO: Falha ao adicionar câmera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar câmera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Câmera'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome da Câmera',
                    hintText: 'Ex: Câmera da Entrada',
                    prefixIcon: Icon(Icons.videocam),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nome é obrigatório';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Endereço IP',
                    hintText: 'Ex: 192.168.1.100',
                    prefixIcon: Icon(Icons.router),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'IP é obrigatório';
                    }
                    // Validação básica de IP
                    final ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
                    if (!ipRegex.hasMatch(value.trim())) {
                      return 'IP inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Porta',
                    hintText: '554',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Porta é obrigatória';
                    }
                    final port = int.tryParse(value.trim());
                    if (port == null || port < 1 || port > 65535) {
                      return 'Porta deve estar entre 1 e 65535';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Usuário (opcional)',
                    hintText: 'admin',
                    prefixIcon: Icon(Icons.person),
                  ),
                  // Usuário não é obrigatório
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Senha (opcional)',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  // Senha não é obrigatória
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'Caminho do Stream',
                    hintText: '/stream1',
                    prefixIcon: Icon(Icons.route),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Caminho é obrigatório';
                    }
                    if (!value.trim().startsWith('/')) {
                      return 'Caminho deve começar com /';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addCamera,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}