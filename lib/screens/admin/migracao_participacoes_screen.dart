import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

class MigracaoParticipacoesScreen extends StatefulWidget {
  const MigracaoParticipacoesScreen({super.key});

  @override
  State<MigracaoParticipacoesScreen> createState() => _MigracaoParticipacoesScreenState();
}

class _MigracaoParticipacoesScreenState extends State<MigracaoParticipacoesScreen> {
  bool _isMigrating = false;
  String _statusMessage = '';
  int _successCount = 0;
  int _errorCount = 0;
  int _alunosNaoEncontrados = 0;
  int _eventosNaoEncontrados = 0;
  List<String> _errors = [];

  // Cache para evitar buscas repetidas
  final Map<String, String> _alunosCache = {}; // nome do aluno -> id
  final Map<String, Map<String, dynamic>> _eventosCache = {}; // nome do evento -> dados do evento

  Future<void> _migrarParticipacoes() async {
    setState(() {
      _isMigrating = true;
      _statusMessage = 'Carregando arquivo de participações...';
      _successCount = 0;
      _errorCount = 0;
      _alunosNaoEncontrados = 0;
      _eventosNaoEncontrados = 0;
      _errors = [];
    });

    try {
      // 1️⃣ CARREGAR TODOS OS ALUNOS DO FIRESTORE PARA CACHE
      await _carregarAlunosCache();

      // 2️⃣ CARREGAR TODOS OS EVENTOS DO FIRESTORE PARA CACHE
      await _carregarEventosCache();

      // 3️⃣ CARREGAR ARQUIVO JSON
      final String jsonString = await rootBundle.loadString('assets/participacao_alunos_eventos.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      setState(() {
        _statusMessage = 'Arquivo carregado! Processando ${jsonList.length} participações...';
      });

      // 4️⃣ PROCESSAR CADA PARTICIPAÇÃO
      for (var i = 0; i < jsonList.length; i++) {
        try {
          final participacao = jsonList[i] as Map<String, dynamic>;

          // Extrair dados do JSON
          final nomeAluno = participacao['NOME']?.toString().trim() ?? '';
          final graduacao = participacao['GRADUAÇÃO']?.toString().trim() ?? '';
          final nomeEvento = participacao['EVENTO']?.toString().trim() ?? '';
          final linkCertificado = participacao['CERTIFICADO']?.toString().trim() ?? '';

          if (nomeAluno.isEmpty) {
            setState(() {
              _errorCount++;
              _errors.add('Item ${i + 1}: Nome do aluno vazio');
            });
            continue;
          }

          if (nomeEvento.isEmpty) {
            setState(() {
              _errorCount++;
              _errors.add('Item ${i + 1}: Nome do evento vazio para aluno $nomeAluno');
            });
            continue;
          }

          // Buscar ID do aluno pelo nome
          final alunoId = _alunosCache[nomeAluno];
          if (alunoId == null) {
            setState(() {
              _alunosNaoEncontrados++;
              _errorCount++;
              _errors.add('Aluno não encontrado: "$nomeAluno"');
            });
            continue;
          }

          // Buscar ID do evento pelo nome
          final eventoData = _eventosCache[nomeEvento];
          if (eventoData == null) {
            setState(() {
              _eventosNaoEncontrados++;
              _errorCount++;
              _errors.add('Evento não encontrado: "$nomeEvento"');
            });
            continue;
          }

          final eventoId = eventoData['id'] as String;
          final dataEvento = eventoData['data'] ?? '';
          final tipoEvento = eventoData['tipo_evento'] ?? '';

          // Verificar se já existe participação para evitar duplicatas
          final existingParticipacao = await FirebaseFirestore.instance
              .collection('participacoes_eventos')
              .where('aluno_id', isEqualTo: alunoId)
              .where('evento_id', isEqualTo: eventoId)
              .get();

          if (existingParticipacao.docs.isNotEmpty) {
            // Já existe, atualizar o certificado se necessário
            final docId = existingParticipacao.docs.first.id;
            await FirebaseFirestore.instance
                .collection('participacoes_eventos')
                .doc(docId)
                .update({
              'link_certificado': linkCertificado,
              'graduacao': graduacao,
              'atualizado_em': FieldValue.serverTimestamp(),
            });
          } else {
            // Criar nova participação
            await FirebaseFirestore.instance
                .collection('participacoes_eventos')
                .add({
              'aluno_id': alunoId,
              'aluno_nome': nomeAluno,
              'evento_id': eventoId,
              'evento_nome': nomeEvento,
              'data_evento': dataEvento,
              'tipo_evento': tipoEvento,
              'graduacao': graduacao,
              'link_certificado': linkCertificado,
              'criado_em': FieldValue.serverTimestamp(),
              'atualizado_em': FieldValue.serverTimestamp(),
            });
          }

          setState(() {
            _successCount++;
          });

        } catch (e) {
          setState(() {
            _errorCount++;
            _errors.add('Erro no item ${i + 1}: $e');
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

  Future<void> _carregarAlunosCache() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome']?.toString().trim() ?? '';
        if (nome.isNotEmpty) {
          _alunosCache[nome] = doc.id;
        }
      }

      debugPrint('✅ ${_alunosCache.length} alunos carregados no cache');
    } catch (e) {
      debugPrint('❌ Erro ao carregar alunos: $e');
    }
  }

  Future<void> _carregarEventosCache() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome']?.toString().trim() ?? '';
        if (nome.isNotEmpty) {
          _eventosCache[nome] = {
            'id': doc.id,
            'data': data['data'] ?? '',
            'tipo_evento': data['tipo_evento'] ?? '',
          };
        }
      }

      debugPrint('✅ ${_eventosCache.length} eventos carregados no cache');
    } catch (e) {
      debugPrint('❌ Erro ao carregar eventos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Migração de Participações'),
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
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.emoji_events,
                            color: Colors.amber.shade700,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Importar Participações em Eventos',
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
                      'Este processo irá importar as participações dos alunos nos eventos.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• O arquivo deve estar em assets/participacao_alunos_eventos.json',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Text(
                      '• Os alunos serão vinculados pelo NOME (case insensitive)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Text(
                      '• Os eventos serão vinculados pelo NOME do evento',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Text(
                      '• Se a participação já existir, apenas o certificado será atualizado',
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
                onPressed: _isMigrating ? null : _migrarParticipacoes,
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
                  backgroundColor: Colors.amber.shade700,
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

            // ESTATÍSTICAS
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard(
                  label: 'Sucessos',
                  value: '$_successCount',
                  color: Colors.green,
                  icon: Icons.check_circle,
                ),
                _buildStatCard(
                  label: 'Erros',
                  value: '$_errorCount',
                  color: Colors.red,
                  icon: Icons.error,
                ),
                _buildStatCard(
                  label: 'Alunos não encontrados',
                  value: '$_alunosNaoEncontrados',
                  color: Colors.orange,
                  icon: Icons.person_off,
                ),
                _buildStatCard(
                  label: 'Eventos não encontrados',
                  value: '$_eventosNaoEncontrados',
                  color: Colors.purple,
                  icon: Icons.event_busy,
                ),
              ],
            ),

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

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}