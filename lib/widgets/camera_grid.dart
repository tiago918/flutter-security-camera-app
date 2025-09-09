import 'package:flutter/material.dart';
import '../models/models.dart';


class CameraGrid extends StatelessWidget {
  final List<CameraModel> cameras;
  final CameraModel? selectedCamera;
  final Function(CameraModel) onCameraSelected;
  final Function(CameraModel) onCameraEdit;
  final Function(CameraModel) onCameraRemove;

  const CameraGrid({
    super.key,
    required this.cameras,
    this.selectedCamera,
    required this.onCameraSelected,
    required this.onCameraEdit,
    required this.onCameraRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: cameras.length,
      itemBuilder: (context, index) {
        final camera = cameras[index];
        final isSelected = camera.id == selectedCamera?.id;
        
        return GestureDetector(
          onTap: () => onCameraSelected(camera),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                // Área de vídeo
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: camera.isOnline
                      ? _buildVideoStream(camera)
                      : _buildDisconnectedState(camera),
                ),
                
                // Overlay com informações
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          camera.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 2,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 16,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onCameraEdit(camera);
                              break;
                            case 'remove':
                              onCameraRemove(camera);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Remover', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Status de conexão
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: camera.isOnline ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      camera.isOnline ? 'Conectado' : 'Desconectado',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoStream(CameraModel camera) {
    // Placeholder para stream de vídeo
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[800]!,
            Colors.grey[900]!,
          ],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam,
              color: Colors.white70,
              size: 32,
            ),
            SizedBox(height: 4),
            Text(
              'Stream Ativo',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedState(CameraModel camera) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[800],
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              color: Colors.white54,
              size: 32,
            ),
            SizedBox(height: 4),
            Text(
              'Desconectado',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}