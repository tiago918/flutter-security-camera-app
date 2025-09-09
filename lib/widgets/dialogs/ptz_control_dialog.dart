import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/services.dart';

class PTZControlDialog extends StatefulWidget {
  final CameraModel camera;
  final PTZService ptzService;

  const PTZControlDialog({
    super.key,
    required this.camera,
    required this.ptzService,
  });

  @override
  State<PTZControlDialog> createState() => _PTZControlDialogState();
}

class _PTZControlDialogState extends State<PTZControlDialog> {
  PTZSpeed _currentSpeed = PTZSpeed.medium;
  bool _isMoving = false;
  List<int> _presets = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    setState(() => _isLoading = true);
    try {
      final presets = await widget.ptzService.getPresets(widget.camera.id);
      setState(() => _presets = presets);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar presets: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _moveCamera(PTZDirection direction) async {
    if (_isMoving) return;
    
    setState(() => _isMoving = true);
    try {
      await widget.ptzService.moveCamera(widget.camera.id, direction, _currentSpeed);
      await Future.delayed(const Duration(milliseconds: 500));
      await widget.ptzService.stopMovement(widget.camera.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao mover câmera: $e')),
        );
      }
    } finally {
      setState(() => _isMoving = false);
    }
  }

  Future<void> _zoomCamera(PTZDirection direction) async {
    if (_isMoving) return;
    
    setState(() => _isMoving = true);
    try {
      await widget.ptzService.zoomCamera(widget.camera.id, direction, _currentSpeed);
      await Future.delayed(const Duration(milliseconds: 300));
      await widget.ptzService.stopMovement(widget.camera.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao fazer zoom: $e')),
        );
      }
    } finally {
      setState(() => _isMoving = false);
    }
  }

  Future<void> _gotoPreset(int presetNumber) async {
    setState(() => _isMoving = true);
    try {
      await widget.ptzService.gotoPreset(widget.camera.id, presetNumber);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao ir para preset: $e')),
        );
      }
    } finally {
      setState(() => _isMoving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.control_camera, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Controle PTZ - ${widget.camera.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Speed Control
            Text(
              'Velocidade',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<PTZSpeed>(
              segments: const [
                ButtonSegment(
                  value: PTZSpeed.slow,
                  label: Text('Lenta'),
                  icon: Icon(Icons.speed, size: 16),
                ),
                ButtonSegment(
                  value: PTZSpeed.medium,
                  label: Text('Média'),
                  icon: Icon(Icons.speed, size: 16),
                ),
                ButtonSegment(
                  value: PTZSpeed.fast,
                  label: Text('Rápida'),
                  icon: Icon(Icons.speed, size: 16),
                ),
              ],
              selected: {_currentSpeed},
              onSelectionChanged: (Set<PTZSpeed> selection) {
                setState(() => _currentSpeed = selection.first);
              },
            ),
            const SizedBox(height: 24),
            
            // Movement Controls
            Text(
              'Movimento',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            // PTZ Control Grid
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Top row
                  Row(
                    children: [
                      _buildControlButton(
                        icon: Icons.north_west,
                        onPressed: () => _moveCamera(PTZDirection.upLeft),
                      ),
                      _buildControlButton(
                        icon: Icons.north,
                        onPressed: () => _moveCamera(PTZDirection.up),
                      ),
                      _buildControlButton(
                        icon: Icons.north_east,
                        onPressed: () => _moveCamera(PTZDirection.upRight),
                      ),
                    ],
                  ),
                  // Middle row
                  Row(
                    children: [
                      _buildControlButton(
                        icon: Icons.west,
                        onPressed: () => _moveCamera(PTZDirection.left),
                      ),
                      _buildControlButton(
                        icon: Icons.home,
                        onPressed: () => widget.ptzService.stopMovement(widget.camera.id),
                      ),
                      _buildControlButton(
                        icon: Icons.east,
                        onPressed: () => _moveCamera(PTZDirection.right),
                      ),
                    ],
                  ),
                  // Bottom row
                  Row(
                    children: [
                      _buildControlButton(
                        icon: Icons.south_west,
                        onPressed: () => _moveCamera(PTZDirection.downLeft),
                      ),
                      _buildControlButton(
                        icon: Icons.south,
                        onPressed: () => _moveCamera(PTZDirection.down),
                      ),
                      _buildControlButton(
                        icon: Icons.south_east,
                        onPressed: () => _moveCamera(PTZDirection.downRight),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Zoom Controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isMoving ? null : () => _zoomCamera(PTZDirection.zoomIn),
                    icon: const Icon(Icons.zoom_in),
                    label: const Text('Zoom In'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isMoving ? null : () => _zoomCamera(PTZDirection.zoomOut),
                    icon: const Icon(Icons.zoom_out),
                    label: const Text('Zoom Out'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Presets
            if (_presets.isNotEmpty) ..[
              Text(
                'Presets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets.map((preset) => 
                  ElevatedButton(
                    onPressed: _isMoving ? null : () => _gotoPreset(preset),
                    child: Text('Preset $preset'),
                  ),
                ).toList(),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(1),
          child: ElevatedButton(
            onPressed: _isMoving ? null : onPressed,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: const RoundedRectangleBorder(),
            ),
            child: Icon(icon),
          ),
        ),
      ),
    );
  }
}