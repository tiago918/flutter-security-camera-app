import 'package:flutter/material.dart';
import '../models/models.dart';

class AddCameraDialog extends StatefulWidget {
  final Function(CameraModel)? onAdd;
  
  const AddCameraDialog({super.key, this.onAdd});

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
  final _rtspPathController = TextEditingController(text: '/stream');
  
  CameraType _selectedType = CameraType.ip;
  bool _isSecure = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rtspPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Câmera'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome da Câmera',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira um nome';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<CameraType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tipo da Câmera',
                  border: OutlineInputBorder(),
                ),
                items: CameraType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Endereço IP',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira o endereço IP';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Porta',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira a porta';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Porta inválida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Usuário',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _rtspPathController,
                decoration: const InputDecoration(
                  labelText: 'Caminho RTSP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              
              CheckboxListTile(
                title: const Text('Conexão Segura (HTTPS/RTSPS)'),
                value: _isSecure,
                onChanged: (value) {
                  setState(() {
                    _isSecure = value ?? false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saveCamera,
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  void _saveCamera() {
    if (_formKey.currentState!.validate()) {
      final camera = CameraModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        type: _selectedType,
        ipAddress: _ipController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text.isEmpty ? null : _usernameController.text,
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        rtspPath: _rtspPathController.text,
        isSecure: _isSecure,
        status: CameraStatus.offline,
        streamConfig: StreamConfig.fromQuality(StreamQuality.medium),
        settings: const CameraSettings(),
        capabilities: const CameraCapabilities(
          ptzCapabilities: PTZCapabilities(),
        ),
      );
      
      Navigator.of(context).pop(camera);
    }
  }
}