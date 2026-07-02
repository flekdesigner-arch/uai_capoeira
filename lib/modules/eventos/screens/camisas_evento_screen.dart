// lib/screens/eventos/camisas_evento_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/responsive/uai_responsive.dart';

class CamisasEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const CamisasEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<CamisasEventoScreen> createState() => _CamisasEventoScreenState();
}

class _CamisasStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;
  final Color borderColor;

  const _CamisasStickyHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: backgroundColor,
      elevation: overlapsContent ? 2 : 0,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: child,
      ),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _CamisasStickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.height != height ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor;
  }
}

class _CamisasEventoScreenState extends State<CamisasEventoScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();

  final PermissaoService _permissaoService = PermissaoService();

  static const String modelagemNormal = 'NORMAL';
  static const String modelagemBabyLook = 'BABY_LOOK';

  static const String tipoManga = 'MANGA';
  static const String tipoMangaLonga = 'MANGA_LONGA';
  static const String tipoRegata = 'REGATA';

  final List<String> _tamanhosPadrao = const [
    '1A',
    '2A',
    '4A',
    '6A',
    '8A',
    '10A',
    '12A',
    '14A',
    'PP',
    'P',
    'M',
    'G',
    'GG',
    'EGG',
  ];

  final List<String> _modelagensPadrao = const [
    modelagemNormal,
    modelagemBabyLook,
  ];

  final List<String> _tiposPadrao = const [
    tipoManga,
    tipoMangaLonga,
    tipoRegata,
  ];

  List<String> _tamanhosDisponiveis = [];
  List<String> _modelagensDisponiveis = [];
  List<String> _tiposDisponiveis = [];
  Map<String, double> _valoresPorTipoCamisa = {
    tipoManga: 0,
    tipoMangaLonga: 0,
    tipoRegata: 0,
  };

  String? _tamanhoSelecionado;
  String _modelagemSelecionada = modelagemNormal;
  String _tipoSelecionado = tipoManga;

  bool _isLoadingConfiguracoes = true;
  bool _carregandoPermissoes = true;
  bool _podeGerenciarCamisas = false;
  bool _salvando = false;

  String _filtroStatus = 'TODOS';

  final NumberFormat _realFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void initState() {
    super.initState();
    _inicializarComPermissao();
  }

  Future<void> _inicializarComPermissao() async {
    await _verificarPermissoes();
    if (!mounted || !_podeGerenciarCamisas) return;
    await _carregarConfiguracoesDoEvento();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  // ───────────────────── CORES / TEMA ─────────────────────

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

  Color _onPrimary() => _readableOn(context.uai.primary);
  Color _onSuccess() => _readableOn(context.uai.success);
  Color _onWarning() => _readableOn(context.uai.warning);
  Color _onError() => _readableOn(context.uai.error);
  Color _onInfo() => _readableOn(context.uai.info);

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  InputDecoration _uaiInputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: accent),
      filled: true,
      fillColor: t.cardAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    );
  }

  // ───────────────────── NORMALIZAÇÃO ─────────────────────

  String? _normalizarTamanho(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    return raw
        .replaceAll(' ', '')
        .replaceAll('ANOS', 'A')
        .replaceAll('ANO', 'A');
  }

  String _normalizarModelagem(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return modelagemBabyLook;
    }

    return modelagemNormal;
  }

  String _normalizarTipoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'MANGA_LONGA' ||
        clean == 'LONGA' ||
        clean == 'MANGA_COMPRIDA') {
      return tipoMangaLonga;
    }

    if (clean == 'REGATA') return tipoRegata;

    return tipoManga;
  }

  String _modelagemLabel(String value) {
    switch (_normalizarModelagem(value)) {
      case modelagemBabyLook:
        return 'Baby Look';
      case modelagemNormal:
      default:
        return 'Normal';
    }
  }

  String _tipoLabel(String value) {
    switch (_normalizarTipoCamisa(value)) {
      case tipoMangaLonga:
        return 'Manga Longa';
      case tipoRegata:
        return 'Regata';
      case tipoManga:
      default:
        return 'Manga';
    }
  }

  int _compararTamanhos(String a, String b) {
    final ordem = <String, int>{
      '1A': 1,
      '2A': 2,
      '4A': 4,
      '6A': 6,
      '8A': 8,
      '10A': 10,
      '12A': 12,
      '14A': 14,
      'PP': 100,
      'P': 101,
      'M': 102,
      'G': 103,
      'GG': 104,
      'EGG': 105,
      'XG': 106,
      'XXG': 107,
    };

    final ia = ordem[a] ?? 999;
    final ib = ordem[b] ?? 999;

    if (ia != ib) return ia.compareTo(ib);
    return a.compareTo(b);
  }

  List<String> _normalizarListaTamanhos(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarTamanho(item);
      if (clean == null) continue;
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) return List<String>.from(_tamanhosPadrao);

    result.sort(_compararTamanhos);
    return result;
  }

  List<String> _normalizarListaModelagens(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarModelagem(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) return List<String>.from(_modelagensPadrao);

    result.sort((a, b) {
      final ordem = {modelagemNormal: 0, modelagemBabyLook: 1};

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  List<String> _normalizarListaTipos(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarTipoCamisa(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) return List<String>.from(_tiposPadrao);

    result.sort((a, b) {
      final ordem = {tipoManga: 0, tipoMangaLonga: 1, tipoRegata: 2};

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  double _parseValor(String value) {
    final normalizado = value
        .trim()
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  Map<String, double> _normalizarValoresPorTipoCamisa(
    dynamic raw, {
    double fallback = 0,
  }) {
    final result = <String, double>{
      tipoManga: fallback,
      tipoMangaLonga: fallback,
      tipoRegata: fallback,
    };

    if (raw is Map) {
      raw.forEach((key, value) {
        final tipo = _normalizarTipoCamisa(key);
        final valor = value is num
            ? value.toDouble()
            : double.tryParse(
                    value?.toString().replaceAll(',', '.').trim() ?? '',
                  ) ??
                  fallback;

        result[tipo] = valor;
      });
    }

    return result;
  }

  double _valorPorTipoCamisa(String tipo) {
    final clean = _normalizarTipoCamisa(tipo);
    final valor = _valoresPorTipoCamisa[clean] ?? 0;

    if (valor > 0) return valor;

    // fallback para evento antigo
    return _valoresPorTipoCamisa[tipoManga] ?? 0;
  }

  void _aplicarValorPadraoDoTipoSelecionado() {
    final valor = _valorPorTipoCamisa(_tipoSelecionado);

    if (valor <= 0) return;

    _valorController.text = valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _campoTexto(
    Map<String, dynamic> data,
    List<String> chaves,
    String fallback,
  ) {
    for (final chave in chaves) {
      final value = data[chave]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return fallback;
  }

  String _tamanhoDaCamisa(Map<String, dynamic> data) {
    return _campoTexto(data, ['tamanho', 'tamanho_camisa'], 'OUTRO');
  }

  String _modelagemDaCamisa(Map<String, dynamic> data) {
    return _normalizarModelagem(
      data['modelagem'] ??
          data['modelagem_camisa'] ??
          data['modelagemCamisa'] ??
          modelagemNormal,
    );
  }

  String _tipoDaCamisa(Map<String, dynamic> data) {
    return _normalizarTipoCamisa(
      data['tipo_camisa'] ?? data['tipoCamisa'] ?? data['tipo'] ?? tipoManga,
    );
  }

  String _descricaoCamisa(Map<String, dynamic> data) {
    final modelagem = _modelagemLabel(_modelagemDaCamisa(data));
    final tipo = _tipoLabel(_tipoDaCamisa(data));
    final tamanho = _tamanhoDaCamisa(data);

    return '$modelagem • $tipo • $tamanho';
  }

  // ───────────────────── PERMISSÕES / CONFIGURAÇÃO ─────────────────────

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final pode = await _permissaoService.temQualquerPermissao([
        'pode_gerenciar_camisas_evento',
        'pode_gerenciar_camisas',
      ]);

      if (!mounted) return;
      setState(() {
        _podeGerenciarCamisas = pode;
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões de camisas: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  Future<void> _carregarConfiguracoesDoEvento() async {
    try {
      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      final data = eventoDoc.data();

      final tamanhos = _normalizarListaTamanhos(
        data?['tamanhosDisponiveis'] ?? data?['tamanhos_disponiveis'],
      );

      final modelagens = _normalizarListaModelagens(
        data?['modelagensCamisaDisponiveis'] ??
            data?['modelagens_camisa_disponiveis'] ??
            data?['modelagensDisponiveis'] ??
            data?['modelagens_disponiveis'],
      );

      final tipos = _normalizarListaTipos(
        data?['tiposCamisaDisponiveis'] ??
            data?['tipos_camisa_disponiveis'] ??
            data?['tiposDisponiveis'] ??
            data?['tipos_disponiveis'],
      );

      final valorFallback =
          (data?['valorCamisa'] as num?)?.toDouble() ??
          (data?['valor_camisa'] as num?)?.toDouble() ??
          0;

      final valoresPorTipo = _normalizarValoresPorTipoCamisa(
        data?['valoresPorTipoCamisa'] ??
            data?['valores_por_tipo_camisa'] ??
            data?['valoresTipoCamisa'] ??
            data?['valores_tipo_camisa'],
        fallback: valorFallback,
      );

      if (!mounted) return;
      setState(() {
        _tamanhosDisponiveis = tamanhos;
        _modelagensDisponiveis = modelagens;
        _tiposDisponiveis = tipos;
        _valoresPorTipoCamisa = valoresPorTipo;
        _isLoadingConfiguracoes = false;
      });

      debugPrint('✅ Tamanhos carregados: $_tamanhosDisponiveis');
      debugPrint('✅ Modelagens carregadas: $_modelagensDisponiveis');
      debugPrint('✅ Tipos carregados: $_tiposDisponiveis');
    } catch (e) {
      debugPrint('❌ Erro ao carregar configurações de camisa: $e');
      if (!mounted) return;
      setState(() {
        _tamanhosDisponiveis = List<String>.from(_tamanhosPadrao);
        _modelagensDisponiveis = List<String>.from(_modelagensPadrao);
        _tiposDisponiveis = List<String>.from(_tiposPadrao);
        _valoresPorTipoCamisa = {
          tipoManga: 0,
          tipoMangaLonga: 0,
          tipoRegata: 0,
        };
        _isLoadingConfiguracoes = false;
      });
    }
  }

  void _mostrarSemPermissao([
    String mensagem = 'Você não tem permissão para gerenciar camisas.',
  ]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────── ADICIONAR CAMISA ─────────────────────

  Future<void> _abrirDialogAdicionar() async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para adicionar camisas.');
      return;
    }

    _nomeController.clear();
    _valorController.clear();
    _tamanhoSelecionado = null;
    _modelagemSelecionada = _modelagensDisponiveis.isNotEmpty
        ? _modelagensDisponiveis.first
        : modelagemNormal;
    _tipoSelecionado = _tiposDisponiveis.isNotEmpty
        ? _tiposDisponiveis.first
        : tipoManga;

    _aplicarValorPadraoDoTipoSelecionado();

    await showDialog<void>(
      context: context,
      barrierDismissible: !_salvando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: context.uai.surface,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.uai.cardRadius),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(context.uai.cardRadius),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDialogHeader(dialogContext),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _nomeController,
                                enabled: !_salvando,
                                decoration: _uaiInputDecoration(
                                  label: 'Nome do participante *',
                                  icon: Icons.person_rounded,
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 560;

                                  final modelagemField = _buildOpcaoSelector(
                                    enabled: !_salvando,
                                    label: 'Modelagem *',
                                    value: _modelagemLabel(
                                      _modelagemSelecionada,
                                    ),
                                    icon: Icons.style_rounded,
                                    onTap: () => _selecionarOpcao(
                                      titulo: 'Selecione a modelagem',
                                      opcoes: _modelagensDisponiveis,
                                      valorAtual: _modelagemSelecionada,
                                      labelBuilder: _modelagemLabel,
                                      normalizar: _normalizarModelagem,
                                      onSelected: (value) {
                                        setState(
                                          () => _modelagemSelecionada = value,
                                        );
                                        setDialogState(() {});
                                      },
                                    ),
                                  );

                                  final tipoField = _buildOpcaoSelector(
                                    enabled: !_salvando,
                                    label: 'Tipo *',
                                    value: _tipoLabel(_tipoSelecionado),
                                    icon: Icons.design_services_rounded,
                                    onTap: () => _selecionarOpcao(
                                      titulo: 'Selecione o tipo',
                                      opcoes: _tiposDisponiveis,
                                      valorAtual: _tipoSelecionado,
                                      labelBuilder: _tipoLabel,
                                      normalizar: _normalizarTipoCamisa,
                                      onSelected: (value) {
                                        setState(() {
                                          _tipoSelecionado = value;
                                          _aplicarValorPadraoDoTipoSelecionado();
                                        });
                                        setDialogState(() {});
                                      },
                                    ),
                                  );

                                  if (narrow) {
                                    return Column(
                                      children: [
                                        modelagemField,
                                        const SizedBox(height: 12),
                                        tipoField,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: modelagemField),
                                      const SizedBox(width: 12),
                                      Expanded(child: tipoField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 560;

                                  final tamanhoField = _buildTamanhoSelector(
                                    enabled: !_salvando,
                                    onSelected: () => setDialogState(() {}),
                                  );

                                  final valorField = TextField(
                                    controller: _valorController,
                                    enabled: !_salvando,
                                    decoration: _uaiInputDecoration(
                                      label: 'Valor',
                                      hint: 'R\$ 0,00',
                                      icon: Icons.attach_money_rounded,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  );

                                  if (narrow) {
                                    return Column(
                                      children: [
                                        tamanhoField,
                                        const SizedBox(height: 12),
                                        valorField,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: tamanhoField),
                                      const SizedBox(width: 12),
                                      Expanded(child: valorField),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _compatInfoBox(),
                            ],
                          ),
                        ),
                      ),
                      _buildDialogActions(dialogContext, setDialogState),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogHeader(BuildContext dialogContext) {
    final t = context.uai;
    final bg = t.associacao;
    final fg = _readableOn(bg);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(gradient: t.primaryGradient),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: fg.withOpacity(0.16)),
            ),
            child: Icon(Icons.shopping_bag_rounded, color: fg, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adicionar camisa',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.eventoNome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withOpacity(0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _salvando ? null : () => Navigator.pop(dialogContext),
            icon: Icon(Icons.close_rounded, color: fg),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildDialogActions(
    BuildContext dialogContext,
    void Function(void Function()) setDialogState,
  ) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _salvando ? null : () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _salvando
                  ? null
                  : () async {
                      final ok = await _adicionarCamisa();
                      setDialogState(() {});
                      if (ok && dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
              icon: _salvando
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _onPrimary(),
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'ADICIONAR'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compatInfoBox() {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.cardAlt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(info.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: info.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: info, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Camisas antigas sem tipo/modelagem aparecem como Normal • Manga.',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _adicionarCamisa() async {
    if (!await _permissaoService.temPermissao(
      'pode_gerenciar_camisas_evento',
    )) {
      _mostrarSemPermissao('Você não tem permissão para adicionar camisas.');
      return false;
    }

    final nome = _nomeController.text.trim();
    final tamanho = _tamanhoSelecionado?.trim() ?? '';
    final valor = _parseValor(_valorController.text);
    final modelagem = _normalizarModelagem(_modelagemSelecionada);
    final tipoCamisa = _normalizarTipoCamisa(_tipoSelecionado);

    if (nome.isEmpty || tamanho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Preencha nome e tamanho da camisa!'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    setState(() => _salvando = true);

    try {
      await FirebaseFirestore.instance.collection('camisas_eventos').add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'nome_participante': nome,
        'tamanho': tamanho,
        'modelagem': modelagem,
        'modelagem_camisa': modelagem,
        'tipo_camisa': tipoCamisa,
        'valor_unitario': valor,
        'valor': valor,
        'pago': false,
        'entregue': false,
        'data_registro': FieldValue.serverTimestamp(),
        'data_pagamento': null,
        'data_entrega': null,
      });

      _nomeController.clear();
      _valorController.clear();
      _tamanhoSelecionado = null;
      _modelagemSelecionada = modelagemNormal;
      _tipoSelecionado = tipoManga;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Camisa registrada com sucesso!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao adicionar camisa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ───────────────────── AÇÕES ─────────────────────

  Future<void> _marcarPago(String camisaId, bool pago) async {
    if (!await _permissaoService.temPermissao(
      'pode_gerenciar_camisas_evento',
    )) {
      _mostrarSemPermissao('Você não tem permissão para alterar pagamento.');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
            'pago': pago,
            'data_pagamento': pago ? FieldValue.serverTimestamp() : null,
          });
    } catch (e) {
      debugPrint('Erro ao marcar pagamento: $e');
    }
  }

  Future<void> _marcarEntregue(String camisaId, bool entregue) async {
    if (!await _permissaoService.temPermissao(
      'pode_gerenciar_camisas_evento',
    )) {
      _mostrarSemPermissao('Você não tem permissão para alterar entrega.');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
            'entregue': entregue,
            'data_entrega': entregue ? FieldValue.serverTimestamp() : null,
          });
    } catch (e) {
      debugPrint('Erro ao marcar entrega: $e');
    }
  }

  Future<void> _editarValor(String camisaId, double valorAtual) async {
    if (!await _permissaoService.temPermissao(
      'pode_gerenciar_camisas_evento',
    )) {
      _mostrarSemPermissao('Você não tem permissão para editar valores.');
      return;
    }

    final TextEditingController valorEditController = TextEditingController(
      text: valorAtual.toStringAsFixed(2).replaceAll('.', ','),
    );

    final novoValor = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Editar valor',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: valorEditController,
          decoration: _uaiInputDecoration(
            label: 'Valor (R\$)',
            icon: Icons.attach_money_rounded,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = _parseValor(valorEditController.text);
              Navigator.pop(dialogContext, valor);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );

    valorEditController.dispose();

    if (novoValor != null && novoValor != valorAtual) {
      try {
        await FirebaseFirestore.instance
            .collection('camisas_eventos')
            .doc(camisaId)
            .update({'valor': novoValor});
      } catch (e) {
        debugPrint('Erro ao editar valor: $e');
      }
    }
  }

  Future<void> _editarDadosCamisa(
    String camisaId,
    Map<String, dynamic> data,
  ) async {
    if (!await _permissaoService.temPermissao(
      'pode_gerenciar_camisas_evento',
    )) {
      _mostrarSemPermissao('Você não tem permissão para editar camisa.');
      return;
    }

    String tempModelagem = _modelagemDaCamisa(data);
    String tempTipo = _tipoDaCamisa(data);
    String? tempTamanho = _normalizarTamanho(_tamanhoDaCamisa(data));

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t = context.uai;

            return AlertDialog(
              backgroundColor: t.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Editar camisa',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInlineChips(
                      titulo: 'Modelagem',
                      opcoes: _modelagensDisponiveis,
                      valorAtual: tempModelagem,
                      labelBuilder: _modelagemLabel,
                      onSelected: (value) {
                        setDialogState(() => tempModelagem = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildInlineChips(
                      titulo: 'Tipo',
                      opcoes: _tiposDisponiveis,
                      valorAtual: tempTipo,
                      labelBuilder: _tipoLabel,
                      onSelected: (value) {
                        setDialogState(() => tempTipo = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildInlineChips(
                      titulo: 'Tamanho',
                      opcoes: _tamanhosDisponiveis,
                      valorAtual: tempTamanho ?? '',
                      labelBuilder: (v) => v,
                      onSelected: (value) {
                        setDialogState(() => tempTamanho = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext, {
                      'modelagem': tempModelagem,
                      'tipo_camisa': tempTipo,
                      'tamanho': tempTamanho,
                    });
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('SALVAR'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
            'modelagem': _normalizarModelagem(result['modelagem']),
            'modelagem_camisa': _normalizarModelagem(result['modelagem']),
            'tipo_camisa': _normalizarTipoCamisa(result['tipo_camisa']),
            'tamanho': _normalizarTamanho(result['tamanho']) ?? 'OUTRO',
            'valor_unitario': _valorPorTipoCamisa(
              _normalizarTipoCamisa(result['tipo_camisa']),
            ),
            'valor': _valorPorTipoCamisa(
              _normalizarTipoCamisa(result['tipo_camisa']),
            ),
            'atualizado_em': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Erro ao editar camisa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao editar camisa: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _excluirCamisa(String camisaId, String nome) async {
    if (!await _permissaoService.temPermissao(
      'pode_gerenciar_camisas_evento',
    )) {
      _mostrarSemPermissao('Você não tem permissão para excluir camisas.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Excluir registro',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          nome.trim().isEmpty
              ? 'Remover esta camisa da lista?'
              : 'Remover a camisa de "$nome"?',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('EXCLUIR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _onError(),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('camisas_eventos')
            .doc(camisaId)
            .delete();
      } catch (e) {
        debugPrint('Erro ao excluir camisa: $e');
      }
    }
  }

  // ───────────────────── SELETORES ─────────────────────

  Future<void> _selecionarOpcao({
    required String titulo,
    required List<String> opcoes,
    required String valorAtual,
    required String Function(String) labelBuilder,
    required String Function(dynamic) normalizar,
    required ValueChanged<String> onSelected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.uai.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (context) {
        final t = context.uai;
        final accent = _ensureVisible(t.associacao, t.surface);

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxHeight: 420),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: opcoes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final value = normalizar(opcoes[index]);
                      final selected = value == normalizar(valorAtual);

                      return Material(
                        color: selected
                            ? Color.alphaBlend(
                                accent.withOpacity(0.14),
                                t.cardAlt,
                              )
                            : t.cardAlt,
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            onSelected(value);
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                t.inputRadius,
                              ),
                              border: Border.all(
                                color: selected ? accent : t.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    labelBuilder(value),
                                    style: TextStyle(
                                      color: selected ? accent : t.textPrimary,
                                      fontWeight: selected
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: accent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _selecionarTamanho({VoidCallback? onSelected}) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.uai.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (context) {
        final t = context.uai;
        final accent = _ensureVisible(t.associacao, t.surface);

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            height: 430,
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Selecione o tamanho',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoadingConfiguracoes
                      ? Center(
                          child: CircularProgressIndicator(color: t.primary),
                        )
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1.5,
                              ),
                          itemCount: _tamanhosDisponiveis.length,
                          itemBuilder: (context, index) {
                            final tamanho = _tamanhosDisponiveis[index];
                            final selected = _tamanhoSelecionado == tamanho;

                            return InkWell(
                              onTap: () {
                                setState(() => _tamanhoSelecionado = tamanho);
                                onSelected?.call();
                                Navigator.pop(context);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Color.alphaBlend(
                                          accent.withOpacity(0.18),
                                          t.cardAlt,
                                        )
                                      : t.cardAlt,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected ? accent : t.border,
                                    width: selected ? 1.3 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    tamanho,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: selected ? accent : t.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOpcaoSelector({
    required bool enabled,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.associacao, t.cardAlt);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(t.inputRadius),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.cardAlt,
          borderRadius: BorderRadius.circular(t.inputRadius),
          border: Border.all(color: accent),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isEmpty ? label : value,
                style: TextStyle(
                  color: value.isEmpty ? t.textMuted : t.textPrimary,
                  fontWeight: value.isEmpty ? FontWeight.w600 : FontWeight.w900,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: accent),
          ],
        ),
      ),
    );
  }

  Widget _buildTamanhoSelector({
    required bool enabled,
    VoidCallback? onSelected,
  }) {
    final t = context.uai;
    final hasValue =
        _tamanhoSelecionado != null && _tamanhoSelecionado!.isNotEmpty;
    final accent = _ensureVisible(t.associacao, t.cardAlt);

    return InkWell(
      onTap: enabled ? () => _selecionarTamanho(onSelected: onSelected) : null,
      borderRadius: BorderRadius.circular(t.inputRadius),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.cardAlt,
          borderRadius: BorderRadius.circular(t.inputRadius),
          border: Border.all(color: hasValue ? accent : t.border),
        ),
        child: Row(
          children: [
            Icon(Icons.straighten_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasValue ? _tamanhoSelecionado! : 'Tamanho *',
                style: TextStyle(
                  color: hasValue ? t.textPrimary : t.textMuted,
                  fontWeight: hasValue ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: accent),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineChips({
    required String titulo,
    required List<String> opcoes,
    required String valorAtual,
    required String Function(String) labelBuilder,
    required ValueChanged<String> onSelected,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.associacao, t.surface);

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: opcoes.map((opcao) {
              final selected = opcao == valorAtual;

              return FilterChip(
                selected: selected,
                label: Text(labelBuilder(opcao)),
                selectedColor: accent,
                backgroundColor: t.cardAlt,
                checkmarkColor: _readableOn(accent),
                side: BorderSide(color: selected ? accent : t.border),
                labelStyle: TextStyle(
                  color: selected ? _readableOn(accent) : t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => onSelected(opcao),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ───────────────────── FILTROS / QUERY ─────────────────────

  Widget _buildFiltros() {
    final t = context.uai;
    final r = context.uaiResponsive;

    final List<Map<String, dynamic>> opcoes = [
      {'label': 'TODOS', 'icon': Icons.list_rounded, 'color': t.textMuted},
      {'label': 'PAGO', 'icon': Icons.paid_rounded, 'color': t.success},
      {'label': 'PENDENTE', 'icon': Icons.pending_rounded, 'color': t.warning},
      {
        'label': 'ENTREGUE',
        'icon': Icons.check_circle_rounded,
        'color': t.info,
      },
      {
        'label': 'NÃO ENTREGUE',
        'icon': Icons.access_time_rounded,
        'color': t.error,
      },
    ];

    return Container(
      color: t.background,
      padding: EdgeInsets.fromLTRB(r.pagePadding, 8, r.pagePadding, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: r.isPhone ? double.infinity : 1120,
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  child: Row(
                    children: opcoes.map((opcao) {
                      final isSelected = _filtroStatus == opcao['label'];
                      final rawColor = opcao['color'] as Color;
                      final color = _ensureVisible(rawColor, t.card);
                      final bg = isSelected ? color : t.card;
                      final fg = isSelected
                          ? _readableOn(color)
                          : t.textSecondary;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          showCheckmark: true,
                          checkmarkColor: fg,
                          selectedColor: bg,
                          backgroundColor: bg,
                          side: BorderSide(
                            color: isSelected ? color : t.border,
                          ),
                          visualDensity: r.isPhone
                              ? VisualDensity.compact
                              : VisualDensity.standard,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                opcao['icon'] as IconData,
                                size: 16,
                                color: fg,
                              ),
                              const SizedBox(width: 4),
                              Text(opcao['label'].toString()),
                            ],
                          ),
                          onSelected: (_) {
                            setState(
                              () => _filtroStatus = opcao['label'].toString(),
                            );
                          },
                          labelStyle: TextStyle(
                            color: fg,
                            fontSize: r.isPhone ? 11.5 : 12,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (!r.isPhone) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    _filtroStatus,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('camisas_eventos')
        .where('evento_id', isEqualTo: widget.eventoId);

    switch (_filtroStatus) {
      case 'PAGO':
        query = query.where('pago', isEqualTo: true);
        break;
      case 'PENDENTE':
        query = query.where('pago', isEqualTo: false);
        break;
      case 'ENTREGUE':
        query = query.where('entregue', isEqualTo: true);
        break;
      case 'NÃO ENTREGUE':
        query = query.where('entregue', isEqualTo: false);
        break;
    }

    return query.orderBy('data_registro', descending: true);
  }

  // ───────────────────── RESUMO / CARDS ─────────────────────

  Widget _buildPermissaoBanner() {
    final t = context.uai;

    if (_carregandoPermissoes) {
      return Container(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.all(context.uaiResponsive.isPhone ? 12 : 11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conferindo permissão de camisas...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final color = _podeGerenciarCamisas ? t.success : t.warning;
    final visible = _ensureVisible(color, t.card);

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(visible.withOpacity(0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: visible.withOpacity(0.18)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(
            _podeGerenciarCamisas
                ? Icons.check_circle_rounded
                : Icons.lock_outline_rounded,
            color: visible,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _podeGerenciarCamisas
                  ? 'Permissão liberada para adicionar, editar, marcar pagamento/entrega e excluir camisas.'
                  : 'Você pode visualizar camisas, mas não pode alterar este módulo.',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final t = context.uai;
    final contagemDetalhada = <String, int>{};
    int entregues = 0;
    int pagos = 0;
    double totalValor = 0;

    for (var doc in docs) {
      final data = doc.data();
      final entregue = data['entregue'] as bool? ?? false;
      final pago = data['pago'] as bool? ?? false;
      final valor = (data['valor'] as num?)?.toDouble() ?? 0;

      final key = _descricaoCamisa(data);
      contagemDetalhada[key] = (contagemDetalhada[key] ?? 0) + 1;

      if (entregue) entregues++;
      if (pago) {
        pagos++;
        totalValor += valor;
      }
    }

    final detalhesOrdenados = contagemDetalhada.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.all(context.uaiResponsive.cardPadding),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.associacao.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: t.associacao.withOpacity(0.18)),
                ),
                child: Icon(
                  Icons.analytics_rounded,
                  color: _ensureVisible(t.associacao, t.card),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo das camisas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      'Separado por modelagem, tipo e tamanho.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: t.associacao.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: t.associacao.withOpacity(0.16)),
                ),
                child: Text(
                  'Total: ${docs.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _ensureVisible(t.associacao, t.card),
                  ),
                ),
              ),
            ],
          ),
          if (detalhesOrdenados.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: detalhesOrdenados.map((entry) {
                  final accent = _ensureVisible(t.associacao, t.cardAlt);
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        accent.withOpacity(0.10),
                        t.cardAlt,
                      ),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accent.withOpacity(0.14)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${entry.value}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: t.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 440;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendLine('Pagos: $pagos', t.success),
                  _legendLine('Pendentes: ${docs.length - pagos}', t.warning),
                ],
              );
              final right = Column(
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  _legendLine('Entregues: $entregues', t.info),
                  _legendLine(
                    'Não entregues: ${docs.length - entregues}',
                    t.error,
                  ),
                ],
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [left, const SizedBox(height: 4), right],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [left, right],
              );
            },
          ),
          Divider(height: 18, color: t.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '💰 TOTAL ARRECADADO:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                _realFormat.format(totalValor),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _ensureVisible(t.success, t.card),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendLine(String label, Color color) {
    final visible = _ensureVisible(color, context.uai.card);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: visible),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: visible,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildCamisaCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final t = context.uai;
    final camisa = doc.data();
    final pago = camisa['pago'] as bool? ?? false;
    final entregue = camisa['entregue'] as bool? ?? false;
    final valor = (camisa['valor'] as num?)?.toDouble() ?? 0;
    final nome = camisa['nome_participante']?.toString() ?? '';
    final tamanho = _tamanhoDaCamisa(camisa);
    final descricao = _descricaoCamisa(camisa);

    Color corCard;
    if (pago && entregue) {
      corCard = t.success;
    } else if (pago && !entregue) {
      corCard = t.info;
    } else if (!pago && entregue) {
      corCard = t.warning;
    } else {
      corCard = t.error;
    }

    final visibleCardColor = _ensureVisible(corCard, t.card);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: t.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        side: BorderSide(color: visibleCardColor.withOpacity(0.36), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        visibleCardColor.withOpacity(0.72),
                        visibleCardColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: visibleCardColor.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      tamanho,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _readableOn(visibleCardColor),
                        fontSize: tamanho.length > 3 ? 14 : 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome.isEmpty ? 'Participante sem nome' : nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _realFormat.format(valor),
                        style: TextStyle(
                          color: _ensureVisible(t.success, t.card),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ações',
                  color: t.surface,
                  icon: Icon(Icons.more_vert_rounded, color: t.textSecondary),
                  onSelected: (value) {
                    switch (value) {
                      case 'editar_camisa':
                        _editarDadosCamisa(doc.id, camisa);
                        break;
                      case 'editar_valor':
                        _editarValor(doc.id, valor);
                        break;
                      case 'excluir':
                        _excluirCamisa(doc.id, nome);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'editar_camisa',
                      child: ListTile(
                        leading: Icon(Icons.checkroom_rounded),
                        title: Text('Editar camisa'),
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'editar_valor',
                      child: ListTile(
                        leading: Icon(Icons.attach_money_rounded),
                        title: Text('Editar valor'),
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'excluir',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Excluir'),
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 470;

                final pagoSwitch = _statusSwitch(
                  label: pago ? 'Pago' : 'Pendente',
                  value: pago,
                  color: pago ? t.success : t.warning,
                  onChanged: (value) => _marcarPago(doc.id, value),
                );

                final entregueSwitch = _statusSwitch(
                  label: entregue ? 'Entregue' : 'Não entregue',
                  value: entregue,
                  color: entregue ? t.info : t.error,
                  onChanged: (value) => _marcarEntregue(doc.id, value),
                );

                if (narrow) {
                  return Column(
                    children: [
                      pagoSwitch,
                      const SizedBox(height: 8),
                      entregueSwitch,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: pagoSwitch),
                    const SizedBox(width: 10),
                    Expanded(child: entregueSwitch),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusSwitch({
    required String label,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: _podeGerenciarCamisas ? onChanged : null,
            activeColor: accent,
          ),
        ],
      ),
    );
  }

  Widget _buildContentBox({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final r = context.uaiResponsive;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: r.isPhone ? double.infinity : 1120,
        ),
        child: Padding(
          padding:
              padding ??
              EdgeInsets.fromLTRB(r.pagePadding, 0, r.pagePadding, 0),
          child: child,
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildContentSliver({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return SliverToBoxAdapter(
      child: _buildContentBox(padding: padding, child: child),
    );
  }

  Widget _buildCamisasGridOuLista({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) {
    final r = context.uaiResponsive;

    if (r.isPhone) {
      return Column(
        children: docs
            .map(
              (doc) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCamisaCard(doc),
              ),
            )
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const spacing = 12.0;

        if (columns <= 1) {
          return Column(
            children: docs
                .map(
                  (doc) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildCamisaCard(doc),
                  ),
                )
                .toList(),
          );
        }

        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: docs
              .map(
                (doc) =>
                    SizedBox(width: itemWidth, child: _buildCamisaCard(doc)),
              )
              .toList(),
        );
      },
    );
  }

  // ───────────────────── BUILD ─────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregandoPermissoes) {
      return PermissionAccessGuard.loadingScaffold(
        context,
        title: 'Camisas do evento',
      );
    }

    if (!_podeGerenciarCamisas) {
      return PermissionAccessGuard.deniedScaffold(
        context,
        title: 'Camisas do evento',
        message: 'Você não tem permissão para gerenciar camisas do evento.',
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          'Camisas do Evento',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        foregroundColor: _appBarFg(),
        backgroundColor: _appBarBg(),
        actions: [
          IconButton(
            onPressed: () async {
              await _carregarConfiguracoesDoEvento();
              await _verificarPermissoes();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recarregar configurações',
          ),
        ],
      ),
      floatingActionButton: _podeGerenciarCamisas
          ? FloatingActionButton.extended(
              onPressed: _abrirDialogAdicionar,
              backgroundColor: t.primary,
              foregroundColor: _onPrimary(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'CAMISA',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final r = context.uaiResponsive;

          if (snapshot.hasError) {
            return ListView(
              padding: r.listInsets,
              children: [
                _buildContentBox(child: _buildPermissaoBanner()),
                SizedBox(height: r.sectionSpacing),
                _buildContentBox(
                  child: _errorBox(
                    'Erro ao carregar camisas: ${snapshot.error}',
                  ),
                ),
              ],
            );
          }

          final docs = snapshot.data?.docs ?? [];

          return RefreshIndicator(
            color: t.primary,
            onRefresh: () async {
              await _carregarConfiguracoesDoEvento();
              await _verificarPermissoes();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: r.pagePadding,
                    bottom: r.sectionSpacing,
                  ),
                  sliver: _buildContentSliver(child: _buildPermissaoBanner()),
                ),
                SliverPadding(
                  padding: EdgeInsets.only(bottom: r.sectionSpacing),
                  sliver: _buildContentSliver(child: _buildResumoCard(docs)),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CamisasStickyHeaderDelegate(
                    height: r.stickyFilterHeight,
                    backgroundColor: t.background,
                    borderColor: t.border,
                    child: _buildFiltros(),
                  ),
                ),
                if (loading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: t.primary),
                    ),
                  )
                else if (docs.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      r.pagePadding,
                      r.sectionSpacing,
                      r.pagePadding,
                      92,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _buildContentBox(
                        padding: EdgeInsets.zero,
                        child: _emptyBox(),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      r.pagePadding,
                      r.sectionSpacing,
                      r.pagePadding,
                      92,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: r.isPhone ? double.infinity : 1120,
                          ),
                          child: _buildCamisasGridOuLista(docs: docs),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyBox() {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.checkroom_rounded, size: 42, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            'Nenhuma camisa encontrada',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _podeGerenciarCamisas
                ? 'Toque em + Camisa para adicionar uma camisa avulsa.'
                : 'Ainda não há camisas cadastradas neste evento.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String message) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.error.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: t.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
