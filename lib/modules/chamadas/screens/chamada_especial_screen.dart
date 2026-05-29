// chamada_especial_screen.dart
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ============================================
// ENUM PARA MODO DE VISUALIZAÇÃO
// ============================================
enum ViewMode { list, grid }

// ============================================
// SELETOR DE VISUALIZAÇÃO
// ============================================
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
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.uai.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            context: context,
            icon: Icons.view_list,
            label: 'Lista',
            mode: ViewMode.list,
          ),
          const SizedBox(width: 8),
          _buildButton(
            context: context,
            icon: Icons.grid_view,
            label: 'Grade',
            mode: ViewMode.grid,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required ViewMode mode,
  }) {
    final isSelected = currentMode == mode;
    return GestureDetector(
      onTap: () => onChanged(mode),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? context.uai.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Theme.of(context).colorScheme.onPrimary : context.uai.textSecondary,
            ),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : context.uai.textSecondary,
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
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _alunos = [];
  Map<String, bool> _presencas = {};
  Map<String, String> _observacoes = {};
  final TextEditingController _observacaoController = TextEditingController();

  String _professorNome = 'Carregando...';
  String _professorId = '';
  String _tipoAula = 'CARREGANDO...';
  String _diaSemana = '';
  String _diaSemanaAbrev = '';

  // 🔥 CONTROLE DA ANIMAÇÃO DE SALVAMENTO
  bool _mostrarProgresso = false;
  String _statusMensagem = '';

  // Modo de visualização
  ViewMode _viewMode = ViewMode.grid;

  final Map<String, String> _diasAbreviados = {
    'SEGUNDA': 'seg', 'TERÇA': 'ter', 'TERCA': 'ter',
    'QUARTA': 'qua', 'QUINTA': 'qui', 'SEXTA': 'sex',
    'SÁBADO': 'sab', 'SABADO': 'sab', 'DOMINGO': 'dom',
  };

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      // Formatar o dia da semana
      final diaSemanaOriginal = DateFormat('EEEE', 'pt_BR')
          .format(widget.dataSelecionada).toLowerCase();

      String diaSemanaFormatado = diaSemanaOriginal;

      if (diaSemanaOriginal.contains('segunda')) {
        diaSemanaFormatado = 'SEGUNDA';
      } else if (diaSemanaOriginal.contains('terça') || diaSemanaOriginal.contains('terca')) {
        diaSemanaFormatado = 'TERCA';
      } else if (diaSemanaOriginal.contains('quarta')) {
        diaSemanaFormatado = 'QUARTA';
      } else if (diaSemanaOriginal.contains('quinta')) {
        diaSemanaFormatado = 'QUINTA';
      } else if (diaSemanaOriginal.contains('sexta')) {
        diaSemanaFormatado = 'SEXTA';
      } else if (diaSemanaOriginal.contains('sábado') || diaSemanaOriginal.contains('sabado')) {
        diaSemanaFormatado = 'SABADO';
      } else if (diaSemanaOriginal.contains('domingo')) {
        diaSemanaFormatado = 'DOMINGO';
      }

      _diaSemana = diaSemanaFormatado;
      _diaSemanaAbrev = _getDiaAbreviado(diaSemanaFormatado);

      debugPrint('📅 Data selecionada: ${widget.dataSelecionada}');
      debugPrint('📅 Dia formatado: $_diaSemana');

      // Carregar tipo de aula da configuração da turma
      final turmaDoc = await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .get();

      if (turmaDoc.exists) {
        final turmaData = turmaDoc.data()!;
        final diasConfiguracao = turmaData['dias_configuracao'] as Map<String, dynamic>?;

        if (diasConfiguracao != null) {
          final configuracaoDia = diasConfiguracao[_diaSemana];
          if (configuracaoDia != null) {
            _tipoAula = configuracaoDia['tipoAula'] ?? 'OBJETIVA';
            debugPrint('✅ Tipo de aula: $_tipoAula para $_diaSemana');
          } else {
            _tipoAula = 'OBJETIVA';
          }
        } else {
          _tipoAula = 'OBJETIVA';
        }
      }

      // Carregar dados do professor
      final userDoc = await _firestore
          .collection('usuarios')
          .doc(widget.usuarioId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _professorId = widget.usuarioId;
        _professorNome = userData['nome_completo']?.toString() ??
            userData['nome']?.toString() ?? 'Professor';
      }

      // Carregar alunos da turma
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', whereIn: ['ATIVO(A)', 'ATIVO(A) '])
          .get();

      final alunosList = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'foto': data['foto_perfil_aluno'] as String?,
        };
      }).toList();

      alunosList.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

      final presencasIniciais = <String, bool>{};
      for (var aluno in alunosList) {
        presencasIniciais[aluno['id'] as String] = false;
      }

      setState(() {
        _alunos = alunosList;
        _presencas = presencasIniciais;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
      setState(() {
        _isLoading = false;
        _tipoAula = 'OBJETIVA';
      });
    }
  }

  String _getDiaAbreviado(String diaCompleto) {
    final diaUpper = diaCompleto.toUpperCase().trim();
    if (_diasAbreviados.containsKey(diaUpper)) {
      return _diasAbreviados[diaUpper]!;
    }
    for (var entry in _diasAbreviados.entries) {
      if (diaUpper.contains(entry.key) || entry.key.contains(diaUpper)) {
        return entry.value;
      }
    }
    return diaUpper.length >= 3 ? diaUpper.substring(0, 3).toLowerCase() : diaUpper.toLowerCase();
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
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
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
                if (_observacaoController.text.isNotEmpty) {
                  setState(() {
                    _observacoes[alunoId] = _observacaoController.text;
                  });
                  _observacaoController.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('✅ Observação salva!'),
                        backgroundColor: context.uai.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  Navigator.pop(context);
                }
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
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // ============================================
  // FUNÇÃO PRINCIPAL DE SALVAR CHAMADA ESPECIAL
  // Usa a mesma Cloud Function processarChamada.
  // A Cloud Function agora cria os logs e atualiza os contadores:
  // alunos/{alunoId}/contadores/frequencia_dashboard
  // ============================================
  Future<void> _salvarChamada() async {
    if (_isSaving) return;

    if (_alunos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Não há alunos para salvar chamada'),
            backgroundColor: context.uai.warning,
          ),
        );
      }
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

      return {
        'id': alunoId,
        'nome': aluno['nome']?.toString() ?? 'Sem nome',
        'presente': _presencas[alunoId] ?? false,
        'observacao': _observacoes[alunoId] ?? '',
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

      final HttpsCallable callable = _functions.httpsCallable('processarChamada');
      final result = await callable.call(dadosChamada);

      final data = Map<String, dynamic>.from(result.data as Map);

      final success = data['success'] == true;
      if (!success) {
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

      final bool duplicate = data['duplicate'] == true;

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

  // ============================================
  // TELA DE CONCLUSÃO DA CHAMADA
  // ============================================
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
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [success, success],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 1),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Icon(Icons.celebration, size: 80, color: onSuccess),
                  );
                },
              ),
              SizedBox(height: 20),
              Text(
                dados['duplicate'] == true
                    ? '⚠️ CHAMADA ESPECIAL JÁ EXISTIA!'
                    : '🎉 CHAMADA ESPECIAL CONCLUÍDA!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSuccess),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                DateFormat("dd/MM/yyyy", 'pt_BR').format(widget.dataSelecionada),
                style: TextStyle(fontSize: 16, color: onSuccess.withOpacity(0.72)),
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: onSuccess.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem('${dados['presentes']}', 'Presentes', Icons.check_circle),
                    _buildResumoItem('${dados['ausentes']}', 'Ausentes', Icons.cancel),
                    _buildResumoItem('${dados['porcentagem_frequencia']}%', 'Frequência', Icons.trending_up),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Professor: $_professorNome',
                style: TextStyle(fontSize: 14, color: _onPrimary()),
              ),
              SizedBox(height: 10),
              Text(
                'Tipo de aula: $_tipoAula',
                style: TextStyle(fontSize: 12, color: onSuccess.withOpacity(0.72)),
              ),
              const SizedBox(height: 25),
              TweenAnimationBuilder<Duration>(
                duration: const Duration(seconds: 5),
                tween: Tween(begin: const Duration(seconds: 5), end: Duration.zero),
                onEnd: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                builder: (context, value, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: value.inSeconds / 5,
                        backgroundColor: onSuccess.withOpacity(0.30),
                        valueColor: AlwaysStoppedAnimation<Color>(onSuccess),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fechando em ${value.inSeconds} segundos...',
                        style: TextStyle(color: onSuccess.withOpacity(0.72), fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                child: Text(
                  'FECHAR AGORA',
                  style: TextStyle(color: onSuccess, fontWeight: FontWeight.bold),
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
          style: TextStyle(
            fontSize: 11,
            color: onSuccess.withOpacity(0.72),
          ),
        ),
      ],
    );
  }

  // ============================================
  // TELA DE PROGRESSO
  // ============================================
  Widget _buildTelaProgresso() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: context.uai.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload, size: 60, color: _onPrimary()),
                SizedBox(height: 20),
                Text(
                  'PROCESSANDO CHAMADA ESPECIAL',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _onPrimary()),
                ),
                SizedBox(height: 16),
                Text(
                  _statusMensagem,
                  style: TextStyle(fontSize: 14, color: _onPrimary().withOpacity(0.90)),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 30),
                CircularProgressIndicator(color: _onPrimary()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // WIDGETS DE LISTA E GRADE
  // ============================================
  Widget _buildAlunoListTile(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final observacao = _observacoes[alunoId];
    final fotoUrl = aluno['foto'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: estaPresente
          ? Color.alphaBlend(context.uai.success.withOpacity(0.08), context.uai.card)
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
      child: Container(
        margin: EdgeInsets.all(0),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: estaPresente ? context.uai.success.withOpacity(0.10) : context.uai.border,
            backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
            child: fotoUrl == null || fotoUrl.isEmpty
                ? Icon(Icons.person, size: 18, color: context.uai.textMuted)
                : null,
          ),
          title: Text(
            nomeAluno,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: estaPresente ? context.uai.textPrimary : context.uai.textSecondary,
            ),
          ),
          subtitle: observacao != null
              ? Text(
            observacao,
            style: TextStyle(fontSize: 10, color: context.uai.warning, fontStyle: FontStyle.italic),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
              : null,
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
                      color: observacao != null ? context.uai.warning : context.uai.info,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _adicionarObservacao(alunoId, nomeAluno),
                    splashRadius: 14,
                  ),
                ),
                SizedBox(width: 2),
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
          tileColor: Colors.transparent,
          onTap: () => _togglePresenca(alunoId),
        ),
      ),
    );
  }

  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final fotoUrl = aluno['foto'] as String?;

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
            color: estaPresente ? context.uai.success.withOpacity(0.18) : context.uai.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      color: context.uai.cardAlt,
                      child: fotoUrl != null && fotoUrl.isNotEmpty
                          ? CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: 600,
                        fadeInDuration: const Duration(milliseconds: 120),
                        errorWidget: (c, u, e) => _placeholderIcon(size: 80),
                      )
                          : _placeholderIcon(size: 80),
                    ),
                    if (estaPresente)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(color: context.uai.success, shape: BoxShape.circle),
                          child: Icon(Icons.check, size: 14, color: _onPrimary()),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _adicionarObservacao(alunoId, nomeAluno),
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: context.uai.surface.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 4, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Icon(Icons.note_add, size: 16, color: context.uai.info),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeAluno.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        height: 1.2,
                        color: estaPresente ? context.uai.success : context.uai.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
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
            Flexible(
              child: Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: context.uai.textSecondary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final porcentagem = total > 0 ? (presentes / total * 100).round() : 0;

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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (!_isSaving)
            ViewModeSelector(
              currentMode: _viewMode,
              onChanged: (mode) {
                setState(() {
                  _viewMode = mode;
                });
              },
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
          // Header
          Container(
            padding: EdgeInsets.all(16),
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
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.uai.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'TIPO: $_tipoAula',
                              style: TextStyle(fontSize: 10, color: _readableOn(context.uai.primary), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.uai.cardAlt,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person, size: 12, color: context.uai.textSecondary),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _professorNome.split(' ').first,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.uai.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
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
                SizedBox(height: 8),
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
          ),
          // Lista de alunos
          Expanded(
            child: _viewMode == ViewMode.list
                ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _alunos.length,
              itemBuilder: (context, index) {
                return _buildAlunoListTile(_alunos[index]);
              },
            )
                : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: _alunos.length,
              itemBuilder: (context, index) {
                return _buildAlunoGridItem(_alunos[index]);
              },
            ),
          ),
          // Botão salvar
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.uai.surface,
              border: Border(top: BorderSide(color: context.uai.border)),
            ),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _salvarChamada,
              style: ElevatedButton.styleFrom(
                backgroundColor: _appBarBg(),
                foregroundColor: _appBarFg(),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSaving
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _appBarFg()),
              )
                  : const Icon(Icons.save, size: 24),
              label: _isSaving
                  ? const Text('SALVANDO...')
                  : const Text(
                '✅ SALVAR CHAMADA ESPECIAL',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _observacaoController.dispose();
    super.dispose();
  }
}