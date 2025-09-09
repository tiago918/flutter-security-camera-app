import 'package:flutter/material.dart';
import '../../../models/camera_models.dart';

class PortConfigurationWidget extends StatefulWidget {
  final String host;
  final String username;
  final String password;
  final Function(CameraPortConfiguration) onConfigurationChanged;

  const PortConfigurationWidget({
    Key? key,
    required this.host,
    required this.username,
    required this.password,
    required this.onConfigurationChanged,
  }) : super(key: key);

  @override
  State<PortConfigurationWidget> createState() => _PortConfigurationWidgetState();
}

class _PortConfigurationWidgetState extends State<PortConfigurationWidget> {
  final _rtspPortController = TextEditingController(text: '554');
  final _httpPortController = TextEditingController(text: '80');
  final _onvifPortController = TextEditingController(text: '8080');
  bool _useCustomPorts = false;
  CameraPortConfiguration _configuration = const CameraPortConfiguration();

  @override
  void initState() {
    super.initState();
    _updateConfiguration();
  }

  void _updateConfiguration() {
    _configuration = CameraPortConfiguration(
      rtspPort: int.tryParse(_rtspPortController.text) ?? 554,
      httpPort: int.tryParse(_httpPortController.text) ?? 80,
      onvifPort: int.tryParse(_onvifPortController.text) ?? 8080,
    );
    widget.onConfigurationChanged(_configuration);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _useCustomPorts,
              onChanged: (value) {
                setState(() {
                  _useCustomPorts = value ?? false;
                  _updateConfiguration();
                });
              },
              activeColor: const Color(0xFF4CAF50),
            ),
            const Text(
              'Configurar portas personalizadas',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        if (_useCustomPorts) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _rtspPortController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Porta RTSP',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    hintText: '554',
                    hintStyle: TextStyle(color: Color(0xFF666666)),
                  ),
                  onChanged: (_) => _updateConfiguration(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _httpPortController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Porta HTTP',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    hintText: '80',
                    hintStyle: TextStyle(color: Color(0xFF666666)),
                  ),
                  onChanged: (_) => _updateConfiguration(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _onvifPortController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Porta ONVIF',
                    labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                    hintText: '8080',
                    hintStyle: TextStyle(color: Color(0xFF666666)),
                  ),
                  onChanged: (_) => _updateConfiguration(),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _rtspPortController.dispose();
    _httpPortController.dispose();
    _onvifPortController.dispose();
    super.dispose();
  }
}