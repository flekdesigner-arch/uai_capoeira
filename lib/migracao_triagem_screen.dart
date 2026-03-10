import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'migracao_detalhe_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

// ==================== MODELO DE DADOS PARA JSON ====================
class AlunoJSON {
  final String? nome;
  final String? cpf;
  final String? fotoUrl;
  final String? apelido;
  final String? sexo;
  final String? dataNascimento;
  final String? graduacao;
  final String? dataGraduacao;
  final String? tempoCapoeira;
  final String? endereco;
  final String? contato;
  final String? responsavel;
  final String? contatoResponsavel;
  final String? status;
  final String? cidade;
  final String? academia;
  final String? modalidade;
  final String? turma;
  final String? cadastroPor;
  final String? dataCadastro;
  final String? atualizadoPor;
  final String? dataAtualizacao;
  final bool editavel;
  final int? indexPlanilha;

  AlunoJSON({
    required this.nome,
    required this.cpf,
    required this.fotoUrl,
    required this.apelido,
    required this.sexo,
    required this.dataNascimento,
    required this.graduacao,
    required this.dataGraduacao,
    required this.tempoCapoeira,
    required this.endereco,
    required this.contato,
    required this.responsavel,
    required this.contatoResponsavel,
    required this.status,
    required this.cidade,
    required this.academia,
    required this.modalidade,
    required this.turma,
    required this.cadastroPor,
    required this.dataCadastro,
    required this.atualizadoPor,
    required this.dataAtualizacao,
    required this.editavel,
    required this.indexPlanilha,
  });

  factory AlunoJSON.fromJson(Map<String, dynamic> json) {
    return AlunoJSON(
      nome: json['nome_do_aluno']?.toString(),
      cpf: json['cpf']?.toString(),
      fotoUrl: json['foto_perfil_aluno']?.toString(),
      apelido: json['apelido']?.toString(),
      sexo: json['sexo']?.toString(),
      dataNascimento: json['data_nascimento']?.toString(),
      graduacao: json['graduacao_atual']?.toString(),
      dataGraduacao: json['data_graduacao_atual']?.toString(),
      tempoCapoeira: json['data_tempo_de_capoeira']?.toString(),
      endereco: json['endereco']?.toString(),
      contato: json['contato_aluno']?.toString(),
      responsavel: json['nome_responsavel']?.toString(),
      contatoResponsavel: json['contato_do_responsavel']?.toString(),
      status: json['status_atividade']?.toString(),
      cidade: json['cidade']?.toString(),
      academia: json['academia']?.toString(),
      modalidade: json['modalidade']?.toString(),
      turma: json['turma']?.toString(),
      cadastroPor: json['cadastro_realizado_por']?.toString(),
      dataCadastro: json['data_do_cadastro']?.toString(),
      atualizadoPor: json['atualizado_por']?.toString(),
      dataAtualizacao: json['data_atualizacao']?.toString(),
      editavel: json['editavel'] == true || json['editavel']?.toString().toLowerCase() == "true",
      indexPlanilha: json['index_planilha'] != null
          ? int.tryParse(json['index_planilha'].toString())
          : json['index'] != null
          ? int.tryParse(json['index'].toString())
          : null,
    );
  }
}

// ==================== SERVIÇO DE MIGRAÇÃO EM MASSA ====================
class MigracaoMassaService {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  MigracaoMassaService({
    required this.firestore,
    required this.storage,
  });

  // Método para migrar foto com compressão
  Future<String> migrarFotoComprimida(String driveUrl, String nomeAluno) async {
    if (driveUrl.isEmpty) return '';

    try {
      if (!driveUrl.contains("&export=view")) {
        driveUrl += "&export=view";
      }

      final response = await http.get(Uri.parse(driveUrl));
      if (response.statusCode != 200) {
        debugPrint("❌ Falha ao baixar foto: ${response.statusCode}");
        return '';
      }

      // COMPRESSÃO DA IMAGEM PARA 80% DE QUALIDADE
      final imageBytes = response.bodyBytes;
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        debugPrint("❌ Erro ao decodificar imagem");
        return '';
      }

      // Comprimir para JPEG com 80% de qualidade
      final compressedBytes = img.encodeJpg(image, quality: 80);

      final fileName = _sanitizeFileName(nomeAluno);
      final storageRef = storage
          .ref()
          .child('foto_alunos/${fileName}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putData(compressedBytes, SettableMetadata(contentType: 'image/jpeg'));
      debugPrint("✅ Foto comprimida e enviada: $fileName");
      return await storageRef.getDownloadURL();
    } catch (e) {
      debugPrint("❌ Erro ao migrar foto: $e");
      return '';
    }
  }

  String _sanitizeFileName(String nome) {
    return nome
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  // Buscar academias
  Future<Map<String, String>> buscarAcademias() async {
    try {
      final snapshot = await firestore
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .orderBy('nome')
          .get();

      final academiasMap = <String, String>{};
      for (var doc in snapshot.docs) {
        final nome = doc['nome'] ?? 'Sem nome';
        academiasMap[doc.id] = nome;
      }
      debugPrint("✅ Academias carregadas: ${academiasMap.length}");
      return academiasMap;
    } catch (e) {
      debugPrint('❌ Erro ao buscar academias: $e');
      return {};
    }
  }

  // Buscar turmas
  Future<Map<String, Map<String, dynamic>>> buscarTurmas(String academiaId) async {
    if (academiaId.isEmpty) return {};

    try {
      final snapshot = await firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .orderBy('nome')
          .get();

      final turmasMap = <String, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        turmasMap[doc.id] = {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'horario': data['horario_display'] ?? '',
        };
      }
      return turmasMap;
    } catch (e) {
      debugPrint('❌ Erro ao buscar turmas: $e');
      return {};
    }
  }

  // Buscar graduações
  Future<Map<String, String>> buscarGraduacoes() async {
    try {
      final snapshot = await firestore
          .collection('graduacoes')
          .orderBy('nivel_graduacao')
          .get();

      final gradMap = <String, String>{};
      for (var doc in snapshot.docs) {
        final nome = doc['nome_graduacao']?.toString().trim() ?? '';
        if (nome.isNotEmpty) {
          gradMap[nome] = doc.id;
        }
      }
      debugPrint("✅ Graduações carregadas: ${gradMap.length}");
      return gradMap;
    } catch (e) {
      debugPrint("❌ ERRO AO BUSCAR GRADUAÇÕES: $e");
      return {};
    }
  }

  // Salvar aluno no Firestore
  Future<void> salvarAluno(Map<String, dynamic> dados) async {
    try {
      await firestore.collection('alunos').add(dados);
    } catch (e) {
      debugPrint("❌ Erro ao salvar aluno: $e");
      rethrow;
    }
  }

  // Converter data string para timestamp
  Timestamp? parseDateToTimestamp(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;

    final formats = [
      'dd/MM/yyyy, HH:mm:ss',
      'dd/MM/yyyy HH:mm:ss',
      'dd/MM/yyyy',
      'yyyy-MM-dd',
      'dd/MM/yy',
    ];

    for (var format in formats) {
      try {
        return Timestamp.fromDate(DateFormat(format).parseStrict(dateString));
      } catch (_) {}
    }

    try {
      final parts = dateString.split(' ');
      if (parts.length >= 4 && dateString.contains('GMT')) {
        final day = int.parse(parts[2]);
        final monthStr = parts[1];
        final year = int.parse(parts[3]);
        final monthMap = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
        };
        final monthNum = monthMap[monthStr];
        if (monthNum != null) {
          return Timestamp.fromDate(DateTime(year, monthNum, day));
        }
      }
    } catch (_) {}

    return null;
  }
}

// ==================== TELA PRINCIPAL DE MIGRAÇÃO ====================
class MigracaoTriagemScreen extends StatefulWidget {
  const MigracaoTriagemScreen({super.key});

  @override
  State<MigracaoTriagemScreen> createState() => _MigracaoTriagemScreenState();
}

class _MigracaoTriagemScreenState extends State<MigracaoTriagemScreen> {
  late Future<List<dynamic>> _alunosData;
  List<dynamic> _alunosFiltrados = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _filterStatus = 'Todos';
  bool _isMigrandoEmMassa = false;
  int _alunosMigrados = 0;
  int _totalAlunosParaMigrar = 0;
  late MigracaoMassaService _migracaoService;
  final List<String> _errosMigracao = [];

  @override
  void initState() {
    super.initState();
    _migracaoService = MigracaoMassaService(
      firestore: FirebaseFirestore.instance,
      storage: FirebaseStorage.instance,
    );
    _alunosData = _fetchAlunos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============ LEITURA DO ARQUIVO JSON ============
  Future<List<AlunoJSON>> _lerAlunosDoJSON() async {
    try {
      debugPrint("📂 Carregando arquivo alunos.json...");

      // Carrega o arquivo JSON da pasta assets
      final jsonString = await rootBundle.loadString('assets/alunos.json');

      // Decodifica o JSON
      final dynamic jsonData = jsonDecode(jsonString);

      List<dynamic> alunosList = [];

      if (jsonData is List) {
        // Se o JSON for diretamente uma lista
        alunosList = jsonData;
        debugPrint("📋 JSON formato: Lista direta com ${alunosList.length} itens");
      } else if (jsonData is Map) {
        // Se o JSON for um objeto com uma chave específica
        if (jsonData.containsKey('alunos')) {
          alunosList = jsonData['alunos'] as List;
          debugPrint("📋 JSON formato: Objeto com chave 'alunos' - ${alunosList.length} itens");
        } else if (jsonData.containsKey('data')) {
          alunosList = jsonData['data'] as List;
          debugPrint("📋 JSON formato: Objeto com chave 'data' - ${alunosList.length} itens");
        } else {
          // Tenta pegar o primeiro valor que seja uma lista
          try {
            final firstList = jsonData.values.firstWhere(
                  (v) => v is List,
              orElse: () => [],
            );
            alunosList = firstList as List;
            debugPrint("📋 JSON formato: Primeira lista encontrada - ${alunosList.length} itens");
          } catch (e) {
            debugPrint("❌ Nenhuma lista encontrada no JSON");
          }
        }
      }

      final alunos = <AlunoJSON>[];

      for (int i = 0; i < alunosList.length; i++) {
        final item = alunosList[i];

        try {
          // Adiciona o index se não existir
          if (item is Map<String, dynamic>) {
            if (!item.containsKey('index_planilha') && !item.containsKey('index')) {
              item['index_planilha'] = i;
            }
          }

          final aluno = AlunoJSON.fromJson(item);
          alunos.add(aluno);
        } catch (e) {
          debugPrint("❌ Erro ao processar aluno $i: $e");
        }
      }

      debugPrint("✅ Total de alunos lidos do JSON: ${alunos.length}");
      return alunos;
    } catch (e) {
      debugPrint("❌ Erro CRÍTICO ao ler JSON: $e");
      throw Exception('Erro ao ler arquivo JSON: $e\nVerifique se o arquivo alunos.json existe na pasta assets');
    }
  }

  // ============ BUSCAR ALUNOS PARA EXIBIÇÃO ============
  Future<List<dynamic>> _fetchAlunos() async {
    try {
      final alunosJSON = await _lerAlunosDoJSON();

      // Converter para o formato que a tela espera
      final alunos = alunosJSON.map((aluno) => {
        'nome_do_aluno': aluno.nome ?? 'Sem nome',
        'status_migracao': 'Pendente',
        'turma_atual': aluno.turma ?? 'Sem turma',
        'data_triagem': '',
        'index_planilha': aluno.indexPlanilha,
        ..._alunoJSONToMap(aluno),
      }).toList();

      _alunosFiltrados = List.from(alunos);
      return alunos;
    } catch (e) {
      debugPrint("❌ Erro ao carregar alunos: $e");
      throw Exception('Erro ao carregar dados do JSON: $e');
    }
  }

  // ============ CONVERSOR DE AlunoJSON PARA MAP ============
  Map<String, dynamic> _alunoJSONToMap(AlunoJSON aluno) {
    return {
      'cpf': aluno.cpf,
      'foto_perfil_aluno': aluno.fotoUrl,
      'apelido': aluno.apelido,
      'sexo': aluno.sexo,
      'data_nascimento': aluno.dataNascimento,
      'graduacao_atual': aluno.graduacao,
      'data_graduacao_atual': aluno.dataGraduacao,
      'data_tempo_de_capoeira': aluno.tempoCapoeira,
      'endereco': aluno.endereco,
      'contato_aluno': aluno.contato,
      'nome_responsavel': aluno.responsavel,
      'contato_do_responsavel': aluno.contatoResponsavel,
      'status_atividade': aluno.status,
      'cidade': aluno.cidade,
      'academia': aluno.academia,
      'modalidade': aluno.modalidade,
      'turma': aluno.turma,
      'cadastro_realizado_por': aluno.cadastroPor,
      'data_do_cadastro': aluno.dataCadastro,
      'atualizado_por': aluno.atualizadoPor,
      'data_atualizacao': aluno.dataAtualizacao,
      'editavel': aluno.editavel ? "true" : "false",
    };
  }

  // ============ MÉTODO PRINCIPAL - MIGRAÇÃO EM MASSA DO JSON ============
  Future<void> _iniciarMigracaoMassaJSON() async {
    setState(() {
      _isMigrandoEmMassa = true;
      _alunosMigrados = 0;
      _errosMigracao.clear();
    });

    try {
      final alunosJSON = await _lerAlunosDoJSON();

      if (alunosJSON.isEmpty) {
        _mostrarErro('Nenhum aluno encontrado no arquivo JSON');
        setState(() => _isMigrandoEmMassa = false);
        return;
      }

      setState(() {
        _totalAlunosParaMigrar = alunosJSON.length;
      });

      // Carrega dados de referência uma única vez
      debugPrint("🔄 Carregando dados de referência...");
      final academias = await _migracaoService.buscarAcademias();
      final graduacoes = await _migracaoService.buscarGraduacoes();

      // Mapa para cache de turmas por academia
      final turmasCache = <String, Map<String, Map<String, dynamic>>>{};

      // Mostrar diálogo de progresso
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Migrando Alunos do JSON',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: _totalAlunosParaMigrar > 0
                                  ? _alunosMigrados / _totalAlunosParaMigrar
                                  : 0,
                              strokeWidth: 8,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                          Text(
                            '${((_alunosMigrados / _totalAlunosParaMigrar) * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '$_alunosMigrados / $_totalAlunosParaMigrar',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _totalAlunosParaMigrar > 0
                            ? _alunosMigrados / _totalAlunosParaMigrar
                            : 0,
                        backgroundColor: Colors.grey[200],
                        color: Colors.green,
                        minHeight: 8,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Processando: ${_alunosMigrados < _totalAlunosParaMigrar ? alunosJSON[_alunosMigrados].nome ?? 'Aluno' : 'Concluído'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_errosMigracao.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red[700], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Erros: ${_errosMigracao.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      // Processar cada aluno
      for (int i = 0; i < alunosJSON.length; i++) {
        final aluno = alunosJSON[i];

        try {
          debugPrint('📦 [${i + 1}/${alunosJSON.length}] Processando: ${aluno.nome ?? 'Sem nome'}');

          // 1. Migrar foto (com compressão de 80%)
          String fotoFinalUrl = '';
          if (aluno.fotoUrl != null && aluno.fotoUrl!.isNotEmpty && aluno.nome != null) {
            try {
              fotoFinalUrl = await _migracaoService.migrarFotoComprimida(
                aluno.fotoUrl!,
                aluno.nome!,
              );
              if (fotoFinalUrl.isNotEmpty) {
                debugPrint('✅ Foto migrada com sucesso');
              }
            } catch (e) {
              debugPrint('⚠️ Erro ao migrar foto: $e');
              _errosMigracao.add('${aluno.nome}: Erro na foto');
            }
          }

          // 2. Buscar dados da graduação
          Map<String, dynamic> graduacaoData = {};
          String? graduacaoId;

          if (aluno.graduacao != null && aluno.graduacao!.isNotEmpty) {
            graduacaoId = graduacoes[aluno.graduacao!];
            if (graduacaoId != null) {
              try {
                final gradDoc = await FirebaseFirestore.instance
                    .collection('graduacoes')
                    .doc(graduacaoId)
                    .get();

                if (gradDoc.exists) {
                  graduacaoData = {
                    'graduacao_cor1': gradDoc['hex_cor1'],
                    'graduacao_cor2': gradDoc['hex_cor2'],
                    'graduacao_ponta1': gradDoc['hex_ponta1'],
                    'graduacao_ponta2': gradDoc['hex_ponta2'],
                    'nivel_graduacao': gradDoc['nivel_graduacao'],
                  };
                }
              } catch (e) {
                debugPrint('⚠️ Erro ao buscar dados da graduação: $e');
              }
            }
          }

          // 3. Buscar academia e turma
          String? academiaId;
          String? academiaNome;
          String? turmaId;
          String? turmaNome;

          if (aluno.academia != null && aluno.academia!.isNotEmpty) {
            final academiaEntry = academias.entries.firstWhere(
                  (entry) => entry.value.toLowerCase().trim() == aluno.academia!.toLowerCase().trim(),
              orElse: () => MapEntry('', ''),
            );

            if (academiaEntry.key.isNotEmpty) {
              academiaId = academiaEntry.key;
              academiaNome = academiaEntry.value;

              if (aluno.turma != null && aluno.turma!.isNotEmpty) {
                if (!turmasCache.containsKey(academiaId)) {
                  final turmas = await _migracaoService.buscarTurmas(academiaId);
                  turmasCache[academiaId] = turmas;
                }

                final turmas = turmasCache[academiaId]!;
                final turmaEntry = turmas.entries.firstWhere(
                      (entry) => entry.value['nome'].toString().toLowerCase().trim() == aluno.turma!.toLowerCase().trim(),
                  orElse: () => MapEntry('', {}),
                );

                if (turmaEntry.key.isNotEmpty) {
                  turmaId = turmaEntry.key;
                  turmaNome = turmaEntry.value['nome'] as String?;
                }
              }
            }
          }

          // 4. Preparar dados para salvar
          final dadosParaSalvar = {
            'nome': aluno.nome?.trim() ?? '',
            'cpf': aluno.cpf?.trim() ?? '',
            'foto_perfil_aluno': fotoFinalUrl,
            'apelido': aluno.apelido?.trim() ?? '',
            'sexo': aluno.sexo?.toUpperCase() ?? 'MASCULINO',
            'data_nascimento': _migracaoService.parseDateToTimestamp(aluno.dataNascimento),
            'graduacao_atual': aluno.graduacao?.trim() ?? '',
            'graduacao_id': graduacaoId,
            'data_graduacao_atual': _migracaoService.parseDateToTimestamp(aluno.dataGraduacao),
            'tempo_capoeira': _migracaoService.parseDateToTimestamp(aluno.tempoCapoeira),
            'endereco': aluno.endereco?.trim() ?? '',
            'contato_aluno': aluno.contato?.trim() ?? '',
            'nome_responsavel': aluno.responsavel?.trim() ?? '',
            'contato_responsavel': aluno.contatoResponsavel?.trim() ?? '',
            'status_atividade': aluno.status?.toUpperCase() ?? 'ATIVO(A)',
            'cidade': aluno.cidade?.trim() ?? '',
            'modalidade': aluno.modalidade?.trim() ?? '',
            'editavel': aluno.editavel,
            'cadastro_realizado_por': aluno.cadastroPor?.trim() ?? '',
            'data_do_cadastro': _migracaoService.parseDateToTimestamp(aluno.dataCadastro),
            'atualizado_por': aluno.atualizadoPor?.trim() ?? '',
            'data_atualizacao': _migracaoService.parseDateToTimestamp(aluno.dataAtualizacao),
            'index_original': aluno.indexPlanilha,
            'migrado_em': FieldValue.serverTimestamp(),
            'origem_dados': 'migracao_json',
            ...graduacaoData,
          };

          // Adicionar vínculos de academia e turma se encontrados
          if (academiaId != null && academiaId.isNotEmpty) {
            dadosParaSalvar['academia_id'] = academiaId;
            dadosParaSalvar['academia'] = academiaNome ?? aluno.academia?.trim();
          } else {
            dadosParaSalvar['academia'] = aluno.academia?.trim() ?? '';
          }

          if (turmaId != null && turmaId.isNotEmpty) {
            dadosParaSalvar['turma_id'] = turmaId;
            dadosParaSalvar['turma'] = turmaNome ?? aluno.turma?.trim();
          } else {
            dadosParaSalvar['turma'] = aluno.turma?.trim() ?? '';
          }

          // 5. Salvar no Firestore
          await _migracaoService.salvarAluno(dadosParaSalvar);
          debugPrint('✅ Aluno salvo no Firestore: ${aluno.nome}');

          // Atualizar progresso
          if (mounted) {
            setState(() {
              _alunosMigrados = i + 1;
            });
          }

        } catch (e) {
          debugPrint('❌ Erro ao migrar aluno ${aluno.nome}: $e');
          _errosMigracao.add('${aluno.nome}: $e');
        }
      }

      // Fechar diálogo e mostrar resultado
      if (mounted) {
        Navigator.pop(context); // Fecha diálogo de progresso

        setState(() {
          _isMigrandoEmMassa = false;
        });

        _mostrarResultadoMigracaoMassa();

        // Recarregar dados
        _alunosData = _fetchAlunos();
        setState(() {});
      }

    } catch (e) {
      debugPrint('❌ ERRO CRÍTICO na migração em massa: $e');
      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _isMigrandoEmMassa = false;
        });
        _mostrarErro('Erro na migração em massa: $e');
      }
    }
  }

  // ============ MOSTRAR RESULTADO DA MIGRAÇÃO ============
  void _mostrarResultadoMigracaoMassa() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migração Concluída'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(
                Icons.check_circle,
                size: 64,
                color: Colors.green[400],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Migração em massa do JSON concluída!',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('$_totalAlunosParaMigrar'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Migrados:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('$_alunosMigrados', style: const TextStyle(color: Colors.green)),
                ],
              ),
            ),
            if (_errosMigracao.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Erros: ${_errosMigracao.length}',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_errosMigracao.length > 3) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errosMigracao.take(3).join('\n'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                        ),
                      ),
                      if (_errosMigracao.length > 3)
                        Text(
                          '... e mais ${_errosMigracao.length - 3} erros',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _errosMigracao.join('\n'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Fotos migradas com compressão de 80% de qualidade.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============ FILTROS ============
  void _filterAlunos(String query, String status) {
    setState(() {
      _isSearching = query.isNotEmpty;
      _filterStatus = status;

      _alunosData.then((alunos) {
        List<dynamic> filtered = alunos;

        if (query.isNotEmpty) {
          filtered = filtered.where((aluno) {
            final nome = aluno['nome_do_aluno']?.toString().toLowerCase() ?? '';
            return nome.contains(query.toLowerCase());
          }).toList();
        }

        if (status != 'Todos') {
          filtered = filtered.where((aluno) {
            final alunoStatus = aluno['status_migracao']?.toString() ?? 'Pendente';
            return alunoStatus == status;
          }).toList();
        }

        _alunosFiltrados = filtered;
      });
    });
  }

  // ============ NAVEGAÇÃO ============
  void _navigateToDetail(Map<String, dynamic> alunoData) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MigracaoDetalheScreen(alunoData: alunoData),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    ).then((_) {
      setState(() {
        _alunosData = _fetchAlunos();
      });
    });
  }

  // ============ CORES E ÍCONES ============
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Concluído':
        return Colors.green;
      case 'Em Andamento':
        return Colors.orange;
      case 'Pendente':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Concluído':
        return Icons.check_circle;
      case 'Em Andamento':
        return Icons.autorenew;
      case 'Pendente':
        return Icons.pending;
      default:
        return Icons.help_outline;
    }
  }

  // ============ WIDGETS DE CARREGAMENTO E ERRO ============
  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Ops! Algo deu errado',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.red[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _alunosData = _fetchAlunos();
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarMensagem(String mensagem, Color cor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ============ STAT CARD ============
  Widget _buildStatCard(String title, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.red[700],
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // ============ BUILD PRINCIPAL ============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Triagem de Migração',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Colors.red[800],
        foregroundColor: Colors.white,
        elevation: 3,
        shadowColor: Colors.red[900]!.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
        actions: [
          // BOTÃO PARA MIGRAÇÃO EM MASSA DO JSON
          IconButton(
            icon: _isMigrandoEmMassa
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.cloud_upload),
            onPressed: _isMigrandoEmMassa ? null : _iniciarMigracaoMassaJSON,
            tooltip: 'Migrar todos do JSON',
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sobre a Migração'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Migração em Massa via JSON',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Os dados são lidos do arquivo alunos.json\n'
                            '• Fotos são comprimidas para 80% de qualidade\n'
                            '• Upload automático para o Firebase Storage\n'
                            '• Vinculação com academias e turmas existentes\n'
                            '• Datas são convertidas automaticamente',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700], size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Certifique-se que o arquivo alunos.json está na pasta assets',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Cabeçalho com estatísticas
          FutureBuilder<List<dynamic>>(
            future: _alunosData,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final alunos = snapshot.data!;
                final total = alunos.length;
                final concluidos = alunos.where((a) => a['status_migracao'] == 'Concluído').length;
                final pendentes = total - concluidos;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.red[50]!,
                        Colors.orange[50]!,
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard('Total', total.toString(), Icons.group),
                      _buildStatCard('Concluídos', concluidos.toString(), Icons.check_circle),
                      _buildStatCard('Pendentes', pendentes.toString(), Icons.pending),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms);
              }
              return Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard('Total', '...', Icons.group),
                    _buildStatCard('Concluídos', '...', Icons.check_circle),
                    _buildStatCard('Pendentes', '...', Icons.pending),
                  ],
                ),
              );
            },
          ),

          // Barra de pesquisa e filtros
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar aluno...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterAlunos('', _filterStatus);
                      },
                    )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (value) => _filterAlunos(value, _filterStatus),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Todos', 'Pendente', 'Concluído']
                        .map((status) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(status),
                        selected: _filterStatus == status,
                        onSelected: (selected) {
                          _filterAlunos(_searchController.text, status);
                        },
                        backgroundColor: Colors.grey[200],
                        selectedColor: status == 'Concluído'
                            ? Colors.green
                            : status == 'Pendente'
                            ? Colors.red
                            : Colors.grey,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _filterStatus == status
                              ? Colors.white
                              : Colors.grey[700],
                        ),
                      ),
                    ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),

          // Lista de alunos
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _alunosData,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildShimmerLoading();
                }

                if (snapshot.hasError) {
                  return _buildErrorWidget(snapshot.error.toString());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum aluno encontrado',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Verifique se o arquivo alunos.json está na pasta assets',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _alunosData = _fetchAlunos();
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Recarregar'),
                        ),
                      ],
                    ),
                  );
                }

                final alunos = _isSearching || _filterStatus != 'Todos'
                    ? _alunosFiltrados
                    : snapshot.data!;

                if (alunos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum aluno encontrado',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tente outros termos de busca',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: alunos.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final aluno = alunos[index] as Map<String, dynamic>;
                    final nome = aluno['nome_do_aluno'] ?? 'Nome não informado';
                    final status = aluno['status_migracao']?.toString() ?? 'Pendente';
                    final turma = aluno['turma_atual']?.toString() ?? 'Sem turma';
                    final academia = aluno['academia']?.toString() ?? '';

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Icon(
                            _getStatusIcon(status),
                            color: _getStatusColor(status),
                            size: 24,
                          ),
                        ),
                        title: Text(
                          nome,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            if (academia.isNotEmpty)
                              Row(
                                children: [
                                  Icon(Icons.school, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      academia,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            if (turma.isNotEmpty)
                              Row(
                                children: [
                                  Icon(Icons.group, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      turma,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: _getStatusColor(status),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () => _navigateToDetail(aluno),
                      ),
                    ).animate().fadeIn(delay: (index * 50).ms);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isMigrandoEmMassa)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Migrando: $_alunosMigrados/$_totalAlunosParaMigrar',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          FloatingActionButton.extended(
            onPressed: () {
              setState(() {
                _alunosData = _fetchAlunos();
                _searchController.clear();
                _filterStatus = 'Todos';
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar'),
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
            elevation: 4,
          ),
        ],
      ),
    );
  }
}