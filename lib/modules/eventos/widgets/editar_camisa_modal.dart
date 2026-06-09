import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class EditarCamisaModal extends StatefulWidget {
  final String? tamanhoAtual;
  final String? modelagemAtual;
  final String? tipoAtual;
  final bool entregue;
  final List<String> tamanhosDisponiveis;
  final List<String> modelagensDisponiveis;
  final List<String> tiposDisponiveis;

  /// Opcional: valores por tipo de camisa.
  /// Se não for informado, o modal continua funcionando normalmente.
  final Map<String, double> valoresPorTipoCamisa;

  const EditarCamisaModal({
    super.key,
    this.tamanhoAtual,
    this.modelagemAtual,
    this.tipoAtual,
    required this.entregue,
    required this.tamanhosDisponiveis,
    this.modelagensDisponiveis = const [
      'NORMAL',
      'BABY_LOOK',
    ],
    this.tiposDisponiveis = const [
      'MANGA',
      'MANGA_LONGA',
      'REGATA',
    ],
    this.valoresPorTipoCamisa = const {},
  });

  @override
  State<EditarCamisaModal> createState() => _EditarCamisaModalState();
}

class _EditarCamisaModalState extends State<EditarCamisaModal> {
  static const String modelagemNormal = 'NORMAL';
  static const String modelagemBabyLook = 'BABY_LOOK';

  static const String tipoManga = 'MANGA';
  static const String tipoMangaLonga = 'MANGA_LONGA';
  static const String tipoRegata = 'REGATA';

  late String? _tamanhoSelecionado;
  late String _modelagemSelecionada;
  late String _tipoSelecionado;
  late bool _entregue;

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

  @override
  void initState() {
    super.initState();

    _tamanhoSelecionado = _normalizarTamanho(widget.tamanhoAtual);
    _modelagemSelecionada = _normalizarModelagem(
      widget.modelagemAtual ?? modelagemNormal,
    );
    _tipoSelecionado = _normalizarTipoCamisa(
      widget.tipoAtual ?? tipoManga,
    );
    _entregue = widget.entregue;

    final modelagens = _modelagens;
    if (!modelagens.contains(_modelagemSelecionada)) {
      _modelagemSelecionada = modelagens.isNotEmpty ? modelagens.first : modelagemNormal;
    }

    final tipos = _tipos;
    if (!tipos.contains(_tipoSelecionado)) {
      _tipoSelecionado = tipos.isNotEmpty ? tipos.first : tipoManga;
    }

    final tamanhos = _tamanhos;
    if (_tamanhoSelecionado != null && !tamanhos.contains(_tamanhoSelecionado)) {
      _tamanhoSelecionado = null;
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
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

  List<String> get _tamanhos {
    final source = widget.tamanhosDisponiveis.isNotEmpty
        ? widget.tamanhosDisponiveis
        : _tamanhosPadrao;

    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarTamanho(item);
      if (clean == null) continue;
      if (!result.contains(clean)) result.add(clean);
    }

    result.sort(_compararTamanhos);
    return result;
  }

  List<String> get _modelagens {
    final source = widget.modelagensDisponiveis.isNotEmpty
        ? widget.modelagensDisponiveis
        : const [modelagemNormal, modelagemBabyLook];

    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarModelagem(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) result.add(modelagemNormal);

    result.sort((a, b) {
      final ordem = {
        modelagemNormal: 0,
        modelagemBabyLook: 1,
      };

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  List<String> get _tipos {
    final source = widget.tiposDisponiveis.isNotEmpty
        ? widget.tiposDisponiveis
        : const [tipoManga, tipoMangaLonga, tipoRegata];

    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarTipoCamisa(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) result.add(tipoManga);

    result.sort((a, b) {
      final ordem = {
        tipoManga: 0,
        tipoMangaLonga: 1,
        tipoRegata: 2,
      };

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.card);
    final primary = _ensureVisible(t.primary, t.card);
    final success = _ensureVisible(t.success, t.card);
    final warning = _ensureVisible(t.warning, t.card);
    final error = _ensureVisible(t.error, t.card);

    return Dialog(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: info.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: info.withOpacity(0.18)),
                    ),
                    child: Icon(Icons.checkroom_rounded, color: info),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'EDITAR CAMISA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              _sectionTitle(
                title: 'Modelagem',
                subtitle: 'Normal ou Baby Look feminina',
                icon: Icons.style_rounded,
                color: primary,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _modelagens.map((modelagem) {
                  final isSelected = _modelagemSelecionada == modelagem;

                  return FilterChip(
                    label: Text(
                      _modelagemLabel(modelagem),
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                        color: isSelected ? Colors.white : t.textPrimary,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _modelagemSelecionada = modelagem);
                    },
                    backgroundColor: t.cardAlt,
                    selectedColor: primary,
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? primary : t.border,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              _sectionTitle(
                title: 'Tipo de camisa',
                subtitle: 'Manga, Manga Longa ou Regata',
                icon: Icons.design_services_rounded,
                color: warning,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tipos.map((tipo) {
                  final isSelected = _tipoSelecionado == tipo;

                  return FilterChip(
                    label: Text(
                      _tipoLabel(tipo),
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                        color: isSelected ? _readableOn(warning) : t.textPrimary,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _tipoSelecionado = tipo);
                    },
                    backgroundColor: t.cardAlt,
                    selectedColor: warning,
                    checkmarkColor: _readableOn(warning),
                    side: BorderSide(
                      color: isSelected ? warning : t.border,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              _sectionTitle(
                title: 'Tamanho',
                subtitle: 'Selecione o tamanho da peça',
                icon: Icons.straighten_rounded,
                color: info,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tamanhos.map((tamanho) {
                  final isSelected = _tamanhoSelecionado == tamanho;

                  return FilterChip(
                    label: Text(
                      tamanho,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                        color: isSelected ? Colors.white : t.textPrimary,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _tamanhoSelecionado = tamanho);
                    },
                    backgroundColor: t.cardAlt,
                    selectedColor: info,
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? info : t.border,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.inputRadius),
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                      title: 'Status da entrega',
                      subtitle: 'Controle se a camisa já foi entregue',
                      icon: Icons.inventory_2_rounded,
                      color: success,
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Pendente',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      value: false,
                      groupValue: _entregue,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _entregue = value);
                      },
                      activeColor: warning,
                    ),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Entregue',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      value: true,
                      groupValue: _entregue,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _entregue = value);
                      },
                      activeColor: success,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Container(
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
                        'Peças antigas sem configuração entram como Normal • Manga até serem alteradas.',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 380;

                  final cancelar = TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: error,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'CANCELAR',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  );

                  final salvar = ElevatedButton.icon(
                    onPressed: _salvar,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text(
                      'SALVAR',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: info,
                      foregroundColor: _appBarFg(),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                      ),
                    ),
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cancelar,
                        const SizedBox(height: 8),
                        salvar,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: cancelar),
                      const SizedBox(width: 12),
                      Expanded(child: salvar),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _salvar() {
    Navigator.pop(context, {
      // Mantém compatibilidade com código antigo.
      'tamanho': _tamanhoSelecionado,
      'entregue': _entregue,

      // Novos campos oficiais.
      'modelagem_camisa': _modelagemSelecionada,
      'tipo_camisa': _tipoSelecionado,
      'valor_camisa': _valorDoTipoSelecionado(),
      'valorCamisa': _valorDoTipoSelecionado(),

      // Aliases úteis para telas que usarem camelCase.
      'modelagemCamisa': _modelagemSelecionada,
      'tipoCamisa': _tipoSelecionado,
    });
  }

  static String? _normalizarTamanho(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    return raw
        .replaceAll(' ', '')
        .replaceAll('ANOS', 'A')
        .replaceAll('ANO', 'A');
  }

  static int _compararTamanhos(String a, String b) {
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

  static String _normalizarModelagem(dynamic value) {
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

  static String _normalizarTipoCamisa(dynamic value) {
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

    if (clean == 'REGATA') {
      return tipoRegata;
    }

    return tipoManga;
  }

  static String _modelagemLabel(String value) {
    switch (_normalizarModelagem(value)) {
      case modelagemBabyLook:
        return 'Baby Look';
      case modelagemNormal:
      default:
        return 'Normal';
    }
  }

  static String _tipoLabel(String value) {
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
  double _valorDoTipoSelecionado() {
    final tipo = _normalizarTipoCamisa(_tipoSelecionado);

    for (final entry in widget.valoresPorTipoCamisa.entries) {
      if (_normalizarTipoCamisa(entry.key) == tipo) {
        return entry.value;
      }
    }

    return 0;
  }

  String _formatarValor(double value) {
    if (value <= 0) return '';
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

}
