// lib/modules/chamadas/screens/chamada_especial_screen.dart
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  Map<String, String> _observacoes = {};

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
          'foto': data['foto_perfil_aluno'] as String?,
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
                  color: onSuccess.withOpacity(0.78),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: onSuccess.withOpacity(0.18),
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
                  color: onSuccess.withOpacity(0.78),
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
          style: TextStyle(fontSize: 11, color: onSuccess.withOpacity(0.74)),
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
                color: _onPrimary().withOpacity(0.90),
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
            color: Colors.black.withOpacity(0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildAlunoListTile(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final observacao = _observacoes[alunoId];
    final fotoUrl = aluno['foto'] as String?;
    final indicadorColor = _corIndicadorAusencia(aluno);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: estaPresente
          ? Color.alphaBlend(
              context.uai.success.withOpacity(0.08),
              context.uai.card,
            )
          : context.uai.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: estaPresente
              ? context.uai.success.withOpacity(0.45)
              : context.uai.border,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: estaPresente
                  ? context.uai.success.withOpacity(0.10)
                  : context.uai.border,
              backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
                  ? NetworkImage(fotoUrl)
                  : null,
              child: fotoUrl == null || fotoUrl.isEmpty
                  ? Icon(Icons.person, size: 18, color: context.uai.textMuted)
                  : null,
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: _buildIndicadorBolinha(aluno, size: 12),
            ),
          ],
        ),
        title: Text(
          nomeAluno,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: estaPresente
                ? context.uai.textPrimary
                : context.uai.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_indicadoresAusenciaAtivo &&
                _mostrarTextoUltimaPresencaIndicador)
              Text(
                _textoUltimaPresenca(aluno),
                style: TextStyle(
                  fontSize: 10.5,
                  color: indicadorColor,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (observacao != null && observacao.trim().isNotEmpty)
              Text(
                observacao,
                style: TextStyle(
                  fontSize: 10,
                  color: context.uai.warning,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: SizedBox(
          width: 72,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  icon: Icon(
                    Icons.note_add,
                    size: 14,
                    color: observacao != null
                        ? context.uai.warning
                        : context.uai.info,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _adicionarObservacao(alunoId, nomeAluno),
                  splashRadius: 14,
                ),
              ),
              const SizedBox(width: 2),
              Transform.scale(
                scale: 0.55,
                child: Switch(
                  value: estaPresente,
                  activeColor: context.uai.success,
                  inactiveTrackColor: context.uai.textMuted,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) => _togglePresenca(alunoId),
                ),
              ),
            ],
          ),
        ),
        onTap: () => _togglePresenca(alunoId),
      ),
    );
  }

  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final fotoUrl = aluno['foto'] as String?;
    final indicadorColor = _corIndicadorAusencia(aluno);

    return Card(
      elevation: 0,
      color: context.uai.card,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: estaPresente ? context.uai.success : context.uai.border,
          width: estaPresente ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _togglePresenca(alunoId),
        child: Container(
          decoration: BoxDecoration(
            color: estaPresente
                ? context.uai.success.withOpacity(0.18)
                : context.uai.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: context.uai.cardAlt,
                        child: fotoUrl != null && fotoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: fotoUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                memCacheWidth: 600,
                                fadeInDuration: const Duration(
                                  milliseconds: 120,
                                ),
                                errorWidget: (c, u, e) =>
                                    _placeholderIcon(size: 80),
                              )
                            : _placeholderIcon(size: 80),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _buildIndicadorBolinha(aluno, size: 14),
                    ),
                    if (estaPresente)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.uai.success,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: _readableOn(context.uai.success),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _adicionarObservacao(alunoId, nomeAluno),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: context.uai.surface.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.16),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.note_add,
                            size: 16,
                            color: context.uai.info,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeAluno.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        height: 1.2,
                        color: estaPresente
                            ? context.uai.success
                            : context.uai.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    if (_indicadoresAusenciaAtivo &&
                        _mostrarTextoUltimaPresencaIndicador) ...[
                      Text(
                        _textoUltimaPresenca(aluno),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: indicadorColor,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Align(
                      alignment: Alignment.center,
                      child: Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: estaPresente,
                          activeColor: context.uai.success,
                          inactiveTrackColor: context.uai.textMuted,
                          onChanged: (_) => _togglePresenca(alunoId),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  Widget _buildHeaderResumo() {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final porcentagem = total > 0 ? (presentes / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.surface,
        border: Border(bottom: BorderSide(color: context.uai.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _diaSemana,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.uai.textPrimary,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.uai.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'TIPO: $_tipoAula',
                        style: TextStyle(
                          fontSize: 10,
                          color: _readableOn(context.uai.primary),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.uai.cardAlt,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person,
                      size: 12,
                      color: context.uai.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _professorNome.split(' ').first,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.uai.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                value: '$presentes',
                label: 'Presentes',
                color: context.uai.success,
                icon: Icons.check_circle,
              ),
              _buildStatItem(
                value: '${total - presentes}',
                label: 'Ausentes',
                color: context.uai.error,
                icon: Icons.cancel,
              ),
              _buildStatItem(
                value: '$porcentagem%',
                label: 'Frequência',
                color: context.uai.info,
                icon: Icons.trending_up,
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total > 0 ? presentes / total : 0,
            backgroundColor: context.uai.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              presentes == 0
                  ? context.uai.error
                  : presentes == total
                  ? context.uai.success
                  : context.uai.warning,
            ),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
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
            const Text('CHAMADA ESPECIAL', style: TextStyle(fontSize: 14)),
            Text(
              '${widget.turmaNome} - ${DateFormat('dd/MM/yyyy').format(widget.dataSelecionada)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (!_isSaving)
            ViewModeSelector(
              currentMode: _viewMode,
              onChanged: (mode) => setState(() => _viewMode = mode),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: context.uai.primary))
          : _isSaving && _mostrarProgresso
          ? _buildTelaProgresso()
          : Column(
              children: [
                _buildHeaderResumo(),
                Expanded(
                  child: _viewMode == ViewMode.list
                      ? ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _alunos.length,
                          itemBuilder: (context, index) =>
                              _buildAlunoListTile(_alunos[index]),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.75,
                              ),
                          itemCount: _alunos.length,
                          itemBuilder: (context, index) =>
                              _buildAlunoGridItem(_alunos[index]),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.uai.surface,
                      border: Border(
                        top: BorderSide(color: context.uai.border),
                      ),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _salvarChamada,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _appBarBg(),
                        foregroundColor: _appBarFg(),
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isSaving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _appBarFg(),
                              ),
                            )
                          : const Icon(Icons.save, size: 24),
                      label: _isSaving
                          ? const Text('SALVANDO...')
                          : Text(
                              '✅ SALVAR • $presentes P / $ausentes A',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
