enum CameraStatus {
  offline,
  connecting,
  online,
  error,
  recording,
  streaming,
  maintenance;

  String get displayName {
    switch (this) {
      case CameraStatus.offline:
        return 'Offline';
      case CameraStatus.connecting:
        return 'Conectando';
      case CameraStatus.online:
        return 'Online';
      case CameraStatus.error:
        return 'Erro';
      case CameraStatus.recording:
        return 'Gravando';
      case CameraStatus.streaming:
        return 'Transmitindo';
      case CameraStatus.maintenance:
        return 'Manutenção';
    }
  }

  bool get isConnected {
    switch (this) {
      case CameraStatus.online:
      case CameraStatus.recording:
      case CameraStatus.streaming:
        return true;
      case CameraStatus.offline:
      case CameraStatus.connecting:
      case CameraStatus.error:
      case CameraStatus.maintenance:
        return false;
    }
  }

  bool get canStream {
    switch (this) {
      case CameraStatus.online:
      case CameraStatus.streaming:
        return true;
      case CameraStatus.offline:
      case CameraStatus.connecting:
      case CameraStatus.error:
      case CameraStatus.recording:
      case CameraStatus.maintenance:
        return false;
    }
  }

  bool get canRecord {
    switch (this) {
      case CameraStatus.online:
      case CameraStatus.recording:
        return true;
      case CameraStatus.offline:
      case CameraStatus.connecting:
      case CameraStatus.error:
      case CameraStatus.streaming:
      case CameraStatus.maintenance:
        return false;
    }
  }
}