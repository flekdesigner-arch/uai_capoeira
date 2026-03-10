import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/migracao_chamadas_service.dart';
import '../../widgets/progress_dialog.dart';

class MigracaoChamadasScreen extends StatefulWidget {
  const MigracaoChamadasScreen({super.key});

  @override
  State<MigracaoChamadasScreen> createState() => _MigracaoChamadasScreenState();
}

class _MigracaoChamadasScreenState extends State<MigracaoChamadasScreen> {
  final MigracaoChamadasService _service = MigracaoChamadasService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _dadosJson = [];
  bool _isLoading = false;
  bool _arquivoCarregado = false;
  Map<String, dynamic>? _estatisticas;
  List<String> _arquivosCarregados = [];

  // Cache para alunos
  Map<String, Map<String, dynamic>> _cacheAlunos = {};

  final List<String> _arquivos = [
    'assets/log_presenca_alunos_1.json',
    'assets/log_presenca_alunos_2.json',
    'assets/log_presenca_alunos_3.json',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Migração de Chamadas'),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // CARD DE INFORMAÇÕES
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.purple.shade900),
                        const SizedBox(width: 8),
                        const Text(
                          'Instruções',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '📁 Arquivos fonte:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ..._arquivos.map((arquivo) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 2),
                      child: Text('• $arquivo'),
                    )),
                    const SizedBox(height: 12),
                    const Text(
                      '• 🔥 O sistema VINCULA pelo NOME DO ALUNO!\n'
                          '• Busca automaticamente: aluno_id, turma_id, turma_nome, academia\n'
                          '• Processar em 3 etapas:\n'
                          '  1️⃣ Criar registros individuais (log_presenca_alunos)\n'
                          '  2️⃣ Atualizar contadores dos alunos\n'
                          '  3️⃣ Agrupar chamadas por data/turma\n'
                          '• O processo é atômico (tudo ou nada)',
                      style: TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ÁREA DOS ARQUIVOS
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _arquivoCarregado ? Colors.green.shade400 : Colors.purple.shade200,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
                color: _arquivoCarregado ? Colors.green.shade50 : Colors.purple.shade50,
              ),
              child: Column(
                children: [
                  Icon(
                    _arquivoCarregado ? Icons.check_circle : Icons.folder_copy,
                    size: 60,
                    color: _arquivoCarregado ? Colors.green.shade700 : Colors.purple.shade900,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _arquivoCarregado
                        ? '✅ ${_arquivosCarregados.length} arquivos carregados!'
                        : '📄 ${_arquivos.length} arquivos disponíveis',
                    style: TextStyle(
                      color: _arquivoCarregado ? Colors.green.shade700 : Colors.purple.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (_arquivoCarregado) ...[
                    const SizedBox(height: 8),
                    ..._arquivosCarregados.map((arquivo) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '✅ $arquivo',
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: 12,
                        ),
                      ),
                    )),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _carregarArquivos,
                    icon: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Icon(_arquivoCarregado ? Icons.refresh : Icons.download),
                    label: Text(
                      _isLoading
                          ? 'CARREGANDO...'
                          : _arquivoCarregado
                          ? 'RECARREGAR ARQUIVOS'
                          : 'CARREGAR ARQUIVOS',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _arquivoCarregado ? Colors.green.shade700 : Colors.purple.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ESTATÍSTICAS (se houver dados)
            if (_estatisticas != null) ...[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Card(
                        elevation: 2,
                        color: Colors.purple.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Text(
                                '📊 PRÉ-VISUALIZAÇÃO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildEstatisticaRow(
                                'Total de registros',
                                '${_estatisticas!['totalRegistros']}',
                                Icons.list,
                                Colors.purple,
                              ),
                              _buildEstatisticaRow(
                                'Alunos únicos',
                                '${_estatisticas!['alunosUnicos']}',
                                Icons.people,
                                Colors.purple,
                              ),
                              _buildEstatisticaRow(
                                'Datas únicas',
                                '${_estatisticas!['datasUnicas']}',
                                Icons.calendar_today,
                                Colors.purple,
                              ),
                              _buildEstatisticaRow(
                                'Turmas envolvidas',
                                '${_estatisticas!['turmasUnicas']}',
                                Icons.group,
                                Colors.purple,
                              ),
                              const Divider(),
                              _buildEstatisticaRow(
                                '✅ Presenças',
                                '${_estatisticas!['totalPresentes']}',
                                Icons.check_circle,
                                Colors.green,
                              ),
                              _buildEstatisticaRow(
                                '❌ Ausências',
                                '${_estatisticas!['totalAusencias']}',
                                Icons.cancel,
                                Colors.red,
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
                          onPressed: _isLoading ? null : _iniciarMigracao,
                          icon: _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            _isLoading ? 'PROCESSANDO...' : 'INICIAR MIGRAÇÃO',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple.shade900,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEstatisticaRow(
      String label,
      String valor,
      IconData icon,
      Color cor,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 FUNÇÃO PARA CARREGAR ARQUIVOS
  Future<void> _carregarArquivos() async {
    setState(() {
      _isLoading = true;
      _arquivosCarregados.clear();
      _dadosJson.clear();
    });

    debugPrint('🚀 ===== INICIANDO CARREGAMENTO DE ARQUIVOS =====');

    try {
      List<Map<String, dynamic>> todosDados = [];

      for (String arquivo in _arquivos) {
        try {
          debugPrint('📂 Tentando carregar: $arquivo');

          final String jsonString = await rootBundle.loadString(arquivo);
          debugPrint('✅ Arquivo lido, tamanho: ${jsonString.length} caracteres');

          final List<dynamic> jsonData = json.decode(jsonString);
          debugPrint('✅ JSON decodificado, ${jsonData.length} registros');

          final dadosArquivo = jsonData.map((item) => item as Map<String, dynamic>).toList();

          todosDados.addAll(dadosArquivo);
          _arquivosCarregados.add(arquivo);

          debugPrint('✅ $arquivo: ${dadosArquivo.length} registros');

          // Mostrar amostra do primeiro registro
          if (dadosArquivo.isNotEmpty) {
            debugPrint('📝 Amostra do primeiro registro:');
            debugPrint('   Nome: ${dadosArquivo.first['aluno_nome']}');
            debugPrint('   Data: ${dadosArquivo.first['data_formatada']}');
            debugPrint('   Status: ${dadosArquivo.first['presente']}');
          }

        } catch (e, stacktrace) {
          debugPrint('❌ Erro CRÍTICO ao carregar $arquivo: $e');
          debugPrint('📚 Stacktrace: $stacktrace');
        }
      }

      if (todosDados.isEmpty) {
        throw Exception('Nenhum arquivo pôde ser carregado! Verifique os logs acima.');
      }

      debugPrint('📊 TOTAL DE REGISTROS ANTES DO FILTRO: ${todosDados.length}');

      // 🔥 TESTE: PEGA SÓ OS PRIMEIROS 10 PARA TESTAR (depois remover)
      // todosDados = todosDados.take(10).toList();
      // debugPrint('⚠️ MODO TESTE: Processando apenas 10 registros!');

      _dadosJson = todosDados;

      // Enriquecer dados
      await _enriquecerDados();

      // Calcular estatísticas
      _estatisticas = _service.calcularEstatisticas(_dadosJson);

      setState(() {
        _isLoading = false;
        _arquivoCarregado = true;
      });

      debugPrint('✅ CARREGAMENTO FINALIZADO COM SUCESSO!');
      debugPrint('📊 Total final: ${_dadosJson.length} registros');
      debugPrint('📦 Cache alunos: ${_cacheAlunos.length} alunos');

      _mostrarSnackBar(
        '✅ ${_arquivosCarregados.length} arquivos carregados! Total: ${_dadosJson.length} registros',
        Colors.green,
      );

    } catch (e, stacktrace) {
      debugPrint('❌ ERRO FATAL NO CARREGAMENTO: $e');
      debugPrint('📚 Stacktrace: $stacktrace');

      setState(() {
        _isLoading = false;
        _arquivoCarregado = false;
      });

      _mostrarSnackBar(
        '❌ Erro ao carregar arquivos: $e',
        Colors.red,
      );
    }
  }

  // 🔥 FUNÇÃO PARA ENRIQUECER DADOS - AGORA COM MUITOS LOGS!
  Future<void> _enriquecerDados() async {
    debugPrint('\n🔍 ===== INICIANDO ENRIQUECIMENTO DE DADOS =====');
    debugPrint('📊 Registros para processar: ${_dadosJson.length}');

    // Coletar nomes únicos dos alunos
    final nomesAlunos = _dadosJson
        .map((e) => e['aluno_nome']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    debugPrint('👥 Alunos únicos encontrados: ${nomesAlunos.length}');

    if (nomesAlunos.isEmpty) {
      debugPrint('❌ CRÍTICO: Nenhum nome de aluno encontrado nos JSONs!');
      return;
    }

    // Mostrar os primeiros 10 nomes como amostra
    debugPrint('📝 Amostra dos primeiros 10 alunos:');
    for (int i = 0; i < (nomesAlunos.length > 10 ? 10 : nomesAlunos.length); i++) {
      debugPrint('   ${i + 1}. ${nomesAlunos[i]}');
    }

    _cacheAlunos.clear();

    // Buscar alunos em lote
    debugPrint('🔍 Consultando Firestore...');

    for (int i = 0; i < nomesAlunos.length; i += 10) {
      final lote = nomesAlunos.skip(i).take(10).toList();
      debugPrint('📦 Processando lote ${i ~/ 10 + 1}/${(nomesAlunos.length / 10).ceil()}');

      try {
        final querySnapshot = await _firestore
            .collection('alunos')
            .where('nome', whereIn: lote)
            .get();

        debugPrint('   ✅ Lote retornou ${querySnapshot.docs.length} alunos');

        for (var doc in querySnapshot.docs) {
          final alunoData = doc.data();
          final nomeAluno = alunoData['nome']?.toString() ?? '';

          _cacheAlunos[nomeAluno] = {
            'aluno_id': doc.id,
            'turma_id': alunoData['turma_id'] ?? '',
            'turma_nome': alunoData['turma'] ?? '',
            'academia_id': alunoData['academia_id'] ?? '',
            'academia_nome': alunoData['academia'] ?? '',
          };

          debugPrint('   ✅ Cache adicionado: $nomeAluno -> ${doc.id}');
        }

        // Verificar alunos não encontrados neste lote
        final encontrados = querySnapshot.docs.map((d) => d.data()['nome']?.toString()).toSet();
        final naoEncontrados = lote.where((nome) => !encontrados.contains(nome)).toList();

        if (naoEncontrados.isNotEmpty) {
          debugPrint('   ⚠️ Alunos NÃO encontrados neste lote:');
          for (var nome in naoEncontrados) {
            debugPrint('      • $nome');
          }
        }

      } catch (e, stacktrace) {
        debugPrint('❌ Erro ao buscar lote: $e');
        debugPrint('📚 Stacktrace: $stacktrace');
      }
    }

    debugPrint('📦 Cache final: ${_cacheAlunos.length} alunos encontrados');

    // Agora, enriquecer cada registro
    debugPrint('\n🔄 Enriquecendo registros individuais...');

    int encontrados = 0;
    int naoEncontrados = 0;
    List<String> alunosNaoEncontradosList = [];

    for (var registro in _dadosJson) {
      final nomeAluno = registro['aluno_nome']?.toString() ?? '';

      if (_cacheAlunos.containsKey(nomeAluno)) {
        final dadosAluno = _cacheAlunos[nomeAluno]!;

        registro['aluno_id'] = dadosAluno['aluno_id'];
        registro['turma_id'] = dadosAluno['turma_id'];
        registro['turma_nome'] = dadosAluno['turma_nome'];
        registro['academia_id'] = dadosAluno['academia_id'];
        registro['academia_nome'] = dadosAluno['academia_nome'];

        encontrados++;
      } else {
        registro['aluno_id'] = null;
        registro['turma_id'] = null;
        registro['turma_nome'] = null;
        registro['academia_id'] = null;
        registro['academia_nome'] = null;
        registro['erro'] = 'Aluno não encontrado no Firestore';

        naoEncontrados++;
        if (!alunosNaoEncontradosList.contains(nomeAluno)) {
          alunosNaoEncontradosList.add(nomeAluno);
        }
      }
    }

    debugPrint('\n📊 RESULTADO DO ENRIQUECIMENTO:');
    debugPrint('   ✅ Registros enriquecidos: $encontrados');
    debugPrint('   ❌ Registros ignorados: $naoEncontrados');

    if (alunosNaoEncontradosList.isNotEmpty) {
      debugPrint('\n⚠️ Alunos NÃO encontrados no Firestore:');
      for (var nome in alunosNaoEncontradosList) {
        debugPrint('   • $nome');
      }
    }

    // Filtrar apenas registros com aluno encontrado
    final antes = _dadosJson.length;
    _dadosJson = _dadosJson.where((r) => r['aluno_id'] != null).toList();
    final depois = _dadosJson.length;

    debugPrint('\n🎯 FILTRAGEM FINAL:');
    debugPrint('   📉 Registros removidos: ${antes - depois}');
    debugPrint('   📈 Registros válidos: $depois');
    debugPrint('🔍 ===== FIM DO ENRIQUECIMENTO =====\n');
  }

  Future<void> _iniciarMigracao() async {
    final user = _auth.currentUser;
    if (user == null) {
      _mostrarSnackBar('❌ Usuário não autenticado!', Colors.red);
      return;
    }

    debugPrint('\n🚀 ===== INICIANDO MIGRAÇÃO =====');
    debugPrint('📊 Total de registros: ${_dadosJson.length}');
    debugPrint('👤 Professor: ${user.displayName} (${user.uid})');

    // Mostrar amostra dos dados enriquecidos
    if (_dadosJson.isNotEmpty) {
      debugPrint('📝 Amostra do primeiro registro enriquecido:');
      debugPrint('   Nome: ${_dadosJson.first['aluno_nome']}');
      debugPrint('   aluno_id: ${_dadosJson.first['aluno_id']}');
      debugPrint('   turma_id: ${_dadosJson.first['turma_id']}');
      debugPrint('   presente: ${_dadosJson.first['presente']}');
    }

    // Verificar se tem dados para migrar
    if (_dadosJson.isEmpty) {
      debugPrint('❌ ERRO: Nenhum registro válido para migrar!');
      _mostrarSnackBar('❌ Nenhum registro válido para migrar!', Colors.red);
      return;
    }

    // Dialog de progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProgressDialog(
        message: 'Preparando migração com ${_dadosJson.length} registros...',
      ),
    );

    try {
      debugPrint('⏳ Chamando serviço de migração...');

      final resultado = await _service.migrarChamadas(
        dados: _dadosJson,
        professorId: user.uid,
        professorNome: user.displayName ?? 'Sistema',
        onProgress: (progress, message) {
          debugPrint('📊 Progresso: $progress% - $message');
        },
      );

      debugPrint('✅ Serviço finalizado com sucesso!');
      debugPrint('📊 Resultado: $resultado');

      if (context.mounted) Navigator.pop(context);
      _mostrarResultadoDialog(resultado);

    } catch (e, stacktrace) {
      debugPrint('❌ ERRO NA MIGRAÇÃO: $e');
      debugPrint('📚 Stacktrace: $stacktrace');

      if (context.mounted) Navigator.pop(context);
      _mostrarSnackBar('❌ Erro na migração: $e', Colors.red);
    }
  }

  void _mostrarResultadoDialog(Map<String, dynamic> resultado) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              resultado['sucesso'] ? Icons.check_circle : Icons.warning,
              color: resultado['sucesso'] ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(resultado['sucesso'] ? 'SUCESSO!' : 'ATENÇÃO'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildResultadoItem(
                  'Registros individuais',
                  resultado['logsCriados'],
                  resultado['totalRegistros'],
                ),
                _buildResultadoItem(
                  'Contadores atualizados',
                  resultado['contadoresAtualizados'],
                  resultado['alunosUnicos'],
                ),
                _buildResultadoItem(
                  'Chamadas de turma',
                  resultado['chamadasCriadas'],
                  resultado['chamadasEsperadas'],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '⏱️ Tempo total: ${resultado['tempoExecucao']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (resultado['erros'] != null && resultado['erros'].length > 0) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '❌ Erros encontrados:',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...resultado['erros'].map<Widget>((erro) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $erro',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultadoItem(String label, int valor, int total) {
    final cor = valor == total ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record, size: 12, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            '$valor/$total',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarSnackBar(String mensagem, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}