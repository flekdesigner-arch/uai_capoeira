import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

class ArvoreVisitasDialog extends StatefulWidget {
  const ArvoreVisitasDialog({super.key});

  @override
  State<ArvoreVisitasDialog> createState() => _ArvoreVisitasDialogState();
}

class _ArvoreVisitasDialogState extends State<ArvoreVisitasDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic> _dadosAgregados = {};
  bool _carregando = true;
  String? _paisExpandido;
  String? _estadoExpandido;

  @override
  void initState() {
    super.initState();
    _carregarContadores();
  }

  Future<void> _carregarContadores() async {
    try {
      debugPrint('🔍 Buscando documento contadores_agregados...');

      final doc = await _firestore
          .collection('estatisticas')
          .doc('contadores_agregados')
          .get(GetOptions(source: Source.server));

      debugPrint('📄 Documento existe? ${doc.exists}');

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        debugPrint('📊 Dados carregados: $data');

        final dadosConvertidos = _converterNotacaoPontoParaArvore(data);

        if (!mounted) return;

        setState(() {
          _dadosAgregados = dadosConvertidos;
          _carregando = false;
        });
      } else {
        debugPrint('⚠️ Documento não encontrado ou vazio');

        if (!mounted) return;

        setState(() {
          _dadosAgregados = {};
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar contadores: $e');

      if (!mounted) return;

      setState(() => _carregando = false);
    }
  }

  Map<String, dynamic> _converterNotacaoPontoParaArvore(
      Map<dynamic, dynamic> dados,
      ) {
    final Map<String, dynamic> resultado = {};

    dados.forEach((chave, valor) {
      final chaveString = chave.toString();

      if (chaveString == 'total_visitas' ||
          chaveString == 'ultima_atualizacao') {
        resultado[chaveString] = valor;
      } else {
        final partes = chaveString.split('.');
        Map<String, dynamic> atual = resultado;

        for (int i = 0; i < partes.length - 1; i++) {
          final parte = partes[i];

          if (!atual.containsKey(parte)) {
            atual[parte] = <String, dynamic>{};
          }

          atual = atual[parte] as Map<String, dynamic>;
        }

        final ultimaParte = partes.last;
        atual[ultimaParte] = valor;
      }
    });

    debugPrint('✅ Dados convertidos: $resultado');
    return resultado;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

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

  String _formatarNumero(int numero) {
    if (numero < 1000) return numero.toString();

    if (numero < 1000000) {
      final milhares = numero / 1000;
      return milhares < 10
          ? '${milhares.toStringAsFixed(1).replaceAll('.', ',')}k'
          : '${milhares.toStringAsFixed(0)}k';
    }

    final milhoes = numero / 1000000;
    return '${milhoes.toStringAsFixed(1).replaceAll('.', ',')}M';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    final totalVisitas = _toInt(_dadosAgregados['total_visitas']);

    Map<String, dynamic> paises = {};
    if (_dadosAgregados['paises'] != null) {
      paises = Map<String, dynamic>.from(_dadosAgregados['paises'] as Map);
    }

    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(14),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: height * 0.82,
          minWidth: width < 420 ? width * 0.92 : 360,
        ),
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 4),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              children: [
                _buildCabecalho(totalVisitas),
                Expanded(
                  child: _carregando
                      ? Center(
                    child: CircularProgressIndicator(color: t.primary),
                  )
                      : paises.isEmpty
                      ? _buildVazio()
                      : _buildListaPaises(paises),
                ),
                _buildRodape(totalVisitas, paises),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCabecalho(int totalVisitas) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.cardRadius + 4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.travel_explore_rounded,
              color: onPrimary,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visitantes',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Distribuição geográfica dos acessos',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.78),
                    fontSize: 12.5,
                    height: 1.22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility_rounded,
                  color: onPrimary,
                  size: 17,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatarNumero(totalVisitas),
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Fechar',
            icon: Icon(Icons.close_rounded, color: onPrimary, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildVazio() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: t.cardAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.border),
                ),
                child: Icon(
                  Icons.public_off_rounded,
                  size: 56,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Nenhuma visita registrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Os acessos aparecerão aqui',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: t.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaPaises(Map<String, dynamic> paises) {
    final paisesOrdenados = paises.entries.toList()
      ..sort((a, b) {
        final totalA = _toInt((a.value as Map<String, dynamic>)['total']);
        final totalB = _toInt((b.value as Map<String, dynamic>)['total']);
        return totalB.compareTo(totalA);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: paisesOrdenados.length,
      itemBuilder: (context, index) {
        final entry = paisesOrdenados[index];
        final paisNome = entry.key;
        final paisData = entry.value as Map<String, dynamic>;

        return _buildPaisItem(paisNome, paisData);
      },
    );
  }

  Widget _buildPaisItem(String paisNome, Map<String, dynamic> paisData) {
    final t = context.uai;

    final totalPais = _toInt(paisData['total']);
    final expandido = _paisExpandido == paisNome;
    final countryAccent = _ensureVisible(t.info, t.card);

    Map<String, dynamic> estados = {};
    if (paisData['estados'] != null) {
      estados = Map<String, dynamic>.from(paisData['estados'] as Map);
    }

    final estadosOrdenados = estados.entries.toList()
      ..sort((a, b) {
        final totalA = _toInt((a.value as Map<String, dynamic>)['total']);
        final totalB = _toInt((b.value as Map<String, dynamic>)['total']);
        return totalB.compareTo(totalA);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: expandido
            ? Color.alphaBlend(countryAccent.withOpacity(0.08), t.card)
            : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: expandido
                  ? countryAccent.withOpacity(0.28)
                  : t.border,
              width: expandido ? 1.4 : 1,
            ),
            boxShadow: expandido ? t.softShadow : null,
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _paisExpandido = expandido ? null : paisNome;
                    _estadoExpandido = null;
                  });
                },
                borderRadius: BorderRadius.circular(t.cardRadius),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            countryAccent.withOpacity(0.13),
                            t.cardAlt,
                          ),
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                          border: Border.all(
                            color: countryAccent.withOpacity(0.16),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _getBandeira(paisNome),
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              paisNome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 14,
                                  color: t.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${estados.length} estado${estados.length != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _countPill(
                        value: totalPais,
                        color: t.info,
                        background: t.cardAlt,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: expandido
                              ? Color.alphaBlend(
                            countryAccent.withOpacity(0.11),
                            t.cardAlt,
                          )
                              : t.cardAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.border),
                        ),
                        child: Icon(
                          expandido
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: expandido ? countryAccent : t.textSecondary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expandido && estadosOrdenados.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                  child: Column(
                    children: estadosOrdenados.map((entry) {
                      final estadoNome = entry.key;
                      final estadoData = entry.value as Map<String, dynamic>;
                      return _buildEstadoItem(paisNome, estadoNome, estadoData);
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEstadoItem(
      String paisNome,
      String estadoNome,
      Map<String, dynamic> estadoData,
      ) {
    final t = context.uai;

    final totalEstado = _toInt(estadoData['total']);
    final chaveEstado = '$paisNome|$estadoNome';
    final expandido = _estadoExpandido == chaveEstado;
    final stateAccent = _ensureVisible(t.success, t.cardAlt);

    Map<String, dynamic> cidades = {};
    if (estadoData['cidades'] != null) {
      cidades = Map<String, dynamic>.from(estadoData['cidades'] as Map);
    }

    final cidadesOrdenadas = cidades.entries.toList()
      ..sort((a, b) {
        final totalA = _toInt((a.value as Map<String, dynamic>)['total']);
        final totalB = _toInt((b.value as Map<String, dynamic>)['total']);
        return totalB.compareTo(totalA);
      });

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: expandido
            ? Color.alphaBlend(stateAccent.withOpacity(0.09), t.cardAlt)
            : t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(
              color: expandido
                  ? stateAccent.withOpacity(0.26)
                  : t.border,
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _estadoExpandido = expandido ? null : chaveEstado;
                  });
                },
                borderRadius: BorderRadius.circular(t.inputRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            stateAccent.withOpacity(0.12),
                            t.card,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: stateAccent.withOpacity(0.14),
                          ),
                        ),
                        child: Icon(
                          Icons.map_rounded,
                          color: stateAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          estadoNome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _countPill(
                        value: totalEstado,
                        color: t.success,
                        background: t.card,
                        small: true,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        expandido
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: expandido ? stateAccent : t.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (expandido && cidadesOrdenadas.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 10, 10),
                  child: Column(
                    children: cidadesOrdenadas.map((entry) {
                      final cidadeNome = entry.key;
                      final cidadeData = entry.value as Map<String, dynamic>;
                      final totalCidade = _toInt(cidadeData['total']);

                      return _buildCidadeItem(
                        cidadeNome: cidadeNome,
                        totalCidade: totalCidade,
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCidadeItem({
    required String cidadeNome,
    required int totalCidade,
  }) {
    final t = context.uai;
    final cityAccent = _ensureVisible(t.warning, t.card);

    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.inputRadius - 2),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Color.alphaBlend(cityAccent.withOpacity(0.11), t.cardAlt),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: cityAccent.withOpacity(0.14)),
            ),
            child: Icon(
              Icons.location_city_rounded,
              color: cityAccent,
              size: 16,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              cidadeNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _countPill(
            value: totalCidade,
            color: t.warning,
            background: t.cardAlt,
            small: true,
          ),
        ],
      ),
    );
  }

  Widget _countPill({
    required int value,
    required Color color,
    required Color background,
    bool small = false,
  }) {
    final accent = _ensureVisible(color, background);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 10 : 12,
        vertical: small ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _formatarNumero(value),
        style: TextStyle(
          color: _readableOn(accent),
          fontSize: small ? 12 : 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildRodape(int totalVisitas, Map<String, dynamic> paises) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(t.cardRadius + 4),
        ),
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;

          final stats = [
            _FooterStatData(
              icon: Icons.visibility_rounded,
              value: _formatarNumero(totalVisitas),
              label: 'Total de visitas',
              color: t.primary,
            ),
            _FooterStatData(
              icon: Icons.public_rounded,
              value: '${paises.length}',
              label: 'Países',
              color: t.info,
            ),
            _FooterStatData(
              icon: Icons.location_city_rounded,
              value: '${_contarCidades(paises)}',
              label: 'Cidades',
              color: t.warning,
            ),
          ];

          if (compact) {
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: stats.map((stat) {
                return SizedBox(
                  width: (constraints.maxWidth - 16) / 3,
                  child: _buildEstatisticaRodape(stat, compact: true),
                );
              }).toList(),
            );
          }

          return Row(
            children: [
              Expanded(child: _buildEstatisticaRodape(stats[0])),
              _dividerVertical(),
              Expanded(child: _buildEstatisticaRodape(stats[1])),
              _dividerVertical(),
              Expanded(child: _buildEstatisticaRodape(stats[2])),
            ],
          );
        },
      ),
    );
  }

  Widget _dividerVertical() {
    final t = context.uai;

    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: t.border,
    );
  }

  Widget _buildEstatisticaRodape(
      _FooterStatData data, {
        bool compact = false,
      }) {
    final t = context.uai;
    final accent = _ensureVisible(data.color, t.card);

    return Row(
      mainAxisAlignment:
      compact ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          child: Icon(data.icon, color: accent, size: compact ? 14 : 16),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: compact ? 13 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                data.label,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  color: t.textSecondary,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _contarCidades(Map<String, dynamic> paises) {
    int total = 0;

    for (final pais in paises.values) {
      final estados =
      (pais as Map<String, dynamic>)['estados'] as Map<String, dynamic>?;

      if (estados != null) {
        for (final estado in estados.values) {
          final cidades =
          (estado as Map<String, dynamic>)['cidades']
          as Map<String, dynamic>?;

          if (cidades != null) {
            total += cidades.length;
          }
        }
      }
    }

    return total;
  }

  String _getBandeira(String pais) {
    switch (pais.toLowerCase()) {
      case 'brasil':
      case 'brazil':
        return '🇧🇷';
      case 'estados unidos':
      case 'united states':
        return '🇺🇸';
      case 'portugal':
        return '🇵🇹';
      case 'argentina':
        return '🇦🇷';
      case 'espanha':
      case 'spain':
        return '🇪🇸';
      case 'frança':
      case 'france':
        return '🇫🇷';
      case 'alemanha':
      case 'germany':
        return '🇩🇪';
      case 'italia':
      case 'italy':
        return '🇮🇹';
      case 'japao':
      case 'japan':
        return '🇯🇵';
      default:
        return '🌍';
    }
  }
}

class _FooterStatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _FooterStatData({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
}
