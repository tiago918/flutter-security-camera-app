import 'package:flutter/material.dart';

Future<void> showRecordingStatusDialog(
  BuildContext context, {
  required String cameraName,
  required bool isActive,
  required int totalRecordings,
  required num totalSizeMB,
}) async {
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        'Status da Gravação - $cameraName',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusRow('Status:', isActive ? 'Ativo' : 'Inativo'),
          _buildStatusRow('Total de Gravações:', '$totalRecordings'),
          _buildStatusRow('Espaço Usado:', '${totalSizeMB} MB'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar', style: TextStyle(color: Colors.blue)),
        ),
      ],
    ),
  );
}

Widget _buildStatusRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}