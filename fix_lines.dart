void main() {
  // Exemplo de string XML para teste
  String xmlRecord = '<record id="123" name="example" start="2024-01-01" end="2024-01-02" size="1024">';
  
  // Parse dos atributos XML usando RegExp
  parseXmlAttributes(xmlRecord);
}

void parseXmlAttributes(String xmlRecord) {
  // Expressões regulares para extrair atributos XML
  final idMatch = RegExp(r'id=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final nameMatch = RegExp(r'name=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final startMatch = RegExp(r'start=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final endMatch = RegExp(r'end=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final sizeMatch = RegExp(r'size=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  
  // Extração dos valores dos atributos
  String? id = idMatch?.group(1);
  String? name = nameMatch?.group(1);
  String? start = startMatch?.group(1);
  String? end = endMatch?.group(1);
  String? size = sizeMatch?.group(1);
  
  // Exibição dos resultados
  print('ID: $id');
  print('Name: $name');
  print('Start: $start');
  print('End: $end');
  print('Size: $size');
}

// Função auxiliar para processar múltiplos registros XML
void processXmlRecords(List<String> xmlRecords) {
  for (String record in xmlRecords) {
    print('\n--- Processando registro ---');
    parseXmlAttributes(record);
  }
}

// Classe para representar um registro XML parseado
class XmlRecord {
  final String? id;
  final String? name;
  final String? start;
  final String? end;
  final String? size;
  
  XmlRecord({
    this.id,
    this.name,
    this.start,
    this.end,
    this.size,
  });
  
  @override
  String toString() {
    return 'XmlRecord(id: $id, name: $name, start: $start, end: $end, size: $size)';
  }
}

// Função para criar objeto XmlRecord a partir de string XML
XmlRecord parseToXmlRecord(String xmlRecord) {
  final idMatch = RegExp(r'id=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final nameMatch = RegExp(r'name=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final startMatch = RegExp(r'start=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final endMatch = RegExp(r'end=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  final sizeMatch = RegExp(r'size=["'""']([^"'""'>]+)["'""']').firstMatch(xmlRecord);
  
  return XmlRecord(
    id: idMatch?.group(1),
    name: nameMatch?.group(1),
    start: startMatch?.group(1),
    end: endMatch?.group(1),
    size: sizeMatch?.group(1),
  );
}