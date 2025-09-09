import 'package:flutter/material.dart';
import '../models/models.dart';


class EditCameraDialog extends StatefulWidget {
  final CameraModel camera;
  
  const EditCameraDialog({super.key, required this.camera});

  @override
  State<EditCameraDialog> createState() => _EditCameraDialogState();
}

class _EditCameraDialogState extends State<EditCameraDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _rtspPathController;
  
  late CameraType _selectedType;
  late bool _isSecure;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.camera.name);
    _ipController = TextEditingController(text: widget.camera.ipAddress);
    _portController = TextEditingController(text: widget.camera.port.toString());
    _usernameController = TextEditingController(text: widget.camera.username ?? '');
    _passwordController = TextEditingController(text: widget.camera.password ?? '');
    _rtspPathController = TextEditingController(text: widget.camera.rtspPath);
    _selectedType = widget.camera.type;
    _isSecure = widget.camera.isSecure;
  }

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
      title: const Text('Editar Câmera'),
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
      final updatedCamera = widget.camera.copyWith(
        name: _nameController.text,
        type: _selectedType,
        ipAddress: _ipController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text.isEmpty ? null : _usernameController.text,
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        rtspPath: _rtspPathController.text,
        isSecure: _isSecure,
      );
      
      Navigator.of(context).pop(updatedCamera);
    }
  }
}