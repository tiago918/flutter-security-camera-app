import 'package:flutter/material.dart';

class CameraControls extends StatelessWidget {
  final String cameraId;
  final Function(String, String) onControlAction;

  const CameraControls({
    super.key,
    required this.cameraId,
    required this.onControlAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Título
            Text(
              'Controles da Câmera',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            
            // Controles PTZ
            Expanded(
              child: Row(
                children: [
                  // Controles direcionais
                  Expanded(
                    flex: 2,
                    child: _buildPTZControls(),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Controles de zoom e outras funções
                  Expanded(
                    flex: 1,
                    child: _buildZoomControls(),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Controles de gravação e snapshot
                  Expanded(
                    flex: 1,
                    child: _buildRecordingControls(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPTZControls() {
    return Column(
      children: [
        // Linha superior
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildControlButton(
              icon: Icons.keyboard_arrow_up,
              onPressed: () => onControlAction(cameraId, 'ptz_up'),
              tooltip: 'Mover para cima',
            ),
          ],
        ),
        
        // Linha do meio
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlButton(
              icon: Icons.keyboard_arrow_left,
              onPressed: () => onControlAction(cameraId, 'ptz_left'),
              tooltip: 'Mover para esquerda',
            ),
            _buildControlButton(
              icon: Icons.home,
              onPressed: () => onControlAction(cameraId, 'ptz_home'),
              tooltip: 'Posição inicial',
            ),
            _buildControlButton(
              icon: Icons.keyboard_arrow_right,
              onPressed: () => onControlAction(cameraId, 'ptz_right'),
              tooltip: 'Mover para direita',
            ),
          ],
        ),
        
        // Linha inferior
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildControlButton(
              icon: Icons.keyboard_arrow_down,
              onPressed: () => onControlAction(cameraId, 'ptz_down'),
              tooltip: 'Mover para baixo',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: Icons.zoom_in,
          onPressed: () => onControlAction(cameraId, 'zoom_in'),
          tooltip: 'Zoom In',
        ),
        _buildControlButton(
          icon: Icons.zoom_out,
          onPressed: () => onControlAction(cameraId, 'zoom_out'),
          tooltip: 'Zoom Out',
        ),
        _buildControlButton(
          icon: Icons.center_focus_strong,
          onPressed: () => onControlAction(cameraId, 'focus_auto'),
          tooltip: 'Foco Automático',
        ),
      ],
    );
  }

  Widget _buildRecordingControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: Icons.fiber_manual_record,
          onPressed: () => onControlAction(cameraId, 'start_recording'),
          tooltip: 'Iniciar Gravação',
          color: Colors.red,
        ),
        _buildControlButton(
          icon: Icons.stop,
          onPressed: () => onControlAction(cameraId, 'stop_recording'),
          tooltip: 'Parar Gravação',
        ),
        _buildControlButton(
          icon: Icons.camera_alt,
          onPressed: () => onControlAction(cameraId, 'take_snapshot'),
          tooltip: 'Capturar Imagem',
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: color ?? Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}