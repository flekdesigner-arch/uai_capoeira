// lib/modules/sistema/admin/indicadores_ausencia_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

import 'robo_inatividade_dialog.dart';

class IndicadoresAusenciaScreen extends StatefulWidget {
  const IndicadoresAusenciaScreen({super.key});

  @override
  State<IndicadoresAusenciaScreen> createState() =>
      _IndicadoresAusenciaScreenState();
}

class _IndicadoresAusenciaScreenState extends State<IndicadoresAusenciaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissionAccessGuard _accessGuard = PermissionAccessGuard();

  static const String _collection = 'configuracoes_sistema';
  static const String _document = 'indicadores_ausencia';

  bool _isLoading = true;
  bool _isSaving = false;
  bool _verificandoAcesso = true;
  bool _acessoNegado = false;
  bool _ativo = true;
  bool _mostrarTextoUltimaPresenca = true;

  final List<_FaixaAusenciaController> _faixas = [];
  int? _expandedFaixaIndex;

  @override
  void initState() {
    super.initState();
    _verificarAcesso();
  }

  @override
  void dispose() {
    for (final faixa in _faixas) {
      faixa.dispose();
    }
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

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

  String _mensagemPadraoAlerta() {
    return 'Olá! Tudo bem? Aqui é da UAI Capoeira. Sentimos falta de {nome_aluno} nos treinos da turma {turma}. '
        'A última presença registrada foi {ultima_presenca}. Podemos contar com a presença dele(a) nos próximos treinos?';
  }

  List<Map<String, dynamic>> _faixasPadrao() {
    return [
      {
        'ate_dias': 3,
        'cor': '#2196F3',
        'label': 'Frequente',
        'gera_alerta': false,
        'mensagem_alerta': '',
      },
      {
        'ate_dias': 6,
        'cor': '#4CAF50',
        'label': 'Regular',
        'gera_alerta': false,
        'mensagem_alerta': '',
      },
      {
        'ate_dias': 12,
        'cor': '#FFC107',
        'label': 'Atenção',
        'gera_alerta': true,
        'mensagem_alerta': _mensagemPadraoAlerta(),
      },
      {
        'ate_dias': 24,
        'cor': '#FF9800',
        'label': 'Ausente',
        'gera_alerta': true,
        'mensagem_alerta': _mensagemPadraoAlerta(),
      },
      {
        'ate_dias': 35,
        'cor': '#FF5722',
        'label': 'Muito ausente',
        'gera_alerta': true,
        'mensagem_alerta': _mensagemPadraoAlerta(),
      },
      {
        'ate_dias': 9999,
        'cor': '#F44336',
        'label': 'Risco de inatividade',
        'gera_alerta': true,
        'mensagem_alerta': _mensagemPadraoAlerta(),
      },
    ];
  }

  int _parseInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
  }

  Color _colorFromHex(String value, {Color? fallback}) {
    try {
      var cleaned = value.trim().replaceAll('#', '').toUpperCase();
      if (cleaned.length == 6) cleaned = 'FF$cleaned';
      if (cleaned.length != 8) return fallback ?? Colors.grey;
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return fallback ?? Colors.grey;
    }
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  String _normalizarHex(String value, String fallback) {
    var cleaned = value.trim().replaceAll('#', '').toUpperCase();

    if (cleaned.length == 8 && cleaned.startsWith('FF')) {
      cleaned = cleaned.substring(2);
    }

    final valid = RegExp(r'^[0-9A-F]{6}$').hasMatch(cleaned);
    if (!valid) return fallback;

    return '#$cleaned';
  }

  Future<void> _verificarAcesso() async {
    final permitido = await _accessGuard.canAccess(
      permission: 'pode_configurar_indicadores_ausencia',
    );
    if (!mounted) return;

    setState(() {
      _verificandoAcesso = false;
      _acessoNegado = !permitido;
    });

    if (permitido) {
      await _carregarConfiguracao();
    }
  }

  Future<bool> _revalidarAcesso() async {
    final permitido = await _accessGuard.canAccess(
      permission: 'pode_configurar_indicadores_ausencia',
    );
    if (!mounted) return false;

    if (!permitido) {
      setState(() => _acessoNegado = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Você não tem permissão para configurar indicadores de ausência.',
          ),
          backgroundColor: context.uai.error,
        ),
      );
    }

    return permitido;
  }

  Future<void> _carregarConfiguracao() async {
    if (!await _revalidarAcesso()) return;

    setState(() => _isLoading = true);

    try {
      final doc = await _firestore.collection(_collection).doc(_document).get();
      final data = doc.data();

      final faixasRaw = data?['faixas'];
      final List<Map<String, dynamic>> faixasData = faixasRaw is List
          ? faixasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : _faixasPadrao();

      faixasData.sort((a, b) {
        final aDias = _parseInt(a['ate_dias'], fallback: 9999);
        final bDias = _parseInt(b['ate_dias'], fallback: 9999);
        return aDias.compareTo(bDias);
      });

      for (final faixa in _faixas) {
        faixa.dispose();
      }

      _faixas
        ..clear()
        ..addAll(faixasData.map(_FaixaAusenciaController.fromMap));

      setState(() {
        _expandedFaixaIndex = null;
        _ativo = data?['ativo'] != false;
        _mostrarTextoUltimaPresenca =
            data?['mostrar_texto_ultima_presenca'] != false;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar indicadores de ausência: $e');

      for (final faixa in _faixas) {
        faixa.dispose();
      }

      _faixas
        ..clear()
        ..addAll(_faixasPadrao().map(_FaixaAusenciaController.fromMap));

      if (mounted) {
        setState(() {
          _expandedFaixaIndex = null;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Não foi possível carregar. Usando configuração padrão.',
            ),
            backgroundColor: context.uai.warning,
          ),
        );
      }
    }
  }

  void _sortFaixasInMemory({
    _FaixaAusenciaController? keepExpandedFaixa,
    bool expandAfterSort = true,
  }) {
    _faixas.sort((a, b) {
      final aDias = _parseInt(a.diasController.text, fallback: 9999);
      final bDias = _parseInt(b.diasController.text, fallback: 9999);
      return aDias.compareTo(bDias);
    });

    if (!expandAfterSort) {
      _expandedFaixaIndex = null;
      return;
    }

    if (keepExpandedFaixa != null) {
      _expandedFaixaIndex = _faixas.indexOf(keepExpandedFaixa);
    } else if (_expandedFaixaIndex != null &&
        _expandedFaixaIndex! >= 0 &&
        _expandedFaixaIndex! < _faixas.length) {
      final current = _faixas[_expandedFaixaIndex!];
      _expandedFaixaIndex = _faixas.indexOf(current);
    }
  }

  int _suggestedDaysForNewFaixa() {
    final sorted = _faixas
        .map((e) => _parseInt(e.diasController.text, fallback: 9999))
        .toList()
      ..sort();

    if (sorted.isEmpty) return 7;
    if (sorted.length == 1) return (sorted.first + 3).clamp(1, 9998);

    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];

      if (next >= 9999 && current < 9999) {
        return (current + 7).clamp(1, 9998);
      }

      final gap = next - current;
      if (gap > 1) {
        return current + (gap ~/ 2);
      }
    }

    final penultimate = sorted.length >= 2 ? sorted[sorted.length - 2] : 0;
    final last = sorted.last;
    if (last >= 9999) {
      return (penultimate + 7).clamp(1, 9998);
    }
    return (last + 7).clamp(1, 9998);
  }

  Future<void> _pickColor({
    required String titulo,
    required Color corAtual,
    required ValueChanged<Color> onColorChanged,
  }) async {
    Color pickedColor = corAtual;
    final hexController = TextEditingController(text: _colorToHex(corAtual));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        final accent = _ensureVisible(t.primary, t.surface);

        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                void aplicarCor(Color color) {
                  final hex = _colorToHex(color);
                  setDialogState(() {
                    pickedColor = color;
                    hexController.text = hex;
                  });
                  onColorChanged(color);
                }

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: accent.withAlpha(31),
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                            ),
                            child: Icon(Icons.palette_rounded, color: accent),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              titulo,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(
                              Icons.close_rounded,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: pickedColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.surface, width: 4),
                              boxShadow: [
                                BoxShadow(
                                  color: pickedColor.withAlpha(64),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: hexController,
                              textCapitalization:
                                  TextCapitalization.characters,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                              decoration: _inputDecoration(
                                context: dialogContext,
                                label: 'Código HEX',
                                hint: '#RRGGBB',
                                icon: Icons.tag_rounded,
                              ),
                              onChanged: (value) {
                                final normalized = _normalizarHex(value, '');
                                if (normalized.isEmpty) return;
                                final color = _colorFromHex(
                                  normalized,
                                  fallback: pickedColor,
                                );
                                setDialogState(() => pickedColor = color);
                                onColorChanged(color);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.cardAlt,
                          borderRadius: BorderRadius.circular(t.cardRadius),
                          border: Border.all(color: t.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paleta rápida',
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            BlockPicker(
                              pickerColor: pickedColor,
                              onColorChanged: aplicarCor,
                              availableColors: const [
                                Color(0xFF2196F3),
                                Color(0xFF4CAF50),
                                Color(0xFFFFC107),
                                Color(0xFFFF9800),
                                Color(0xFFFF5722),
                                Color(0xFFF44336),
                                Color(0xFF9C27B0),
                                Color(0xFF673AB7),
                                Color(0xFF009688),
                                Color(0xFF607D8B),
                                Color(0xFF795548),
                                Color(0xFFE91E63),
                              ],
                              layoutBuilder: (context, colors, child) {
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: colors.map(child).toList(),
                                );
                              },
                              itemBuilder: (color, isCurrentColor, changeColor) {
                                return GestureDetector(
                                  onTap: changeColor,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isCurrentColor
                                            ? _readableOn(color)
                                            : Colors.white,
                                        width: isCurrentColor ? 3 : 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withAlpha(61),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: isCurrentColor
                                        ? Icon(
                                            Icons.check_rounded,
                                            color: _readableOn(color),
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: t.textSecondary,
                                side: BorderSide(color: t.border),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                              ),
                              child: const Text('CANCELAR'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.primary,
                                foregroundColor: _readableOn(t.primary),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                onColorChanged(pickedColor);
                                Navigator.of(dialogContext).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    hexController.dispose();
  }

  void _adicionarFaixa() {
    final novaFaixa = _FaixaAusenciaController.fromMap({
      'ate_dias': _suggestedDaysForNewFaixa(),
      'cor': '#9C27B0',
      'label': 'Nova faixa',
      'gera_alerta': false,
      'mensagem_alerta': _mensagemPadraoAlerta(),
    });

    setState(() {
      _faixas.add(novaFaixa);
      _sortFaixasInMemory(keepExpandedFaixa: novaFaixa);
    });
  }

  void _removerFaixa(int index) {
    if (_faixas.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mantenha pelo menos 2 faixas de ausência.'),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    setState(() {
      final faixa = _faixas.removeAt(index);
      faixa.dispose();
      if (_expandedFaixaIndex == index) {
        _expandedFaixaIndex = null;
      } else if (_expandedFaixaIndex != null && _expandedFaixaIndex! > index) {
        _expandedFaixaIndex = _expandedFaixaIndex! - 1;
      }
    });
  }

  Future<void> _restaurarPadrao() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.uai;
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Text(
            'Restaurar padrão?',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Isso volta as faixas para azul, verde, amarelo, laranja e vermelho.',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restaurar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    for (final faixa in _faixas) {
      faixa.dispose();
    }

    setState(() {
      _ativo = true;
      _mostrarTextoUltimaPresenca = true;
      _expandedFaixaIndex = null;
      _faixas
        ..clear()
        ..addAll(_faixasPadrao().map(_FaixaAusenciaController.fromMap));
    });
  }

  Future<void> _salvarConfiguracao() async {
    if (!await _revalidarAcesso()) return;
    if (!mounted) return;

    FocusScope.of(context).unfocus();

    final faixas = <Map<String, dynamic>>[];

    for (final faixa in _faixas) {
      final dias = _parseInt(faixa.diasController.text, fallback: -1);
      final label = faixa.labelController.text.trim().isEmpty
          ? 'Sem título'
          : faixa.labelController.text.trim();
      final cor = _normalizarHex(faixa.corController.text, '#9E9E9E');

      if (dias <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Todas as faixas precisam ter quantidade de dias maior que zero.',
            ),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      faixas.add({
        'ate_dias': dias,
        'cor': cor,
        'label': label,
        'gera_alerta': faixa.geraAlerta,
        'mensagem_alerta': faixa.mensagemController.text.trim(),
      });
    }

    faixas.sort((a, b) {
      final aDias = _parseInt(a['ate_dias'], fallback: 9999);
      final bDias = _parseInt(b['ate_dias'], fallback: 9999);
      return aDias.compareTo(bDias);
    });

    setState(() => _isSaving = true);

    try {
      final uid = _auth.currentUser?.uid ?? '';

      await _firestore.collection(_collection).doc(_document).set({
        'ativo': _ativo,
        'mostrar_texto_ultima_presenca': _mostrarTextoUltimaPresenca,
        'faixas': faixas,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': uid,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Indicadores de ausência salvos com sucesso!'),
          backgroundColor: context.uai.success,
        ),
      );

      await _carregarConfiguracao();
    } catch (e) {
      debugPrint('❌ Erro ao salvar indicadores de ausência: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar indicadores: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAcesso) {
      return PermissionAccessGuard.loadingScaffold(
        context,
        title: 'Indicadores de Ausência',
      );
    }

    if (_acessoNegado) {
      return PermissionAccessGuard.deniedScaffold(
        context,
        title: 'Indicadores de Ausência',
        message:
            'Você não tem permissão para configurar indicadores de ausência.',
      );
    }

    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg =
        Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        title: const Text(
          'Indicadores de Ausência',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Restaurar padrão',
            onPressed: _isSaving ? null : _restaurarPadrao,
            icon: const Icon(Icons.restore_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth < 700 ? 14.0 : 22.0;

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      14,
                      horizontal,
                      118,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(context),
                              const SizedBox(height: 14),
                              _buildSummaryBar(context),
                              const SizedBox(height: 14),
                              _buildSwitches(context),
                              const SizedBox(height: 14),
                              _buildFaixasSection(context),
                              const SizedBox(height: 14),
                              _buildRoboButton(context),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      bottomNavigationBar: _isLoading
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: t.cardAlt,
                  border: Border(top: BorderSide(color: t.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 14,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _salvarConfiguracao,
                  icon: _isSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _readableOn(t.primary),
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _isSaving ? 'SALVANDO...' : 'SALVAR INDICADORES',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: _readableOn(t.primary),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: onPrimary.withAlpha(36),
                  borderRadius: BorderRadius.circular(t.cardRadius - 2),
                  border: Border.all(color: onPrimary.withAlpha(41)),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: onPrimary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Régua visual de frequência',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Configure cores, nomes e alertas das faixas. A tela de alunos usa essa régua para destacar ausências automaticamente.',
                      style: TextStyle(
                        color: onPrimary.withAlpha(209),
                        fontSize: 12.5,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeaderBadge(
                context,
                icon: Icons.layers_rounded,
                label: '${_faixas.length} faixas configuradas',
              ),
              _buildHeaderBadge(
                context,
                icon: _ativo ? Icons.visibility_rounded : Icons.visibility_off,
                label: _ativo ? 'Indicadores ativos' : 'Indicadores desligados',
              ),
              _buildHeaderBadge(
                context,
                icon: Icons.swap_vert_rounded,
                label: 'Ordem crescente automática',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(31),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withAlpha(46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: onPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _boxDecoration(context),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildSummaryChip(
            context,
            icon: Icons.schedule_rounded,
            title: 'Faixas em ordem',
            subtitle: 'A tela mantém tudo crescente por dias.',
            color: t.info,
          ),
          _buildSummaryChip(
            context,
            icon: Icons.add_circle_outline_rounded,
            title: 'Inserção inteligente',
            subtitle: 'Nova faixa entra no lugar certo.',
            color: t.success,
          ),
          _buildSummaryChip(
            context,
            icon: Icons.notifications_active_rounded,
            title: 'Alertas por faixa',
            subtitle: 'Cada nível pode ter sua própria mensagem.',
            color: t.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 310),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: visible.withAlpha(20),
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        border: Border.all(color: visible.withAlpha(46)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: visible.withAlpha(36),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: visible),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitches(BuildContext context) {
    return Container(
      decoration: _boxDecoration(context),
      child: Column(
        children: [
          _buildSettingRow(
            context: context,
            icon: Icons.radio_button_checked_rounded,
            title: 'Ativar indicadores nos cards',
            subtitle:
                'Liga ou desliga a bolinha colorida usada na tela de alunos.',
            value: _ativo,
            onChanged: (value) => setState(() => _ativo = value),
          ),
          Divider(height: 1, color: context.uai.border),
          _buildSettingRow(
            context: context,
            icon: Icons.text_fields_rounded,
            title: 'Mostrar texto da última presença',
            subtitle:
                'Exibe “Última presença há X dias” abaixo da graduação do aluno.',
            value: _mostrarTextoUltimaPresenca,
            onChanged: (value) =>
                setState(() => _mostrarTextoUltimaPresenca = value),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (value ? t.success : t.textMuted).withAlpha(31),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? t.success : t.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            activeThumbColor: switch (Theme.of(context).platform) {
              TargetPlatform.iOS || TargetPlatform.macOS => null,
              _ => t.success,
            },
            activeTrackColor: switch (Theme.of(context).platform) {
              TargetPlatform.iOS || TargetPlatform.macOS => t.success,
              _ => null,
            },
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildFaixasSection(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _boxDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.tune_rounded, color: t.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Faixas de ausência',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A primeira faixa compatível com os dias do aluno será aplicada.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _adicionarFaixa,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Adicionar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: t.border),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildMiniInfo(context, Icons.auto_awesome_rounded,
                    'Ao adicionar uma faixa, ela entra automaticamente na ordem correta.'),
                _buildMiniInfo(context, Icons.swap_vert_rounded,
                    'Se você alterar os dias, a faixa se reposiciona na régua.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(_faixas.length, (index) {
            return _buildFaixaCard(context, index);
          }),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    final t = context.uai;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: t.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaixaCard(BuildContext context, int index) {
    final t = context.uai;
    final faixa = _faixas[index];
    final isUltima = index == _faixas.length - 1;
    final expanded = _expandedFaixaIndex == index;

    return AnimatedBuilder(
      animation: Listenable.merge([
        faixa.diasController,
        faixa.corController,
        faixa.labelController,
        faixa.mensagemController,
      ]),
      builder: (context, _) {
        final currentColor = _colorFromHex(
          faixa.corController.text,
          fallback: t.primary,
        );
        final currentVisible = _ensureVisible(currentColor, t.card);
        final label = faixa.labelController.text.trim().isEmpty
            ? 'Sem título'
            : faixa.labelController.text.trim();
        final dias = faixa.diasController.text.trim().isEmpty
            ? '?'
            : faixa.diasController.text.trim();
        final mensagemPreenchida = faixa.mensagemController.text
            .trim()
            .isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              currentVisible.withAlpha(expanded ? 20 : 11),
              t.card,
            ),
            borderRadius: BorderRadius.circular(t.cardRadius - 6),
            border: Border.all(
              color: expanded
                  ? currentVisible.withAlpha(87)
                  : currentVisible.withAlpha(41),
              width: expanded ? 1.4 : 1,
            ),
            boxShadow: expanded ? t.softShadow : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(t.cardRadius - 6),
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _expandedFaixaIndex = expanded ? null : index;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: currentColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.card, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: currentColor.withAlpha(64),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: t.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
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
                                        color: currentVisible.withAlpha(26),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '#${index + 1}',
                                        style: TextStyle(
                                          color: currentVisible,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    _buildMiniTag(
                                      context: context,
                                      icon: Icons.schedule_rounded,
                                      label: isUltima
                                          ? 'até $dias dias ou mais'
                                          : 'até $dias dias',
                                      color: currentVisible,
                                    ),
                                    _buildMiniTag(
                                      context: context,
                                      icon: faixa.geraAlerta
                                          ? Icons.notifications_active_rounded
                                          : Icons.notifications_off_rounded,
                                      label: faixa.geraAlerta
                                          ? 'gera alerta'
                                          : 'sem alerta',
                                      color: faixa.geraAlerta
                                          ? currentVisible
                                          : t.textMuted,
                                    ),
                                    if (mensagemPreenchida)
                                      _buildMiniTag(
                                        context: context,
                                        icon: Icons.message_rounded,
                                        label: 'msg pronta',
                                        color: t.info,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Remover faixa',
                            onPressed: () => _removerFaixa(index),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: t.error,
                            ),
                          ),
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: currentVisible,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        Divider(height: 1, color: t.border),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 620;

                            final diasField = _buildInput(
                              context: context,
                              controller: faixa.diasController,
                              label: 'Até quantos dias',
                              hint: 'Ex: 12',
                              keyboardType: TextInputType.number,
                              suffixText: 'dias',
                              onChanged: (_) {
                                setState(() {
                                  _sortFaixasInMemory(
                                    keepExpandedFaixa: faixa,
                                  );
                                });
                              },
                            );

                            final colorButton = _buildColorButton(
                              context: context,
                              label: 'Cor do indicador',
                              color: currentColor,
                              onColorChanged: (color) {
                                setState(() {
                                  faixa.corController.text = _colorToHex(color);
                                });
                              },
                            );

                            final labelField = _buildInput(
                              context: context,
                              controller: faixa.labelController,
                              label: 'Nome interno',
                              hint: 'Ex: Atenção',
                            );

                            final mensagemField = _buildMensagemInput(
                              context: context,
                              controller: faixa.mensagemController,
                            );

                            if (!twoColumns) {
                              return Column(
                                children: [
                                  diasField,
                                  const SizedBox(height: 10),
                                  colorButton,
                                  const SizedBox(height: 10),
                                  labelField,
                                  const SizedBox(height: 10),
                                  _buildAlertaSwitch(context, faixa),
                                  const SizedBox(height: 10),
                                  mensagemField,
                                ],
                              );
                            }

                            return Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: diasField),
                                    const SizedBox(width: 10),
                                    Expanded(child: colorButton),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                labelField,
                                const SizedBox(height: 10),
                                _buildAlertaSwitch(context, faixa),
                                const SizedBox(height: 10),
                                mensagemField,
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniTag({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: visible.withAlpha(26),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: visible.withAlpha(46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: visible),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: visible,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMensagemInput({
    required BuildContext context,
    required TextEditingController controller,
  }) {
    final t = context.uai;

    return TextField(
      controller: controller,
      minLines: 4,
      maxLines: 7,
      style: TextStyle(
        color: t.textPrimary,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      decoration:
          _inputDecoration(
            context: context,
            label: 'Mensagem pronta do alerta',
            hint: _mensagemPadraoAlerta(),
            icon: Icons.message_rounded,
          ).copyWith(
            helperMaxLines: 4,
            helperText:
                'Variáveis: {nome_aluno}, {turma}, {indicador}, {dias}, {ultima_presenca}',
          ),
    );
  }

  InputDecoration _inputDecoration({
    required BuildContext context,
    required String label,
    required String hint,
    IconData? icon,
    String? suffixText,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      prefixIcon: icon == null ? null : Icon(icon, color: accent),
      filled: true,
      fillColor: t.cardAlt,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      suffixStyle: TextStyle(
        color: t.textSecondary,
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  Widget _buildColorButton({
    required BuildContext context,
    required String label,
    required Color color,
    required ValueChanged<Color> onColorChanged,
  }) {
    final t = context.uai;
    final visibleColor = _ensureVisible(color, t.cardAlt);

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _pickColor(
          titulo: label,
          corAtual: color,
          onColorChanged: onColorChanged,
        ),
        borderRadius: BorderRadius.circular(t.inputRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: visibleColor.withAlpha(56),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _colorToHex(color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.palette_rounded, color: visibleColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertaSwitch(
    BuildContext context,
    _FaixaAusenciaController faixa,
  ) {
    final t = context.uai;
    final currentColor = _colorFromHex(
      faixa.corController.text,
      fallback: t.primary,
    );
    final visibleColor = _ensureVisible(currentColor, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(
          color: faixa.geraAlerta ? visibleColor.withAlpha(87) : t.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: faixa.geraAlerta
                  ? visibleColor.withAlpha(36)
                  : t.textMuted.withAlpha(26),
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
            child: Icon(
              faixa.geraAlerta
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: faixa.geraAlerta ? visibleColor : t.textMuted,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gerar alerta',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ativa notificações e ações automáticas para esta faixa.',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: faixa.geraAlerta,
            activeThumbColor: visibleColor,
            onChanged: (value) {
              setState(() => faixa.geraAlerta = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInput({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? suffixText,
    ValueChanged<String>? onChanged,
  }) {
    final t = context.uai;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
      decoration: _inputDecoration(
        context: context,
        label: label,
        hint: hint,
        suffixText: suffixText,
      ),
    );
  }

  Widget _buildRoboButton(BuildContext context) {
    final t = context.uai;
    return Container(
      decoration: _boxDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(t.buttonRadius),
          onTap: () => showDialog<bool>(
            context: context,
            builder: (_) => const RoboInatividadeDialog(),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: t.border),
              gradient: LinearGradient(
                colors: [
                  t.primary.withAlpha(15),
                  t.primary.withAlpha(5),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: t.primary.withAlpha(31),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.smart_toy_rounded, color: t.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configurar Robô de Inatividade e Novatos',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Abra as regras automáticas, turmas atendidas, simulação e auditoria do robô.',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward_ios_rounded, color: t.primary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _boxDecoration(BuildContext context) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _FaixaAusenciaController {
  final TextEditingController diasController;
  final TextEditingController corController;
  final TextEditingController labelController;
  final TextEditingController mensagemController;
  bool geraAlerta;

  _FaixaAusenciaController({
    required this.diasController,
    required this.corController,
    required this.labelController,
    required this.mensagemController,
    required this.geraAlerta,
  });

  factory _FaixaAusenciaController.fromMap(Map<String, dynamic> data) {
    return _FaixaAusenciaController(
      diasController: TextEditingController(text: '${data['ate_dias'] ?? ''}'),
      corController: TextEditingController(
        text: data['cor']?.toString() ?? '#9E9E9E',
      ),
      labelController: TextEditingController(
        text: data['label']?.toString() ?? '',
      ),
      mensagemController: TextEditingController(
        text:
            data['mensagem_alerta']?.toString() ??
            data['mensagem']?.toString() ??
            '',
      ),
      geraAlerta:
          data['gera_alerta'] == true ||
          data['gerar_alerta'] == true ||
          data['alerta'] == true,
    );
  }

  void dispose() {
    diasController.dispose();
    corController.dispose();
    labelController.dispose();
    mensagemController.dispose();
  }
}
