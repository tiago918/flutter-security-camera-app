# Script para corrigir expressões regulares problemáticas
$file = 'lib\services\onvif_playback_service.dart'
$content = Get-Content $file

# Substituir as linhas problemáticas
for ($i = 0; $i -lt $content.Length; $i++) {
    if ($content[$i] -match "final idMatch = RegExp\(r'id=\[") {
        $content[$i] = "      final idMatch = RegExp(r'id=[\"\\\']([^\"\\\'>]+)[\"\\\']').firstMatch(xmlRecord);"
    }
    elseif ($content[$i] -match "final nameMatch = RegExp\(r'name=\[") {
        $content[$i] = "      final nameMatch = RegExp(r'name=[\"\\\']([^\"\\\'>]+)[\"\\\']').firstMatch(xmlRecord);"
    }
    elseif ($content[$i] -match "final startMatch = RegExp\(r'start=\[") {
        $content[$i] = "      final startMatch = RegExp(r'start=[\"\\\']([^\"\\\'>]+)[\"\\\']').firstMatch(xmlRecord);"
    }
    elseif ($content[$i] -match "final endMatch = RegExp\(r'end=\[") {
        $content[$i] = "      final endMatch = RegExp(r'end=[\"\\\']([^\"\\\'>]+)[\"\\\']').firstMatch(xmlRecord);"
    }
    elseif ($content[$i] -match "final sizeMatch = RegExp\(r'size=\[") {
        $content[$i] = "      final sizeMatch = RegExp(r'size=[\"\\\']([^\"\\\'>]+)[\"\\\']').firstMatch(xmlRecord);"
    }
}

# Salvar o arquivo corrigido
$content | Set-Content $file

Write-Host "Expressões regulares corrigidas com sucesso!"