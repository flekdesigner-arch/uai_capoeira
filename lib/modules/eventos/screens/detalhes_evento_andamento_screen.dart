// lib/screens/eventos/detalhes_evento_andamento_screen.dart

import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/services/participacao_service.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'participantes_evento_screen.dart';
import 'gastos_evento_screen.dart';
import 'patrocinadores_evento_screen.dart';
import 'camisas_evento_screen.dart';
import 'package:uai_capoeira/modules/eventos/reports/relatorio_financeiro_screen.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/screens/gerador_certificados_evento_screen.dart';

class DetalhesEventoAndamentoScreen extends StatefulWidget {
  final EventoModel evento;
  final String eventoId;

  const DetalhesEventoAndamentoScreen({
    super.key,
    required this.evento,
    required this.eventoId,
  });

  @override
  State<DetalhesEventoAndamentoScreen> createState() => _DetalhesEventoAndamentoScreenState();
}

class _DetalhesEventoAndamentoScreenState extends State<DetalhesEventoAndamentoScreen> {
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

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _appBarBg() => Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() => Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());


  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PermissaoService _permissaoService = PermissaoService();

  bool _isLoading = true;
  int _totalParticipantes = 0;
  double _totalGastos = 0;
  double _totalPatrocinioValor = 0;
  Map<String, int> _camisasCount = {};
  int _totalCamisas = 0;

  // 🔥 LISTA COMBINADA DE CAMISAS (participações + avulsas)
  List<Map<String, dynamic>> _todasCamisas = [];

  // Permissões dinâmicas do evento
  bool _carregandoPermissoes = true;
  bool _podeAcessarEventoAndamento = false;
  bool _podeGerenciarParticipantes = false;
  bool _podeGerenciarGastos = false;
  bool _podeGerenciarPatrocinadores = false;
  bool _podeGerenciarCamisas = false;
  bool _podeVerRelatorios = false;
  bool _podeGerarCertificados = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _verificarPermissoes();
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final permissoes = await Future.wait<bool>([
        _permissaoService.temQualquerPermissao([
          'pode_ver_eventos_andamento',
          'pode_acessar_eventos_andamento',
          'pode_gerenciar_eventos_andamento',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_gerenciar_participantes_evento',
          'pode_gerenciar_participantes',
          'pode_adicionar_participante_evento',
          'pode_adcionar_aluno_a_eventos',
          'pode_remover_participante_evento',
          'pode_remover_alunos_de_eventos',
          'pode_editar_participacao_evento',
          'pode_concluir_participacao_evento',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_gerenciar_gastos_evento',
          'pode_gerenciar_financeiro',
          'pode_gerenciar_taxas',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_gerenciar_patrocinadores_evento',
          'pode_gerenciar_patrocinadores',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_gerenciar_camisas_evento',
          'pode_gerenciar_camisas',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_ver_relatorio_evento',
          'pode_ver_relatorios',
          'pode_visualizar_relatorios',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_gerar_certificados_evento',
          'pode_gerar_certificados',
        ]),
      ]);

      if (!mounted) return;

      setState(() {
        _podeAcessarEventoAndamento = permissoes[0];
        _podeGerenciarParticipantes = permissoes[1];
        _podeGerenciarGastos = permissoes[2];
        _podeGerenciarPatrocinadores = permissoes[3];
        _podeGerenciarCamisas = permissoes[4];
        _podeVerRelatorios = permissoes[5];
        _podeGerarCertificados = permissoes[6];
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões do evento: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _carregarEstatisticas(),
        _carregarGastos(),
        _carregarPatrocinadores(),
        _carregarTodasCamisas(), // 🔥 Carrega TODAS as camisas
      ]);
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: ${e.toString()}'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _carregarEstatisticas() async {
    try {
      final estatisticas = await _participacaoService.getEstatisticasPorEvento(widget.eventoId);

      setState(() {
        _totalParticipantes = estatisticas['total'] ?? 0;
      });
    } catch (e) {
      debugPrint('Erro ao carregar participantes: $e');
    }
  }

  Future<void> _carregarGastos() async {
    try {
      final gastosSnapshot = await FirebaseFirestore.instance
          .collection('gastos_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      double total = 0;
      for (var doc in gastosSnapshot.docs) {
        total += (doc['valor'] as num?)?.toDouble() ?? 0;
      }

      setState(() {
        _totalGastos = total;
      });
    } catch (e) {
      debugPrint('Erro ao carregar gastos: $e');
    }
  }

  Future<void> _carregarPatrocinadores() async {
    try {
      final patrocinadoresSnapshot = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      double totalValor = 0;

      for (var doc in patrocinadoresSnapshot.docs) {
        final data = doc.data();

        if (data['valor'] != null) {
          totalValor += (data['valor'] as num?)?.toDouble() ?? 0;
        }

        if (data['valor_patrocinio'] != null) {
          totalValor += (data['valor_patrocinio'] as num?)?.toDouble() ?? 0;
        }

        final valorInicial = (data['valor_inicial'] as num?)?.toDouble() ?? 0;
        final saldo = (data['saldo_disponivel'] as num?)?.toDouble() ?? 0;

        if (valorInicial > 0) {
          totalValor += valorInicial - saldo;
        }
      }

      setState(() {
        _totalPatrocinioValor = totalValor;
      });
    } catch (e) {
      debugPrint('Erro ao carregar patrocinadores: $e');
    }
  }

  // 🔥 NOVO: Carrega TODAS as camisas (participações + avulsas)
  Future<void> _carregarTodasCamisas() async {
    try {
      final Map<String, int> contagemCombinada = {};

      // 1️⃣ Busca camisas das PARTICIPAÇÕES
      final participacoesSnapshot = await FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .where('evento_id', isEqualTo: widget.eventoId)
          .where('tamanho_camisa', isNotEqualTo: null)
          .get();

      for (var doc in participacoesSnapshot.docs) {
        final tamanho = doc['tamanho_camisa'] as String?;
        if (tamanho != null && tamanho.isNotEmpty) {
          contagemCombinada[tamanho] = (contagemCombinada[tamanho] ?? 0) + 1;
        }
      }

      debugPrint('📊 Camisas de PARTICIPAÇÕES: ${participacoesSnapshot.docs.length}');

      // 2️⃣ Busca camisas AVULSAS
      final camisasSnapshot = await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      for (var doc in camisasSnapshot.docs) {
        final tamanho = doc['tamanho'] as String?;
        if (tamanho != null && tamanho.isNotEmpty) {
          contagemCombinada[tamanho] = (contagemCombinada[tamanho] ?? 0) + 1;
        }
      }

      debugPrint('📊 Camisas AVULSAS: ${camisasSnapshot.docs.length}');

      setState(() {
        _camisasCount = Map.fromEntries(
          contagemCombinada.entries.toList()..sort((a, b) {
            // Ordenação personalizada (PP, P, M, G, GG, XG, XXG, 4A, 6A, etc)
            final ordem = ['PP', 'P', 'M', 'G', 'GG', 'XG', 'XXG', '4A', '6A', '8A', '10A', '12A', '14A'];
            final indexA = ordem.indexOf(a.key);
            final indexB = ordem.indexOf(b.key);
            if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
            if (indexA != -1) return -1;
            if (indexB != -1) return 1;
            return a.key.compareTo(b.key);
          }),
        );
        _totalCamisas = contagemCombinada.values.fold(0, (sum, val) => sum + val);
      });

      debugPrint('🎯 TOTAL DE CAMISAS: $_totalCamisas');
      debugPrint('📋 Distribuição: $_camisasCount');

    } catch (e) {
      debugPrint('❌ Erro ao carregar camisas: $e');
    }
  }

  // 🔥 DIÁLOGO PREMIUM E RESPONSIVO - SÓ MOSTRA TAMANHOS E QUANTIDADES
  void _mostrarDetalhesCamisas() {
    if (_camisasCount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nenhuma camisa registrada'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        final entries = _camisasCount.entries.toList();

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          backgroundColor: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = MediaQuery.of(context).size;
              final maxWidth = size.width < 480 ? size.width - 28 : 440.0;
              final maxHeight = size.height * 0.82;
              final isSmall = size.width < 380;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                  ),
                  child: Material(
                    color: context.uai.card,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header fixo
                        Container(
                          padding: EdgeInsets.fromLTRB(16, 14, 8, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                context.uai.warning,
                                context.uai.warning,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                child: Icon(
                                  Icons.shopping_bag_rounded,
                                  color: context.uai.card,
                                  size: 23,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Camisas do Evento',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.uai.card,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Distribuição por tamanho',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close_rounded, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),

                        // Conteúdo rolável para evitar fita zebrada em celular pequeno
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: context.uai.warning.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: context.uai.warning.withOpacity(0.12)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'TOTAL DE CAMISAS',
                                          style: TextStyle(
                                            fontSize: isSmall ? 12 : 13,
                                            fontWeight: FontWeight.w900,
                                            color: context.uai.warning,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context.uai.warning,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          '$_totalCamisas',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: context.uai.card,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Tamanhos',
                                    style: TextStyle(
                                      color: _onCard(),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                LayoutBuilder(
                                  builder: (context, localConstraints) {
                                    final availableWidth = localConstraints.maxWidth;
                                    final columns = availableWidth < 270
                                        ? 2
                                        : availableWidth < 390
                                        ? 3
                                        : 4;
                                    const spacing = 9.0;
                                    final itemWidth =
                                        (availableWidth - (spacing * (columns - 1))) / columns;

                                    return Wrap(
                                      spacing: spacing,
                                      runSpacing: spacing,
                                      children: entries.map((entry) {
                                        return SizedBox(
                                          width: itemWidth,
                                          child: Container(
                                            constraints: BoxConstraints(minHeight: 82),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: context.uai.card,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: context.uai.warning.withOpacity(0.12),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: context.uai.warning.withOpacity(0.12).withOpacity(0.35),
                                                  blurRadius: 5,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    entry.key,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      fontSize: isSmall ? 17 : 19,
                                                      fontWeight: FontWeight.w900,
                                                      color: context.uai.warning,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 7),
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: context.uai.warning.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(99),
                                                    border: Border.all(
                                                      color: context.uai.warning.withOpacity(0.12),
                                                    ),
                                                  ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      '${entry.value}',
                                                      maxLines: 1,
                                                      style: TextStyle(
                                                        fontSize: isSmall ? 15 : 17,
                                                        fontWeight: FontWeight.w900,
                                                        color: context.uai.warning,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Rodapé fixo
                        Container(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
                          decoration: BoxDecoration(
                            color: context.uai.surface,
                            border: Border(
                              top: BorderSide(color: context.uai.cardAlt),
                            ),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.check_rounded),
                              label: Text('ENTENDI'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.uai.warning,
                                foregroundColor: _appBarFg(),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }


  Future<void> _abrirLink(String? url) async {
    if (url == null || url.isEmpty) return;

    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível abrir o link'),
              backgroundColor: context.uai.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir link: ${e.toString()}'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  String _formatarData() {
    return widget.evento.dataFormatada;
  }

  String _formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2)}';
  }


  Widget _buildAcessoAndamentoBloqueado() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Container(
          padding: EdgeInsets.all(22),
          constraints: BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.uai.warning.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 58, color: context.uai.warning),
              const SizedBox(height: 12),
              Text(
                'Evento em andamento bloqueado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onCard(),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Peça para o administrador liberar a permissão "Ver eventos em andamento".',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onCardMuted(),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final evento = widget.evento;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          'Gerenciar Evento',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        elevation: 0,
        actions: [
          if (_podeVerRelatorios)
            IconButton(
              icon: const Icon(Icons.assessment_rounded),
              onPressed: _abrirRelatorioFinanceiro,
              tooltip: 'Relatório Financeiro',
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              await Future.wait([
                _carregarDados(),
                _verificarPermissoes(),
              ]);
            },
            tooltip: 'Atualizar dados e permissões',
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _compartilharEvento,
            tooltip: 'Compartilhar',
          ),
        ],
      ),
      body: (_isLoading || _carregandoPermissoes)
          ? _buildLoadingState()
          : !_podeAcessarEventoAndamento
          ? _buildAcessoAndamentoBloqueado()
          : RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _carregarDados(),
            _verificarPermissoes(),
          ]);
        },
        color: context.uai.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(evento),
                    const SizedBox(height: 14),
                    _buildEstatisticasCard(),
                    const SizedBox(height: 14),
                    _buildMenuBotoes(evento),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(22),
        padding: EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.uai.cardAlt),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            const SizedBox(height: 14),
            Text(
              'Carregando dados do evento...',
              style: TextStyle(
                color: _onCardMuted(),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirRelatorioFinanceiro() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RelatorioFinanceiroScreen(
          eventoId: widget.eventoId,
          eventoNome: widget.evento.nome,
        ),
      ),
    );
  }

  void _abrirGeradorCertificados() {
    final eventoComId = widget.evento.copyWith(id: widget.eventoId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GeradorCertificadosEventoScreen(
          evento: eventoComId,
        ),
      ),
    ).then((_) => _carregarDados());
  }

  Widget _buildHeader(EventoModel evento) {
    final hasBanner = evento.linkBanner != null && evento.linkBanner!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.65,
              child: hasBanner
                  ? Image.network(
                evento.linkBanner!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallbackBanner(),
              )
                  : _buildFallbackBanner(),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.10),
                      Colors.black.withOpacity(0.50),
                      Colors.black.withOpacity(0.86),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _headerChip(
                        icon: Icons.pending_actions_rounded,
                        text: 'EM ANDAMENTO',
                        color: context.uai.success,
                      ),
                      if (evento.tipo.trim().isNotEmpty)
                        _headerChip(
                          icon: evento.iconeDoTipo,
                          text: evento.tipo,
                          color: context.uai.warning,
                        ),
                    ],
                  ),
                  SizedBox(height: 11),
                  Text(
                    evento.nome,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.03,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _headerMeta(Icons.calendar_month_rounded, _formatarData()),
                      if (evento.horario.trim().isNotEmpty)
                        _headerMeta(Icons.access_time_rounded, evento.horario),
                      if (evento.cidade.trim().isNotEmpty)
                        _headerMeta(Icons.location_city_rounded, evento.cidade),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.uai.primary, context.uai.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.event_available_rounded, size: 72, color: Colors.white),
      ),
    );
  }

  Widget _headerChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.44),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerMeta(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTituloEvento(EventoModel evento) {
    return const SizedBox.shrink();
  }

  Widget _buildEstatisticasCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.dashboard_rounded,
            title: 'Resumo do evento',
            subtitle: 'Dados atualizados de participantes, camisas, gastos e patrocínios.',
            color: context.uai.primary,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 620 ? 2 : 4;
              const spacing = 10.0;
              final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

              final items = [
                _StatData(Icons.people_rounded, '$_totalParticipantes', 'Participantes', context.uai.info, null),
                _StatData(Icons.shopping_bag_rounded, '$_totalCamisas', 'Camisas', context.uai.warning, _mostrarDetalhesCamisas),
                _StatData(Icons.money_off_rounded, _formatarMoeda(_totalGastos), 'Gastos', context.uai.error, null),
                _StatData(Icons.volunteer_activism_rounded, _formatarMoeda(_totalPatrocinioValor), 'Patrocínio', context.uai.success, null),
              ];

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: items.map((item) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildStatItem(
                      icon: item.icon,
                      value: item.value,
                      label: item.label,
                      color: item.color,
                      onTap: item.onTap,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuBotoes(EventoModel evento) {
    final buttons = <Widget>[
      if (_podeGerenciarParticipantes)
        _buildMenuButton(
          icon: Icons.people_rounded,
          title: 'Participantes',
          subtitle: 'Adicionar, remover, editar e acompanhar alunos',
          color: context.uai.info,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ParticipantesEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                  evento: evento,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeGerarCertificados)
        _buildMenuButton(
          icon: Icons.workspace_premium_rounded,
          title: 'Gerador de certificados',
          subtitle: 'Gerar PDFs, PNGs, impressão em lotes e pacote para gráfica',
          color: context.uai.associacao,
          onTap: _abrirGeradorCertificados,
        ),
      if (_podeGerenciarGastos)
        _buildMenuButton(
          icon: Icons.attach_money_rounded,
          title: 'Gastos',
          subtitle: 'Controlar despesas do evento',
          color: context.uai.error,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GastosEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeGerenciarPatrocinadores)
        _buildMenuButton(
          icon: Icons.volunteer_activism_rounded,
          title: 'Patrocinadores',
          subtitle: 'Gerenciar apoios e beneficiados',
          color: context.uai.success,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PatrocinadoresEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeGerenciarCamisas)
        _buildMenuButton(
          icon: Icons.shopping_bag_rounded,
          title: 'Camisas avulsas',
          subtitle: 'Registrar, conferir, marcar pagamento e entrega',
          color: context.uai.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CamisasEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeVerRelatorios)
        _buildMenuButton(
          icon: Icons.assessment_rounded,
          title: 'Relatório financeiro',
          subtitle: 'PDFs, conferências e resumo geral',
          color: context.uai.associacao,
          onTap: _abrirRelatorioFinanceiro,
        ),
    ];

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.apps_rounded,
            title: 'Ações do evento',
            subtitle: 'Escolha o que deseja gerenciar.',
            color: context.uai.primary,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              if (!wide) {
                return Column(children: buttons);
              }

              const spacing = 12.0;
              final itemWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: buttons
                    .map((b) => SizedBox(width: itemWidth, child: b))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSemPermissaoModulo() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.uai.warning.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: context.uai.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Você pode visualizar este evento, mas ainda não tem permissão para gerenciar participantes, certificados, gastos, patrocinadores, camisas ou relatórios.',
              style: TextStyle(
                color: context.uai.warning,
                height: 1.28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onCardMuted(),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Toque para ver',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.12)),
              color: color.withOpacity(0.035),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(icon, color: color, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _onCard(),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _onCardMuted(),
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: _onCardMuted(),
                  fontSize: 11.5,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: context.uai.card,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.uai.cardAlt),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Future<void> _compartilharEvento() async {
    final String organizadores = widget.evento.organizadores is List
        ? (widget.evento.organizadores as List).join(', ')
        : widget.evento.organizadores?.toString() ?? 'Não informado';

    String texto = '''
🎉 *${widget.evento.nome}* (EM ANDAMENTO)

📅 Data: ${_formatarData()} ${widget.evento.horario.isNotEmpty ? 'às ${widget.evento.horario}' : ''}
📍 Local: ${widget.evento.local} - ${widget.evento.cidade}

👥 Organizadores: $organizadores

📊 Estatísticas atuais:
• Participantes: $_totalParticipantes
• Gastos: ${_formatarMoeda(_totalGastos)}
• Patrocínios: ${_formatarMoeda(_totalPatrocinioValor)}
• Camisas: $_totalCamisas

🔗 Gerencie este evento no app UAI CAPOEIRA!
''';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compartilhamento será implementado'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}


class _StatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatData(this.icon, this.value, this.label, this.color, this.onTap);
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.uai.success,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.uai.card, width: 2),
      ),
      child: Text(
        'EM ANDAMENTO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
