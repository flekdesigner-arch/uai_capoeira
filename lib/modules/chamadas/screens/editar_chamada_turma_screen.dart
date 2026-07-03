import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

Color _readableOn(Color background) => background.computeLuminance() > 0.48
    ? const Color(0xFF111827)
    : const Color(0xFFFFFFFF);

class EditarChamadaTurmaScreen extends StatefulWidget {
  final String chamadaId;
  final Map<String, dynamic> chamadaData;
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const EditarChamadaTurmaScreen({
    super.key,
    required this.chamadaId,
    required this.chamadaData,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<EditarChamadaTurmaScreen> createState() =>
      _EditarChamadaTurmaScreenState();
}

class _EditarChamadaTurmaScreenState extends State<EditarChamadaTurmaScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _buscaController = TextEditingController();
  final _professorController = TextEditingController();
  final _observacaoController = TextEditingController();

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  List<Map<String, dynamic>> _alunosOriginal = [];
  List<Map<String, dynamic>> _alunosEdit = [];
  final Map<String, bool> _presencas = {};
  final Map<String, String> _observacoes = {};

  DateTime _dataOriginal = DateTime.now();
  DateTime _dataEdit = DateTime.now();
  String _tipoOriginal = 'OBJETIVA';
  String _tipoEdit = 'OBJETIVA';
  String _professorOriginal = '';
  String _professorIdOriginal = '';
  String _buscaAluno = '';
  String _filtroPresenca = 'Todos';
  bool _modoListaCompacta = false;
  bool _salvando = false;
  bool _mostrarProgresso = false;
  String _statusMensagem = '';
  Timer? _buscaDebounce;
  String _cacheAssinaturaFiltro = '';
  List<Map<String, dynamic>> _cacheAlunosFiltrados = [];

  final List<String> _tiposAula = const [
    'OBJETIVA',
    'RODA',
    'INSTRUMENTAÇÃO',
    'ESPECIAL',
    'EVENTO',
    'BATIZADO',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _inicializarDados();
    _buscaController.addListener(_onBuscaChanged);
  }

  @override
  void dispose() {
    _buscaDebounce?.cancel();
    _buscaController.dispose();
    _professorController.dispose();
    _observacaoController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Color _onPrimary() {
    final t = context.uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;
    return temaEscuro ? Colors.white : _readableOn(t.primary);
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(background.computeLuminance() < 0.45 ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _saveButtonBg() =>
      _ensureVisible(context.uai.primary, context.uai.cardAlt);
  Color _saveButtonFg() => _readableOn(_saveButtonBg());

  void _inicializarDados() {
    final data = widget.chamadaData;
    _dataOriginal = _parseDateTime(data['data_chamada']) ?? DateTime.now();
    _dataEdit = _dataOriginal;
    _tipoOriginal = (data['tipo_aula']?.toString().trim().isEmpty ?? true)
        ? 'OBJETIVA'
        : data['tipo_aula'].toString().trim().toUpperCase();
    _tipoEdit = _tipoOriginal;
    _professorOriginal = data['professor_nome']?.toString() ?? 'Professor';
    _professorIdOriginal = data['professor_id']?.toString() ?? '';
    _professorController.text = _professorOriginal;

    _alunosOriginal = (data['alunos'] as List? ?? [])
        .whereType<Map>()
        .map((a) => _normalizarAluno(Map<String, dynamic>.from(a)))
        .where((a) => (a['id']?.toString() ?? '').isNotEmpty)
        .toList();
    _alunosEdit = _alunosOriginal
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
    for (final aluno in _alunosEdit) {
      final id = aluno['id']?.toString() ?? '';
      _presencas[id] = aluno['presente'] == true;
      _observacoes[id] = aluno['observacao']?.toString() ?? '';
    }
  }

  Map<String, dynamic> _normalizarAluno(Map<String, dynamic> source) {
    final id = (source['aluno_id'] ?? source['id'] ?? '').toString();
    final nome = (source['aluno_nome'] ?? source['nome'] ?? 'Sem nome')
        .toString();
    final foto = (source['foto_perfil_aluno'] ?? source['foto'] ?? '')
        .toString();
    return {
      ...source,
      'aluno_id': id,
      'id': id,
      'aluno_nome': nome,
      'nome': nome,
      'apelido': source['apelido']?.toString() ?? '',
      'presente': source['presente'] == true,
      'observacao': source['observacao']?.toString() ?? '',
      'foto_perfil_aluno': foto,
      'foto': foto,
      'graduacao_id': source['graduacao_id'],
      'graduacao_nome': source['graduacao_nome']?.toString() ?? '',
      'ultimo_dia_presente': source['ultimo_dia_presente'],
    };
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  void _onBuscaChanged() {
    _buscaDebounce?.cancel();
    _buscaDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _buscaAluno = _buscaController.text.trim();
        _invalidarCacheFiltro();
      });
    });
  }

  void _invalidarCacheFiltro() => _cacheAssinaturaFiltro = '';

  String _normalizarTextoBusca(String texto) => texto
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  List<Map<String, dynamic>> get _alunosFiltrados {
    final assinatura = _assinaturaFiltroAlunos();
    if (_cacheAssinaturaFiltro == assinatura) return _cacheAlunosFiltrados;
    final busca = _normalizarTextoBusca(_buscaAluno);
    final resultado = <Map<String, dynamic>>[];
    for (final aluno in _alunosEdit) {
      final id = aluno['id']?.toString() ?? '';
      final presente = _presencas[id] ?? false;
      final observacao = (_observacoes[id] ?? '').trim();
      if (_filtroPresenca == 'Presentes' && !presente) continue;
      if (_filtroPresenca == 'Ausentes' && presente) continue;
      if (_filtroPresenca == 'Com observação' && observacao.isEmpty) continue;
      if (busca.isNotEmpty) {
        final nome = aluno['nome']?.toString() ?? '';
        final apelido = aluno['apelido']?.toString() ?? '';
        final graduacao = aluno['graduacao_nome']?.toString() ?? '';
        final texto = _normalizarTextoBusca(
          '$nome $apelido $graduacao $observacao',
        );
        if (!texto.contains(busca)) continue;
      }
      resultado.add(aluno);
    }
    _cacheAssinaturaFiltro = assinatura;
    _cacheAlunosFiltrados = resultado;
    return resultado;
  }

  String _assinaturaFiltroAlunos() {
    final presentes = _presencas.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .join('|');
    final observacoes = _observacoes.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => '${e.key}:${e.value.trim().length}')
        .join('|');
    return '${_alunosEdit.length}::${_normalizarTextoBusca(_buscaAluno)}::'
        '$_filtroPresenca::$presentes::$observacoes';
  }

  int get _presentes => _presencas.values.where((v) => v).length;
  int get _total => _alunosEdit.length;
  int get _ausentes => _total - _presentes;
  int get _percentual => _total > 0 ? ((_presentes / _total) * 100).round() : 0;

  String _dataFormatada(DateTime data) => DateFormat('yyyy-MM-dd').format(data);
  String _mesKey(DateTime data) => DateFormat('yyyy-MM').format(data);

  String _semanaKey(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final yearStart = DateTime.utc(thursday.year, 1, 1);
    final week = ((thursday.difference(yearStart).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  String _diaSemanaAbrev(DateTime data) {
    switch (data.weekday) {
      case DateTime.monday:
        return 'seg';
      case DateTime.tuesday:
        return 'ter';
      case DateTime.wednesday:
        return 'qua';
      case DateTime.thursday:
        return 'qui';
      case DateTime.friday:
        return 'sex';
      case DateTime.saturday:
        return 'sab';
      case DateTime.sunday:
        return 'dom';
      default:
        return 'seg';
    }
  }

  bool _mesAtual(DateTime data) {
    final now = DateTime.now();
    return data.year == now.year && data.month == now.month;
  }

  bool _semanaAtual(DateTime data) =>
      _semanaKey(data) == _semanaKey(DateTime.now());

  void _addNestedDelta(Map<String, dynamic> map, List<String> path, int delta) {
    if (delta == 0 || path.isEmpty) return;
    if (path.length == 1) {
      final key = path.first;
      final atual = map[key];
      map[key] = atual is int ? atual + delta : delta;
      return;
    }
    final key = path.first;
    final child = Map<String, dynamic>.from((map[key] as Map?) ?? {});
    map[key] = child;
    _addNestedDelta(child, path.sublist(1), delta);
  }

  void _aplicarDeltaContador(
    Map<String, dynamic> contador,
    DateTime data,
    int delta,
  ) {
    if (delta == 0) return;
    final ano = data.year.toString();
    final mes = _mesKey(data);
    final semana = _semanaKey(data);
    _addNestedDelta(contador, ['total'], delta);
    _addNestedDelta(contador, ['porAno', ano], delta);
    _addNestedDelta(contador, ['porMes', mes], delta);
    _addNestedDelta(contador, ['porSemana', semana], delta);
    if (_mesAtual(data)) _addNestedDelta(contador, ['mes'], delta);
    if (_semanaAtual(data)) _addNestedDelta(contador, ['semana'], delta);
  }

  Map<String, dynamic> _materializarIncrements(
    Map<String, dynamic> raw, {
    bool incrementContext = false,
  }) {
    final result = <String, dynamic>{};
    raw.forEach((key, value) {
      final shouldIncrement =
          incrementContext || key == 'total' || key == 'mes' || key == 'semana';
      final childIncrement =
          incrementContext ||
          key == 'porAno' ||
          key == 'porMes' ||
          key == 'porSemana' ||
          key == 'contadores';
      if (value is int) {
        if (shouldIncrement) {
          if (value != 0) result[key] = FieldValue.increment(value);
        } else {
          result[key] = value;
        }
      } else if (value is Map<String, dynamic>) {
        final child = _materializarIncrements(
          value,
          incrementContext: childIncrement,
        );
        if (child.isNotEmpty) result[key] = child;
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  _ResumoEdicao _calcularResumoEdicao() {
    final originalPorId = {
      for (final a in _alunosOriginal) (a['id'] ?? '').toString(): a,
    };
    final presenca = <String>{};
    final observacao = <String>{};
    final logs = <String>{};
    final recalcular = <String>{};
    int ajustesContador = 0;
    final mudouData =
        _dataFormatada(_dataOriginal) != _dataFormatada(_dataEdit) ||
        _dataOriginal.hour != _dataEdit.hour ||
        _dataOriginal.minute != _dataEdit.minute;
    final mudouTipo = _tipoOriginal != _tipoEdit;
    final professorNovo = _professorController.text.trim().isEmpty
        ? 'Professor'
        : _professorController.text.trim();
    final mudouProfessor = professorNovo != _professorOriginal;

    for (final aluno in _alunosEdit) {
      final id = aluno['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final original = originalPorId[id];
      final antes = original?['presente'] == true;
      final depois = _presencas[id] == true;
      final obsAntes = original?['observacao']?.toString().trim() ?? '';
      final obsDepois = (_observacoes[id] ?? '').trim();
      final alterouPresenca = antes != depois;
      final alterouObs = obsAntes != obsDepois;
      if (alterouPresenca) {
        presenca.add(id);
        logs.add(id);
        recalcular.add(id);
      }
      if (alterouObs) {
        observacao.add(id);
        logs.add(id);
      }
      if (mudouData || mudouTipo || mudouProfessor) logs.add(id);
      if (mudouData && (antes || depois)) recalcular.add(id);
      if ((mudouTipo || mudouProfessor) && (antes || depois))
        recalcular.add(id);
      if (mudouData) {
        if (antes) ajustesContador++;
        if (depois) ajustesContador++;
      } else if (alterouPresenca) {
        ajustesContador++;
      }
    }

    return _ResumoEdicao(
      mudouData: mudouData,
      mudouTipo: mudouTipo,
      mudouProfessor: mudouProfessor,
      alunosComPresencaAlterada: presenca,
      alunosComObservacaoAlterada: observacao,
      alunosComLogAlterado: logs,
      alunosParaRecalcularUltimos: recalcular,
      ajustesContador: ajustesContador,
    );
  }

  Map<String, dynamic> _alunoEditadoParaSalvar(Map<String, dynamic> aluno) {
    final id = aluno['id']?.toString() ?? aluno['aluno_id']?.toString() ?? '';
    final nome =
        aluno['nome']?.toString() ??
        aluno['aluno_nome']?.toString() ??
        'Sem nome';
    final foto =
        aluno['foto_perfil_aluno']?.toString().trim().isNotEmpty == true
        ? aluno['foto_perfil_aluno'].toString().trim()
        : aluno['foto']?.toString().trim() ?? '';
    return {
      ...aluno,
      'aluno_id': id,
      'id': id,
      'aluno_nome': nome,
      'nome': nome,
      'apelido': aluno['apelido']?.toString() ?? '',
      'presente': _presencas[id] == true,
      'observacao': (_observacoes[id] ?? '').trim(),
      'foto_perfil_aluno': foto,
      'foto': foto,
      'graduacao_id': aluno['graduacao_id'],
      'graduacao_nome': aluno['graduacao_nome']?.toString() ?? '',
      'ultimo_dia_presente': aluno['ultimo_dia_presente'],
    };
  }

  Map<String, dynamic> _montarLogData(Map<String, dynamic> aluno) {
    final alunoId =
        aluno['id']?.toString() ?? aluno['aluno_id']?.toString() ?? '';
    final professorNome = _professorController.text.trim().isEmpty
        ? 'Professor'
        : _professorController.text.trim();
    return {
      'log_id': 'log_${widget.turmaId}_${alunoId}_${_dataFormatada(_dataEdit)}',
      'chamada_id': widget.chamadaId,
      'aluno_id': alunoId,
      'aluno_nome':
          aluno['aluno_nome']?.toString() ??
          aluno['nome']?.toString() ??
          'Sem nome',
      'turma_id': widget.turmaId,
      'turma_nome': widget.turmaNome,
      'academia_id': widget.academiaId,
      'academia_nome': widget.academiaNome,
      'data_aula': Timestamp.fromDate(_dataEdit),
      'data_formatada': _dataFormatada(_dataEdit),
      'dia_semana_abrev': _diaSemanaAbrev(_dataEdit),
      'presente': _presencas[alunoId] == true,
      'tipo_aula': _tipoEdit,
      'observacao': (_observacoes[alunoId] ?? '').trim(),
      'professor_id': _professorIdOriginal,
      'professor_nome': professorNome,
      'atualizado_em': FieldValue.serverTimestamp(),
      'tipo_registro': 'chamada_turma_editada',
    };
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _buscarLogsDoAluno(
    String alunoId,
    String dataFormatadaAntiga,
  ) async {
    final porChamada = await _firestore
        .collection('log_presenca_alunos')
        .where('chamada_id', isEqualTo: widget.chamadaId)
        .where('aluno_id', isEqualTo: alunoId)
        .get();
    if (porChamada.docs.isNotEmpty) return porChamada.docs;
    final fallback = await _firestore
        .collection('log_presenca_alunos')
        .where('turma_id', isEqualTo: widget.turmaId)
        .where('aluno_id', isEqualTo: alunoId)
        .where('data_formatada', isEqualTo: dataFormatadaAntiga)
        .get();
    return fallback.docs;
  }

  Future<bool> _confirmarSalvar(_ResumoEdicao resumo) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: context.uai.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
            ),
            title: Text(
              'Confirmar edição da chamada',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildResumoLinha(
                  'Alunos com presença alterada',
                  resumo.alunosComPresencaAlterada.length,
                ),
                _buildResumoLinha(
                  'Alunos com observação alterada',
                  resumo.alunosComObservacaoAlterada.length,
                ),
                _buildResumoLinha(
                  'Mudou data',
                  resumo.mudouData ? 'sim' : 'não',
                ),
                _buildResumoLinha(
                  'Mudou tipo',
                  resumo.mudouTipo ? 'sim' : 'não',
                ),
                _buildResumoLinha(
                  'Mudou professor',
                  resumo.mudouProfessor ? 'sim' : 'não',
                ),
                _buildResumoLinha(
                  'Contadores que serão ajustados',
                  resumo.ajustesContador,
                ),
                if (resumo.mudouData) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.uai.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.uai.warning.withOpacity(0.28),
                      ),
                    ),
                    child: Text(
                      'A alteração de data exige ajuste dos logs da chamada.',
                      style: TextStyle(
                        color: _ensureVisible(
                          context.uai.warning,
                          context.uai.surface,
                        ),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
                  backgroundColor: _saveButtonBg(),
                  foregroundColor: _saveButtonFg(),
                ),
                child: const Text('Salvar edição'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildResumoLinha(String label, Object value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.uai.textSecondary),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _salvarEdicao() async {
    if (_salvando) return;
    final resumo = _calcularResumoEdicao();
    if (!resumo.temAlteracao) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Nenhuma alteração detectada.'),
          backgroundColor: context.uai.info,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final confirmou = await _confirmarSalvar(resumo);
    if (!confirmou || !mounted) return;

    setState(() {
      _salvando = true;
      _mostrarProgresso = true;
      _statusMensagem = 'Atualizando chamada...';
    });
    _animationController.forward();

    try {
      final user = _auth.currentUser;
      final alunosSalvar = _alunosEdit.map(_alunoEditadoParaSalvar).toList();
      final dataNovaFormatada = _dataFormatada(_dataEdit);
      final dataAntigaFormatada = _dataFormatada(_dataOriginal);
      final professorNome = _professorController.text.trim().isEmpty
          ? 'Professor'
          : _professorController.text.trim();
      final originalPorId = {
        for (final a in _alunosOriginal) (a['id'] ?? '').toString(): a,
      };
      final editadoPorNome = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : user?.email;
      final batch = _firestore.batch();

      batch.update(_firestore.collection('chamadas').doc(widget.chamadaId), {
        'data_chamada': Timestamp.fromDate(_dataEdit),
        'data_formatada': dataNovaFormatada,
        'dia_semana_abrev': _diaSemanaAbrev(_dataEdit),
        'tipo_aula': _tipoEdit,
        'professor_nome': professorNome,
        'professor_id': _professorIdOriginal,
        'alunos': alunosSalvar,
        'presentes': _presentes,
        'ausentes': _ausentes,
        'total_alunos': _total,
        'porcentagem_frequencia': _percentual,
        'atualizado_em': FieldValue.serverTimestamp(),
        'editado_em': FieldValue.serverTimestamp(),
        'chamada_editada': true,
        'editado_por_uid': user?.uid,
        'editado_por_nome': editadoPorNome,
        'editado_por_email': user?.email,
        'edicao_origem': 'editar_chamada_turma_screen',
        'resumo_edicao': resumo.textoCurto,
      });

      setState(() => _statusMensagem = 'Sincronizando logs...');
      for (final aluno in alunosSalvar) {
        final alunoId = aluno['id']?.toString() ?? '';
        if (alunoId.isEmpty || !resumo.alunosComLogAlterado.contains(alunoId)) {
          continue;
        }
        final logs = await _buscarLogsDoAluno(alunoId, dataAntigaFormatada);
        final logData = _montarLogData(aluno);
        if (logs.isNotEmpty) {
          batch.set(logs.first.reference, logData, SetOptions(merge: true));
          for (final extra in logs.skip(1)) {
            batch.delete(extra.reference);
          }
        } else {
          batch.set(
            _firestore
                .collection('log_presenca_alunos')
                .doc('log_${widget.turmaId}_${alunoId}_$dataNovaFormatada'),
            {...logData, 'registrado_em': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        }
      }

      setState(() => _statusMensagem = 'Ajustando contadores...');
      for (final aluno in alunosSalvar) {
        final alunoId = aluno['id']?.toString() ?? '';
        if (alunoId.isEmpty) continue;
        final original = originalPorId[alunoId];
        final antes = original?['presente'] == true;
        final depois = _presencas[alunoId] == true;
        final alterouPresenca = antes != depois;
        final precisaContador = resumo.mudouData
            ? (antes || depois)
            : alterouPresenca;
        if (!precisaContador) continue;

        final contadorRaw = <String, dynamic>{
          'aluno_id': alunoId,
          'aluno_nome': aluno['aluno_nome']?.toString() ?? 'Sem nome',
          'turma_id_atual': widget.turmaId,
          'turma_nome_atual': widget.turmaNome,
          'academia_id_atual': widget.academiaId,
          'academia_nome_atual': widget.academiaNome,
          'cache_versao': 5,
          'atualizado_em': FieldValue.serverTimestamp(),
          'ultima_sync_logs': FieldValue.serverTimestamp(),
          'periodo_mes_atual': _mesKey(DateTime.now()),
          'periodo_semana_atual': _semanaKey(DateTime.now()),
        };
        final legacyRaw = <String, dynamic>{};
        if (resumo.mudouData) {
          if (antes) {
            _aplicarDeltaContador(contadorRaw, _dataOriginal, -1);
            _addNestedDelta(legacyRaw, [
              'contadores',
              _mesKey(_dataOriginal),
            ], -1);
          }
          if (depois) {
            _aplicarDeltaContador(contadorRaw, _dataEdit, 1);
            _addNestedDelta(legacyRaw, ['contadores', _mesKey(_dataEdit)], 1);
          }
        } else if (alterouPresenca) {
          if (!antes && depois) {
            _aplicarDeltaContador(contadorRaw, _dataEdit, 1);
            _addNestedDelta(legacyRaw, ['contadores', _mesKey(_dataEdit)], 1);
          } else if (antes && !depois) {
            _aplicarDeltaContador(contadorRaw, _dataOriginal, -1);
            _addNestedDelta(legacyRaw, [
              'contadores',
              _mesKey(_dataOriginal),
            ], -1);
          }
        }
        final contadorUpdate = _materializarIncrements(contadorRaw);
        if (contadorUpdate.isNotEmpty) {
          batch.set(
            _firestore
                .collection('alunos')
                .doc(alunoId)
                .collection('contadores')
                .doc('frequencia_dashboard'),
            contadorUpdate,
            SetOptions(merge: true),
          );
        }
        final legacyUpdate = _materializarIncrements(legacyRaw);
        if (legacyUpdate.isNotEmpty) {
          batch.set(
            _firestore.collection('alunos').doc(alunoId),
            legacyUpdate,
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();
      setState(() => _statusMensagem = 'Recalculando últimas presenças...');
      for (final alunoId in resumo.alunosParaRecalcularUltimos) {
        await _recalcularUltimosDoAluno(alunoId);
      }
      if (!mounted) return;
      setState(() => _statusMensagem = 'Finalizando...');
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Chamada editada com sucesso.'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Erro ao salvar edição da chamada: $e');
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _mostrarProgresso = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar edição: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _recalcularUltimosDoAluno(String alunoId) async {
    try {
      final alunoRef = _firestore.collection('alunos').doc(alunoId);
      final contadorRef = alunoRef
          .collection('contadores')
          .doc('frequencia_dashboard');
      final ultimaPresencaQuery = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: alunoId)
          .where('presente', isEqualTo: true)
          .orderBy('data_aula', descending: true)
          .limit(1)
          .get();
      final ultimaChamadaQuery = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: alunoId)
          .orderBy('data_aula', descending: true)
          .limit(1)
          .get();
      final updatesAluno = <String, dynamic>{};
      final updatesContador = <String, dynamic>{};
      if (ultimaPresencaQuery.docs.isNotEmpty) {
        final d = ultimaPresencaQuery.docs.first.data();
        updatesAluno['ultima_presenca'] = d['data_aula'];
        updatesAluno['ultimo_dia_presente'] = d['data_formatada'];
        updatesContador['ultima_presenca'] = d['data_aula'];
        updatesContador['ultimo_dia_presente'] = d['data_formatada'];
      } else {
        updatesAluno['ultima_presenca'] = null;
        updatesAluno['ultimo_dia_presente'] = null;
        updatesContador['ultima_presenca'] = null;
        updatesContador['ultimo_dia_presente'] = null;
      }
      if (ultimaChamadaQuery.docs.isNotEmpty) {
        final d = ultimaChamadaQuery.docs.first.data();
        updatesAluno['ultima_chamada'] = d['data_aula'];
        updatesAluno['ultima_chamada_por'] = d['professor_nome'];
        updatesAluno['ultima_chamada_por_id'] = d['professor_id'];
      } else {
        updatesAluno['ultima_chamada'] = null;
        updatesAluno['ultima_chamada_por'] = null;
        updatesAluno['ultima_chamada_por_id'] = null;
      }
      updatesAluno['atualizado_em'] = FieldValue.serverTimestamp();
      updatesContador['atualizado_em'] = FieldValue.serverTimestamp();
      updatesContador['ultima_sync_logs'] = FieldValue.serverTimestamp();
      await alunoRef.set(updatesAluno, SetOptions(merge: true));
      await contadorRef.set(updatesContador, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao recalcular últimos do aluno $alunoId: $e');
    }
  }

  void _marcarTodosFiltrados(bool presente) {
    if (_salvando) return;
    final filtrados = _alunosFiltrados;
    if (filtrados.isEmpty) return;
    setState(() {
      for (final aluno in filtrados) {
        final id = aluno['id']?.toString() ?? '';
        if (id.isNotEmpty) _presencas[id] = presente;
      }
      _invalidarCacheFiltro();
    });
    HapticFeedback.lightImpact();
  }

  void _inverterFiltrados() {
    if (_salvando) return;
    final filtrados = _alunosFiltrados;
    if (filtrados.isEmpty) return;
    setState(() {
      for (final aluno in filtrados) {
        final id = aluno['id']?.toString() ?? '';
        if (id.isNotEmpty) _presencas[id] = !(_presencas[id] ?? false);
      }
      _invalidarCacheFiltro();
    });
    HapticFeedback.mediumImpact();
  }

  void _togglePresenca(String alunoId) {
    if (_salvando) return;
    setState(() {
      _presencas[alunoId] = !(_presencas[alunoId] ?? false);
      _invalidarCacheFiltro();
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _selecionarData() async {
    if (_salvando) return;
    final data = await showDatePicker(
      context: context,
      initialDate: _dataEdit,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dataEdit),
    );
    if (!mounted) return;
    setState(() {
      _dataEdit = DateTime(
        data.year,
        data.month,
        data.day,
        hora?.hour ?? _dataEdit.hour,
        hora?.minute ?? _dataEdit.minute,
      );
    });
  }

  void _adicionarObservacao(String alunoId, String nomeAluno) {
    if (_salvando) return;
    _observacaoController.text = _observacoes[alunoId] ?? '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        title: Text(
          'Observação para $nomeAluno',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: _observacaoController,
          maxLines: 3,
          style: TextStyle(color: context.uai.textPrimary),
          decoration: InputDecoration(
            hintText: 'Digite uma observação...',
            hintStyle: TextStyle(color: context.uai.textMuted),
            filled: true,
            fillColor: context.uai.cardAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(context.uai.inputRadius),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(context.uai.inputRadius),
              borderSide: BorderSide(color: context.uai.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(context.uai.inputRadius),
              borderSide: BorderSide(color: context.uai.primary, width: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _observacoes[alunoId] = _observacaoController.text;
                _invalidarCacheFiltro();
              });
              _observacaoController.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _saveButtonBg(),
              foregroundColor: _saveButtonFg(),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  bool _isChamadaDesktop(double width) => width >= 760;
  double _maxChamadaContentWidth(double width) => width >= 1200 ? 1180 : width;

  EdgeInsets _gridPaddingForWidth(double width) {
    if (width >= 1200) return const EdgeInsets.fromLTRB(18, 10, 18, 18);
    if (width >= 700) return const EdgeInsets.fromLTRB(14, 8, 14, 16);
    return const EdgeInsets.fromLTRB(14, 8, 14, 14);
  }

  SliverGridDelegate _gridDelegateForChamada(double width) {
    if (!_isChamadaDesktop(width)) {
      return const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.76,
      );
    }
    return const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 245,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 0.76,
    );
  }

  SliverGridDelegate _compactDelegateForChamada(double width) {
    return const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 560,
      mainAxisExtent: 82,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Editar Chamada', style: TextStyle(fontSize: 16)),
            Text(
              '${widget.turmaNome} • ${DateFormat('dd/MM/yyyy HH:mm').format(_dataEdit)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          _buildTelaEdicao(),
          if (_mostrarProgresso) _buildTelaProgresso(),
        ],
      ),
    );
  }

  Widget _buildTelaEdicao() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraTela = constraints.maxWidth;
        final maxWidth = _maxChamadaContentWidth(larguraTela);
        final resumo = _calcularResumoEdicao();
        return Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _buildChamadaHeader(),
              ),
            ),
            Expanded(child: _buildAlunosList()),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  larguraTela >= 700 ? 18 : 14,
                  10,
                  larguraTela >= 700 ? 18 : 14,
                  12,
                ),
                decoration: BoxDecoration(
                  color: context.uai.cardAlt,
                  border: Border(top: BorderSide(color: context.uai.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 14,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _salvando
                                ? null
                                : () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ensureVisible(
                                context.uai.primary,
                                context.uai.cardAlt,
                              ),
                              side: BorderSide(color: context.uai.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text(
                              'CANCELAR',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: larguraTela >= 700 ? 3 : 2,
                          child: ElevatedButton(
                            onPressed: _salvando ? null : _salvarEdicao,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _saveButtonBg(),
                              foregroundColor: _saveButtonFg(),
                              disabledBackgroundColor: context.uai.border,
                              disabledForegroundColor:
                                  context.uai.textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.save_rounded, size: 22),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Salvar edição • ${resumo.totalAlteracoes} alterações',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _alunoPresencaAlterada(String id) {
    final original = _alunosOriginal.cast<Map<String, dynamic>?>().firstWhere(
      (a) => (a?['id'] ?? '').toString() == id,
      orElse: () => null,
    );
    return (original?['presente'] == true) != (_presencas[id] == true);
  }

  bool _alunoObservacaoAlterada(String id) {
    final original = _alunosOriginal.cast<Map<String, dynamic>?>().firstWhere(
      (a) => (a?['id'] ?? '').toString() == id,
      orElse: () => null,
    );
    final antes = original?['observacao']?.toString().trim() ?? '';
    final depois = (_observacoes[id] ?? '').trim();
    return antes != depois;
  }

  String _nomeAlunoCurto(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return 'Aluno';
    if (partes.length == 1) return partes.first;
    return '${partes.first} ${partes.last}';
  }

  Color _corIndicadorUltimaPresenca(Map<String, dynamic> aluno) {
    final data =
        _parseDateTime(aluno['ultimo_dia_presente']) ??
        _parseDateTime(aluno['ultima_presenca']);
    if (data == null) return context.uai.error;
    final hoje = DateTime.now();
    final dias = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
    ).difference(DateTime(data.year, data.month, data.day)).inDays;
    if (dias <= 7) return context.uai.success;
    if (dias <= 21) return context.uai.warning;
    return context.uai.error;
  }

  Widget _buildChamadaHeader() {
    final progress = _total > 0 ? _presentes / _total : 0.0;
    final progressColor = _presentes == 0
        ? context.uai.error
        : _presentes == _total
        ? context.uai.success
        : context.uai.warning;
    final onPrimary = _onPrimary();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: onPrimary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: onPrimary.withOpacity(0.16)),
                ),
                child: Icon(Icons.edit_calendar_rounded, color: onPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.turmaNome,
                            style: TextStyle(
                              color: onPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.uai.warning.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'MODO EDIÇÃO',
                            style: TextStyle(
                              color: _readableOn(context.uai.warning),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('dd/MM/yyyy HH:mm').format(_dataEdit)} • $_tipoEdit',
                      style: TextStyle(
                        color: onPrimary.withOpacity(0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$_presentes/$_total',
                style: TextStyle(
                  color: onPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildHeaderTinyStat('P', _presentes, context.uai.success),
              const SizedBox(width: 6),
              _buildHeaderTinyStat('A', _ausentes, context.uai.error),
              const SizedBox(width: 6),
              _buildHeaderTinyStat('T', _total, onPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: onPrimary.withOpacity(0.20),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _ensureVisible(progressColor, context.uai.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$_percentual%',
                style: TextStyle(
                  color: onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildInfoButton(
                  Icons.event_rounded,
                  DateFormat('dd/MM/yyyy HH:mm').format(_dataEdit),
                  _selecionarData,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildTipoDropdown()),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _professorController,
            enabled: !_salvando,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.person_rounded,
                color: context.uai.primary,
              ),
              labelText: 'Professor registrado',
              labelStyle: TextStyle(color: context.uai.textSecondary),
              filled: true,
              fillColor: context.uai.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
                borderSide: BorderSide(color: context.uai.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
                borderSide: BorderSide(color: context.uai.primary, width: 1.4),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _buildBusca(),
        ],
      ),
    );
  }

  Widget _buildHeaderTinyStat(String label, int value, Color color) {
    final onPrimary = _onPrimary();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: onPrimary.withOpacity(0.72),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '$value',
              style: TextStyle(
                color: _ensureVisible(color, context.uai.primary),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoButton(IconData icon, String text, VoidCallback onTap) {
    return InkWell(
      onTap: _salvando ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.uai.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.uai.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: _onCard(),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.uai.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _tiposAula.contains(_tipoEdit) ? _tipoEdit : _tiposAula.first,
          isExpanded: true,
          dropdownColor: context.uai.surface,
          iconEnabledColor: context.uai.primary,
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w800,
          ),
          items: _tiposAula
              .map((tipo) => DropdownMenuItem(value: tipo, child: Text(tipo)))
              .toList(),
          onChanged: _salvando
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _tipoEdit = value);
                },
        ),
      ),
    );
  }

  Widget _buildResumoCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            Icons.check_circle_rounded,
            'Presentes',
            '$_presentes',
            context.uai.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            Icons.cancel_rounded,
            'Ausentes',
            '$_ausentes',
            context.uai.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            Icons.groups_rounded,
            'Total',
            '$_total',
            context.uai.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            Icons.percent_rounded,
            'Frequência',
            '$_percentual%',
            context.uai.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final accent = _ensureVisible(color, context.uai.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: _onCard(),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: _onCardMuted(),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBusca() {
    return TextField(
      controller: _buscaController,
      enabled: !_salvando,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search_rounded, color: context.uai.primary),
        hintText: 'Buscar aluno ou observação...',
        hintStyle: TextStyle(color: context.uai.textMuted),
        filled: true,
        fillColor: context.uai.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: context.uai.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: context.uai.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildAlunosList() {
    if (_alunosEdit.isEmpty) {
      return _buildListaVazia(
        icon: Icons.people_outline_rounded,
        title: 'Nenhum aluno nesta chamada',
        subtitle: 'O documento da chamada não possui alunos no snapshot.',
      );
    }
    final alunos = _alunosFiltrados;
    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraTela = constraints.maxWidth;
        final maxWidth = _maxChamadaContentWidth(larguraTela);
        final isDesktop = _isChamadaDesktop(larguraTela);
        return Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _buildPainelControleChamada(),
              ),
            ),
            Expanded(
              child: alunos.isEmpty
                  ? _buildListaVazia(
                      icon: Icons.search_off_rounded,
                      title: 'Nenhum aluno neste filtro',
                      subtitle:
                          'Toque em "Todos" para voltar para a chamada completa.',
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: _modoListaCompacta
                            ? isDesktop
                                  ? GridView.builder(
                                      cacheExtent: 700,
                                      padding: _gridPaddingForWidth(
                                        larguraTela,
                                      ),
                                      gridDelegate: _compactDelegateForChamada(
                                        larguraTela,
                                      ),
                                      itemCount: alunos.length,
                                      itemBuilder: (context, index) =>
                                          _buildAlunoCompactTile(alunos[index]),
                                    )
                                  : ListView.builder(
                                      cacheExtent: 500,
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 14,
                                      ),
                                      itemCount: alunos.length,
                                      itemBuilder: (context, index) =>
                                          _buildAlunoCompactTile(alunos[index]),
                                    )
                            : GridView.builder(
                                cacheExtent: 800,
                                padding: _gridPaddingForWidth(larguraTela),
                                gridDelegate: _gridDelegateForChamada(
                                  larguraTela,
                                ),
                                itemCount: alunos.length,
                                itemBuilder: (context, index) =>
                                    _buildAlunoGridItem(alunos[index]),
                              ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPainelControleChamada() {
    final total = _alunosEdit.length;
    final filtrados = _alunosFiltrados.length;
    final presentesFiltrados = _alunosFiltrados
        .where((a) => _presencas[a['id']?.toString() ?? ''] == true)
        .length;
    return Container(
      color: context.uai.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFiltroPresencaChip('Todos', Icons.groups_rounded),
                _buildFiltroPresencaChip(
                  'Presentes',
                  Icons.check_circle_rounded,
                ),
                _buildFiltroPresencaChip('Ausentes', Icons.cancel_rounded),
                _buildFiltroPresencaChip(
                  'Com observação',
                  Icons.sticky_note_2_rounded,
                ),
                const SizedBox(width: 4),
                _buildModoVisualBotao(),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: context.uai.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.uai.border),
              boxShadow: context.uai.softShadow,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: context.uai.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$presentesFiltrados presentes • $filtrados/$total alunos',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.uai.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildMiniAcao(
                  label: 'Todos',
                  icon: Icons.done_all_rounded,
                  color: context.uai.success,
                  onTap: () => _marcarTodosFiltrados(true),
                ),
                const SizedBox(width: 5),
                _buildMiniAcao(
                  label: 'Zerar',
                  icon: Icons.remove_done_rounded,
                  color: context.uai.primaryDark,
                  onTap: () => _marcarTodosFiltrados(false),
                ),
                const SizedBox(width: 5),
                _buildMiniAcao(
                  label: 'Inverter',
                  icon: Icons.swap_vert_rounded,
                  color: context.uai.info,
                  onTap: _inverterFiltrados,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModoVisualBotao() {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: _salvando
            ? null
            : () => setState(() => _modoListaCompacta = !_modoListaCompacta),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.uai.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _modoListaCompacta
                    ? Icons.grid_view_rounded
                    : Icons.view_list_rounded,
                size: 15,
                color: context.uai.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _modoListaCompacta ? 'Grade' : 'Lista',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.uai.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltroPresencaChip(String filtro, IconData icon) {
    final ativo = _filtroPresenca == filtro;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: ativo,
        avatar: Icon(
          icon,
          size: 15,
          color: ativo
              ? _readableOn(context.uai.primary)
              : context.uai.textSecondary,
        ),
        label: Text(
          filtro,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: ativo
                ? _readableOn(context.uai.primary)
                : context.uai.textSecondary,
          ),
        ),
        selectedColor: context.uai.primary,
        backgroundColor: context.uai.card,
        side: BorderSide(
          color: ativo ? context.uai.primary : context.uai.border,
        ),
        onSelected: _salvando
            ? null
            : (_) => setState(() {
                _filtroPresenca = filtro;
                _invalidarCacheFiltro();
              }),
      ),
    );
  }

  Widget _buildMiniAcao({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final accent = _ensureVisible(color, context.uai.card);
    return InkWell(
      onTap: _salvando ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.24)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final id = aluno['id']?.toString() ?? '';
    final presente = _presencas[id] ?? false;
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final nomeCurto = _nomeAlunoCurto(nome);
    final foto =
        aluno['foto_perfil_aluno']?.toString().trim().isNotEmpty == true
        ? aluno['foto_perfil_aluno'].toString().trim()
        : aluno['foto']?.toString().trim() ?? '';
    final obs = (_observacoes[id] ?? '').trim();
    final presencaAlterada = _alunoPresencaAlterada(id);
    final observacaoAlterada = _alunoObservacaoAlterada(id);
    final statusColor = presente ? context.uai.success : context.uai.error;
    final accent = _ensureVisible(statusColor, context.uai.card);
    final ultimaColor = _ensureVisible(
      _corIndicadorUltimaPresenca(aluno),
      context.uai.card,
    );

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(presente ? 0.18 : 0.14),
              blurRadius: presente ? 13 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _togglePresenca(id),
            onLongPress: () => _adicionarObservacao(id, nome),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: presente
                      ? context.uai.success
                      : context.uai.error.withOpacity(0.70),
                  width: presente ? 2.2 : 1.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                foto.isEmpty
                                    ? Container(
                                        color: context.uai.cardAlt,
                                        child: Icon(
                                          Icons.person_rounded,
                                          size: 68,
                                          color: context.uai.textMuted,
                                        ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: foto,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 420,
                                        placeholder: (context, url) =>
                                            Container(
                                              color: context.uai.cardAlt,
                                              child: Center(
                                                child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            context.uai.primary,
                                                      ),
                                                ),
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                              color: context.uai.cardAlt,
                                              child: Icon(
                                                Icons.person_rounded,
                                                size: 68,
                                                color: context.uai.textMuted,
                                              ),
                                            ),
                                      ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.center,
                                        colors: [
                                          Colors.black.withOpacity(0.58),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  bottom: 10,
                                  child: Center(
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 132,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.34),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.10),
                                        ),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          nomeCurto,
                                          textAlign: TextAlign.center,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            height: 1.08,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withOpacity(
                                                  0.55,
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _buildAlunoMeta(aluno)),
                                    if (presencaAlterada || observacaoAlterada)
                                      _buildAlteradoBadge(
                                        presencaAlterada: presencaAlterada,
                                        observacaoAlterada: observacaoAlterada,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 112,
                                  height: 31,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _togglePresenca(id),
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: presente
                                          ? context.uai.success
                                          : context.uai.primary,
                                      foregroundColor: _readableOn(
                                        presente
                                            ? context.uai.success
                                            : context.uai.primary,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(17),
                                      ),
                                    ),
                                    icon: Icon(
                                      presente
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      size: 15,
                                    ),
                                    label: Text(
                                      presente ? 'Presente' : 'Marcar',
                                      style: const TextStyle(
                                        fontSize: 10.8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _adicionarObservacao(id, nome),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: obs.isNotEmpty
                                ? context.uai.warning
                                : Colors.white.withOpacity(0.94),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.16),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                          child: Icon(
                            obs.isNotEmpty
                                ? Icons.sticky_note_2_rounded
                                : Icons.note_add_outlined,
                            size: 17,
                            color: obs.isNotEmpty
                                ? _readableOn(context.uai.warning)
                                : _ensureVisible(
                                    context.uai.info,
                                    Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: presente
                              ? context.uai.success
                              : context.uai.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.uai.card, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 27,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: ultimaColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.uai.card, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (presencaAlterada)
                      Positioned(
                        left: 8,
                        bottom: 61,
                        child: _buildBadgeAlteradoCompacto(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlteradoBadge({
    required bool presencaAlterada,
    required bool observacaoAlterada,
  }) {
    final color = presencaAlterada ? context.uai.info : context.uai.warning;
    final accent = _ensureVisible(color, context.uai.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Icon(
        presencaAlterada ? Icons.edit_rounded : Icons.sticky_note_2_rounded,
        size: 13,
        color: accent,
      ),
    );
  }

  Widget _buildBadgeAlteradoCompacto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: context.uai.info.withOpacity(0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 6),
        ],
      ),
      child: Text(
        'alterado',
        style: TextStyle(
          color: _readableOn(context.uai.info),
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildAlunoCompactTile(Map<String, dynamic> aluno) {
    final id = aluno['id']?.toString() ?? '';
    final presente = _presencas[id] ?? false;
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final foto =
        aluno['foto_perfil_aluno']?.toString().trim().isNotEmpty == true
        ? aluno['foto_perfil_aluno'].toString().trim()
        : aluno['foto']?.toString().trim() ?? '';
    final obs = (_observacoes[id] ?? '').trim();
    final presencaAlterada = _alunoPresencaAlterada(id);
    final observacaoAlterada = _alunoObservacaoAlterada(id);
    final statusColor = presente ? context.uai.success : context.uai.error;
    final accent = _ensureVisible(statusColor, context.uai.card);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: presencaAlterada
              ? context.uai.info
              : accent.withOpacity(presente ? 0.52 : 0.22),
          width: presencaAlterada ? 2 : (presente ? 2 : 1),
        ),
      ),
      child: ListTile(
        onTap: () => _togglePresenca(id),
        leading: CircleAvatar(
          backgroundColor: context.uai.cardAlt,
          backgroundImage: foto.isEmpty
              ? null
              : CachedNetworkImageProvider(foto),
          child: foto.isEmpty
              ? Icon(Icons.person_rounded, color: context.uai.textMuted)
              : null,
        ),
        title: Text(
          nome,
          style: TextStyle(color: _onCard(), fontWeight: FontWeight.w900),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          obs.isEmpty ? _textoUltimaPresenca(aluno) : obs,
          style: TextStyle(
            color: obs.isEmpty
                ? _onCardMuted()
                : _ensureVisible(context.uai.warning, context.uai.card),
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (presencaAlterada || observacaoAlterada)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  presencaAlterada
                      ? Icons.edit_rounded
                      : Icons.sticky_note_2_rounded,
                  size: 18,
                  color: presencaAlterada
                      ? context.uai.info
                      : context.uai.warning,
                ),
              ),
            IconButton(
              tooltip: 'Observação',
              onPressed: () => _adicionarObservacao(id, nome),
              icon: Icon(
                obs.isEmpty
                    ? Icons.note_add_outlined
                    : Icons.sticky_note_2_rounded,
                color: observacaoAlterada
                    ? context.uai.warning
                    : obs.isEmpty
                    ? context.uai.textMuted
                    : context.uai.warning,
              ),
            ),
            Icon(
              presente ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlunoMeta(Map<String, dynamic> aluno) {
    final graduacao = aluno['graduacao_nome']?.toString() ?? '';
    final ultima = _textoUltimaPresenca(aluno);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (graduacao.isNotEmpty)
          Text(
            graduacao,
            style: TextStyle(
              color: context.uai.primary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        Text(
          ultima,
          style: TextStyle(color: _onCardMuted(), fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _textoUltimaPresenca(Map<String, dynamic> aluno) {
    final data =
        _parseDateTime(aluno['ultimo_dia_presente']) ??
        _parseDateTime(aluno['ultima_presenca']);
    if (data == null) return 'Sem presença registrada';
    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final dataLimpa = DateTime(data.year, data.month, data.day);
    final dias = hojeLimpo.difference(dataLimpa).inDays;
    if (dias <= 0) return 'Última presença hoje';
    if (dias == 1) return 'Última presença ontem';
    return 'Última presença há $dias dias';
  }

  Widget _buildListaVazia({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: context.uai.border),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelaProgresso() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.36),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [context.uai.primary, context.uai.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 58, color: _onPrimary()),
                    const SizedBox(height: 18),
                    Text(
                      'SALVANDO EDIÇÃO',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _onPrimary(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _onPrimary().withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _onPrimary().withOpacity(0.16),
                        ),
                      ),
                      child: Text(
                        _statusMensagem,
                        style: TextStyle(
                          fontSize: 14,
                          color: _onPrimary().withOpacity(0.92),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),
                    CircularProgressIndicator(color: _onPrimary()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResumoEdicao {
  const _ResumoEdicao({
    required this.mudouData,
    required this.mudouTipo,
    required this.mudouProfessor,
    required this.alunosComPresencaAlterada,
    required this.alunosComObservacaoAlterada,
    required this.alunosComLogAlterado,
    required this.alunosParaRecalcularUltimos,
    required this.ajustesContador,
  });

  final bool mudouData;
  final bool mudouTipo;
  final bool mudouProfessor;
  final Set<String> alunosComPresencaAlterada;
  final Set<String> alunosComObservacaoAlterada;
  final Set<String> alunosComLogAlterado;
  final Set<String> alunosParaRecalcularUltimos;
  final int ajustesContador;

  int get totalAlteracoes =>
      alunosComPresencaAlterada.length +
      alunosComObservacaoAlterada.length +
      (mudouData ? 1 : 0) +
      (mudouTipo ? 1 : 0) +
      (mudouProfessor ? 1 : 0);

  bool get temAlteracao =>
      mudouData ||
      mudouTipo ||
      mudouProfessor ||
      alunosComPresencaAlterada.isNotEmpty ||
      alunosComObservacaoAlterada.isNotEmpty;

  String get textoCurto {
    final partes = <String>[];
    if (alunosComPresencaAlterada.isNotEmpty) {
      partes.add('${alunosComPresencaAlterada.length} presença(s)');
    }
    if (alunosComObservacaoAlterada.isNotEmpty) {
      partes.add('${alunosComObservacaoAlterada.length} observação(ões)');
    }
    if (mudouData) partes.add('data');
    if (mudouTipo) partes.add('tipo');
    if (mudouProfessor) partes.add('professor');
    return partes.isEmpty ? 'Sem alterações' : partes.join(', ');
  }
}
