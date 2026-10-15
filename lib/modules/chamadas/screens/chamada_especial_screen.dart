import 'dart:async';
import 'package:uai_capoeira/core/session_log/session_log_service.dart';
// lib/modules/chamadas/screens/chamada_especial_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/modules/chamadas/services/aluno_foto_resolver.dart';
import 'package:uai_capoeira/core/image_cache/uai_student_photo.dart';

enum ViewMode { list, grid }

class ViewModeSelector extends StatelessWidget {
  final ViewMode currentMode;
  final ValueChanged<ViewMode> onChanged;

  const ViewModeSelector({
    super.key,
    required this.currentMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final onPrimary = t.primary.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            context,
            Icons.view_list,
            'Lista',
            ViewMode.list,
            onPrimary,
          ),
          const SizedBox(width: 8),
          _buildButton(
            context,
            Icons.grid_view,
            'Grade',
            ViewMode.grid,
            onPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    IconData icon,
    String label,
    ViewMode mode,
    Color onPrimary,
  ) {
    final t = context.uai;
    final isSelected = currentMode == mode;

    return GestureDetector(
      onTap: () => onChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? t.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? onPrimary : t.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? onPrimary : t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChamadaEspecialScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final String usuarioId;
  final DateTime dataSelecionada;

  const ChamadaEspecialScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    required this.usuarioId,
    required this.dataSelecionada,
  });

  @override
  State<ChamadaEspecialScreen> createState() => _ChamadaEspecialScreenState();
}

class _ChamadaEspecialScreenState extends State<ChamadaEspecialScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final TextEditingController _observacaoController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _mostrarProgresso = false;

  List<Map<String, dynamic>> _alunos = [];
  Map<String, bool> _presencas = {};
  final Map<String, String> _observacoes = {};

  String _professorNome = 'Carregando...';
  String _professorId = '';
  String _tipoAula = 'OBJETIVA';
  String _diaSemana = '';
  String _statusMensagem = '';
  ViewMode _viewMode = ViewMode.grid;

  bool _indicadoresAusenciaAtivo = true;
  bool _mostrarTextoUltimaPresencaIndicador = true;
  List<Map<String, dynamic>> _faixasIndicadoresAusencia = [];

  final Map<String, String> _diasAbreviados = {
    'SEGUNDA': 'seg',
    'TERÇA': 'ter',
    'TERCA': 'ter',
    'QUARTA': 'qua',
    'QUINTA': 'qui',
    'SEXTA': 'sex',
    'SÁBADO': 'sab',
    'SABADO': 'sab',
    'DOMINGO': 'dom',
  };

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _observacaoController.dispose();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  int _parseIntIndicador(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
  }

  List<Map<String, dynamic>> _faixasIndicadoresPadrao() {
    return [
      {'ate_dias': 3, 'cor': '#2196F3', 'label': 'Frequente'},
      {'ate_dias': 6, 'cor': '#4CAF50', 'label': 'Regular'},
      {'ate_dias': 12, 'cor': '#FFC107', 'label': 'Atenção'},
      {'ate_dias': 24, 'cor': '#FF9800', 'label': 'Ausente'},
      {'ate_dias': 35, 'cor': '#FF5722', 'label': 'Muito ausente'},
      {'ate_dias': 9999, 'cor': '#F44336', 'label': 'Risco de inatividade'},
    ];
  }

  Color _colorFromHexIndicador(String value, {Color? fallback}) {
    try {
      var cleaned = value.trim().replaceAll('#', '').toUpperCase();
      if (cleaned.length == 6) cleaned = 'FF$cleaned';
      if (cleaned.length != 8) return fallback ?? context.uai.textMuted;
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return fallback ?? context.uai.textMuted;
    }
  }

  Future<void> _carregarConfiguracaoIndicadoresAusencia() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('indicadores_ausencia')
          .get();

      final data = doc.data();
      final faixasRaw = data?['faixas'];
      final faixas = faixasRaw is List
          ? faixasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : _faixasIndicadoresPadrao();

      faixas.sort((a, b) {
        final aDias = _parseIntIndicador(a['ate_dias'], fallback: 9999);
        final bDias = _parseIntIndicador(b['ate_dias'], fallback: 9999);
        return aDias.compareTo(bDias);
      });

      _indicadoresAusenciaAtivo = data?['ativo'] != false;
      _mostrarTextoUltimaPresencaIndicador =
          data?['mostrar_texto_ultima_presenca'] != false;
      _faixasIndicadoresAusencia = faixas;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar configuração dos indicadores: $e');
      _indicadoresAusenciaAtivo = true;
      _mostrarTextoUltimaPresencaIndicador = true;
      _faixasIndicadoresAusencia = _faixasIndicadoresPadrao();
    }
  }

  DateTime? _dateTimeSeguro(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    if (value is String) {
      final texto = value.trim();
      if (texto.isEmpty) return null;
      final parsedIso = DateTime.tryParse(texto);
      if (parsedIso != null) return parsedIso;
      try {
        return DateFormat('dd/MM/yyyy').parseStrict(texto);
      } catch (_) {
        return null;
      }
    }

    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
      }
    }

    return null;
  }

  DateTime? _ultimaPresencaDoAluno(Map<String, dynamic> aluno) {
    final campos = [
      aluno['ultimo_dia_presente'],
      aluno['ultimoDiaPresente'],
      aluno['ultima_presenca'],
      aluno['ultimaPresenca'],
      aluno['data_ultima_presenca'],
      aluno['dataUltimaPresenca'],
      aluno['ultimo_presente_em'],
      aluno['ultimoPresenteEm'],
      aluno['last_presence'],
      aluno['lastPresence'],
    ];

    for (final campo in campos) {
      final data = _dateTimeSeguro(campo);
      if (data != null) return data;
    }

    return null;
  }

  int? _diasDesdeUltimaPresenca(Map<String, dynamic> aluno) {
    final ultima = _ultimaPresencaDoAluno(aluno);
    if (ultima == null) return null;

    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final ultimaLimpa = DateTime(ultima.year, ultima.month, ultima.day);
    final dias = hojeLimpo.difference(ultimaLimpa).inDays;

    return dias < 0 ? 0 : dias;
  }

  Color _corIndicadorAusencia(Map<String, dynamic> aluno) {
    if (!_indicadoresAusenciaAtivo) return context.uai.textMuted;

    final dias = _diasDesdeUltimaPresenca(aluno);
    if (dias == null) return context.uai.textMuted;

    final faixas = _faixasIndicadoresAusencia.isEmpty
        ? _faixasIndicadoresPadrao()
        : _faixasIndicadoresAusencia;

    for (final faixa in faixas) {
      final ateDias = _parseIntIndicador(faixa['ate_dias'], fallback: 9999);
      if (dias <= ateDias) {
        return _colorFromHexIndicador(
          faixa['cor']?.toString() ?? '#9E9E9E',
          fallback: context.uai.textMuted,
        );
      }
    }

    final ultimaFaixa = faixas.isNotEmpty ? faixas.last : null;
    return _colorFromHexIndicador(
      ultimaFaixa?['cor']?.toString() ?? '#F44336',
      fallback: context.uai.error,
    );
  }

  String _textoUltimaPresenca(Map<String, dynamic> aluno) {
    final dias = _diasDesdeUltimaPresenca(aluno);

    if (dias == null) return 'Sem presença registrada';
    if (dias == 0) return 'Última presença hoje';
    if (dias == 1) return 'Última presença ontem';
    return 'Última presença há $dias dias';
  }

  String _getDiaAbreviado(String diaCompleto) {
    final diaUpper = diaCompleto.toUpperCase().trim();
    if (_diasAbreviados.containsKey(diaUpper)) {
      return _diasAbreviados[diaUpper]!;
    }
    for (final entry in _diasAbreviados.entries) {
      if (diaUpper.contains(entry.key) || entry.key.contains(diaUpper)) {
        return entry.value;
      }
    }
    return diaUpper.length >= 3
        ? diaUpper.substring(0, 3).toLowerCase()
        : diaUpper.toLowerCase();
  }

  String _formatarDiaSemana(DateTime data) {
    final diaSemanaOriginal = DateFormat(
      'EEEE',
      'pt_BR',
    ).format(data).toLowerCase();

    if (diaSemanaOriginal.contains('segunda')) return 'SEGUNDA';
    if (diaSemanaOriginal.contains('terça') ||
        diaSemanaOriginal.contains('terca')) {
      return 'TERCA';
    }
    if (diaSemanaOriginal.contains('quarta')) return 'QUARTA';
    if (diaSemanaOriginal.contains('quinta')) return 'QUINTA';
    if (diaSemanaOriginal.contains('sexta')) return 'SEXTA';
    if (diaSemanaOriginal.contains('sábado') ||
        diaSemanaOriginal.contains('sabado')) {
      return 'SABADO';
    }
    if (diaSemanaOriginal.contains('domingo')) return 'DOMINGO';

    return diaSemanaOriginal.toUpperCase();
  }

  Future<void> _carregarDados() async {
    try {
      await _carregarConfiguracaoIndicadoresAusencia();

      final diaSemanaFormatado = _formatarDiaSemana(widget.dataSelecionada);
      final diaSemanaAbrev = _getDiaAbreviado(diaSemanaFormatado);

      final turmaDoc = await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .get();
      String tipoAula = 'OBJETIVA';

      if (turmaDoc.exists) {
        final turmaData = turmaDoc.data() ?? {};
        final diasConfiguracao =
            turmaData['dias_configuracao'] as Map<String, dynamic>?;
        final configuracaoDia = diasConfiguracao?[diaSemanaFormatado];
        if (configuracaoDia is Map<String, dynamic>) {
          tipoAula = configuracaoDia['tipoAula']?.toString() ?? 'OBJETIVA';
        }
      }

      final userDoc = await _firestore
          .collection('usuarios')
          .doc(widget.usuarioId)
          .get();
      String professorNome = 'Professor';
      if (userDoc.exists) {
        final userData = userDoc.data() ?? {};
        professorNome =
            userData['nome_completo']?.toString() ??
            userData['nome']?.toString() ??
            'Professor';
      }

      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where(
            'status_atividade',
            whereIn: ['ATIVO(A)', 'ATIVO(A) ', 'ATIVO'],
          )
          .get();

      final alunosList = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'foto': AlunoFotoResolver.fotoDoMapa(data),
          'ultimo_dia_presente':
              data['ultimo_dia_presente'] ??
              data['ultimoDiaPresente'] ??
              data['ultima_presenca'] ??
              data['ultimaPresenca'] ??
              data['data_ultima_presenca'] ??
              data['dataUltimaPresenca'] ??
              data['ultimo_presente_em'] ??
              data['ultimoPresenteEm'] ??
              data['last_presence'] ??
              data['lastPresence'],
        };
      }).toList();

      alunosList.sort(
        (a, b) => (a['nome'] as String).compareTo(b['nome'] as String),
      );

      final presencasIniciais = <String, bool>{};
      for (final aluno in alunosList) {
        presencasIniciais[aluno['id'] as String] = false;
      }

      if (!mounted) return;
      setState(() {
        _diaSemana = diaSemanaFormatado;
        _tipoAula = tipoAula;
        _professorId = widget.usuarioId;
        _professorNome = professorNome;
        _alunos = alunosList;
        _presencas = presencasIniciais;
        _isLoading = false;
      });

      debugPrint('📅 Chamada especial: $diaSemanaFormatado / $diaSemanaAbrev');
      debugPrint(
        '✅ ${alunosList.length} alunos carregados para chamada especial',
      );
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados da chamada especial: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _tipoAula = 'OBJETIVA';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  void _togglePresenca(String alunoId) {
    setState(() {
      _presencas[alunoId] = !(_presencas[alunoId] ?? false);
    });
  }

  void _adicionarObservacao(String alunoId, String nomeAluno) {
    _observacaoController.text = _observacoes[alunoId] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        final t = context.uai;
        final primary = _ensureVisible(t.primary, t.surface);

        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Text(
            'Observação para $nomeAluno',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: _observacaoController,
            maxLines: 3,
            style: TextStyle(color: t.textPrimary),
            cursorColor: primary,
            decoration: InputDecoration(
              hintText: 'Digite uma observação...',
              hintStyle: TextStyle(color: t.textMuted),
              filled: true,
              fillColor: t.cardAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.inputRadius),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.inputRadius),
                borderSide: BorderSide(color: t.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.inputRadius),
                borderSide: BorderSide(color: primary, width: 1.4),
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
                  final texto = _observacaoController.text.trim();
                  if (texto.isEmpty) {
                    _observacoes.remove(alunoId);
                  } else {
                    _observacoes[alunoId] = texto;
                  }
                });
                _observacaoController.clear();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: _readableOn(primary),
              ),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _salvarChamada() async {
    if (_isSaving) return;

    if (_alunos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ Não há alunos para salvar chamada'),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    final presentes = _presencas.values.where((v) => v).length;

    if (presentes == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          final t = context.uai;
          final warning = _ensureVisible(t.warning, t.surface);

          return AlertDialog(
            backgroundColor: t.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.cardRadius),
            ),
            title: Text(
              '❌ Nenhum aluno presente',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              'Deseja salvar a chamada especial mesmo sem nenhum aluno presente?',
              style: TextStyle(color: t.textSecondary, height: 1.3),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: warning,
                  foregroundColor: _readableOn(warning),
                ),
                child: const Text('Salvar mesmo assim'),
              ),
            ],
          );
        },
      );

      if (confirm != true) return;
    }

    final alunosPayload = _alunos.map((aluno) {
      final alunoId = aluno['id']?.toString() ?? '';
      final fotoPerfilAluno = (aluno['foto']?.toString() ?? '').trim();

      return {
        'id': alunoId,
        'nome': aluno['nome']?.toString() ?? 'Sem nome',
        'presente': _presencas[alunoId] ?? false,
        'observacao': _observacoes[alunoId] ?? '',

        // Snapshot econômico para a lista/histórico de chamada.
        // Assim a tela não precisa consultar alunos/{id} só para exibir foto.
        'foto_perfil_aluno': fotoPerfilAluno,
        'foto': fotoPerfilAluno,
        'ultimo_dia_presente': aluno['ultimo_dia_presente'],
      };
    }).toList();

    final dadosChamada = {
      'turmaId': widget.turmaId,
      'turmaNome': widget.turmaNome,
      'academiaId': widget.academiaId,
      'academiaNome': widget.academiaNome,
      'dataChamada': widget.dataSelecionada.toIso8601String(),
      'tipoAula': _tipoAula,
      'professorId': _professorId,
      'professorNome': _professorNome,
      'alunos': alunosPayload,
    };

    setState(() {
      _isSaving = true;
      _mostrarProgresso = true;
      _statusMensagem = 'Enviando chamada especial para a nuvem...';
    });

    try {
      setState(() {
        _statusMensagem = 'Criando chamada, logs e contadores...';
      });

      final callable = _functions.httpsCallable('processarChamada');
      final result = await callable.call(dadosChamada);
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        throw Exception('A Cloud Function não confirmou o salvamento.');
      }

      unawaited(SessionLogService.instance.recordEntityOperation(
        module: 'chamadas', entityType: 'turma',
        entityId: widget.turmaId, operation: 'criou', result: 'sucesso',
      ));
      final processados = _toInt(data['processados']);
      final presentesCloud = _toInt(data['presentes']);
      final ausentesCloud = _toInt(data['ausentes']);
      final porcentagemCloud = data.containsKey('porcentagem_frequencia')
          ? _toInt(data['porcentagem_frequencia'])
          : processados > 0
          ? ((presentesCloud / processados) * 100).round()
          : 0;
      final duplicate = data['duplicate'] == true;

      if (!mounted) return;
      setState(() {
        _statusMensagem = duplicate
            ? '⚠️ Esta chamada já existia. Dados carregados sem duplicar.'
            : '✅ Chamada especial salva e contadores atualizados!';
      });

      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        _mostrarTelaConclusao({
          'presentes': presentesCloud,
          'ausentes': ausentesCloud,
          'total_alunos': processados,
          'porcentagem_frequencia': porcentagemCloud,
          'duplicate': duplicate,
        });
      }
    } catch (e) {
      unawaited(SessionLogService.instance.recordEntityOperation(
        module: 'chamadas', entityType: 'turma',
        entityId: widget.turmaId, operation: 'criou', result: 'falha',
      ));
      debugPrint('❌ Erro ao processar chamada especial: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _mostrarProgresso = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar chamada especial: ${e.toString()}'),
            backgroundColor: context.uai.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _mostrarTelaConclusao(Map<String, dynamic> dados) {
    final success = _ensureVisible(context.uai.success, context.uai.background);
    final onSuccess = _readableOn(success);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: success,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration, size: 76, color: onSuccess),
              const SizedBox(height: 18),
              Text(
                dados['duplicate'] == true
                    ? '⚠️ CHAMADA ESPECIAL JÁ EXISTIA!'
                    : '🎉 CHAMADA ESPECIAL CONCLUÍDA!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: onSuccess,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                DateFormat(
                  'dd/MM/yyyy',
                  'pt_BR',
                ).format(widget.dataSelecionada),
                style: TextStyle(
                  fontSize: 16,
                  color: onSuccess.withAlpha(199),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: onSuccess.withAlpha(46),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem(
                      '${dados['presentes']}',
                      'Presentes',
                      Icons.check_circle,
                    ),
                    _buildResumoItem(
                      '${dados['ausentes']}',
                      'Ausentes',
                      Icons.cancel,
                    ),
                    _buildResumoItem(
                      '${dados['porcentagem_frequencia']}%',
                      'Frequência',
                      Icons.trending_up,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Professor: $_professorNome',
                style: TextStyle(fontSize: 14, color: onSuccess),
              ),
              const SizedBox(height: 8),
              Text(
                'Tipo de aula: $_tipoAula',
                style: TextStyle(
                  fontSize: 12,
                  color: onSuccess.withAlpha(199),
                ),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                child: Text(
                  'FECHAR',
                  style: TextStyle(
                    color: onSuccess,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoItem(String value, String label, IconData icon) {
    final success = _ensureVisible(context.uai.success, context.uai.background);
    final onSuccess = _readableOn(success);

    return Column(
      children: [
        Icon(icon, color: onSuccess, size: 24),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: onSuccess,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: onSuccess.withAlpha(189)),
        ),
      ],
    );
  }

  Widget _buildTelaProgresso() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: context.uai.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: context.uai.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload, size: 60, color: _onPrimary()),
            const SizedBox(height: 20),
            Text(
              'PROCESSANDO CHAMADA ESPECIAL',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _onPrimary(),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _statusMensagem,
              style: TextStyle(
                fontSize: 14,
                color: _onPrimary().withAlpha(230),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            CircularProgressIndicator(color: _onPrimary()),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicadorBolinha(
    Map<String, dynamic> aluno, {
    double size = 13,
  }) {
    if (!_indicadoresAusenciaAtivo) return const SizedBox.shrink();

    final color = _corIndicadorAusencia(aluno);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.uai.card, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(46),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
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

  Widget _buildAlunoListTile(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final nomeExibicao = _nomeAlunoCurto(nomeAluno);
    final estaPresente = _presencas[alunoId] ?? false;
    final observacao = (_observacoes[alunoId] ?? '').trim();
    final fotoUrl = aluno['foto'] as String?;
    final indicadorColor = _corIndicadorAusencia(aluno);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: estaPresente
              ? context.uai.success.withAlpha(140)
              : context.uai.border,
          width: estaPresente ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(11),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _togglePresenca(alunoId),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: estaPresente ? context.uai.success : context.uai.border,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: fotoUrl != null && fotoUrl.trim().isNotEmpty
                    ? UaiStudentPhoto(
                        studentId: alunoId,
                        imageUrl: fotoUrl,
                        profile: UaiStudentPhotoProfile.compact,
                        fit: BoxFit.cover,
                        fallback: _placeholderIcon(size: 24),
                      )
                    : _placeholderIcon(size: 24),
              ),
            ),
            if (_indicadoresAusenciaAtivo)
              Positioned(
                right: -1,
                bottom: -1,
                child: _buildIndicadorBolinha(aluno, size: 12),
              ),
          ],
        ),
        title: Text(
          nomeExibicao,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: estaPresente ? context.uai.success : context.uai.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          observacao.isNotEmpty
              ? observacao
              : (_mostrarTextoUltimaPresencaIndicador
                  ? _textoUltimaPresenca(aluno)
                  : (estaPresente
                      ? 'Presente na chamada'
                      : 'Ausente na chamada')),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: observacao.isNotEmpty
                ? context.uai.warning
                : indicadorColor,
            fontWeight: observacao.isNotEmpty
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (observacao.isNotEmpty)
              Icon(
                Icons.sticky_note_2_rounded,
                color: context.uai.warning,
                size: 20,
              ),
            IconButton(
              tooltip: 'Observação',
              onPressed: () => _adicionarObservacao(alunoId, nomeAluno),
              icon: Icon(Icons.note_add_outlined, color: context.uai.info),
            ),
            Switch(
              value: estaPresente,
              activeThumbColor: context.uai.success,
              onChanged: (_) => _togglePresenca(alunoId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final nomeAlunoExibicao = _nomeAlunoCurto(nomeAluno);
    final estaPresente = _presencas[alunoId] ?? false;
    final temObservacao = (_observacoes[alunoId] ?? '').trim().isNotEmpty;
    final fotoUrl = aluno['foto'] as String?;
    final indicadorColor = _corIndicadorAusencia(aluno);

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: estaPresente
                  ? context.uai.success.withAlpha(46)
                  : context.uai.error.withAlpha(36),
              blurRadius: estaPresente ? 13 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _togglePresenca(alunoId),
            onLongPress: () => _adicionarObservacao(alunoId, nomeAluno),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: estaPresente
                      ? context.uai.success
                      : context.uai.error.withAlpha(179),
                  width: estaPresente ? 2.2 : 1.8,
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
                                fotoUrl != null && fotoUrl.trim().isNotEmpty
                                    ? UaiStudentPhoto(
                                        studentId: alunoId,
                                        imageUrl: fotoUrl,
                                        profile: UaiStudentPhotoProfile.grid,
                                        fit: BoxFit.cover,
                                        placeholder: Container(
                                          color: context.uai.cardAlt,
                                          child: Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: context.uai.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        fallback: Container(
                                          color: context.uai.cardAlt,
                                          child: _placeholderIcon(size: 68),
                                        ),
                                      )
                                    : Container(
                                        color: context.uai.cardAlt,
                                        child: _placeholderIcon(size: 68),
                                      ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.center,
                                        colors: [
                                          Colors.black.withAlpha(148),
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
                                      constraints:
                                          const BoxConstraints(maxWidth: 132),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(87),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: Colors.white.withAlpha(26),
                                        ),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          nomeAlunoExibicao,
                                          textAlign: TextAlign.center,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            height: 1.08,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withAlpha((255.0 * (
                                                  0.55)).round()),
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
                              color: estaPresente
                                  ? context.uai.success.withAlpha(26)
                                  : context.uai.error.withAlpha(26),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_indicadoresAusenciaAtivo &&
                                    _mostrarTextoUltimaPresencaIndicador)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      _textoUltimaPresenca(aluno),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: indicadorColor,
                                        fontSize: 9.8,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                Center(
                                  child: SizedBox(
                                    width: 108,
                                    height: 31,
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _togglePresenca(alunoId),
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        backgroundColor: estaPresente
                                            ? context.uai.success
                                            : context.uai.primary,
                                        foregroundColor: _readableOn(
                                          estaPresente
                                              ? context.uai.success
                                              : context.uai.primary,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(17),
                                        ),
                                      ),
                                      icon: Icon(
                                        estaPresente
                                            ? Icons.check_circle_rounded
                                            : Icons
                                                .radio_button_unchecked_rounded,
                                        size: 15,
                                      ),
                                      label: Text(
                                        estaPresente ? 'Presente' : 'Marcar',
                                        style: const TextStyle(
                                          fontSize: 10.8,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                        onTap: () => _adicionarObservacao(alunoId, nomeAluno),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: temObservacao
                                ? context.uai.warning
                                : Colors.white.withAlpha(240),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(41),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                          child: Icon(
                            temObservacao
                                ? Icons.sticky_note_2_rounded
                                : Icons.note_add_outlined,
                            size: 17,
                            color: temObservacao
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
                          color: estaPresente
                              ? context.uai.success
                              : context.uai.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.uai.card, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(46),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_indicadoresAusenciaAtivo)
                      Positioned(
                        top: 8,
                        left: 27,
                        child: _buildIndicadorBolinha(aluno, size: 12),
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

  Widget _placeholderIcon({double size = 50}) {
    return Center(
      child: Icon(
        Icons.person_rounded,
        size: size,
        color: context.uai.textMuted,
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: context.uai.textSecondary),
        ),
      ],
    );
  }

  bool _isChamadaDesktop(double width) => width >= 700;

  double _maxChamadaContentWidth(double width) {
    if (width >= 1600) return 1640;
    if (width >= 1200) return 1480;
    if (width >= 900) return 1180;
    return width;
  }

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

  Widget _buildHeaderTinyStat(String label, int value, Color color) {
    final onPrimary = _onPrimary();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(33),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onPrimary.withAlpha(41)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: onPrimary.withAlpha(179),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '$value',
              style: TextStyle(
                color: _ensureVisible(color, context.uai.primary),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderResumo() {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final ausentes = total - presentes;
    final porcentagem = total > 0 ? (presentes / total * 100).round() : 0;
    final onPrimary = _onPrimary();
    final progressColor = presentes == 0
        ? context.uai.error
        : presentes == total
        ? context.uai.success
        : context.uai.warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withAlpha(31),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: onPrimary, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.turmaNome,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${DateFormat('dd/MM').format(widget.dataSelecionada)} • $_tipoAula',
                style: TextStyle(
                  color: onPrimary.withAlpha(199),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildHeaderTinyStat('P', presentes, context.uai.success),
              const SizedBox(width: 6),
              _buildHeaderTinyStat('A', ausentes, context.uai.error),
              const SizedBox(width: 6),
              _buildHeaderTinyStat('T', total, onPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: total > 0 ? presentes / total : 0,
                    minHeight: 6,
                    backgroundColor: onPrimary.withAlpha(51),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _ensureVisible(progressColor, context.uai.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$porcentagem%',
                style: TextStyle(
                  color: onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: onPrimary.withAlpha(26),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: onPrimary.withAlpha(36)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: onPrimary),
                const SizedBox(width: 6),
                Text(
                  'CHAMADA ESPECIAL',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: onPrimary.withAlpha(153),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prof. ${_professorNome.split(' ').first} • $_diaSemana',
                    style: TextStyle(
                      color: onPrimary.withAlpha(199),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final ausentes = total - presentes;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CHAMADA', style: TextStyle(fontSize: 16)),
            Text(
              widget.turmaNome,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _appBarFg().withAlpha(41),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _appBarFg().withAlpha(41)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 15, color: _appBarFg()),
                const SizedBox(width: 5),
                Text(
                  'ESPECIAL',
                  style: TextStyle(
                    color: _appBarFg(),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: context.uai.primary))
          : _isSaving && _mostrarProgresso
          ? _buildTelaProgresso()
          : LayoutBuilder(
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
                        child: _buildHeaderResumo(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Container(
                          color: context.uai.surface,
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$presentes presentes • $ausentes ausentes • $total alunos',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.uai.textSecondary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ViewModeSelector(
                                currentMode: _viewMode,
                                onChanged: (mode) =>
                                    setState(() => _viewMode = mode),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: _viewMode == ViewMode.list
                              ? isDesktop
                                  ? GridView.builder(
                                      scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                                      padding: _gridPaddingForWidth(larguraTela),
                                      gridDelegate:
                                          const SliverGridDelegateWithMaxCrossAxisExtent(
                                            maxCrossAxisExtent: 560,
                                            mainAxisExtent: 82,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                          ),
                                      itemCount: _alunos.length,
                                      itemBuilder: (context, index) =>
                                          _buildAlunoListTile(_alunos[index]),
                                    )
                                  : ListView.builder(
                                      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        6,
                                        14,
                                        14,
                                      ),
                                      itemCount: _alunos.length,
                                      itemBuilder: (context, index) =>
                                          _buildAlunoListTile(_alunos[index]),
                                    )
                              : GridView.builder(
                                  scrollCacheExtent: const ScrollCacheExtent.pixels(800),
                                  padding: _gridPaddingForWidth(larguraTela),
                                  gridDelegate:
                                      _gridDelegateForChamada(larguraTela),
                                  itemCount: _alunos.length,
                                  itemBuilder: (context, index) =>
                                      _buildAlunoGridItem(_alunos[index]),
                                ),
                        ),
                      ),
                    ),
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
                          border: Border(
                            top: BorderSide(color: context.uai.border),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              blurRadius: 14,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _salvarChamada,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _appBarBg(),
                                foregroundColor: _appBarFg(),
                                disabledBackgroundColor: context.uai.border,
                                disabledForegroundColor:
                                    context.uai.textSecondary,
                                minimumSize: const Size(double.infinity, 50),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _isSaving
                                  ? SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _appBarFg(),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.save_rounded,
                                      size: 21,
                                    ),
                              label: Text(
                                _isSaving
                                    ? 'SALVANDO...'
                                    : 'SALVAR CHAMADA • $presentes P / $ausentes A',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
