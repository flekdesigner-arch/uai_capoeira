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

  // Método para ATUALIZAR APENAS FOTO de um aluno existente
  Future<String> atualizarFotoAluno(String driveUrl, String alunoId, String nomeAluno) async {
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

      final imageBytes = response.bodyBytes;
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        debugPrint("❌ Erro ao decodificar imagem");
        return '';
      }

      final compressedBytes = img.encodeJpg(image, quality: 80);

      final fileName = _sanitizeFileName(nomeAluno);
      final storageRef = storage
          .ref()
          .child('fotos_perfil_alunos/${fileName}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putData(compressedBytes, SettableMetadata(contentType: 'image/jpeg'));
      debugPrint("✅ Foto atualizada e enviada: $fileName");

      final novaUrl = await storageRef.getDownloadURL();

      await firestore.collection('alunos').doc(alunoId).update({
        'foto_perfil_aluno': novaUrl,
        'ultima_atualizacao_foto': FieldValue.serverTimestamp(),
      });

      return novaUrl;
    } catch (e) {
      debugPrint("❌ Erro ao atualizar foto: $e");
      return '';
    }
  }

  // Método para MIGRAR foto (criar novo aluno)
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

      final imageBytes = response.bodyBytes;
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        debugPrint("❌ Erro ao decodificar imagem");
        return '';
      }

      final compressedBytes = img.encodeJpg(image, quality: 80);

      final fileName = _sanitizeFileName(nomeAluno);
      final storageRef = storage
          .ref()
          .child('fotos_perfil_alunos/${fileName}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putData(compressedBytes, SettableMetadata(contentType: 'image/jpeg'));
      debugPrint("✅ Foto migrada e enviada: $fileName");
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
  bool _isAtualizandoFotos = false;
  bool _isMigrandoNovos = false;
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
      final jsonString = await rootBundle.loadString('assets/alunos.json');
      final dynamic jsonData = jsonDecode(jsonString);

      List<dynamic> alunosList = [];

      if (jsonData is List) {
        alunosList = jsonData;
      } else if (jsonData is Map) {
        if (jsonData.containsKey('alunos')) {
          alunosList = jsonData['alunos'] as List;
        } else if (jsonData.containsKey('data')) {
          alunosList = jsonData['data'] as List;
        } else {
          try {
            final firstList = jsonData.values.firstWhere(
                  (v) => v is List,
              orElse: () => [],
            );
            alunosList = firstList as List;
          } catch (e) {
            debugPrint("❌ Nenhuma lista encontrada no JSON");
          }
        }
      }

      final alunos = <AlunoJSON>[];
      for (int i = 0; i < alunosList.length; i++) {
        final item = alunosList[i];
        try {
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
      throw Exception('Erro ao ler arquivo JSON: $e');
    }
  }

  // ============ BUSCAR ALUNOS PARA EXIBIÇÃO ============
  Future<List<dynamic>> _fetchAlunos() async {
    try {
      final alunosJSON = await _lerAlunosDoJSON();
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

  // ============ MÉTODO PARA ATUALIZAR APENAS FOTOS ============
  Future<void> _atualizarApenasFotos() async {
    if (_isMigrandoEmMassa || _isAtualizandoFotos || _isMigrandoNovos) return;

    setState(() {
      _isAtualizandoFotos = true;
      _alunosMigrados = 0;
      _errosMigracao.clear();
    });

    try {
      final alunosJSON = await _lerAlunosDoJSON();
      final alunosParaAtualizar = <Map<String, dynamic>>[];

      for (var aluno in alunosJSON) {
        if (aluno.fotoUrl != null && aluno.fotoUrl!.isNotEmpty && aluno.nome != null) {
          QuerySnapshot query;
          if (aluno.cpf != null && aluno.cpf!.isNotEmpty) {
            query = await FirebaseFirestore.instance
                .collection('alunos')
                .where('cpf', isEqualTo: aluno.cpf)
                .limit(1)
                .get();
          } else {
            query = await FirebaseFirestore.instance
                .collection('alunos')
                .where('nome', isEqualTo: aluno.nome)
                .limit(1)
                .get();
          }

          if (query.docs.isNotEmpty) {
            alunosParaAtualizar.add({
              'id': query.docs.first.id,
              'nome': aluno.nome,
              'fotoUrl': aluno.fotoUrl,
              'cpf': aluno.cpf,
            });
          }
        }
      }

      setState(() {
        _totalAlunosParaMigrar = alunosParaAtualizar.length;
      });

      if (alunosParaAtualizar.isEmpty) {
        _mostrarErro('Nenhum aluno com foto encontrado no Firestore');
        setState(() => _isAtualizandoFotos = false);
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('📸 Atualizar Fotos'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Serão atualizadas as fotos de ${alunosParaAtualizar.length} alunos.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ATENÇÃO: Isso vai SOBRESCREVER as fotos atuais!',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Atualizar Fotos'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isAtualizandoFotos = false);
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Atualizando Fotos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: _totalAlunosParaMigrar > 0 ? _alunosMigrados / _totalAlunosParaMigrar : 0,
                              strokeWidth: 8,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                          Text(
                            '${((_alunosMigrados / _totalAlunosParaMigrar) * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('$_alunosMigrados / $_totalAlunosParaMigrar', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _totalAlunosParaMigrar > 0 ? _alunosMigrados / _totalAlunosParaMigrar : 0,
                        backgroundColor: Colors.grey[200],
                        color: Colors.blue,
                        minHeight: 8,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Processando: ${_alunosMigrados < _totalAlunosParaMigrar ? alunosParaAtualizar[_alunosMigrados]['nome'] : 'Concluído'}',
                                style: TextStyle(fontSize: 12, color: Colors.blue[700]),
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
                          decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red[700], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Erros: ${_errosMigracao.length}',
                                  style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.bold),
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

      for (int i = 0; i < alunosParaAtualizar.length; i++) {
        final aluno = alunosParaAtualizar[i];
        try {
          debugPrint('📸 [${i + 1}/${alunosParaAtualizar.length}] Atualizando foto: ${aluno['nome']}');
          final novaUrl = await _migracaoService.atualizarFotoAluno(
            aluno['fotoUrl'],
            aluno['id'],
            aluno['nome'],
          );
          if (novaUrl.isNotEmpty) {
            debugPrint('✅ Foto atualizada: ${aluno['nome']}');
          } else {
            _errosMigracao.add('${aluno['nome']}: Falha ao atualizar foto');
          }
          if (mounted) setState(() => _alunosMigrados = i + 1);
        } catch (e) {
          debugPrint('❌ Erro ao atualizar foto ${aluno['nome']}: $e');
          _errosMigracao.add('${aluno['nome']}: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() => _isAtualizandoFotos = false);
        _mostrarResultado('Atualização de Fotos', _totalAlunosParaMigrar, _alunosMigrados, _errosMigracao);
        _alunosData = _fetchAlunos();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _isAtualizandoFotos = false);
        _mostrarErro('Erro: $e');
      }
    }
  }

  // ============ MÉTODO PARA MIGRAR ALUNOS NOVOS (QUE NÃO EXISTEM) ============
  Future<void> _migrarAlunosNovos() async {
    if (_isMigrandoEmMassa || _isAtualizandoFotos || _isMigrandoNovos) return;

    setState(() {
      _isMigrandoNovos = true;
      _alunosMigrados = 0;
      _errosMigracao.clear();
    });

    try {
      final alunosJSON = await _lerAlunosDoJSON();
      final academias = await _migracaoService.buscarAcademias();
      final graduacoes = await _migracaoService.buscarGraduacoes();
      final turmasCache = <String, Map<String, Map<String, dynamic>>>{};

      // Buscar alunos que JÁ EXISTEM no Firestore
      final nomesExistentes = <String>{};
      final cpfsExistentes = <String>{};

      final alunosExistentes = await FirebaseFirestore.instance.collection('alunos').get();
      for (var doc in alunosExistentes.docs) {
        final nome = doc['nome'] as String?;
        final cpf = doc['cpf'] as String?;
        if (nome != null) nomesExistentes.add(nome.toLowerCase().trim());
        if (cpf != null && cpf.isNotEmpty) cpfsExistentes.add(cpf.trim());
      }

      // Filtrar apenas alunos que NÃO EXISTEM
      final alunosNovos = alunosJSON.where((aluno) {
        if (aluno.cpf != null && aluno.cpf!.isNotEmpty) {
          return !cpfsExistentes.contains(aluno.cpf!.trim());
        }
        return !nomesExistentes.contains(aluno.nome?.toLowerCase().trim());
      }).toList();

      setState(() {
        _totalAlunosParaMigrar = alunosNovos.length;
      });

      if (alunosNovos.isEmpty) {
        _mostrarErro('Nenhum aluno novo encontrado para migrar');
        setState(() => _isMigrandoNovos = false);
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('➕ Migrar Alunos Novos'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Serão migrados ${alunosNovos.length} alunos novos.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Os alunos que já existem no Firestore NÃO serão duplicados.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              child: const Text('Migrar Novos Alunos'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isMigrandoNovos = false);
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Migrando Novos Alunos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: _totalAlunosParaMigrar > 0 ? _alunosMigrados / _totalAlunosParaMigrar : 0,
                              strokeWidth: 8,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                          Text(
                            '${((_alunosMigrados / _totalAlunosParaMigrar) * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('$_alunosMigrados / $_totalAlunosParaMigrar', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _totalAlunosParaMigrar > 0 ? _alunosMigrados / _totalAlunosParaMigrar : 0,
                        backgroundColor: Colors.grey[200],
                        color: Colors.green,
                        minHeight: 8,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.green[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Processando: ${_alunosMigrados < _totalAlunosParaMigrar ? alunosNovos[_alunosMigrados].nome ?? 'Aluno' : 'Concluído'}',
                                style: TextStyle(fontSize: 12, color: Colors.green[700]),
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
                          decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red[700], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Erros: ${_errosMigracao.length}',
                                  style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.bold),
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

      for (int i = 0; i < alunosNovos.length; i++) {
        final aluno = alunosNovos[i];
        try {
          debugPrint('➕ [${i + 1}/${alunosNovos.length}] Migrando: ${aluno.nome}');

          String fotoFinalUrl = '';
          if (aluno.fotoUrl != null && aluno.fotoUrl!.isNotEmpty && aluno.nome != null) {
            fotoFinalUrl = await _migracaoService.migrarFotoComprimida(aluno.fotoUrl!, aluno.nome!);
          }

          Map<String, dynamic> graduacaoData = {};
          String? graduacaoId;
          if (aluno.graduacao != null && aluno.graduacao!.isNotEmpty) {
            graduacaoId = graduacoes[aluno.graduacao!];
            if (graduacaoId != null) {
              final gradDoc = await FirebaseFirestore.instance.collection('graduacoes').doc(graduacaoId).get();
              if (gradDoc.exists) {
                graduacaoData = {
                  'graduacao_cor1': gradDoc['hex_cor1'],
                  'graduacao_cor2': gradDoc['hex_cor2'],
                  'graduacao_ponta1': gradDoc['hex_ponta1'],
                  'graduacao_ponta2': gradDoc['hex_ponta2'],
                  'nivel_graduacao': gradDoc['nivel_graduacao'],
                };
              }
            }
          }

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
                  turmasCache[academiaId] = await _migracaoService.buscarTurmas(academiaId);
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

          await _migracaoService.salvarAluno(dadosParaSalvar);
          debugPrint('✅ Aluno migrado: ${aluno.nome}');

          if (mounted) setState(() => _alunosMigrados = i + 1);
        } catch (e) {
          debugPrint('❌ Erro ao migrar ${aluno.nome}: $e');
          _errosMigracao.add('${aluno.nome}: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() => _isMigrandoNovos = false);
        _mostrarResultado('Migração de Novos Alunos', _totalAlunosParaMigrar, _alunosMigrados, _errosMigracao);
        _alunosData = _fetchAlunos();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _isMigrandoNovos = false);
        _mostrarErro('Erro: $e');
      }
    }
  }

  void _mostrarResultado(String titulo, int total, int sucesso, List<String> erros) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: erros.isEmpty ? Colors.green : Colors.orange),
            const SizedBox(height: 16),
            Text('Total: $total', style: const TextStyle(fontSize: 16)),
            Text('Processados: $sucesso', style: const TextStyle(fontSize: 16, color: Colors.green)),
            if (erros.isNotEmpty) ...[
              const Divider(),
              Text('Erros: ${erros.length}', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: erros.length > 5 ? 5 : erros.length,
                  itemBuilder: (context, index) => Text('• ${erros[index]}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ),
              if (erros.length > 5) Text('... e mais ${erros.length - 5} erros', style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          if (erros.isNotEmpty)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _reprocessarErros();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Reprocessar Erros'),
            ),
        ],
      ),
    );
  }

  Future<void> _reprocessarErros() async {
    if (_errosMigracao.isEmpty) {
      _mostrarMensagem('Nenhum erro registrado', Colors.orange);
      return;
    }

    setState(() {
      _isAtualizandoFotos = true;
      _alunosMigrados = 0;
    });

    try {
      final alunosJSON = await _lerAlunosDoJSON();
      final nomesComErro = _errosMigracao.map((e) => e.split(':').first.trim()).toList();
      final alunosParaReprocessar = alunosJSON.where((a) => nomesComErro.contains(a.nome)).toList();

      setState(() {
        _totalAlunosParaMigrar = alunosParaReprocessar.length;
        _errosMigracao.clear();
      });

      if (alunosParaReprocessar.isEmpty) {
        _mostrarMensagem('Nenhum aluno com erro encontrado', Colors.orange);
        setState(() => _isAtualizandoFotos = false);
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Reprocessando...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                CircularProgressIndicator(value: _alunosMigrados / _totalAlunosParaMigrar),
                const SizedBox(height: 16),
                Text('$_alunosMigrados / $_totalAlunosParaMigrar'),
              ],
            ),
          ),
        ),
      );

      for (int i = 0; i < alunosParaReprocessar.length; i++) {
        final aluno = alunosParaReprocessar[i];
        try {
          final query = await FirebaseFirestore.instance
              .collection('alunos')
              .where('nome', isEqualTo: aluno.nome)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            final novaUrl = await _migracaoService.atualizarFotoAluno(
              aluno.fotoUrl!,
              query.docs.first.id,
              aluno.nome!,
            );
            if (novaUrl.isEmpty) _errosMigracao.add('${aluno.nome}: Falha');
          } else {
            _errosMigracao.add('${aluno.nome}: Não encontrado');
          }
          if (mounted) setState(() => _alunosMigrados = i + 1);
        } catch (e) {
          _errosMigracao.add('${aluno.nome}: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() => _isAtualizandoFotos = false);
        _mostrarResultado('Reprocessamento', _totalAlunosParaMigrar, _totalAlunosParaMigrar - _errosMigracao.length, _errosMigracao);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _isAtualizandoFotos = false);
        _mostrarErro('Erro: $e');
      }
    }
  }

  // ============ MÉTODO PARA MIGRAÇÃO EM MASSA DO JSON (COMPLETA) ============
  Future<void> _iniciarMigracaoMassaJSON() async {
    if (_isMigrandoEmMassa || _isAtualizandoFotos || _isMigrandoNovos) return;

    setState(() {
      _isMigrandoEmMassa = true;
      _alunosMigrados = 0;
      _errosMigracao.clear();
    });

    try {
      final alunosJSON = await _lerAlunosDoJSON();
      setState(() => _totalAlunosParaMigrar = alunosJSON.length);

      final academias = await _migracaoService.buscarAcademias();
      final graduacoes = await _migracaoService.buscarGraduacoes();
      final turmasCache = <String, Map<String, Map<String, dynamic>>>{};

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Migração Completa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Serão migrados ${alunosJSON.length} alunos.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text('ATENÇÃO: Alunos duplicados serão criados!', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('Migrar Tudo'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isMigrandoEmMassa = false);
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Migrando...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(value: _alunosMigrados / _totalAlunosParaMigrar),
                    Text('${((_alunosMigrados / _totalAlunosParaMigrar) * 100).toStringAsFixed(0)}%'),
                  ],
                ),
                const SizedBox(height: 16),
                Text('$_alunosMigrados / $_totalAlunosParaMigrar'),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _alunosMigrados / _totalAlunosParaMigrar),
                const SizedBox(height: 16),
                Text('Processando: ${_alunosMigrados < _totalAlunosParaMigrar ? alunosJSON[_alunosMigrados].nome ?? 'Aluno' : 'Concluído'}', style: const TextStyle(fontSize: 12)),
                if (_errosMigracao.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Erros: ${_errosMigracao.length}', style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      );

      for (int i = 0; i < alunosJSON.length; i++) {
        final aluno = alunosJSON[i];
        try {
          debugPrint('📦 [${i + 1}/${alunosJSON.length}] Processando: ${aluno.nome}');

          String fotoFinalUrl = '';
          if (aluno.fotoUrl != null && aluno.fotoUrl!.isNotEmpty && aluno.nome != null) {
            fotoFinalUrl = await _migracaoService.migrarFotoComprimida(aluno.fotoUrl!, aluno.nome!);
          }

          Map<String, dynamic> graduacaoData = {};
          String? graduacaoId;
          if (aluno.graduacao != null && aluno.graduacao!.isNotEmpty) {
            graduacaoId = graduacoes[aluno.graduacao!];
            if (graduacaoId != null) {
              final gradDoc = await FirebaseFirestore.instance.collection('graduacoes').doc(graduacaoId).get();
              if (gradDoc.exists) {
                graduacaoData = {
                  'graduacao_cor1': gradDoc['hex_cor1'],
                  'graduacao_cor2': gradDoc['hex_cor2'],
                  'graduacao_ponta1': gradDoc['hex_ponta1'],
                  'graduacao_ponta2': gradDoc['hex_ponta2'],
                  'nivel_graduacao': gradDoc['nivel_graduacao'],
                };
              }
            }
          }

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
                  turmasCache[academiaId] = await _migracaoService.buscarTurmas(academiaId);
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

          await _migracaoService.salvarAluno(dadosParaSalvar);
          debugPrint('✅ Aluno migrado: ${aluno.nome}');

          if (mounted) setState(() => _alunosMigrados = i + 1);
        } catch (e) {
          debugPrint('❌ Erro ao migrar ${aluno.nome}: $e');
          _errosMigracao.add('${aluno.nome}: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() => _isMigrandoEmMassa = false);
        _mostrarResultado('Migração Completa', _totalAlunosParaMigrar, _alunosMigrados, _errosMigracao);
        _alunosData = _fetchAlunos();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _isMigrandoEmMassa = false);
        _mostrarErro('Erro: $e');
      }
    }
  }

  // ============ FILTROS ============
  void _filterAlunos(String query, String status) {
    setState(() {
      _isSearching = query.isNotEmpty;
      _filterStatus = status;
      _alunosData.then((alunos) {
        List<dynamic> filtered = alunos;
        if (query.isNotEmpty) {
          filtered = filtered.where((aluno) => (aluno['nome_do_aluno']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())).toList();
        }
        if (status != 'Todos') {
          filtered = filtered.where((aluno) => (aluno['status_migracao']?.toString() ?? 'Pendente') == status).toList();
        }
        _alunosFiltrados = filtered;
      });
    });
  }

  void _navigateToDetail(Map<String, dynamic> alunoData) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MigracaoDetalheScreen(alunoData: alunoData),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    ).then((_) => setState(() => _alunosData = _fetchAlunos()));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Concluído': return Colors.green;
      case 'Em Andamento': return Colors.orange;
      case 'Pendente': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Concluído': return Icons.check_circle;
      case 'Em Andamento': return Icons.autorenew;
      case 'Pendente': return Icons.pending;
      default: return Icons.help_outline;
    }
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(height: 80, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Ops! Algo deu errado', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.red[700], fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() => _alunosData = _fetchAlunos()),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarMensagem(String mensagem, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem), backgroundColor: cor, duration: const Duration(seconds: 3)));
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem), backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
          child: Icon(icon, color: Colors.red[700], size: 28),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Triagem de Migração', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        backgroundColor: Colors.red[800],
        foregroundColor: Colors.white,
        elevation: 3,
        shadowColor: Colors.red[900]!.withOpacity(0.3),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
        actions: [
          if (_errosMigracao.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reprocessarErros,
              tooltip: 'Reprocessar erros (${_errosMigracao.length})',
            ),
          IconButton(
            icon: _isAtualizandoFotos ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.photo_library_outlined),
            onPressed: _isAtualizandoFotos ? null : _atualizarApenasFotos,
            tooltip: 'Atualizar apenas fotos',
          ),
          IconButton(
            icon: _isMigrandoNovos ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.person_add_alt_1),
            onPressed: _isMigrandoNovos ? null : _migrarAlunosNovos,
            tooltip: 'Migrar apenas alunos novos',
          ),
          IconButton(
            icon: _isMigrandoEmMassa ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload),
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
                      const Text('Opções de Migração:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('📸 Atualizar Fotos - Só atualiza fotos de alunos que já existem'),
                      const Text('➕ Alunos Novos - Cria apenas alunos que não existem no Firestore'),
                      const Text('☁️ Migrar Tudo - Cria TODOS os alunos (pode duplicar)'),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                        child: const Text('Use "Alunos Novos" para não duplicar dados!', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.red[50]!, Colors.orange[50]!]), border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
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
              return Container(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStatCard('Total', '...', Icons.group), _buildStatCard('Concluídos', '...', Icons.check_circle), _buildStatCard('Pendentes', '...', Icons.pending)]));
            },
          ),
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
                    suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _filterAlunos('', _filterStatus); }) : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: (value) => _filterAlunos(value, _filterStatus),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Todos', 'Pendente', 'Concluído'].map((status) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(status),
                        selected: _filterStatus == status,
                        onSelected: (selected) => _filterAlunos(_searchController.text, status),
                        backgroundColor: Colors.grey[200],
                        selectedColor: status == 'Concluído' ? Colors.green : status == 'Pendente' ? Colors.red : Colors.grey,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(color: _filterStatus == status ? Colors.white : Colors.grey[700]),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _alunosData,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return _buildShimmerLoading();
                if (snapshot.hasError) return _buildErrorWidget(snapshot.error.toString());
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Nenhum aluno encontrado', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        Text('Verifique se o arquivo alunos.json está na pasta assets', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(onPressed: () => setState(() => _alunosData = _fetchAlunos()), icon: const Icon(Icons.refresh), label: const Text('Recarregar')),
                      ],
                    ),
                  );
                }
                final alunos = (_isSearching || _filterStatus != 'Todos') ? _alunosFiltrados : snapshot.data!;
                if (alunos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Nenhum aluno encontrado', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        Text('Tente outros termos de busca', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500])),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(25)),
                          child: Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 24),
                        ),
                        title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            if (academia.isNotEmpty) Row(children: [Icon(Icons.school, size: 14, color: Colors.grey[600]), const SizedBox(width: 4), Expanded(child: Text(academia, style: TextStyle(color: Colors.grey[600], fontSize: 13), overflow: TextOverflow.ellipsis))]),
                            if (turma.isNotEmpty) Row(children: [Icon(Icons.group, size: 14, color: Colors.grey[600]), const SizedBox(width: 4), Expanded(child: Text(turma, style: TextStyle(color: Colors.grey[600], fontSize: 13), overflow: TextOverflow.ellipsis))]),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text(status, style: TextStyle(color: _getStatusColor(status), fontSize: 12, fontWeight: FontWeight.w600)),
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
      floatingActionButton: FloatingActionButton.extended(
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
    );
  }
}