import 'package:flutter/material.dart';
import '../../../models/camera_models.dart';
import '../../../models/connection_log.dart';
import '../../../services/camera_connection_manager.dart';
import '../../../services/auto_reconnection_service.dart';
import '../../../widgets/camera_card_widget.dart';

class CameraGridWidget extends StatelessWidget {
  final List<CameraModel> cameras;
  final VoidCallback onAddCamera;
  final CameraModel? selectedCamera;
  final Function(CameraModel) onCameraSelected;
  final Function(CameraModel) onCameraEdit;
  final Function(CameraModel) onCameraRemove;
  final CameraConnectionManager? connectionManager;
  final AutoReconnectionService? reconnectionService;
  final Map<String, ConnectionStatus>? connectionStates;

  const CameraGridWidget({
    super.key,
    required this.cameras,
    required this.onAddCamera,
    this.selectedCamera,
    required this.onCameraSelected,
    required this.onCameraEdit,
    required this.onCameraRemove,
    this.connectionManager,
    this.reconnectionService,
    this.connectionStates,
  });

  @override
  Widget build(BuildContext context) {
    final int cameraCount = cameras.length;

    // Quando não há câmeras, exibimos um placeholder de altura fixa (364px)
    // para manter a seção de Notificações na mesma posição vertical original.
    if (cameraCount == 0) {
      return _buildEmptyCamerasPlaceholder();
    }

    // Layout scrollable com câmeras empilhadas verticalmente
    return SizedBox(
      height: cameraCount == 1 ? 300 : 600, // Altura fixa para permitir scroll interno
      child: SingleChildScrollView(
        child: Column(
          children: cameras.asMap().entries.map((entry) {
            final index = entry.key;
            final camera = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                children: [
                  if (index > 0) const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => onCameraSelected?.call(camera),
                    child: Container(
                      decoration: BoxDecoration(
                        border: selectedCamera?.id == camera.id 
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CameraCardWidget(
                        camera: camera,
                        videoController: null,
                        isLarge: cameraCount == 1,
                        isLoading: false,
                        onPlayPause: () {},
                        connectionManager: connectionManager,
                        reconnectionService: reconnectionService,
                        onEdit: onCameraEdit != null ? () => onCameraEdit!(camera) : null,
                        onRemove: onCameraRemove != null ? () => onCameraRemove!(camera) : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Placeholder para quando não existem câmeras cadastradas
  Widget _buildEmptyCamerasPlaceholder() {
    return Container(
      height: 364, // altura fixa para manter as notificações na mesma posição
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_outlined, color: Color(0xFF888888), size: 52),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma câmera adicionada',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Adicione uma câmera para começar a monitorar',
              style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAddCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Adicionar câmera',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}