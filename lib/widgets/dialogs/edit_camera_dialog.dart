import 'package:flutter/material.dart';

import '../../services/camera_service.dart';

class EditCameraDialog extends StatefulWidget {
  final CameraModel camera;

  const EditCameraDialog({
    super.key,
    required this.camera,
  });

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
  late final TextEditingController _pathController;
  
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.camera.name);
    _ipController = TextEditingController(text: widget.camera.getHost());
    _portController = TextEditingController(text: widget.camera.port.toString());
    _usernameController = TextEditingController(text: widget.camera.username);
    _passwordController = TextEditingController(text: widget.camera.password);
    _pathController = TextEditingController(text: widget.camera.streamPath);
  }

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

  Future<void> _updateCamera() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedCamera = widget.camera.copyWith(
        name: _nameController.text.trim(),
        ip: _ipController.text.trim(),
        port: int.parse(_portController.text),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        streamPath: _pathController.text.trim(),
      );

      await CameraService.instance.updateCamera(updatedCamera);
      
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Câmera "${updatedCamera.name}" atualizada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar câmera: $e'),
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

  Future<void> _deleteCamera() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir a câmera "${widget.camera.name}"?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await CameraService.instance.removeCamera(widget.camera.id);
        
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Câmera "${widget.camera.name}" excluída com sucesso!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir câmera: $e'),
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
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit),
          const SizedBox(width: 8),
          const Text('Editar Câmera'),
          const Spacer(),
          IconButton(
            onPressed: _isLoading ? null : _deleteCamera,
            icon: const Icon(Icons.delete),
            color: Colors.red,
            tooltip: 'Excluir câmera',
          ),
        ],
      ),
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
                    labelText: 'Usuário',
                    hintText: 'admin',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Usuário é obrigatório';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Senha',
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
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Senha é obrigatória';
                    }
                    return null;
                  },
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
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status da Conexão',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              widget.camera.isConnected
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: widget.camera.isConnected
                                  ? Colors.green
                                  : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.camera.isConnected
                                  ? 'Conectada'
                                  : 'Desconectada',
                              style: TextStyle(
                                color: widget.camera.isConnected
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
          onPressed: _isLoading ? null : _updateCamera,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}