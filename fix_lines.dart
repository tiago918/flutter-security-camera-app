final idMatch = RegExp(r'id=["\\\']([^"\\\'>]+)["\\\']').firstMatch(xmlRecord);
      final nameMatch = RegExp(r'name=["\\\']([^"\\\'>]+)["\\\']').firstMatch(xmlRecord);
      final startMatch = RegExp(r'start=["\\\']([^"\\\'>]+)["\\\']').firstMatch(xmlRecord);
      final endMatch = RegExp(r'end=["\\\']([^"\\\'>]+)["\\\']').firstMatch(xmlRecord);
      final sizeMatch = RegExp(r'size=["\\\']([^"\\\'>]+)["\\\']').firstMatch(xmlRecord);