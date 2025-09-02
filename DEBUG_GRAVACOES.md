# Debug - Detecção de Gravações do Cartão SD

## Problema Atual
Os vídeos gravados no cartão SD não estão sendo detectados pelo aplicativo.

## Logs de Debug Adicionados
Foi adicionado logging detalhado no serviço de playback para identificar onde está falhando a busca:

### Como Visualizar os Logs
1. Conecte o dispositivo Android ao computador
2. Ative as "Opções do desenvolvedor" e "Depuração USB"
3. Execute o comando: `adb logcat | grep "Playback:"`
4. Abra o app e tente buscar gravações
5. Observe os logs no terminal

### Logs Esperados
```
Playback: Starting search for recordings on [Nome da Câmera]
Playback: Searching recordings for [Nome] at [IP]
Playback: Search period: [Data Início] to [Data Fim]
Playback: Attempting ONVIF connection to [IP] with user: [usuário]
Playback: Trying connection to [IP]:[porta]
```

## Possíveis Causas do Problema

### 1. Falha na Conexão ONVIF
- **Sintoma**: Logs mostram "Failed to connect" para todas as portas
- **Causa**: Credenciais incorretas, firewall, ou câmera não suporta ONVIF
- **Solução**: Verificar usuário/senha, testar portas manualmente

### 2. Câmera Não Suporta Profile G (Recording)
- **Sintoma**: "Device does not support ONVIF Profile G (Recording)"
- **Causa**: Câmera antiga ou fabricante não implementou padrão ONVIF completo
- **Solução**: Usar métodos alternativos (HTTP API específica do fabricante)

### 3. Falha nos Métodos Alternativos
- **Sintoma**: "Trying alternative methods" mas retorna 0 gravações
- **Causa**: URLs de API incorretas ou formato de resposta não suportado
- **Solução**: Implementar suporte específico para o modelo da câmera

### 4. Período de Busca Incorreto
- **Sintoma**: Conexão OK mas 0 gravações encontradas
- **Causa**: Não há gravações no período especificado
- **Solução**: Ajustar período de busca ou verificar se há gravações no cartão SD

## Teste Manual

### Verificar Gravações Manualmente
1. Acesse a interface web da câmera
2. Vá para "Playback" ou "Reprodução"
3. Verifique se há gravações no período desejado
4. Anote o formato das URLs de acesso às gravações

### Testar Conectividade ONVIF
```bash
# Testar se a câmera responde ONVIF
curl -X POST http://[IP_CAMERA]/onvif/device_service \
  -H "Content-Type: application/soap+xml" \
  -d '<soap:Envelope>...</soap:Envelope>'
```

## Implementação Atual

O serviço tenta 3 métodos em ordem:

1. **ONVIF Recording Service** (padrão oficial)
   - Conecta via portas: 80, 8080, 8000, 8899, 2020
   - Verifica suporte a Profile G
   - Busca via `getRecordings()` e `getRecordingConfigurations()`

2. **HTTP API Específica do Fabricante**
   - Hikvision ISAPI
   - Dahua CGI
   - Axis CGI

3. **Padrões de URL Comuns**
   - Tenta URLs conhecidas de diferentes fabricantes
   - Analisa respostas em XML, JSON e texto

## Próximos Passos

1. **Instalar o APK atualizado** (build\app\outputs\flutter-apk\app-release.apk)
2. **Executar com logs**: `adb logcat | grep "Playback:"`
3. **Testar busca de gravações** no app
4. **Analisar logs** para identificar onde está falhando
5. **Reportar resultados** com os logs específicos

## Nota Importante
⚠️ **Esta implementação inclui funcionalidades reais de busca de gravações, mas pode não funcionar com todos os modelos de câmera devido às diferenças de implementação entre fabricantes.**

Cada fabricante pode ter:
- Portas ONVIF diferentes
- APIs proprietárias
- Formatos de resposta únicos
- Autenticação específica

Para suporte completo, seria necessário implementar drivers específicos para cada modelo de câmera.