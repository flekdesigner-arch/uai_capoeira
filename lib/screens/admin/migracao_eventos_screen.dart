import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

class MigracaoEventosScreen extends StatefulWidget {
  const MigracaoEventosScreen({super.key});

  @override
  State<MigracaoEventosScreen> createState() => _MigracaoEventosScreenState();
}

class _MigracaoEventosScreenState extends State<MigracaoEventosScreen> {
  bool _isMigrating = false;
  String _statusMessage = '';
  int _successCount = 0;
  int _errorCount = 0;
  List<String> _errors = [];

  // 🔥 MODELO DE EVENTO CORRIGIDO
  final List<Map<String, dynamic>> _eventosExemplo = [
    {
      "nome": "2° BATIZADO & TROCA DE CORDAS - BOC",
      "tipo_evento": "BATIZADO & TROCA DE CORDAS",
      "data": "25/11/2018",
      "horario": "10:00",
      "local": "CENTRO DE CONVIVIO",
      "cidade": "BOCAIUVA-MG",
      "link_banner": "https://drive.google.com/file/d/1Aq_m1OlCYUL2aRGsx9T5Ctqc5mw-zqLv/view",
      "organizadores": "TICO-TICO, TOQUINHO, BODE, WARLEY",
      "link_fotos_videos": "https://photos.app.goo.gl/rDKtWQ1uzZdMMVYC9",
      "previa_video": "https://youtu.be/bwWPprzkoNg",
      "link_playlist": "",
      "status": "finalizado"
    }
  ];

  Future<void> _migrarEventos() async {
    setState(() {
      _isMigrating = true;
      _statusMessage = 'Carregando arquivo de eventos...';
      _successCount = 0;
      _errorCount = 0;
      _errors = [];
    });

    try {
      // 1️⃣ Carregar arquivo JSON dos assets
      final String jsonString = await rootBundle.loadString('assets/eventos.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      setState(() {
        _statusMessage = 'Arquivo carregado! Processando ${jsonList.length} eventos...';
      });

      // 2️⃣ Processar cada evento
      for (var i = 0; i < jsonList.length; i++) {
        try {
          final evento = jsonList[i] as Map<String, dynamic>;

          // 🔥 CONVERTER CAMPOS
          final Map<String, dynamic> eventoProcessado = {
            // Campos principais
            'nome': evento['NOME'] ?? 'Sem nome',
            'tipo_evento': evento['TIPO DO EVENTO'] ?? 'Não informado',
            'data': _formatarData(evento['DATA']),
            'horario': evento['HORARIO'] ?? '',
            'local': evento['LOCAL'] ?? '',
            'cidade': evento['CIDADE'] ?? '',
            'link_banner': evento['LINK DO BANNER'] ?? '',
            'organizadores': evento['ORGANIZADORES'] ?? '',
            'link_fotos_videos': evento['LINK DA FOTOS E VIDEOS'] ?? '',
            'previa_video': evento['PREVIA VIDEO'] ?? '',
            'link_playlist': evento['LINK PLAYLIST'] ?? '',

            // 🔥 STATUS CONVERTIDO (finalizado → finalizado, vazio → andamento)
            'status': _converterStatus(evento['FINALIZADO?']),

            // Metadados
            'criado_em': FieldValue.serverTimestamp(),
            'atualizado_em': FieldValue.serverTimestamp(),
          };

          // 3️⃣ Salvar no Firestore
          await FirebaseFirestore.instance
              .collection('eventos')
              .add(eventoProcessado);

          setState(() {
            _successCount++;
          });

        } catch (e) {
          setState(() {
            _errorCount++;
            _errors.add('Erro no evento ${i + 1}: $e');
          });
        }
      }

      setState(() {
        _isMigrating = false;
        _statusMessage = 'Migração concluída!';
      });

    } catch (e) {
      setState(() {
        _isMigrating = false;
        _statusMessage = 'Erro ao carregar arquivo: $e';
      });
    }
  }

  // 🔥 FORMATAR DATA (DD/MM/AAAA → formato do Firestore)
  String _formatarData(dynamic data) {
    if (data == null) return '';

    String dataStr = data.toString().trim();

    // Se vier com hora (ex: "08/06/2025, 0:00:00")
    if (dataStr.contains(',')) {
      dataStr = dataStr.split(',')[0].trim();
    }

    return dataStr;
  }

  // 🔥 CONVERTER FINALIZADO? para status
  String _converterStatus(dynamic finalizado) {
    if (finalizado == null) return 'andamento';
    if (finalizado is bool) {
      return finalizado ? 'finalizado' : 'andamento';
    }
    if (finalizado is String) {
      return finalizado.toLowerCase() == 'true' ? 'finalizado' : 'andamento';
    }
    return 'andamento';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Migração de Eventos'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD DE INFORMAÇÕES
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.event,
                            color: Colors.green.shade700,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Importar Eventos do JSON',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Este processo irá importar os eventos do arquivo eventos.json para o Firestore.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• O arquivo deve estar em assets/eventos.json',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Text(
                      '• Eventos duplicados serão criados como novos documentos',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Text(
                      '• Status convertido: true → finalizado | false → andamento',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // BOTÃO DE MIGRAÇÃO
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isMigrating ? null : _migrarEventos,
                icon: _isMigrating
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  _isMigrating ? 'MIGRANDO...' : 'INICIAR MIGRAÇÃO',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // STATUS DA MIGRAÇÃO
            if (_statusMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isMigrating ? Icons.info : Icons.check_circle,
                      color: _isMigrating ? Colors.blue : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _isMigrating ? Colors.blue.shade900 : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // CONTADORES DE SUCESSO/ERRO
            if (_successCount > 0 || _errorCount > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            '$_successCount',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                          const Text(
                            'Sucessos',
                            style: TextStyle(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.error, color: Colors.red.shade700, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            '$_errorCount',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const Text(
                            'Erros',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // LISTA DE ERROS
            if (_errors.isNotEmpty) ...[
              const Text(
                'Erros encontrados:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _errors.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _errors[index],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade900,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}