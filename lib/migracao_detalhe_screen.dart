import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

// 1. MODELOS FORTEMENTE TIPADOS
class AlunoMigracao {
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

  AlunoMigracao({
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

  factory AlunoMigracao.fromMap(Map<String, dynamic> map) {
    return AlunoMigracao(
      nome: map['nome_do_aluno']?.toString(),
      cpf: map['cpf']?.toString(),
      fotoUrl: map['foto_perfil_aluno']?.toString(),
      apelido: map['apelido']?.toString(),
      sexo: map['sexo']?.toString(),
      dataNascimento: map['data_nascimento']?.toString(),
      graduacao: map['graduacao_atual']?.toString(),
      dataGraduacao: map['data_graduacao_atual']?.toString(),
      tempoCapoeira: map['data_tempo_de_capoeira']?.toString(),
      endereco: map['endereco']?.toString(),
      contato: map['contato_aluno']?.toString(),
      responsavel: map['nome_responsavel']?.toString(),
      contatoResponsavel: map['contato_do_responsavel']?.toString(),
      status: map['status_atividade']?.toString(),
      cidade: map['cidade']?.toString(),
      academia: map['academia']?.toString(),
      modalidade: map['modalidade']?.toString(),
      turma: map['turma']?.toString(),
      cadastroPor: map['cadastro_realizado_por']?.toString(),
      dataCadastro: map['data_do_cadastro']?.toString(),
      atualizadoPor: map['atualizado_por']?.toString(),
      dataAtualizacao: map['data_atualizacao']?.toString(),
      editavel: map['editavel']?.toString().toLowerCase() == "true",
      indexPlanilha: int.tryParse(map['index_planilha']?.toString() ?? ''),
    );
  }
}

// 2. CLASSE AUXILIAR PARA RESULTADO DE GRADUAÇÕES
class GraduacoesResult {
  final List<QueryDocumentSnapshot> docs;
  final Map<String, String> map;

  GraduacoesResult(this.docs, this.map);
}

// 3. SERVICE PARA OPERAÇÕES DE MIGRAÇÃO
class MigracaoService {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  MigracaoService({
    required this.firestore,
    required this.storage,
  });

  // MÉTODO PARA MIGRAR FOTO
  Future<String> migrarFoto(String driveUrl, String nomeAluno) async {
    if (driveUrl.isEmpty) return '';

    try {
      if (!driveUrl.contains("&export=view")) {
        driveUrl += "&export=view";
      }

      final response = await http.get(Uri.parse(driveUrl));
      if (response.statusCode != 200) {
        debugPrint("Falha ao baixar foto: ${response.statusCode}");
        return '';
      }

      final fileName = _sanitizeFileName(nomeAluno);
      final storageRef = storage
          .ref()
          .child('foto_alunos/${fileName}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putData(response.bodyBytes);
      return await storageRef.getDownloadURL();
    } catch (e) {
      debugPrint("Erro ao migrar foto: $e");
      return '';
    }
  }

  String _sanitizeFileName(String nome) {
    return nome
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  // MÉTODO PARA BUSCAR ACADEMIAS
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
      return academiasMap;
    } catch (e) {
      debugPrint('Erro ao buscar academias: $e');
      return {};
    }
  }

  // MÉTODO PARA BUSCAR TURMAS
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
          'capacidade': data['capacidade_maxima'] ?? 0,
        };
      }
      return turmasMap;
    } catch (e) {
      debugPrint('Erro ao buscar turmas: $e');
      return {};
    }
  }

  // MÉTODO PARA BUSCAR GRADUAÇÕES
  Future<GraduacoesResult> buscarGraduacoes() async {
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

      return GraduacoesResult(snapshot.docs, gradMap);
    } catch (e) {
      debugPrint("‼️ ERRO AO BUSCAR GRADUAÇÕES: $e");
      return GraduacoesResult([], {});
    }
  }

  // MÉTODO PARA SALVAR ALUNO NO FIRESTORE
  Future<void> salvarAluno(Map<String, dynamic> dados) async {
    await firestore.collection('alunos').add(dados);
  }
}

// 4. CONTROLLER PARA GERENCIAR ESTADO
class MigracaoDetalheController extends ChangeNotifier {
  final MigracaoService service;
  final AlunoMigracao alunoOriginal;

  // CONTROLLERS
  late TextEditingController nomeController;
  late TextEditingController cpfController;
  late TextEditingController fotoController;
  late TextEditingController apelidoController;
  late TextEditingController sexoController;
  late TextEditingController dataNascimentoController;
  late TextEditingController graduacaoController;
  late TextEditingController dataGraduacaoController;
  late TextEditingController tempoCapoeiraController;
  late TextEditingController enderecoController;
  late TextEditingController contatoController;
  late TextEditingController responsavelController;
  late TextEditingController contatoResponsavelController;
  late TextEditingController statusController;
  late TextEditingController cidadeController;
  late TextEditingController academiaController;
  late TextEditingController modalidadeController;
  late TextEditingController turmaController;
  late TextEditingController cadastroPorController;
  late TextEditingController dataCadastroController;
  late TextEditingController atualizadoPorController;
  late TextEditingController dataAtualizacaoController;

  // ESTADOS
  bool _isSaving = false;
  bool _editavel = false;
  bool _carregandoTurmas = false;
  bool _isLoadingGraduacoes = true;

  // DADOS DROPDOWN
  Map<String, String> _academiasMap = {};
  Map<String, Map<String, dynamic>> _turmasMap = {};
  Map<String, String> _graduacoesMap = {};
  List<QueryDocumentSnapshot> _graduacoesDocs = [];

  // SELECIONADOS
  String? _selectedAcademiaId;
  String? _selectedAcademiaNome;
  String? _selectedTurmaId;
  String? _selectedTurmaNome;
  String? _selectedGraduacaoId;

  // GETTERS
  bool get isSaving => _isSaving;
  bool get editavel => _editavel;
  bool get carregandoTurmas => _carregandoTurmas;
  bool get isLoadingGraduacoes => _isLoadingGraduacoes;
  Map<String, String> get academiasMap => _academiasMap;
  Map<String, Map<String, dynamic>> get turmasMap => _turmasMap;
  Map<String, String> get graduacoesMap => _graduacoesMap;
  List<QueryDocumentSnapshot> get graduacoesDocs => _graduacoesDocs;
  String? get selectedAcademiaId => _selectedAcademiaId;
  String? get selectedAcademiaNome => _selectedAcademiaNome;
  String? get selectedTurmaId => _selectedTurmaId;
  String? get selectedTurmaNome => _selectedTurmaNome;
  String? get selectedGraduacaoId => _selectedGraduacaoId;

  // LISTAS PARA DROPDOWNS
  List<String> opcoesStatus = ['ATIVO(A)', 'INATIVO(A)', 'NOVATO(A)'];
  List<String> opcoesSexo = ['MASCULINO', 'FEMININO'];

  MigracaoDetalheController({
    required this.service,
    required this.alunoOriginal,
  }) {
    _inicializarControllers();
    _carregarDadosIniciais();
  }

  void _inicializarControllers() {
    nomeController = TextEditingController(text: alunoOriginal.nome ?? '');
    cpfController = TextEditingController(text: alunoOriginal.cpf ?? '');
    fotoController = TextEditingController(text: alunoOriginal.fotoUrl ?? '');
    apelidoController = TextEditingController(text: alunoOriginal.apelido ?? '');
    sexoController = TextEditingController(text: (alunoOriginal.sexo ?? 'MASCULINO').toUpperCase());
    dataNascimentoController = TextEditingController(text: _normalizeDateForDisplay(alunoOriginal.dataNascimento));
    graduacaoController = TextEditingController(text: alunoOriginal.graduacao ?? '');
    dataGraduacaoController = TextEditingController(text: _normalizeDateForDisplay(alunoOriginal.dataGraduacao));
    tempoCapoeiraController = TextEditingController(text: _normalizeDateForDisplay(alunoOriginal.tempoCapoeira));
    enderecoController = TextEditingController(text: alunoOriginal.endereco ?? '');
    contatoController = TextEditingController(text: alunoOriginal.contato ?? '');
    responsavelController = TextEditingController(text: alunoOriginal.responsavel ?? '');
    contatoResponsavelController = TextEditingController(text: alunoOriginal.contatoResponsavel ?? '');
    statusController = TextEditingController(text: (alunoOriginal.status ?? 'ATIVO(A)').toUpperCase());
    cidadeController = TextEditingController(text: alunoOriginal.cidade ?? '');
    academiaController = TextEditingController(text: alunoOriginal.academia ?? '');
    modalidadeController = TextEditingController(text: alunoOriginal.modalidade ?? '');
    turmaController = TextEditingController(text: alunoOriginal.turma ?? '');
    cadastroPorController = TextEditingController(text: alunoOriginal.cadastroPor ?? '');
    dataCadastroController = TextEditingController(text: _normalizeDateForDisplay(alunoOriginal.dataCadastro));
    atualizadoPorController = TextEditingController(text: alunoOriginal.atualizadoPor ?? '');
    dataAtualizacaoController = TextEditingController(text: _normalizeDateForDisplay(alunoOriginal.dataAtualizacao));

    _editavel = alunoOriginal.editavel;
  }

  // MANTIDO IGUAL - FUNCIONANDO PERFEITAMENTE
  String _normalizeDateForDisplay(String? input) {
    if (input == null || input.isEmpty) return '';
    final timestamp = _parseDateToTimestamp(input);
    return timestamp != null ? DateFormat('dd/MM/yyyy').format(timestamp.toDate()) : input;
  }

  // MANTIDO IGUAL - FUNCIONANDO PERFEITAMENTE
  Timestamp? _parseDateToTimestamp(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;

    final formats = [
      'dd/MM/yyyy, HH:mm:ss',
      'dd/MM/yyyy HH:mm:ss',
      'dd/MM/yyyy',
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

    debugPrint("AVISO: Não foi possível converter a data '$dateString'. O campo será salvo como nulo.");
    return null;
  }

  Future<void> _carregarDadosIniciais() async {
    await _carregarAcademias();
    await _carregarGraduacoes();
  }

  Future<void> _carregarAcademias() async {
    _academiasMap = await service.buscarAcademias();

    // TENTAR PRE-SELECIONAR ACADEMIA DA PLANILHA
    final academiaPlanilha = alunoOriginal.academia ?? '';
    if (academiaPlanilha.isNotEmpty) {
      final academiaId = _academiasMap.entries
          .firstWhere(
            (entry) => entry.value == academiaPlanilha,
        orElse: () => MapEntry('', ''),
      ).key;

      if (academiaId.isNotEmpty) {
        _selectedAcademiaId = academiaId;
        _selectedAcademiaNome = _academiasMap[academiaId];
        await carregarTurmas(academiaId);
      }
    }

    notifyListeners();
  }

  Future<void> carregarTurmas(String? academiaId) async {
    if (academiaId == null || academiaId.isEmpty) {
      _turmasMap = {};
      _selectedTurmaId = null;
      _selectedTurmaNome = null;
      _carregandoTurmas = false;
      notifyListeners();
      return;
    }

    _carregandoTurmas = true;
    notifyListeners();

    _turmasMap = await service.buscarTurmas(academiaId);

    // TENTAR PRE-SELECIONAR TURMA DA PLANILHA
    final turmaPlanilha = alunoOriginal.turma ?? '';
    if (turmaPlanilha.isNotEmpty && _selectedTurmaId == null) {
      final turmaEntry = _turmasMap.entries.firstWhere(
            (entry) => entry.value['nome'] == turmaPlanilha,
        orElse: () => MapEntry('', {}),
      );

      if (turmaEntry.key.isNotEmpty) {
        _selectedTurmaId = turmaEntry.key;
        _selectedTurmaNome = turmaEntry.value['nome'] as String?;
      }
    }

    _carregandoTurmas = false;
    notifyListeners();
  }

  Future<void> _carregarGraduacoes() async {
    final result = await service.buscarGraduacoes();
    _graduacoesDocs = result.docs;
    _graduacoesMap = result.map;

    final gradText = graduacaoController.text.trim();
    if (gradText.isNotEmpty) {
      if (_graduacoesMap.containsKey(gradText)) {
        _selectedGraduacaoId = _graduacoesMap[gradText];
        debugPrint('✅ Graduação encontrada: "$gradText" -> $_selectedGraduacaoId');
      } else {
        String? matchingKey;
        try {
          matchingKey = _graduacoesMap.keys.firstWhere(
                (key) => key.toLowerCase().contains(gradText.toLowerCase()) ||
                gradText.toLowerCase().contains(key.toLowerCase()),
          );
        } catch (e) {
          matchingKey = null;
        }

        if (matchingKey != null && matchingKey.isNotEmpty) {
          _selectedGraduacaoId = _graduacoesMap[matchingKey];
          debugPrint('✅ Graduação encontrada (parcial): "$gradText" -> "$matchingKey" -> $_selectedGraduacaoId');
        } else {
          debugPrint('⚠️ Graduação não encontrada: "$gradText"');
          _selectedGraduacaoId = null;
        }
      }
    }

    _isLoadingGraduacoes = false;
    notifyListeners();
  }

  // MÉTODOS PARA ATUALIZAR ESTADO
  void setSelectedAcademia(String? id, String? nome) {
    _selectedAcademiaId = id;
    _selectedAcademiaNome = nome;
    _selectedTurmaId = null;
    _selectedTurmaNome = null;
    notifyListeners();

    if (id != null) {
      carregarTurmas(id);
    }
  }

  void setSelectedTurma(String? id, String? nome) {
    _selectedTurmaId = id;
    _selectedTurmaNome = nome;
    notifyListeners();
  }

  void setSelectedGraduacao(String? id) {
    _selectedGraduacaoId = id;
    if (id != null) {
      final doc = _graduacoesDocs.firstWhere((doc) => doc.id == id);
      graduacaoController.text = doc.get('nome_graduacao') ?? '';
    }
    notifyListeners();
  }

  void setEditavel(bool value) {
    _editavel = value;
    notifyListeners();
  }

  void setSaving(bool value) {
    _isSaving = value;
    notifyListeners();
  }

  @override
  void dispose() {
    nomeController.dispose();
    cpfController.dispose();
    fotoController.dispose();
    apelidoController.dispose();
    sexoController.dispose();
    dataNascimentoController.dispose();
    graduacaoController.dispose();
    dataGraduacaoController.dispose();
    tempoCapoeiraController.dispose();
    enderecoController.dispose();
    contatoController.dispose();
    responsavelController.dispose();
    contatoResponsavelController.dispose();
    statusController.dispose();
    cidadeController.dispose();
    academiaController.dispose();
    modalidadeController.dispose();
    turmaController.dispose();
    cadastroPorController.dispose();
    dataCadastroController.dispose();
    atualizadoPorController.dispose();
    dataAtualizacaoController.dispose();
    super.dispose();
  }
}

// 5. WIDGET PRINCIPAL REFATORADO (SIMPLIFICADO SEM PROVIDER COMPLEXO)
class MigracaoDetalheScreen extends StatefulWidget {
  final Map<String, dynamic> alunoData;
  const MigracaoDetalheScreen({super.key, required this.alunoData});

  @override
  _MigracaoDetalheScreenState createState() => _MigracaoDetalheScreenState();
}

class _MigracaoDetalheScreenState extends State<MigracaoDetalheScreen> {
  final String _urlScript = "https://script.google.com/macros/s/AKfycbwaMU-QDZBBWotVcHFJh7nq2svmKQFkJixgDrrp5at5Jrl7xGjTQhh_rrh4sFKUtpCX/exec";
  late MigracaoDetalheController _controller;

  @override
  void initState() {
    super.initState();
    final aluno = AlunoMigracao.fromMap(widget.alunoData);
    final service = MigracaoService(
      firestore: FirebaseFirestore.instance,
      storage: FirebaseStorage.instance,
    );
    _controller = MigracaoDetalheController(
      service: service,
      alunoOriginal: aluno,
    );

    // Adicionar listener para atualizações
    _controller.addListener(_onControllerUpdated);
  }

  void _onControllerUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdated);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!mounted) return;

    _controller.setSaving(true);

    try {
      // 1. Migrar foto
      String fotoFinalUrl = '';
      if (_controller.fotoController.text.isNotEmpty) {
        try {
          fotoFinalUrl = await _controller.service.migrarFoto(
              _controller.fotoController.text,
              _controller.nomeController.text
          );
          debugPrint('Foto migrada: ${fotoFinalUrl.isNotEmpty ? "Sim" : "Não"}');
        } catch (e) {
          debugPrint('⚠️ Erro ao migrar foto: $e');
        }
      }

      // 2. Buscar dados da graduação
      Map<String, dynamic> graduacaoData = {};
      if (_controller.selectedGraduacaoId != null) {
        try {
          final gradDoc = await FirebaseFirestore.instance
              .collection('graduacoes')
              .doc(_controller.selectedGraduacaoId)
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

      // 3. Salvar no Firestore
      debugPrint('Salvando no Firestore...');

      final dadosParaSalvar = {
        'nome': _controller.nomeController.text.trim(),
        'cpf': _controller.cpfController.text.trim(),
        'foto_perfil_aluno': fotoFinalUrl,
        'apelido': _controller.apelidoController.text.trim(),
        'sexo': _controller.sexoController.text,
        'data_nascimento': _controller._parseDateToTimestamp(_controller.dataNascimentoController.text),
        'graduacao_atual': _controller.graduacaoController.text.trim(),
        'graduacao_id': _controller.selectedGraduacaoId,
        'data_graduacao_atual': _controller._parseDateToTimestamp(_controller.dataGraduacaoController.text),
        'tempo_capoeira': _controller._parseDateToTimestamp(_controller.tempoCapoeiraController.text),
        'endereco': _controller.enderecoController.text.trim(),
        'contato_aluno': _controller.contatoController.text.trim(),
        'nome_responsavel': _controller.responsavelController.text.trim(),
        'contato_responsavel': _controller.contatoResponsavelController.text.trim(),
        'status_atividade': _controller.statusController.text,
        'cidade': _controller.cidadeController.text.trim(),
        'modalidade': _controller.modalidadeController.text.trim(),
        'editavel': _controller.editavel,
        'cadastro_realizado_por': _controller.cadastroPorController.text.trim(),
        'data_do_cadastro': _controller._parseDateToTimestamp(_controller.dataCadastroController.text),
        'atualizado_por': _controller.atualizadoPorController.text.trim(),
        'data_atualizacao': _controller._parseDateToTimestamp(_controller.dataAtualizacaoController.text),
        'migrado_em': FieldValue.serverTimestamp(),
        ...graduacaoData,
      };

      // ADICIONAR VÍNCULOS DE ACADEMIA E TURMA
      if (_controller.selectedAcademiaId != null && _controller.selectedAcademiaId!.isNotEmpty) {
        dadosParaSalvar['academia_id'] = _controller.selectedAcademiaId;
        dadosParaSalvar['academia'] = _controller.selectedAcademiaNome ?? _controller.academiasMap[_controller.selectedAcademiaId];
      } else {
        dadosParaSalvar['academia'] = _controller.academiaController.text.trim();
      }

      if (_controller.selectedTurmaId != null && _controller.selectedTurmaId!.isNotEmpty) {
        dadosParaSalvar['turma_id'] = _controller.selectedTurmaId;
        dadosParaSalvar['turma'] = _controller.selectedTurmaNome ?? _controller.turmasMap[_controller.selectedTurmaId]?['nome'];
      } else {
        dadosParaSalvar['turma'] = _controller.turmaController.text.trim();
      }

      await _controller.service.salvarAluno(dadosParaSalvar);
      debugPrint('✅ Salvo no Firestore!');

      // 4. Marcar na planilha
      final linha = widget.alunoData['index_planilha'];
      await _marcarNaPlanilha(linha);

      // 5. Voltar para tela anterior
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ ERRO CRÍTICO: $e');
      _mostrarErro("❌ Erro ao migrar: ${e.toString()}");
    } finally {
      if (mounted) {
        _controller.setSaving(false);
      }
    }
  }

  Future<void> _marcarNaPlanilha(int? linha) async {
    if (linha == null) return;

    debugPrint('Marcando linha $linha na planilha...');

    try {
      final response = await http.post(
        Uri.parse(_urlScript),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'acao': 'marcar_concluido', 'linha': linha.toString()},
      ).timeout(const Duration(seconds: 15));

      debugPrint('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = response.body.trim();

        try {
          final jsonResponse = json.decode(responseBody) as Map<String, dynamic>;
          if (jsonResponse['sucesso'] == true) {
            _mostrarSucesso("✅ Aluno migrado com sucesso!");
          } else {
            final erro = jsonResponse['erro'] ?? 'Erro desconhecido';
            _mostrarSucessoComAviso('Script: $erro');
          }
        } catch (jsonError) {
          if (responseBody.toLowerCase().contains('sucesso') || responseBody.toLowerCase().contains('success')) {
            _mostrarSucessoComAviso('Migrado! (script respondeu OK)');
          } else if (responseBody.contains('<!DOCTYPE') || responseBody.contains('<html>')) {
            _mostrarSucessoComAviso('Erro no script (HTML retornado)');
          } else {
            final length = responseBody.length > 50 ? 50 : responseBody.length;
            _mostrarSucessoComAviso('Script respondeu: ${responseBody.substring(0, length)}...');
          }
        }
      } else {
        _mostrarSucessoComAviso('Erro HTTP ${response.statusCode}');
      }
    } catch (scriptError) {
      debugPrint('❌ Erro script: $scriptError');
      _mostrarSucessoComAviso('Não foi possível conectar ao script');
    }
  }

  void _mostrarSucesso(String mensagem) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        )
    );
  }

  void _mostrarSucessoComAviso(String aviso) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✅ Aluno migrado para o Firestore!'),
              const SizedBox(height: 4),
              Text('Obs: $aviso', style: const TextStyle(fontSize: 12)),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        )
    );
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        )
    );
  }

  Future<void> _selecionarData(TextEditingController controller) async {
    DateTime? initialDate;
    try {
      initialDate = DateFormat('dd/MM/yyyy').parseStrict(controller.text);
    } catch(_){
      initialDate = DateTime.now();
    }

    DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100)
    );

    if (picked != null && mounted) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _controller.nomeController.text.isNotEmpty
                ? _controller.nomeController.text
                : 'Migrar Aluno'
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (_controller.isSaving)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
      body: _controller.isSaving
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Migrando aluno...', style: TextStyle(fontSize: 16, color: Colors.grey)),
            Text('Por favor, aguarde', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FOTO
              if (_controller.fotoController.text.isNotEmpty)
                _buildFotoPreview(),

              // DADOS PESSOAIS
              _buildSectionTitle('👤 Dados Pessoais'),
              _buildTextField(_controller.nomeController, 'Nome Completo', isRequired: true),
              _buildTextField(_controller.apelidoController, 'Apelido'),
              _buildTextField(_controller.cpfController, 'CPF', keyboardType: TextInputType.number),
              _buildDropdown(_controller.sexoController, 'Sexo', _controller.opcoesSexo),
              _buildDateField(_controller.dataNascimentoController, 'Data de Nascimento'),

              // LOCAL TREINO
              _buildSectionTitle('🏢 Local de Treino'),
              _buildAcademiaDropdown(),
              _buildTurmaDropdown(),
              _buildTextField(_controller.cidadeController, 'Cidade'),
              _buildTextField(_controller.modalidadeController, 'Modalidade'),

              // DADOS CAPOEIRA
              _buildSectionTitle('🥋 Dados de Capoeira'),
              _buildGraduacaoDropdown(),
              _buildDateField(_controller.dataGraduacaoController, 'Data da Última Graduação'),
              _buildDateField(_controller.tempoCapoeiraController, 'Início na Capoeira'),
              _buildDropdown(_controller.statusController, 'Status da Atividade', _controller.opcoesStatus),

              // CONTATOS
              _buildSectionTitle('📞 Contatos e Endereço'),
              _buildTextField(_controller.contatoController, 'Contato do Aluno', keyboardType: TextInputType.phone),
              _buildTextField(_controller.responsavelController, 'Nome do Responsável'),
              _buildTextField(_controller.contatoResponsavelController, 'Contato do Responsável', keyboardType: TextInputType.phone),
              _buildTextField(_controller.enderecoController, 'Endereço', maxLines: 2),

              // ADMINISTRATIVO
              _buildSectionTitle('📋 Dados Administrativos'),
              _buildTextField(_controller.cadastroPorController, 'Cadastro Realizado Por'),
              _buildTextField(_controller.atualizadoPorController, 'Última Atualização Por'),
              _buildDateField(_controller.dataAtualizacaoController, 'Data da Última Atualização'),
              _buildDateField(_controller.dataCadastroController, 'Data do Cadastro'),

              // EDITÁVEL
              _buildEditavelSwitch(),

              // INFO GRADUAÇÃO
              if (_controller.graduacaoController.text.isNotEmpty)
                _buildInfoGraduacao(),

              const SizedBox(height: 24),

              // BOTÃO PRINCIPAL
              _buildBotaoSalvar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFotoPreview() {
    return Column(
      children: [
        Container(
          width: 200,
          height: 200,
          margin: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _controller.fotoController.text,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[200],
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person, size: 60, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Foto não disponível'),
                    ],
                  ),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildAcademiaDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Academia/Núcleo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _controller.selectedAcademiaId,
                hint: const Text('Selecione uma academia'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Selecione uma academia')),
                  ..._controller.academiasMap.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                ],
                onChanged: _controller.isSaving ? null : (String? novoId) {
                  if (novoId != null) {
                    setState(() {
                      _controller.setSelectedAcademia(
                        novoId,
                        _controller.academiasMap[novoId],
                      );
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurmaDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Turma', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _controller.selectedTurmaId,
                    hint: const Text('Selecione uma turma (opcional)'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sem turma')),
                      ..._controller.turmasMap.entries.map((entry) {
                        final turma = entry.value;
                        final horario = turma['horario'] ?? '';
                        final displayText = horario.isNotEmpty
                            ? '${turma['nome']} ($horario)'
                            : turma['nome'].toString();
                        return DropdownMenuItem(
                          value: entry.key,
                          child: Text(displayText, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                    ],
                    onChanged: _controller.isSaving ? null : (String? novoId) {
                      if (novoId != null) {
                        setState(() {
                          _controller.setSelectedTurma(
                            novoId,
                            _controller.turmasMap[novoId]?['nome'] as String?,
                          );
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_controller.carregandoTurmas)
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withOpacity(0.7),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGraduacaoDropdown() {
    if (_controller.isLoadingGraduacoes) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey[100],
          ),
          child: const Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Carregando graduações...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: _controller.selectedGraduacaoId,
          items: [
            const DropdownMenuItem(value: null, child: Text('-- Sem graduação --')),
            ..._controller.graduacoesDocs.map((doc) {
              final nome = doc['nome_graduacao'] ?? 'Sem nome';
              return DropdownMenuItem(value: doc.id, child: Text(nome));
            }).toList(),
          ],
          onChanged: _controller.isSaving ? null : (v) {
            setState(() {
              _controller.setSelectedGraduacao(v);
            });
          },
          decoration: const InputDecoration(
            labelText: 'Graduação Atual',
            border: OutlineInputBorder(),
          ),
          isExpanded: true,
        )
    );
  }

  Widget _buildEditavelSwitch() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: const Text('Aluno Editável', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Permite que o aluno edite seus dados'),
        value: _controller.editavel,
        activeColor: Colors.red.shade900,
        onChanged: _controller.isSaving ? null : (v) {
          setState(() {
            _controller.setEditavel(v);
          });
        },
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildInfoGraduacao() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _controller.selectedGraduacaoId != null ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _controller.selectedGraduacaoId != null ? Colors.green : Colors.orange,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _controller.selectedGraduacaoId != null ? Icons.check_circle : Icons.warning,
            color: _controller.selectedGraduacaoId != null ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _controller.selectedGraduacaoId != null ? '✅ Graduação vinculada!' : '⚠️ Graduação não encontrada',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _controller.selectedGraduacaoId != null ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Nome: ${_controller.graduacaoController.text}', style: const TextStyle(fontSize: 14)),
                if (_controller.selectedGraduacaoId != null)
                  Text('ID: ${_controller.selectedGraduacaoId}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoSalvar() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _controller.isSaving ? null : _salvar,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _controller.isSaving
            ? const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Migrando...'),
          ],
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_upload, size: 24),
            SizedBox(width: 12),
            Text('SALVAR E FINALIZAR MIGRAÇÃO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // WIDGETS AUXILIARES
  Widget _buildSectionTitle(String title) {
    return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade800,
          ),
        )
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool isRequired = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label + (isRequired ? ' *' : ''),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildDropdown(TextEditingController controller, String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: items.contains(controller.text) ? controller.text : null,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: _controller.isSaving ? null : (v) {
          setState(() {
            controller.text = v ?? '';
          });
        },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        isExpanded: true,
      ),
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _controller.isSaving ? null : () => _selecionarData(controller),
          ),
        ),
        onTap: _controller.isSaving ? null : () => _selecionarData(controller),
      ),
    );
  }
}