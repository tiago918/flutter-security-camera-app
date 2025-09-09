# Guia para Interceptação da Comunicação Computador-Câmera

## Objetivo
Interceptar e analisar a comunicação entre o computador e a câmera IP (192.168.3.49) para fazer engenharia reversa do protocolo de comunicação.

## Ferramentas Necessárias

### 1. Wireshark (Recomendado)
- **Download**: https://www.wireshark.org/download.html
- **Função**: Captura e análise de pacotes de rede
- **Vantagens**: Interface gráfica, filtros avançados, decodificação automática

### 2. tcpdump (Alternativa)
- **Função**: Captura de pacotes via linha de comando
- **Uso**: Para capturas automatizadas ou em sistemas sem interface gráfica

## Passo a Passo para Interceptação

### Preparação
1. **Instale o Wireshark** no computador Windows
2. **Identifique a interface de rede** que está conectada à câmera
3. **Anote o IP da câmera**: 192.168.3.49
4. **Anote o IP do computador**: (verificar com `ipconfig`)

### Captura com Wireshark

#### 1. Configuração Inicial
```
1. Abra o Wireshark como Administrador
2. Selecione a interface de rede (Ethernet ou Wi-Fi)
3. Configure filtros para focar na câmera:
   - Filtro básico: ip.addr == 192.168.3.49
   - Filtro TCP: tcp and ip.addr == 192.168.3.49
```

#### 2. Filtros Específicos
```wireshark
# Capturar todo tráfego da câmera
ip.addr == 192.168.3.49

# Capturar apenas HTTP/HTTPS (porta 8899)
tcp.port == 8899 and ip.addr == 192.168.3.49

# Capturar protocolo proprietário (porta 34567)
tcp.port == 34567 and ip.addr == 192.168.3.49

# Capturar stream de vídeo (porta 2223)
tcp.port == 2223 and ip.addr == 192.168.3.49

# Capturar RTSP (porta 554)
tcp.port == 554 and ip.addr == 192.168.3.49
```

#### 3. Processo de Captura
1. **Inicie a captura** no Wireshark
2. **Acesse a câmera** pelo navegador (192.168.3.49)
3. **Baixe e execute o player** da câmera
4. **Realize as seguintes ações**:
   - Login na interface web
   - Visualização de vídeo ao vivo
   - Acesso a vídeos gravados
   - Controle PTZ (se disponível)
   - Configurações da câmera
5. **Pare a captura** após realizar todas as ações

### Análise dos Dados Capturados

#### 1. Identificação de Protocolos
```
- HTTP/HTTPS: Comunicação web (porta 8899)
- TCP Proprietário: Comandos de controle (porta 34567)
- RTSP/RTP: Stream de vídeo (porta 554/2223)
- UDP: Possível descoberta de dispositivos
```

#### 2. Padrões a Procurar
```
- Cabeçalhos binários (ex: 0xff000000)
- Comandos de login e autenticação
- Estruturas JSON em payloads
- Sequências de bytes repetitivas
- Padrões de handshake
```

#### 3. Exportação de Dados
```
1. Salvar captura: File > Save As > .pcap
2. Exportar objetos HTTP: File > Export Objects > HTTP
3. Exportar dados TCP: Follow TCP Stream
4. Salvar dados binários: Copy as Hex Dump
```

## Comandos Úteis

### Verificar Conectividade
```cmd
# Ping para a câmera
ping 192.168.3.49

# Verificar portas abertas
nmap -p 1-65535 192.168.3.49

# Verificar IP do computador
ipconfig
```

### Captura via tcpdump (se disponível)
```bash
# Capturar todo tráfego da câmera
tcpdump -i eth0 -w camera_capture.pcap host 192.168.3.49

# Capturar apenas TCP
tcpdump -i eth0 -w camera_tcp.pcap tcp and host 192.168.3.49
```

## Análise Comparativa

### Comparar com Interceptação Mobile
1. **Abra os arquivos de interceptação mobile** existentes
2. **Compare os padrões encontrados**:
   - Estruturas de comando similares
   - Sequências de autenticação
   - Formatos de payload
   - Cabeçalhos de protocolo

### Pontos de Comparação
```
- Protocolo de login (MD5, JSON)
- Comandos de controle PTZ
- Solicitação de lista de vídeos
- Stream de vídeo RTSP
- Heartbeat/keep-alive
```

## Resultados Esperados

### Comunicação Web (Porta 8899)
- Requisições HTTP para interface de configuração
- Possível download do player/plugin
- Autenticação via formulário web

### Protocolo Proprietário (Porta 34567)
- Comandos binários com cabeçalhos específicos
- Autenticação MD5 similar ao mobile
- Comandos de controle e configuração

### Stream de Vídeo (Porta 2223/554)
- Protocolo RTSP para negociação
- Stream RTP com dados de vídeo
- Possível H.264/H.265 encoding

## Dicas Importantes

1. **Execute como Administrador**: Wireshark precisa de privilégios elevados
2. **Use Filtros**: Evite capturar todo o tráfego de rede
3. **Documente Ações**: Anote o que está fazendo durante a captura
4. **Salve Regularmente**: Faça backup das capturas importantes
5. **Compare Padrões**: Use os dados mobile como referência

## Próximos Passos

1. Realizar a captura seguindo este guia
2. Analisar os dados capturados
3. Comparar com a interceptação mobile
4. Documentar diferenças e semelhanças
5. Criar implementação baseada nos achados

---

**Nota**: A interceptação de rede é legal quando feita em sua própria rede e dispositivos. Este guia é para fins educacionais e de engenharia reversa de protocolos proprietários.