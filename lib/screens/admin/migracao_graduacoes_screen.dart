import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';

class MigracaoGraduacoesScreen extends StatefulWidget {
  const MigracaoGraduacoesScreen({super.key});

  @override
  State<MigracaoGraduacoesScreen> createState() => _MigracaoGraduacoesScreenState();
}

class _MigracaoGraduacoesScreenState extends State<MigracaoGraduacoesScreen> {
  bool _isLoading = false;
  String _statusMessage = '';
  Color _statusColor = Colors.grey;
  int _successCount = 0;
  int _errorCount = 0;
  int _alunosAtualizadosCount = 0;
  List<String> _graduacoesLogs = [];
  List<String> _alunosLogs = [];

  // Mapeamento das colunas do CSV
  final Map<String, String> columnMapping = {
    'hex_cor1': 'hex_cor1',
    'hex_cor2': 'hex_cor2',
    'hex_ponta1': 'hex_ponta1',
    'hex_ponta2': 'hex_ponta2',
    'idade_minima': 'idade_minima',
    'nivel_graduacao': 'nivel_graduacao',
    'nome_graduacao': 'nome_graduacao',
    'tipo_publico': 'tipo_publico',
    'titulo_graduacao': 'titulo_graduacao',
    'certificado_ou_diploma': 'certificado_ou_diploma',
    'frase': 'frase',
    'corda': 'corda',
  };

  Future<void> _migrarGraduacoes() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Iniciando migração...';
      _statusColor = Colors.blue;
      _successCount = 0;
      _errorCount = 0;
      _alunosAtualizadosCount = 0;
      _graduacoesLogs = [];
      _alunosLogs = [];
    });

    try {
      // PASSO 1: CARREGAR CSV
      _graduacoesLogs.add('📂 Carregando arquivo CSV...');
      final String csvString = await rootBundle.loadString('assets/graduacoes.csv');
      List<Map<String, dynamic>> graduacoes = _parseCsv(csvString);

      _graduacoesLogs.add('📊 Total de graduações no CSV: ${graduacoes.length}');

      if (graduacoes.isEmpty) {
        setState(() {
          _statusMessage = 'Nenhum dado encontrado no arquivo CSV';
          _statusColor = Colors.orange;
          _isLoading = false;
        });
        return;
      }

      final CollectionReference graduacoesRef = FirebaseFirestore.instance.collection('graduacoes');
      final CollectionReference alunosRef = FirebaseFirestore.instance.collection('alunos');

      // PASSO 2: MIGRAR CADA GRADUAÇÃO
      for (var graduacao in graduacoes) {
        try {
          _graduacoesLogs.add('\n🔄 Processando: ${graduacao['nome_graduacao']} (nível ${graduacao['nivel_graduacao']})');

          // Verificar se já existe pelo nome_graduacao
          final querySnapshot = await graduacoesRef
              .where('nome_graduacao', isEqualTo: graduacao['nome_graduacao'])
              .get();

          String graduacaoId;

          if (querySnapshot.docs.isEmpty) {
            // Não existe - criar novo
            _graduacoesLogs.add('  ➕ Criando nova graduação...');
            final docRef = await graduacoesRef.add({
              ...graduacao,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            graduacaoId = docRef.id;
            _graduacoesLogs.add('  ✅ Criada com ID: $graduacaoId');
          } else {
            // Existe - atualizar
            graduacaoId = querySnapshot.docs.first.id;
            _graduacoesLogs.add('  🔄 Graduação já existe - ID: $graduacaoId');
            await graduacoesRef.doc(graduacaoId).update({
              ...graduacao,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            _graduacoesLogs.add('  ✅ Atualizada com sucesso');
          }

          setState(() {
            _successCount++;
          });

          // PASSO 3: BUSCAR E ATUALIZAR ALUNOS COM ESTA GRADUAÇÃO
          _graduacoesLogs.add('  🔍 Buscando alunos com graduacao_atual = "${graduacao['nome_graduacao']}"...');

          // Buscar alunos que tenham graduacao_atual igual ao nome_graduacao
          final alunosSnapshot = await alunosRef
              .where('graduacao_atual', isEqualTo: graduacao['nome_graduacao'])
              .get();

          if (alunosSnapshot.docs.isNotEmpty) {
            _graduacoesLogs.add('  👥 Encontrados ${alunosSnapshot.docs.length} alunos com esta graduação');

            // Atualizar cada aluno
            for (var alunoDoc in alunosSnapshot.docs) {
              try {
                final alunoData = alunoDoc.data() as Map<String, dynamic>;
                final alunoNome = alunoData['nome'] ?? 'Nome não informado';

                _alunosLogs.add('    👤 Aluno: $alunoNome (ID: ${alunoDoc.id})');

                // Campos de graduação que serão atualizados
                final Map<String, dynamic> updateData = {
                  'graduacao_id': graduacaoId,
                  'nivel_graduacao': graduacao['nivel_graduacao'],
                  'graduacao_cor1': graduacao['hex_cor1'],
                  'graduacao_cor2': graduacao['hex_cor2'],
                  'graduacao_ponta1': graduacao['hex_ponta1'],
                  'graduacao_ponta2': graduacao['hex_ponta2'],
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                // 🔥 IMPORTANTE: Manter o campo graduacao_atual original
                // Não vamos remover, apenas adicionar os novos campos

                await alunosRef.doc(alunoDoc.id).update(updateData);
                _alunosLogs.add('      ✅ Atualizado com ID da graduação: $graduacaoId');

                setState(() {
                  _alunosAtualizadosCount++;
                });

              } catch (e) {
                _alunosLogs.add('      ❌ Erro ao atualizar aluno ${alunoDoc.id}: $e');
              }
            }
          } else {
            _graduacoesLogs.add('  ℹ️ Nenhum aluno encontrado com esta graduação');
          }

        } catch (e) {
          setState(() {
            _errorCount++;
          });
          _graduacoesLogs.add('❌ ERRO na graduação: $e');
        }
      }

      // PASSO 4: RESUMO FINAL
      _graduacoesLogs.add('\n📋 ===== RESUMO FINAL =====');
      _graduacoesLogs.add('✅ Graduações processadas: $_successCount');
      _graduacoesLogs.add('👥 Alunos atualizados: $_alunosAtualizadosCount');
      _graduacoesLogs.add('❌ Erros: $_errorCount');

      setState(() {
        _statusMessage = 'Migração concluída! ✅ $_successCount graduações, 👥 $_alunosAtualizadosCount alunos';
        _statusColor = Colors.green;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _statusMessage = 'Erro ao carregar arquivo: $e';
        _statusColor = Colors.red;
        _isLoading = false;
      });
      _graduacoesLogs.add('❌ ERRO GERAL: $e');
    }
  }

  List<Map<String, dynamic>> _parseCsv(String csvString) {
    List<Map<String, dynamic>> result = [];
    List<String> lines = csvString.split('\n');

    if (lines.isEmpty) return result;

    String headerLine = lines.first.trim();
    List<String> headers = _parseCsvLine(headerLine);

    print('📋 Cabeçalhos encontrados: $headers');

    for (int i = 1; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      List<String> values = _parseCsvLine(line);

      if (values.length == headers.length) {
        Map<String, dynamic> graduacao = {};

        for (int j = 0; j < headers.length; j++) {
          String header = headers[j].trim();
          String value = values[j].trim();

          String fieldName = header;

          if (header == 'nivel_graduacao' || header == 'idade_minima') {
            graduacao[fieldName] = int.tryParse(value) ?? 0;
          } else if (header.startsWith('hex_')) {
            if (!value.startsWith('#')) {
              value = '#$value';
            }
            graduacao[fieldName] = value;
          } else {
            graduacao[fieldName] = value;
          }
        }

        if (graduacao.containsKey('nome_graduacao') &&
            graduacao.containsKey('nivel_graduacao')) {
          result.add(graduacao);
        }
      }
    }

    return result;
  }

  List<String> _parseCsvLine(String line) {
    List<String> result = [];
    bool insideQuotes = false;
    StringBuffer current = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      String char = line[i];

      if (char == '"') {
        insideQuotes = !insideQuotes;
      } else if (char == ',' && !insideQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }

    result.add(current.toString());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Migração de Graduações'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card de informações
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      size: 60,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Migração de Graduações',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Importa graduações e vincula aos alunos',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Status da migração
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _statusColor),
                ),
                child: Column(
                  children: [
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (_successCount > 0 || _errorCount > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatusChip(
                            'Graduações: $_successCount',
                            Colors.green,
                          ),
                          _buildStatusChip(
                            'Alunos: $_alunosAtualizadosCount',
                            Colors.blue,
                          ),
                          _buildStatusChip(
                            'Erros: $_errorCount',
                            Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Botão de migração
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _migrarGraduacoes,
              icon: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.upload_file),
              label: Text(_isLoading ? 'Migrando...' : 'Iniciar Migração'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // LOGS DAS GRADUAÇÕES
            if (_graduacoesLogs.isNotEmpty)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.grade, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '📋 LOG DAS GRADUAÇÕES:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _graduacoesLogs.length,
                          itemBuilder: (context, index) {
                            final log = _graduacoesLogs[index];
                            Color textColor = Colors.black87;

                            if (log.contains('✅')) textColor = Colors.green.shade700;
                            else if (log.contains('❌')) textColor = Colors.red.shade700;
                            else if (log.contains('👥')) textColor = Colors.blue.shade700;
                            else if (log.contains('ℹ️')) textColor = Colors.orange.shade700;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                  fontWeight: log.contains('====') ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 10),

            // LOGS DOS ALUNOS
            if (_alunosLogs.isNotEmpty)
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '👥 LOG DOS ALUNOS ATUALIZADOS:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _alunosLogs.length,
                          itemBuilder: (context, index) {
                            final log = _alunosLogs[index];
                            Color textColor = Colors.blue.shade700;

                            if (log.contains('✅')) textColor = Colors.green.shade700;
                            else if (log.contains('❌')) textColor = Colors.red.shade700;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textColor,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}