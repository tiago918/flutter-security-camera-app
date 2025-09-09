import 'package:flutter/material.dart';


class AddCameraDialog extends StatefulWidget {
  const AddCameraDialog({super.key});

  @override
  State<AddCameraDialog> createState() => _AddCameraDialogState();
}

class _AddCameraDialogState extends State<AddCameraDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rtspPathController = TextEditingController();
  
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
          child: SingleChildScrollView(
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
                    labelText: 'Tipo de Câmera',
                    border: OutlineInputBorder(),
                  ),
                  items: CameraType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_getCameraTypeLabel(type)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Endereço IP',
                    border: OutlineInputBorder(),
                    hintText: '192.168.1.100',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o endereço IP';
                    }
                    // Validação básica de IP
                    final ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
                    if (!ipRegex.hasMatch(value)) {
                      return 'Endereço IP inválido';
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
                    hintText: '554',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira a porta';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return 'Porta inválida (1-65535)';
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
                    hintText: '/stream1',
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }

  void _onSave() {
    if (_formKey.currentState!.validate()) {
      final camera = CameraModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        type: _selectedType,
        ipAddress: _ipController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text.isEmpty ? null : _usernameController.text,
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        rtspPath: _rtspPathController.text.isEmpty ? null : _rtspPathController.text,
        isSecure: _isSecure,
        status: CameraStatus.disconnected,
        lastSeen: null,
        settings: const CameraSettings(),
      );
      
      Navigator.of(context).pop(camera);
    }
  }

  String _getCameraTypeLabel(CameraType type) {
    switch (type) {
      case CameraType.ip:
        return 'Câmera IP';
      case CameraType.usb:
        return 'Câmera USB';
      case CameraType.rtsp:
        return 'RTSP Stream';
      case CameraType.onvif:
        return 'ONVIF';
    }
  }
}