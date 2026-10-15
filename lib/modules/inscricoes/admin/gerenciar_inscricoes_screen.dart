import 'dart:developer' as developer;
import 'dart:async';
import 'package:uai_capoeira/core/session_log/session_log_service.dart';
import '../renovacao/atualizar_aluno_inscricao_screen.dart';
import '../experiencia/suportes_inscricao_screen.dart';
import '../experiencia/painel_avaliacoes_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/modules/inscricoes/services/inscricao_email_service.dart';
import 'package:uai_capoeira/modules/inscricoes/ficha/ficha_complementar_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/turmas/screens/cadastro_aluno_turma_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/widgets/inscricoes_aprovadas_dialog.dart';
import 'package:uai_capoeira/modules/inscricoes/public/visualizar_termo_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/widgets/aula_experimental_dialog.dart';
import 'package:uai_capoeira/modules/inscricoes/services/inscricoes_permission_service.dart';
import 'package:uai_capoeira/modules/inscricoes/services/inscricao_archive_service.dart';
import 'configurar_inscricoes_screen.dart';

String formatarDataHoraInscricao(dynamic value) {
  if (value == null) return '';

  try {
    if (value is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(value.toDate());
    }

    if (value is DateTime) {
      return DateFormat('dd/MM/yyyy HH:mm').format(value);
    }
  } catch (_) {}

  return value.toString();
}

bool temDataInscricaoExibivel(String dataFormatada) =>
    dataFormatada.trim().isNotEmpty;

String rotuloDataInscricao(String dataFormatada) =>
    temDataInscricaoExibivel(dataFormatada)
        ? 'Inscrito em $dataFormatada'
        : 'Data de inscrição não informada';

/// Boundaries used by controlled widget tests; the default path uses Firebase.
class GerenciarInscricaoRecord {
  const GerenciarInscricaoRecord(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}

class GerenciarInscricoesOperations {
  const GerenciarInscricoesOperations({
    required this.records,
    required this.permissions,
    required this.archive,
    required this.updateCounter,
    required this.record,
  });

  final Stream<List<GerenciarInscricaoRecord>> Function() records;
  final Future<InscricoesPermissions> Function() permissions;
  final Future<InscricaoArchiveResult> Function(
    String inscricaoId,
    String motivo,
    void Function(String etapa) onProgress,
  ) archive;
  final Future<void> Function() updateCounter;
  final void Function(String inscricaoId, String result) record;
}

class GerenciarInscricoesScreen extends StatefulWidget {
  const GerenciarInscricoesScreen({super.key, this.operations});

  final GerenciarInscricoesOperations? operations;

  @override
  State<GerenciarInscricoesScreen> createState() =>
      _GerenciarInscricoesScreenState();
}

class _GerenciarInscricoesScreenState extends State<GerenciarInscricoesScreen> {
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _turmas = [];
  InscricoesPermissions _acoes = InscricoesPermissions.vazio;
  bool _permissoesCarregadas = false;
  String _filtroTriagem = 'todas';
  Map<String, dynamic> _mensagensModelos = const {};
  Map<String, dynamic> _cardPendenteConfig = const {};
  late final InscricoesPermissionService _inscricoesPermissionService =
      InscricoesPermissionService();
  late final InscricaoArchiveService _archiveService = InscricaoArchiveService();

  Stream<List<GerenciarInscricaoRecord>> _pendingRecords() {
    if (widget.operations != null) return widget.operations!.records();
    return _firestore
        .collection('inscricoes')
        .where('status', isEqualTo: 'pendente')
        .orderBy('data_inscricao', descending: true)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                GerenciarInscricaoRecord(doc.id, Map<String, dynamic>.from(doc.data())),
            ]);
  }

  void _recordArchive(String id, String result) {
    if (widget.operations != null) {
      widget.operations!.record(id, result);
      return;
    }
    unawaited(SessionLogService.instance.recordEntityOperation(
      module: 'inscricoes', entityType: 'inscricao', entityId: id,
      operation: 'recusou', result: result,
    ));
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
        .withLightness(bgIsDark ? 0.74 : 0.30)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  bool _temaNeonEmFundoEscuro([Color? color]) {
    final base = color ?? context.uai.primary;
    final surface = context.uai.surface;
    final background = context.uai.background;
    final hsl = HSLColor.fromColor(base);

    return base.computeLuminance() > 0.44 &&
        (surface.computeLuminance() < 0.38 ||
            background.computeLuminance() < 0.38) &&
        hsl.saturation > 0.50;
  }

  Color _screenAccent() {
    return _ensureVisible(context.uai.inscricoes, context.uai.card);
  }

  Color _safeHeaderBg([Color? baseColor]) {
    final base = baseColor ?? context.uai.primary;
    if (_temaNeonEmFundoEscuro(base)) {
      return Color.alphaBlend(base.withAlpha(87), context.uai.surface);
    }
    return base;
  }

  Color _onHeader(Color background, [Color? sourceColor]) {
    if (_temaNeonEmFundoEscuro(sourceColor ?? background)) {
      return const Color(0xFFFFFFFF);
    }
    return _readableOn(background);
  }

  Gradient _safeHeaderGradient([Color? baseColor]) {
    final original = baseColor ?? context.uai.primary;
    final base = _safeHeaderBg(original);
    final hsl = HSLColor.fromColor(base);
    final bgIsDark = base.computeLuminance() < 0.45;
    final end = hsl
        .withLightness(
          bgIsDark
              ? (hsl.lightness + 0.08).clamp(0.0, 1.0)
              : (hsl.lightness - 0.09).clamp(0.0, 1.0),
        )
        .withSaturation((hsl.saturation + 0.04).clamp(0.0, 1.0))
        .toColor();

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [base, end],
    );
  }

  Color _onPrimary() => _onHeader(_safeHeaderBg(), context.uai.primary);
  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withAlpha(173);

  Color _primaryButtonBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _primaryButtonFg() =>
      Theme.of(context).appBarTheme.foregroundColor ??
      _readableOn(_primaryButtonBg());

  Color _safeAccent(Color color, [Color? background]) {
    return _ensureVisible(color, background ?? context.uai.card);
  }

  bool get _isWideDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  bool get _isDesktopDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1180;
  }

  double get _dashboardMaxWidth {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 1280;
    if (width >= 1180) return 1120;
    if (width >= 900) return 1040;
    return width;
  }

  EdgeInsets get _dashboardPagePadding {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return const EdgeInsets.fromLTRB(22, 18, 22, 30);
    if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 26);
    return const EdgeInsets.fromLTRB(14, 14, 14, 24);
  }

  Widget _dashboardWidthLimiter(Widget child) {
    if (!_isWideDashboard) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dashboardMaxWidth),
        child: child,
      ),
    );
  }

  int _dashboardColumns(
    double width, {
    double minItemWidth = 360,
    int maxColumns = 3,
  }) {
    if (width <= 0) return 1;
    return (width / minItemWidth).floor().clamp(1, maxColumns).toInt();
  }

  Widget _dashboardResponsiveWrap({
    required List<Widget> children,
    double minItemWidth = 380,
    int maxColumns = 3,
    double spacing = 12,
    double runSpacing = 12,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(children.length, (index) {
              final isLast = index == children.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : runSpacing),
                child: SizedBox(width: double.infinity, child: children[index]),
              );
            }),
          );
        }

        final columns = _dashboardColumns(
          width,
          minItemWidth: minItemWidth,
          maxColumns: maxColumns,
        );
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _carregarTurmas();
    _carregarPermissoesAcoes();
    _carregarConfiguracaoMensagens();
  }

  Future<void> _carregarConfiguracaoMensagens() async {
    if (widget.operations != null) return;
    try {
      final doc = await _firestore
          .collection('configuracoes')
          .doc('inscricoes')
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _mensagensModelos = Map<String, dynamic>.from(
          data['mensagens_modelos'] as Map? ?? const {},
        );
        _cardPendenteConfig = Map<String, dynamic>.from(
          data['card_pendente'] as Map? ?? const {},
        );
      });
    } catch (_) {}
  }

  String _aplicarTemplateMensagem(String template, Map<String, String> vars) {
    var out = template;
    for (final entry in vars.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    return out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Future<void> _registrarResultadoAulaExperimental(
    String inscricaoId,
    Map<String, dynamic> inscricao,
  ) async {
    String presenca = 'compareceu';
    String desfecho = 'quer_continuar';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            backgroundColor: t.card,
            title: const Text('Resultado da aula experimental'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _texto(inscricao['nome'], fallback: 'Aluno'),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'compareceu',
                        icon: Icon(Icons.check_circle_rounded),
                        label: Text('COMPARECEU'),
                      ),
                      ButtonSegment(
                        value: 'nao_compareceu',
                        icon: Icon(Icons.cancel_rounded),
                        label: Text('NÃO VEIO'),
                      ),
                    ],
                    selected: {presenca},
                    onSelectionChanged: (value) => setLocal(() {
                      presenca = value.first;
                      desfecho = presenca == 'compareceu'
                          ? 'quer_continuar'
                          : 'remarcar';
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: desfecho,
                    decoration: const InputDecoration(
                      labelText: 'Próximo passo',
                    ),
                    items: presenca == 'compareceu'
                        ? const [
                            DropdownMenuItem(
                              value: 'quer_continuar',
                              child: Text('Quer continuar'),
                            ),
                            DropdownMenuItem(
                              value: 'vai_decidir',
                              child: Text('Ainda vai decidir'),
                            ),
                            DropdownMenuItem(
                              value: 'nao_tem_interesse',
                              child: Text('Não tem interesse'),
                            ),
                          ]
                        : const [
                            DropdownMenuItem(
                              value: 'remarcar',
                              child: Text('Remarcar aula'),
                            ),
                            DropdownMenuItem(
                              value: 'entrar_contato',
                              child: Text('Entrar em contato'),
                            ),
                            DropdownMenuItem(
                              value: 'arquivar',
                              child: Text('Arquivar depois'),
                            ),
                          ],
                    onChanged: (v) => setLocal(() => desfecho = v ?? desfecho),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCELAR'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, {
                  'presenca': presenca,
                  'desfecho': desfecho,
                }),
                icon: const Icon(Icons.save_rounded),
                label: const Text('REGISTRAR'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;

    final presencaFinal = result['presenca']!;
    final desfechoFinal = result['desfecho']!;
    final etapa = presencaFinal == 'compareceu'
        ? (desfechoFinal == 'quer_continuar'
              ? 'interessado'
              : desfechoFinal == 'vai_decidir'
              ? 'aguardando_decisao'
              : 'sem_interesse')
        : (desfechoFinal == 'remarcar'
              ? 'nao_compareceu_remarcar'
              : 'nao_compareceu');
    final titulo = presencaFinal == 'compareceu'
        ? 'Compareceu à aula experimental'
        : 'Não compareceu à aula experimental';
    final descricao = desfechoFinal.replaceAll('_', ' ');

    await _firestore.collection('inscricoes').doc(inscricaoId).set({
      'resultado_aula_experimental': {
        'presenca': presencaFinal,
        'desfecho': desfechoFinal,
        'registrado_em': FieldValue.serverTimestamp(),
        'registrado_por_uid': FirebaseAuth.instance.currentUser?.uid,
        'registrado_por_email': FirebaseAuth.instance.currentUser?.email,
        'registrado_por_nome': FirebaseAuth.instance.currentUser?.displayName,
      },
      'etapa_atendimento': etapa,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
      'timeline': FieldValue.arrayUnion([
        {
          'tipo': presencaFinal == 'compareceu'
              ? 'aula_experimental_compareceu'
              : 'aula_experimental_nao_compareceu',
          'titulo': titulo,
          'descricao': descricao,
          'data': Timestamp.now(),
          'origem': 'painel_inscricoes',
          'usuario_uid': FirebaseAuth.instance.currentUser?.uid,
          'visivel_ao_inscrito': true,
        },
      ]),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$titulo registrado.'),
        backgroundColor: context.uai.success,
      ),
    );
  }

  Future<void> _carregarPermissoesAcoes() async {
    final acoes = widget.operations == null
        ? await _inscricoesPermissionService.carregar()
        : await widget.operations!.permissions();
    if (!mounted) return;
    setState(() {
      _acoes = acoes;
      _permissoesCarregadas = true;
    });
  }

  Future<void> _carregarTurmas() async {
    if (widget.operations != null) return;
    try {
      final snapshot = await _firestore
          .collection('turmas')
          .orderBy('nome')
          .get();
      setState(() {
        _turmas = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'academia_nome': data['academia_nome'] ?? data['nucleo'] ?? '',
            'nucleo': data['nucleo'] ?? data['academia_nome'] ?? '',
            'academia_id': data['academia_id'] ?? '',
            'capacidade_maxima': data['capacidade_maxima'] ?? 0,
            'alunos_ativos': data['alunos_ativos'] ?? 0,
            'status': data['status'] ?? 'ativa',
            'nivel': data['nivel'] ?? '',
            'faixa_etaria': data['faixa_etaria'] ?? '',
            'idade_minima': data['idade_minima'],
            'idade_maxima': data['idade_maxima'],
            'dias_semana': data['dias_semana'] ?? const [],
            'dias_semana_display': data['dias_semana_display'] ?? const [],
            'dias_configuracao': data['dias_configuracao'] ?? const {},
          };
        }).toList();
      });
    } catch (e) {
      developer.log('Erro ao carregar turmas: $e');
    }
  }

  // 🔥 MÉTODO PARA ABRIR FOTO EM TELA CHEIA
  void _abrirFotoTelaCheia(String? fotoUrl, String nomeAluno) {
    if (fotoUrl == null || fotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Esta inscrição não possui foto'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withAlpha(242),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade800,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                size: 64,
                                color: Colors.white54,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Erro ao carregar imagem',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(204),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 32,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  nomeAluno,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Toque para fechar',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
    );
  }

  // 🔥 MÉTODO COMPLETO DO WHATSAPP
  Future<void> _abrirWhatsApp(
    String numero, {
    String? mensagem,
    bool isApp = true,
  }) async {
    try {
      String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanedPhone.startsWith('0')) {
        cleanedPhone = cleanedPhone.substring(1);
      }
      if (!cleanedPhone.startsWith('55')) {
        cleanedPhone = '55$cleanedPhone';
      }

      String url = 'https://wa.me/$cleanedPhone';
      if (mensagem != null && mensagem.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(mensagem);
        url += '?text=$encodedMessage';
      }

      final uri = Uri.parse(url);

      if (isApp) {
        try {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );

          if (!launched) {
            throw Exception('Não foi possível abrir o app do WhatsApp');
          }
        } catch (appError) {
          final webUrl = Uri.parse(
            'https://web.whatsapp.com/send?phone=$cleanedPhone${
                mensagem != null && mensagem.isNotEmpty
                    ? '&text=${Uri.encodeComponent(mensagem)}'
                    : ''}',
          );

          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        final webUrl = Uri.parse(
          'https://web.whatsapp.com/send?phone=$cleanedPhone${
              mensagem != null && mensagem.isNotEmpty
                  ? '&text=${Uri.encodeComponent(mensagem)}'
                  : ''}',
        );

        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _mostrarErro('Erro ao abrir WhatsApp: $e');
    }
  }

  // 🔥 APROVAR - Abre tela de cadastro com dados preenchidos
  void _aprovarInscricao(
    String inscricaoId,
    Map<String, dynamic> dados,
    String turmaId,
    String turmaNome,
    String academiaId,
    String academiaNome,
  ) {
    final dadosComId = Map<String, dynamic>.from(dados);
    dadosComId['id'] = inscricaoId;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroAlunoTurmaScreen(
          turmaId: turmaId,
          turmaNome: turmaNome,
          academiaId: academiaId,
          academiaNome: academiaNome,
          dadosIniciais: dadosComId,
        ),
      ),
    ).then((alunoCadastrado) {
      if (alunoCadastrado == true) {
        unawaited(SessionLogService.instance.recordEntityOperation(
          module: 'inscricoes', entityType: 'inscricao', entityId: inscricaoId,
          operation: 'aprovou', result: 'sucesso',
        ));
      }
      if (alunoCadastrado == true && mounted) {
        {
          _atualizarContadorInscricoes();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '✅ Inscrição aprovada e aluno cadastrado com sucesso!',
              ),
              backgroundColor: context.uai.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<ModalRoute<dynamic>?> _mostrarProcessandoRecusa(
    ValueNotifier<String> etapa,
  ) async {
    final routeReady = Completer<ModalRoute<dynamic>?>();
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!routeReady.isCompleted) {
          routeReady.complete(ModalRoute.of(dialogContext));
        }
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: dialogContext.uai.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(46),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          color: dialogContext.uai.error,
                          backgroundColor: dialogContext.uai.error.withAlpha((255.0 * (
                            .12)).round()),
                        ),
                      ),
                      Icon(
                        Icons.archive_rounded,
                        color: dialogContext.uai.error,
                        size: 26,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Recusando inscrição...',
                    style: TextStyle(
                      color: dialogContext.uai.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: etapa,
                    builder: (_, value, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        value,
                        key: ValueKey(value),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: dialogContext.uai.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Não feche o aplicativo durante este processamento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: dialogContext.uai.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    unawaited(dialogFuture.then((_) {
      if (!routeReady.isCompleted) routeReady.complete(null);
    }));
    return routeReady.future;
  }

  void _finalizarProcessandoRecusa(
    ModalRoute<dynamic>? route,
    ValueNotifier<String> etapa,
  ) {
    final navigator = route?.navigator;
    if (route != null && route.isActive && navigator != null && navigator.mounted) {
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }
    if (route == null) {
      etapa.dispose();
    } else {
      unawaited(route.completed.then((_) => etapa.dispose()));
    }
  }

  // 📦 RECUSAR = ARQUIVAR com preservação dos dados e otimização da foto.
  Future<void> _recusarInscricao(String inscricaoId) async {
    final motivoController = TextEditingController();
    String motivoRapido = 'Não compareceu / sem retorno';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: context.uai.surface,
            insetPadding: const EdgeInsets.all(18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      context.uai.warning.withAlpha(31),
                      context.uai.cardAlt,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.archive_rounded,
                    color: context.uai.warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recusar e arquivar?',
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A inscrição não será apagada. Ela será movida para o histórico, preservando dados, termo e assinatura. A foto será otimizada em JPEG com qualidade 85 para economizar armazenamento.',
                    style: TextStyle(
                      color: context.uai.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Motivo',
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final item in const [
                        'Não compareceu / sem retorno',
                        'Desistiu',
                        'Não confirmou interesse',
                        'Outro',
                      ])
                        ChoiceChip(
                          label: Text(item),
                          selected: motivoRapido == item,
                          onSelected: (_) =>
                              setDialogState(() => motivoRapido = item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: motivoController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observação opcional',
                      hintText: 'Ex.: não compareceu à aula experimental...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.archive_rounded, size: 18),
                label: const Text('RECUSAR E ARQUIVAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.error,
                  foregroundColor: _readableOn(context.uai.error),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) {
      motivoController.dispose();
      return;
    }

    final observacao = motivoController.text.trim();
    motivoController.dispose();
    final motivo = observacao.isEmpty
        ? motivoRapido
        : '$motivoRapido — $observacao';

    final etapa = ValueNotifier<String>('Preparando dados da inscrição...');
    final loadingRoute = await _mostrarProcessandoRecusa(etapa);

    try {
      final result = widget.operations == null
          ? await _archiveService.recusarEArquivar(
              inscricaoId: inscricaoId,
              motivo: motivo,
              onProgress: (texto) => etapa.value = texto,
            )
          : await widget.operations!.archive(
              inscricaoId,
              motivo,
              (texto) => etapa.value = texto,
            );
      _recordArchive(inscricaoId, 'sucesso');
      await _atualizarContadorInscricoes();

      _finalizarProcessandoRecusa(loadingRoute, etapa);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.fotoComprimida
                ? '📦 Inscrição recusada e arquivada • foto otimizada'
                : '📦 Inscrição recusada e arquivada com segurança',
          ),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _recordArchive(inscricaoId, 'falha');
      _finalizarProcessandoRecusa(loadingRoute, etapa);
      if (!mounted) return;
      _mostrarErro('Erro ao arquivar inscrição: $e');
    }
  }

  // 🔥 MOSTRAR TERMO COMPLETO
  void _mostrarTermo(
    BuildContext context,
    Map<String, dynamic> dados,
    String inscricaoId,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            VisualizarTermoScreen(dados: dados, inscricaoId: inscricaoId),
      ),
    );
  }

  // 🔥 DIÁLOGO DE SELEÇÃO DE TURMA
  void _mostrarDialogoSelecionarTurma(
    String inscricaoId,
    Map<String, dynamic> dados,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            decoration: BoxDecoration(
              color: context.uai.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(41),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors:
                          (_safeHeaderGradient(context.uai.success)
                                  as LinearGradient)
                              .colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _readableOn(_safeHeaderBg()).withAlpha(41),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _readableOn(
                              _safeHeaderBg(),
                            ).withAlpha(41),
                          ),
                        ),
                        child: Icon(
                          Icons.class_rounded,
                          color: _readableOn(context.uai.success),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecionar turma',
                              style: TextStyle(
                                color: _readableOn(context.uai.success),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Escolha onde o aluno será cadastrado.',
                              style: TextStyle(
                                color: _readableOn(
                                  context.uai.success,
                                ).withAlpha(199),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: _readableOn(context.uai.success),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _turmas.isEmpty
                      ? _buildEmptyDialogState(
                          icon: Icons.class_outlined,
                          title: 'Nenhuma turma disponível',
                          subtitle:
                              'Cadastre uma turma antes de aprovar a inscrição.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: _turmas.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final turma = _turmas[index];
                            final alunosAtivos = _asInt(turma['alunos_ativos']);
                            final capacidadeMaxima = _asInt(
                              turma['capacidade_maxima'],
                            );
                            final temLimite = capacidadeMaxima > 0;
                            final temVaga =
                                !temLimite || alunosAtivos < capacidadeMaxima;
                            final porcentagem = temLimite
                                ? ((alunosAtivos / capacidadeMaxima) * 100)
                                      .clamp(0, 100)
                                      .round()
                                : 0;
                            final progress = temLimite
                                ? (alunosAtivos / capacidadeMaxima).clamp(
                                    0.0,
                                    1.0,
                                  )
                                : 0.0;

                            return InkWell(
                              onTap: temVaga
                                  ? () {
                                      Navigator.pop(context);
                                      _aprovarInscricao(
                                        inscricaoId,
                                        dados,
                                        turma['id'],
                                        turma['nome'],
                                        turma['academia_id'],
                                        turma['academia_nome'],
                                      );
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: temVaga
                                      ? context.uai.card
                                      : context.uai.cardAlt,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: temVaga
                                        ? context.uai.success.withAlpha(61)
                                        : context.uai.border,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(9),
                                      blurRadius: 7,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: temVaga
                                            ? Color.alphaBlend(
                                                context.uai.success.withAlpha((255.0 * (
                                                  0.10)).round()),
                                                context.uai.cardAlt,
                                              )
                                            : context.uai.border,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Icon(
                                        temVaga
                                            ? Icons.meeting_room_rounded
                                            : Icons.block_rounded,
                                        color: temVaga
                                            ? context.uai.success
                                            : context.uai.textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  turma['nome']?.toString() ??
                                                      'Sem nome',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w900,
                                                    color: temVaga
                                                        ? context
                                                              .uai
                                                              .textPrimary
                                                        : context.uai.textMuted,
                                                  ),
                                                ),
                                              ),
                                              if (!temVaga)
                                                _buildSmallStatusChip(
                                                  label: 'LOTADA',
                                                  color: context.uai.error,
                                                )
                                              else
                                                _buildSmallStatusChip(
                                                  label: 'DISPONÍVEL',
                                                  color: context.uai.success,
                                                ),
                                            ],
                                          ),
                                          if ((turma['academia_nome']
                                                      ?.toString() ??
                                                  '')
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              turma['academia_nome'].toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color:
                                                    context.uai.textSecondary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                  child: LinearProgressIndicator(
                                                    minHeight: 7,
                                                    value: progress,
                                                    backgroundColor:
                                                        context.uai.border,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(
                                                          !temLimite
                                                              ? context
                                                                    .uai
                                                                    .success
                                                              : porcentagem >=
                                                                    90
                                                              ? context
                                                                    .uai
                                                                    .error
                                                              : porcentagem >=
                                                                    70
                                                              ? context
                                                                    .uai
                                                                    .warning
                                                              : context
                                                                    .uai
                                                                    .success,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                temLimite
                                                    ? '$alunosAtivos/$capacidadeMaxima'
                                                    : '$alunosAtivos alunos',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  color:
                                                      context.uai.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCELAR'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔥 DIÁLOGO DE DETALHES COM FOTO E AÇÕES
  void _mostrarDetalhesInscricao(String docId, Map<String, dynamic> dados) {
    final fotoUrl = dados['foto_url']?.toString();
    final nomeAluno = _texto(dados['nome'], fallback: 'Aluno');
    final dataInscricao = formatarDataHoraInscricao(dados['data_inscricao']);
    final temAssinatura = _temTexto(dados['assinatura_url']);
    final headerAccent = _screenAccent();
    final headerBg = _safeHeaderBg(headerAccent);
    final onHeader = _onHeader(headerBg, headerAccent);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            minChildSize: 0.55,
            maxChildSize: 0.96,
            builder: (context, scrollController) {
              return Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _isWideDashboard ? 620 : double.infinity,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.uai.surface,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(46),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 12, 10, 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors:
                                  (_safeHeaderGradient(headerAccent)
                                          as LinearGradient)
                                      .colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: onHeader.withAlpha(115),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _abrirFotoTelaCheia(fotoUrl, nomeAluno),
                                    child: Hero(
                                      tag: 'foto_inscricao_$docId',
                                      child: _buildFotoAvatar(
                                        fotoUrl: fotoUrl,
                                        nome: nomeAluno,
                                        radius: 32,
                                        borderColor: onHeader,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nomeAluno,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: onHeader,
                                            fontSize: 18,
                                            height: 1.05,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          rotuloDataInscricao(dataInscricao),
                                          style: TextStyle(
                                            color: onHeader.withAlpha(199),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_acoes.aprovar && _acoes.editarAluno)
                                    IconButton(
                                      tooltip:
                                          'Atualizar aluno / renovar matrícula',
                                      icon: Icon(
                                        Icons.manage_accounts_rounded,
                                        color: onHeader,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.of(this.context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AtualizarAlunoInscricaoScreen(
                                                  inscricaoId: docId,
                                                  nomeInscricao: nomeAluno,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (_acoes.excluirPermanente)
                                    IconButton(
                                      tooltip: 'Excluir permanentemente',
                                      icon: Icon(
                                        Icons.delete_forever_rounded,
                                        color: onHeader,
                                      ),
                                      onPressed: () =>
                                          _confirmarExcluirInscricaoPermanentemente(
                                            context,
                                            inscricaoId: docId,
                                            nome: nomeAluno,
                                            arquivada: false,
                                          ),
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: onHeader,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(14),
                            children: [
                              _buildTermoCard(
                                temAssinatura: temAssinatura,
                                onTap: () {
                                  Navigator.pop(context);
                                  _mostrarTermo(context, dados, docId);
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildSectionCard(
                                icon: Icons.person_rounded,
                                title: 'Dados do aluno',
                                children: [
                                  _buildInfoTile(
                                    icon: Icons.person_rounded,
                                    label: 'Nome',
                                    value: dados['nome'],
                                    onTap: () {
                                      Navigator.pop(context);
                                      _mostrarTermo(context, dados, docId);
                                    },
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.badge_rounded,
                                    label: 'Apelido',
                                    value: dados['apelido'],
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.assignment_ind_outlined,
                                    label: 'Ficha complementar',
                                    value: 'Cuidados, família e trajetória',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FichaComplementarScreen(
                                          inscricaoId: docId,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.credit_card_rounded,
                                    label: 'CPF',
                                    value: dados['cpf'],
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.wc_rounded,
                                    label: 'Sexo',
                                    value: dados['sexo'],
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.cake_rounded,
                                    label: 'Nascimento',
                                    value: dados['data_nascimento'],
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.calendar_month_rounded,
                                    label: 'Idade',
                                    value: _formatarIdade(
                                      dados['data_nascimento'],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildSecurityDetailCard(dados),
                              if ((dados['timeline'] is List) &&
                                  (dados['timeline'] as List).isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildTimelineDetailCard(dados),
                              ],
                              const SizedBox(height: 12),
                              _buildSectionCard(
                                icon: Icons.phone_android_rounded,
                                title: 'Contato',
                                children: [
                                  _buildInfoTile(
                                    icon: Icons.phone_rounded,
                                    label: 'Contato do aluno',
                                    value: dados['contato_aluno'],
                                  ),
                                  if ((dados['nome_contato_emergencia']
                                              ?.toString() ??
                                          '')
                                      .isNotEmpty)
                                    _buildInfoTile(
                                      icon: Icons.emergency_rounded,
                                      label: 'Contato de emergência',
                                      value:
                                          '${dados['nome_contato_emergencia']} • ${dados['grau_emergencia'] ?? ''} • ${dados['contato_emergencia'] ?? ''}',
                                    ),
                                  _buildInfoTile(
                                    icon: Icons.family_restroom_rounded,
                                    label: 'Responsável',
                                    value: dados['nome_responsavel'],
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.family_restroom_rounded,
                                    label: 'Vínculo com o aluno',
                                    value:
                                        dados['grau_responsavel']?.toString() ??
                                        'Não informado',
                                  ),
                                  _buildInfoTile(
                                    icon: Icons.phone_in_talk_rounded,
                                    label: 'Contato do responsável',
                                    value: dados['contato_responsavel'],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildSectionCard(
                                icon: Icons.location_on_rounded,
                                title: 'Endereço',
                                children: [
                                  _buildInfoTile(
                                    icon: Icons.home_rounded,
                                    label: 'Endereço',
                                    value: dados['endereco'],
                                  ),
                                  if (temDataInscricaoExibivel(dataInscricao))
                                    _buildInfoTile(
                                      icon: Icons.event_rounded,
                                      label: 'Data da inscrição',
                                      value: dataInscricao,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          decoration: BoxDecoration(
                            color: context.uai.cardAlt,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(28),
                            ),
                            border: Border(
                              top: BorderSide(color: context.uai.border),
                            ),
                          ),
                          child: Column(
                            children: [
                              if (_texto(
                                        dados['etapa_atendimento'],
                                        fallback: '',
                                      ) ==
                                      'aula_agendada' ||
                                  _texto(
                                    dados['etapa_atendimento'],
                                    fallback: '',
                                  ).startsWith('nao_compareceu') ||
                                  _texto(
                                        dados['etapa_atendimento'],
                                        fallback: '',
                                      ) ==
                                      'aguardando_decisao') ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _registrarResultadoAulaExperimental(
                                        docId,
                                        dados,
                                      );
                                    },
                                    icon: const Icon(Icons.fact_check_rounded),
                                    label: const Text(
                                      'RESULTADO DA AULA EXPERIMENTAL',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: context.uai.info,
                                      side: BorderSide(
                                        color: context.uai.info.withAlpha((255.0 * (
                                          .35)).round()),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (_permissoesCarregadas && _acoes.aprovar)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _mostrarDialogoSelecionarTurma(
                                        docId,
                                        dados,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.check_circle_rounded,
                                    ),
                                    label: const Text('APROVAR INSCRIÇÃO'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: context.uai.success,
                                      foregroundColor: _readableOn(
                                        context.uai.success,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_permissoesCarregadas && _acoes.aprovar)
                                const SizedBox(height: 12),
                              if (_permissoesCarregadas &&
                                  (_acoes.contatarAluno ||
                                      _acoes.contatarResponsavel))
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 2,
                                      bottom: 7,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.event_available_rounded,
                                          size: 15,
                                          color: context.uai.textMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'AGENDAR AULA EXPERIMENTAL',
                                          style: TextStyle(
                                            color: context.uai.textMuted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.55,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_permissoesCarregadas &&
                                  (_acoes.contatarAluno ||
                                      _acoes.contatarResponsavel))
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_permissoesCarregadas &&
                                        _acoes.contatarAluno)
                                      Expanded(
                                        child: _buildContactButton(
                                          label: 'ALUNO',
                                          numero: dados['contato_aluno']
                                              ?.toString(),
                                          nome: dados['nome']?.toString(),
                                          cor: context.uai.success,
                                          inscricaoId: docId,
                                          inscricao: dados,
                                          destinatarioTipo: 'aluno',
                                        ),
                                      ),
                                    if (_permissoesCarregadas &&
                                        _acoes.contatarAluno &&
                                        _acoes.contatarResponsavel)
                                      const SizedBox(width: 8),
                                    if (_permissoesCarregadas &&
                                        _acoes.contatarResponsavel)
                                      Expanded(
                                        child: _buildContactButton(
                                          label: 'RESPONSÁVEL',
                                          numero: dados['contato_responsavel']
                                              ?.toString(),
                                          nome: dados['nome_responsavel']
                                              ?.toString(),
                                          cor: context.uai.info,
                                          inscricaoId: docId,
                                          inscricao: dados,
                                          destinatarioTipo: 'responsavel',
                                        ),
                                      ),
                                  ],
                                ),
                              if (_permissoesCarregadas &&
                                  (_acoes.visualizarTermo || _acoes.recusar))
                                const SizedBox(height: 10),
                              if (_permissoesCarregadas &&
                                  (_acoes.visualizarTermo || _acoes.recusar))
                                Row(
                                  children: [
                                    if (_acoes.visualizarTermo)
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            Future.delayed(
                                              const Duration(milliseconds: 100),
                                              () {
                                                if (mounted)
                                                  { _mostrarTermo(
                                                    context,
                                                    dados,
                                                    docId,
                                                  ); }
                                              },
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.description_rounded,
                                            size: 19,
                                          ),
                                          label: const Text('TERMO'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: context.uai.info,
                                            side: BorderSide(
                                              color: context.uai.info
                                                  .withAlpha(77),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 13,
                                            ),
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_acoes.visualizarTermo &&
                                        _acoes.recusar)
                                      const SizedBox(width: 8),
                                    if (_acoes.recusar)
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _recusarInscricao(docId);
                                          },
                                          icon: const Icon(
                                            Icons.archive_rounded,
                                            size: 19,
                                          ),
                                          label: const Text('RECUSAR'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _safeAccent(
                                              context.uai.error,
                                              context.uai.cardAlt,
                                            ),
                                            side: BorderSide(
                                              color: context.uai.error
                                                  .withAlpha(77),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 13,
                                            ),
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
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

  bool _enviandoConviteEmail = false;

  Future<void> _planejarAulaExperimental({
    required String inscricaoId,
    required Map<String, dynamic> inscricao,
    required String numero,
    required String? destinatarioNome,
    required String destinatarioTipo,
  }) async {
    if (_enviandoConviteEmail) return;
    debugPrint(
      '🧪 INSCRIÇÕES: planejador ativo | inscrição=$inscricaoId | destino=$destinatarioTipo',
    );
    if (_turmas.isEmpty) {
      _mostrarErro(
        'Nenhuma turma disponível. Cadastre/configure uma turma antes de agendar a aula experimental.',
      );
      return;
    }

    final result = await showAulaExperimentalDialog(
      context: context,
      turmas: _turmas,
      inscricao: inscricao,
      destinatarioTipo: destinatarioTipo,
    );
    if (result == null || !mounted) return;

    final confirmado = await _revisarConviteExperimental(
      result: result,
      inscricao: inscricao,
      destinatarioNome: destinatarioNome,
      destinatarioTipo: destinatarioTipo,
      temWhatsapp: numero.trim().isNotEmpty,
    );
    if (confirmado == null || !mounted) return;
    if (confirmado == 'email') {
      await _enviarConviteEmail(inscricaoId, result, destinatarioTipo);
      return;
    }

    final mensagem = _montarMensagemAulaExperimental(
      result: result,
      inscricao: inscricao,
      destinatarioNome: destinatarioNome,
      destinatarioTipo: destinatarioTipo,
    );

    try {
      await _firestore.collection('inscricoes').doc(inscricaoId).set({
        'aula_experimental': {
          'email_job_id': FieldValue.delete(),
          'turma_id': result.turma['id'],
          'turma_nome': result.turma['nome'],
          'academia_id': result.turma['academia_id'],
          'academia_nome':
              result.academia['nome'] ??
              result.turma['academia_nome'] ??
              result.turma['nucleo'] ??
              '',
          'data': Timestamp.fromDate(result.data),
          'data_formatada': DateFormat('dd/MM/yyyy').format(result.data),
          'horario_inicio': result.horarioInicio,
          'horario_fim': result.horarioFim,
          'destinatario_tipo': destinatarioTipo,
          'destinatario_nome': destinatarioNome ?? '',
          'numero_destino': numero,
          'convite_preparado_em': FieldValue.serverTimestamp(),
          'alterado_por_uid': FirebaseAuth.instance.currentUser?.uid,
          'alterado_por_email': FirebaseAuth.instance.currentUser?.email,
          'alterado_por_nome': FirebaseAuth.instance.currentUser?.displayName,
        },
        'emails_jornada': {
          'convite': {
            'status': 'substituido_por_whatsapp',
            'job_id': FieldValue.delete(),
          },
        },
        'etapa_atendimento': 'aula_agendada',
        'timeline': FieldValue.arrayUnion([
          {
            'tipo': 'aula_experimental_agendada',
            'titulo': 'Aula experimental agendada',
            'descricao':
                '${result.turma['nome']} • ${DateFormat('dd/MM/yyyy').format(result.data)} • ${result.horarioInicio} às ${result.horarioFim}',
            'data': Timestamp.now(),
            'origem': 'painel_inscricoes',
            'destinatario_tipo': destinatarioTipo,
            'visivel_ao_inscrito': true,
          },
        ]),
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _mostrarErro('Não foi possível salvar o agendamento. Tente novamente.');
      return;
    }

    await _abrirWhatsApp(numero, mensagem: mensagem, isApp: true);
  }

  String _montarMensagemAulaExperimental({
    required AulaExperimentalResult result,
    required Map<String, dynamic> inscricao,
    required String? destinatarioNome,
    required String destinatarioTipo,
  }) {
    final aluno = _texto(inscricao['nome'], fallback: 'aluno');
    final pessoa = (destinatarioNome ?? '').trim();
    final saudacaoNome = pessoa.isNotEmpty
        ? pessoa.split(RegExp(r'\s+')).first
        : (destinatarioTipo == 'aluno'
              ? aluno.split(RegExp(r'\s+')).first
              : '');
    final academia = _texto(
      result.academia['nome'],
      fallback: _texto(
        result.turma['academia_nome'] ?? result.turma['nucleo'],
        fallback: 'UAI Capoeira',
      ),
    );
    final endereco = _texto(result.academia['endereco'], fallback: '');
    final referencia = _texto(
      result.academia['referencia_local'],
      fallback: '',
    );
    final maps = _texto(result.academia['google_maps_url'], fallback: '');
    final data = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(result.data);
    final horario = result.horarioFim.trim().isEmpty
        ? result.horarioInicio
        : '${result.horarioInicio} às ${result.horarioFim}';

    final intro = destinatarioTipo == 'responsavel'
        ? 'Recebemos a inscrição de $aluno na UAI Capoeira e gostaríamos de convidá-lo(a) para uma aula experimental. 🥋'
        : 'Recebemos sua inscrição na UAI Capoeira e gostaríamos de convidar você para uma aula experimental. 🥋';

    final linhas = <String>[
      'Olá${saudacaoNome.isNotEmpty ? ', $saudacaoNome' : ''}! 👋',
      '',
      intro,
      '',
      '📅 ${data[0].toUpperCase()}${data.substring(1)}',
      '🕒 Horário: $horario',
      '👥 Turma: ${result.turma['nome'] ?? 'Turma'}',
      '📍 Local: $academia',
      if (endereco.isNotEmpty) '🏠 Endereço: $endereco',
      if (referencia.isNotEmpty) '🧭 Referência: $referencia',
      if (maps.isNotEmpty) '📌 Google Maps: $maps',
      '',
      'Se possível, chegue alguns minutos antes do início da aula.',
      '',
      'Será um prazer receber ${destinatarioTipo == 'responsavel' ? aluno : 'você'}! 🤝',
      'UAI Capoeira',
    ];

    final template = _mensagensModelos['convite_aula']?.toString().trim() ?? '';
    if (template.isNotEmpty && !template.contains('\uFFFD')) {
      return _aplicarTemplateMensagem(template, {
        'aluno': aluno,
        'responsavel': pessoa.isNotEmpty ? pessoa : aluno,
        'turma': result.turma['nome']?.toString() ?? 'Turma',
        'data': data,
        'horario': horario,
        'academia': academia,
        'endereco': endereco,
        'maps': maps,
      });
    }
    return linhas.join('\n');
  }

  Future<void> _enviarConviteEmail(
    String id,
    AulaExperimentalResult aula,
    String tipo,
  ) async {
    if (_enviandoConviteEmail) return;
    _enviandoConviteEmail = true;
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Preparando e enviando o convite…')),
            ],
          ),
        ),
      ),
    );
    final service = InscricaoEmailService.firebase();
    String mensagem;
    try {
      final response = await service
          .call('enviarConviteAulaExperimentalEmail', {
            'inscricao_id': id,
            'turma_id': aula.turma['id'],
            'destinatario_tipo': tipo,
            'dia': DateFormat('yyyy-MM-dd').format(aula.data),
            'inicio': aula.horarioInicio,
            'fim': aula.horarioFim,
          });
      mensagem = switch (response['status']) {
        'enviado' =>
          'Convite aceito pelo serviço de e-mail. Confira também a pasta de spam.',
        'pendente' || 'processando' =>
          'Convite salvo. O envio está pendente e será tentado automaticamente.',
        'revisar' =>
          'Confira o envio no Resend: a janela de repetição segura terminou.',
        'cancelado' =>
          'Este convite foi substituído ou a inscrição não está mais pendente.',
        _ => 'Confira o estado do convite antes de tentar novamente.',
      };
    } on FirebaseFunctionsException catch (e) {
      mensagem =
          e.message ?? 'Não foi possível solicitar o envio. Tente novamente.';
    } catch (e) {
      mensagem =
          'Não foi possível confirmar o envio agora. Tente novamente com a mesma aula; o pedido será reaproveitado.';
    } finally {
      service.dispose();
      _enviandoConviteEmail = false;
      if (navigator.mounted) navigator.pop();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), duration: const Duration(seconds: 7)),
    );
  }

  Future<String?> _revisarConviteExperimental({
    required AulaExperimentalResult result,
    required Map<String, dynamic> inscricao,
    required String? destinatarioNome,
    required String destinatarioTipo,
    required bool temWhatsapp,
  }) {
    final t = context.uai;
    final email = '${inscricao['email_conta_uai'] ?? ''}'.trim();
    final podeEmail =
        inscricao['email_confirmado'] == true && email.contains('@');
    final academia =
        result.academia['nome'] ??
        result.turma['academia_nome'] ??
        result.turma['nucleo'] ??
        'Academia';
    final endereco = '${result.academia['endereco'] ?? ''}'.trim();
    final maps = '${result.academia['google_maps_url'] ?? ''}'.trim();
    final horario = result.horarioFim.trim().isEmpty
        ? result.horarioInicio
        : '${result.horarioInicio} às ${result.horarioFim}';

    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.inscricoes, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.card,
        title: Row(
          children: [
            Icon(Icons.fact_check_rounded, color: t.inscricoes),
            const SizedBox(width: 10),
            const Expanded(child: Text('Revisar convite')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row(
                  Icons.person_rounded,
                  'Aluno',
                  _texto(inscricao['nome'], fallback: 'Aluno'),
                ),
                row(
                  Icons.chat_rounded,
                  'Destinatário',
                  '${destinatarioTipo == 'responsavel' ? 'Responsável' : 'Aluno'}${(destinatarioNome ?? '').trim().isNotEmpty ? ' • ${destinatarioNome!.trim()}' : ''}',
                ),
                row(
                  Icons.groups_2_rounded,
                  'Turma',
                  '${result.turma['nome'] ?? 'Turma'}',
                ),
                row(
                  Icons.event_rounded,
                  'Data',
                  DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(result.data),
                ),
                row(Icons.schedule_rounded, 'Horário', horario),
                row(
                  Icons.email_outlined,
                  'E-mail confirmado da inscrição',
                  podeEmail ? email : 'Não disponível. Use o WhatsApp.',
                ),
                if (inscricao['emails_jornada'] is Map &&
                    inscricao['emails_jornada']['convite'] is Map)
                  row(
                    Icons.info_outline,
                    'Último envio por e-mail',
                    switch (inscricao['emails_jornada']['convite']['status']) {
                      'enviado' => 'Aceito pelo serviço de e-mail',
                      'pendente' ||
                      'processando' => 'Pendente — nova tentativa automática',
                      'revisar' => 'Requer conferência no Resend',
                      'substituido_por_whatsapp' =>
                        'Agendamento atualizado pelo WhatsApp',
                      'cancelado' => 'Convite substituído',
                      _ => 'Não enviado',
                    },
                  ),
                row(Icons.location_on_rounded, 'Local', '$academia'),
                if (endereco.isNotEmpty)
                  row(Icons.home_work_rounded, 'Endereço', endereco),
                if (maps.isNotEmpty)
                  row(Icons.map_rounded, 'Google Maps', 'Link cadastrado ✓'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('EDITAR'),
          ),
          OutlinedButton.icon(
            onPressed: podeEmail
                ? () => Navigator.pop(dialogContext, 'email')
                : null,
            icon: const Icon(Icons.email_outlined),
            label: const Text('ENVIAR POR E-MAIL'),
          ),
          FilledButton.icon(
            onPressed: temWhatsapp
                ? () => Navigator.pop(dialogContext, 'whatsapp')
                : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('ENVIAR NO WHATSAPP'),
            style: FilledButton.styleFrom(backgroundColor: t.success),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required String label,
    required String? numero,
    required String? nome,
    required Color cor,
    required String inscricaoId,
    required Map<String, dynamic> inscricao,
    required String destinatarioTipo,
  }) {
    final temContato =
        (numero != null && numero.trim().isNotEmpty) ||
        (inscricao['email_confirmado'] == true &&
            '${inscricao['email_conta_uai'] ?? ''}'.contains('@'));

    return InkWell(
      onTap: temContato
          ? () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 120), () {
                if (mounted) {
                  debugPrint(
                    '🧪 INSCRIÇÕES: abrindo planejador de aula experimental para $destinatarioTipo',
                  );
                  _planejarAulaExperimental(
                    inscricaoId: inscricaoId,
                    inscricao: inscricao,
                    numero: numero ?? '',
                    destinatarioNome: nome,
                    destinatarioTipo: destinatarioTipo,
                  );
                }
              });
            }
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: temContato
              ? Color.alphaBlend(cor.withAlpha(26), context.uai.cardAlt)
              : context.uai.cardAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: temContato ? cor.withAlpha(46) : context.uai.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: temContato ? cor.withAlpha(26) : context.uai.surface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: SvgPicture.asset(
                'assets/images/whatsapp.svg',
                height: 20,
                width: 20,
                colorFilter: ColorFilter.mode(
                  temContato
                      ? _safeAccent(cor, context.uai.cardAlt)
                      : context.uai.textMuted,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: temContato
                          ? _safeAccent(cor, context.uai.cardAlt)
                          : context.uai.textMuted,
                    ),
                  ),
                  if ((nome ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      nome!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: context.uai.textPrimary.withAlpha((255.0 * (
                          temContato ? 0.82 : 0.45)).round()),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    temContato
                        ? 'Enviar convite para aula experimental'
                        : 'Contato não informado',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.8,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      color: context.uai.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermoCard({
    required bool temAssinatura,
    required VoidCallback onTap,
  }) {
    final color = temAssinatura ? context.uai.success : context.uai.warning;
    final accent = _safeAccent(color, context.uai.cardAlt);
    final bg = Color.alphaBlend(color.withAlpha(26), context.uai.cardAlt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withAlpha(51)),
        ),
        child: Row(
          children: [
            Icon(
              temAssinatura ? Icons.draw_rounded : Icons.description_rounded,
              color: accent,
              size: 28,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temAssinatura
                        ? 'Termo assinado digitalmente'
                        : 'Termo aceito sem assinatura',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Toque para visualizar o termo completo.',
                    style: TextStyle(
                      color: context.uai.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accent),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _screenAccent().withAlpha(26),
                    context.uai.cardAlt,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _screenAccent().withAlpha(36)),
                ),
                child: Icon(icon, color: _screenAccent(), size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required dynamic value,
    VoidCallback? onTap,
  }) {
    final text = _texto(value);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: context.uai.cardAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.uai.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: _screenAccent(), size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.uai.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.2,
                      color: onTap == null
                          ? context.uai.textPrimary
                          : _safeAccent(context.uai.info, context.uai.cardAlt),
                      fontWeight: FontWeight.w800,
                      decoration: onTap == null
                          ? null
                          : TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: context.uai.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return _buildInfoTile(
      icon: Icons.info_outline_rounded,
      label: label,
      value: value,
    );
  }

  Widget _buildInfoRowClickable(
    String label,
    String? value,
    VoidCallback onTap,
  ) {
    return _buildInfoTile(
      icon: Icons.touch_app_rounded,
      label: label,
      value: value,
      onTap: onTap,
    );
  }

  Future<void> _atualizarContadorTurma(String turmaId) async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      await _firestore.collection('turmas').doc(turmaId).update({
        'alunos_count': snapshot.docs.length,
        'alunos_ativos': snapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      developer.log('Erro ao atualizar contador da turma: $e');
    }
  }

  Future<void> _atualizarContadorInscricoes() async {
    if (widget.operations != null) {
      await widget.operations!.updateCounter();
      return;
    }
    try {
      final snapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'total_inscricoes': snapshot.docs.length,
      }, SetOptions(merge: true));
    } catch (e) {
      developer.log('Erro ao atualizar contador: $e');
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _temTexto(dynamic value) {
    return value?.toString().trim().isNotEmpty == true;
  }

  String _texto(dynamic value, {String fallback = 'Não informado'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  DateTime? _parseDataNascimento(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    final texto = value.toString().trim();
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso;

    for (final formato in ['dd/MM/yyyy', 'd/M/yyyy']) {
      try {
        return DateFormat(formato).parseStrict(texto);
      } catch (_) {}
    }

    return null;
  }

  int? _calcularIdade(dynamic dataNascimento) {
    final nascimento = _parseDataNascimento(dataNascimento);
    if (nascimento == null) return null;

    final hoje = DateTime.now();
    var idade = hoje.year - nascimento.year;
    final aindaNaoFezAniversario =
        hoje.month < nascimento.month ||
        (hoje.month == nascimento.month && hoje.day < nascimento.day);

    if (aindaNaoFezAniversario) idade--;
    if (idade < 0 || idade > 130) return null;

    return idade;
  }

  String _formatarIdade(dynamic dataNascimento) {
    final idade = _calcularIdade(dataNascimento);
    if (idade == null) return 'Não informado';
    return idade == 1 ? '1 ano' : '$idade anos';
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';

    if (partes.length == 1) {
      return partes.first.characters.first.toUpperCase();
    }

    return '${partes.first.characters.first}${partes.last.characters.first}'
        .toUpperCase();
  }

  Widget _buildFotoAvatar({
    required String? fotoUrl,
    required String nome,
    required double radius,
    Color? borderColor,
  }) {
    final temFoto = fotoUrl != null && fotoUrl.trim().isNotEmpty;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? context.uai.border,
          width: borderColor == null ? 1.5 : 2.5,
        ),
      ),
      child: ClipOval(
        child: temFoto
            ? CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: context.uai.cardAlt,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: context.uai.primary,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => _avatarFallback(nome),
              )
            : _avatarFallback(nome),
      ),
    );
  }

  Widget _avatarFallback(String nome) {
    return Container(
      color: Color.alphaBlend(
        context.uai.primary.withAlpha(26),
        context.uai.cardAlt,
      ),
      alignment: Alignment.center,
      child: Text(
        _iniciais(nome),
        style: TextStyle(
          color: context.uai.primary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildSmallStatusChip({required String label, required Color color}) {
    final t = context.uai;
    final accent = _safeAccent(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(26), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(41)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildEmptyDialogState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: context.uai.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textSecondary, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }

  Widget _buildHeroResumo(int total) {
    final t = context.uai;
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _safeHeaderGradient(),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withAlpha(36),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withAlpha(41)),
            ),
            child: Icon(
              Icons.assignment_turned_in_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                'Inscrições Pendentes',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Analise as inscrições recebidas, abra o termo, entre em contato, aprove ou arquive cada solicitação.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withAlpha(209),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildWhiteChip(
                    Icons.pending_actions_rounded,
                    '$total pendente${total == 1 ? '' : 's'}',
                  ),
                  _buildWhiteChip(
                    Icons.history_rounded,
                    'Histórico de inscrições',
                  ),
                  _buildWhiteChip(
                    Icons.class_rounded,
                    '${_turmas.length} turma${_turmas.length == 1 ? '' : 's'}',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, const SizedBox(height: 14), text]);
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteChip(IconData icon, String label) {
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _securityOf(Map<String, dynamic> data) {
    final raw = data['seguranca'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _securityFlagsOf(Map<String, dynamic> data) {
    final raw = _securityOf(data)['flags'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Color _securityColor(String nivel) {
    switch (nivel.toLowerCase()) {
      case 'alto':
        return context.uai.error;
      case 'moderado':
        return context.uai.warning;
      case 'atencao':
        return context.uai.warning;
      default:
        return context.uai.success;
    }
  }

  Widget _buildSecurityDetailCard(Map<String, dynamic> data) {
    final security = _securityOf(data);
    final flags = _securityFlagsOf(data);
    final score = (security['score'] as num?)?.toInt() ?? 0;
    final nivel = _texto(security['nivel'], fallback: 'normal').toLowerCase();

    return _buildSectionCard(
      icon: flags.isEmpty
          ? Icons.verified_user_rounded
          : Icons.gpp_maybe_rounded,
      title: 'Verificação da inscrição',
      children: [
        _buildInfoTile(
          icon: Icons.shield_rounded,
          label: 'Classificação',
          value: flags.isEmpty
              ? 'NORMAL • sem alertas'
              : '${nivel.toUpperCase()} • $score/100 • ${flags.length} alerta(s)',
        ),
        if (flags.isEmpty)
          _buildInfoTile(
            icon: Icons.check_circle_rounded,
            label: 'Triagem',
            value:
                'Nenhum sinal relevante foi detectado. A análise é apenas auxiliar.',
          ),
        ...flags.map(
          (flag) => _buildInfoTile(
            icon: Icons.warning_amber_rounded,
            label: _texto(flag['titulo'], fallback: 'Alerta'),
            value: _texto(
              flag['detalhe'],
              fallback: 'Confira os dados informados.',
            ),
          ),
        ),
        _buildInfoTile(
          icon: Icons.info_outline_rounded,
          label: 'Regra',
          value:
              'Alertas nunca bloqueiam a inscrição. Dados compartilhados de responsável não contam como duplicidade.',
        ),
      ],
    );
  }

  Widget _buildTimelineDetailCard(Map<String, dynamic> data) {
    final raw = data['timeline'];
    final events = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    if (events.isEmpty) return const SizedBox.shrink();

    String formatDate(dynamic value) {
      if (value is Timestamp) {
        return DateFormat('dd/MM/yyyy HH:mm').format(value.toDate());
      }
      if (value is DateTime)
        { return DateFormat('dd/MM/yyyy HH:mm').format(value); }
      return '';
    }

    return _buildSectionCard(
      icon: Icons.timeline_rounded,
      title: 'Linha do tempo',
      children: events.reversed.map((event) {
        final title = _texto(event['titulo'], fallback: 'Atualização');
        final desc = _texto(event['descricao'], fallback: '');
        final when = formatDate(event['data']);
        return _buildInfoTile(
          icon: Icons.circle_rounded,
          label: when.isEmpty ? title : '$title • $when',
          value: desc,
        );
      }).toList(),
    );
  }

  Widget _buildFiltrosTriagem(int total, int comAlertas) {
    final t = context.uai;

    Widget chip(String value, String label, IconData icon, Color color) {
      final selected = _filtroTriagem == value;
      final accent = _safeAccent(color, t.card);
      return ChoiceChip(
        selected: selected,
        onSelected: (_) => setState(() => _filtroTriagem = value),
        avatar: Icon(
          icon,
          size: 16,
          color: selected ? _readableOn(accent) : accent,
        ),
        label: Text(label),
        selectedColor: accent,
        backgroundColor: t.card,
        side: BorderSide(color: selected ? accent : t.border),
        labelStyle: TextStyle(
          color: selected ? _readableOn(accent) : t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('todas', 'Todas ($total)', Icons.inbox_rounded, t.info),
          chip(
            'alertas',
            'Com alerta ($comAlertas)',
            Icons.gpp_maybe_rounded,
            comAlertas > 0 ? t.error : t.success,
          ),
          chip(
            'aula',
            'Aula agendada',
            Icons.event_available_rounded,
            t.success,
          ),
          chip('novas', 'Novas', Icons.fiber_new_rounded, t.warning),
        ],
      ),
    );
  }

  Map<String, dynamic> _aulaExperimentalOf(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(data['aula_experimental'] as Map? ?? const {});
  }

  String _formatarAulaExperimental(Map<String, dynamic> data) {
    final aula = _aulaExperimentalOf(data);
    if (aula.isEmpty) return '';
    final dataTexto = _texto(aula['data_formatada'], fallback: 'Data não informada');
    final inicio = _texto(aula['horario_inicio'], fallback: 'horário não informado');
    final fim = _texto(aula['horario_fim'], fallback: '');
    return '$dataTexto • $inicio${fim.isNotEmpty ? ' às $fim' : ''}';
  }

  Future<void> _remarcarPeloCard(String docId, Map<String, dynamic> data) async {
    final aula = _aulaExperimentalOf(data);
    var tipo = _texto(aula['destinatario_tipo'], fallback: 'responsavel') == 'aluno'
        ? 'aluno'
        : 'responsavel';
    if (tipo == 'aluno' && !_acoes.contatarAluno && _acoes.contatarResponsavel) {
      tipo = 'responsavel';
    } else if (tipo == 'responsavel' && !_acoes.contatarResponsavel && _acoes.contatarAluno) {
      tipo = 'aluno';
    }
    final numero = tipo == 'aluno'
        ? _texto(data['contato_aluno'], fallback: '')
        : _texto(data['contato_responsavel'], fallback: '');
    final nome = tipo == 'aluno'
        ? _texto(data['nome'], fallback: '')
        : _texto(data['nome_responsavel'], fallback: '');
    await _planejarAulaExperimental(
      inscricaoId: docId,
      inscricao: data,
      numero: numero,
      destinatarioNome: nome,
      destinatarioTipo: tipo,
    );
  }

  Widget _buildAgendamentoCard(String docId, Map<String, dynamic> data) {
    final aula = _aulaExperimentalOf(data);
    if (aula.isEmpty) return const SizedBox.shrink();
    final accent = _safeAccent(context.uai.success, context.uai.card);
    final turma = _texto(aula['turma_nome'], fallback: 'Turma não informada');
    final podeRemarcar = _acoes.contatarAluno || _acoes.contatarResponsavel;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withAlpha(46)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withAlpha(31),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_available_rounded, color: accent, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AULA EXPERIMENTAL',
                  style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .5),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatarAulaExperimental(data),
                  style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.w900, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  turma,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.uai.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (podeRemarcar)
            Tooltip(
              message: 'Alterar data da aula experimental',
              child: IconButton.filledTonal(
                onPressed: () => _remarcarPeloCard(docId, data),
                icon: const Icon(Icons.edit_calendar_rounded, size: 19),
              ),
            ),
        ],
      ),
    );
  }

  Color _cardStageColor(String etapa) {
    final stages = Map<String, dynamic>.from(
      _cardPendenteConfig['etapas'] as Map? ?? const {},
    );
    final style = Map<String, dynamic>.from(stages[etapa] as Map? ?? const {});
    final defaults = <String, String>{
      'nova': '#2E7D32',
      'interessado': '#00897B',
      'aula_agendada': '#1976D2',
      'aguardando_decisao': '#F57C00',
      'nao_compareceu_remarcar': '#8E24AA',
      'nao_compareceu': '#D32F2F',
      'sem_interesse': '#616161',
    };
    var raw = (style['cor'] ?? defaults[etapa] ?? '#1976D2').toString().trim();
    raw = raw.replaceAll('#', '');
    if (raw.length == 6) raw = 'FF$raw';
    final parsed = int.tryParse(raw, radix: 16);
    return parsed == null ? context.uai.info : Color(parsed);
  }

  String _cardStageLabel(Map<String, dynamic> data) {
    final etapa = _texto(data['etapa_atendimento'], fallback: 'nova');
    final stages = Map<String, dynamic>.from(
      _cardPendenteConfig['etapas'] as Map? ?? const {},
    );
    final style = Map<String, dynamic>.from(stages[etapa] as Map? ?? const {});
    final behavior = Map<String, dynamic>.from(
      _cardPendenteConfig['comportamento'] as Map? ?? const {},
    );
    final defaults = <String, String>{
      'nova': 'Nova inscrição',
      'interessado': 'Interessado',
      'aula_agendada': 'Aula experimental',
      'aguardando_decisao': 'Aguardando decisão',
      'nao_compareceu_remarcar': 'Remarcar aula',
      'nao_compareceu': 'Não compareceu',
      'sem_interesse': 'Sem interesse',
    };
    final base = (style['rotulo'] ?? defaults[etapa] ?? etapa.replaceAll('_', ' ')).toString();

    if (etapa == 'aula_agendada' && behavior['etapa_mostrar_agendamento'] != false) {
      final when = _formatarAulaExperimental(data);
      if (when.isNotEmpty) return '$base • $when';
    }

    if (etapa == 'nova' && behavior['nova_mostrar_data'] != false) {
      final dataCurta = _formatarDataCurta(data['data_inscricao']);
      if (dataCurta.isNotEmpty) return '$base • $dataCurta';
    }

    return base;
  }

  String _formatarDataCurta(dynamic value) {
    final dt = _parseDateTimeFlex(value);
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  DateTime? _parseDateTimeFlex(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    for (final format in ['dd/MM/yyyy HH:mm', 'dd/MM/yyyy', 'd/M/yyyy HH:mm', 'd/M/yyyy']) {
      try {
        return DateFormat(format).parseStrict(raw);
      } catch (_) {}
    }
    return null;
  }

  int? _diasDaInscricao(Map<String, dynamic> data) {
    final criada = _parseDateTimeFlex(data['data_inscricao']);
    if (criada == null) return null;
    final hoje = DateTime.now();
    final a = DateTime(criada.year, criada.month, criada.day);
    final b = DateTime(hoje.year, hoje.month, hoje.day);
    final dias = b.difference(a).inDays;
    return dias < 0 ? 0 : dias;
  }

  String _textoDiasInscricao(Map<String, dynamic> data) {
    final dias = _diasDaInscricao(data);
    if (dias == null) return '';
    if (dias == 0) return 'Hoje';
    if (dias == 1) return 'Há 1 dia';
    return 'Há $dias dias';
  }

  String _turmaAgendada(Map<String, dynamic> data) {
    final aula = _aulaExperimentalOf(data);
    return _texto(
      aula['turma_nome'] ?? data['turma_nome'],
      fallback: '',
    );
  }

  bool _cardBlockVisible(String key) {
    final vis = Map<String, dynamic>.from(
      _cardPendenteConfig['visibilidade'] as Map? ?? const {},
    );
    final version = _asInt(_cardPendenteConfig['versao']);
    if (version < 2) {
      if (key == 'responsavel') return false;
      if (key == 'turma' || key == 'dias') return true;
    }
    if (version < 3 && key == 'seta') return true;
    const defaults = <String, bool>{
      'foto': true,
      'telefone': true,
      'idade': true,
      'responsavel': false,
      'turma': true,
      'dias': true,
      'nome': true,
      'infos': true,
      'data': false,
      'termo': false,
      'alertas': true,
      'etapa': true,
      'seta': true,
    };
    return vis[key] is bool ? vis[key] as bool : (defaults[key] ?? true);
  }

  List<String> _cardBlockOrder() {
    const defaults = ['nome', 'infos', 'data', 'termo', 'alertas', 'etapa'];
    final raw = (_cardPendenteConfig['ordem'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final valid = raw.where(defaults.contains).toList();
    return [...valid, ...defaults.where((e) => !valid.contains(e))];
  }

  Map<String, dynamic> _cardAppearance() => Map<String, dynamic>.from(
        _cardPendenteConfig['aparencia'] as Map? ?? const {},
      );

  Color _hexColor(dynamic value, Color fallback) {
    var raw = (value ?? '').toString().trim().replaceAll('#', '');
    if (raw.length == 6) raw = 'FF$raw';
    final parsed = int.tryParse(raw, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  double _cardAppearanceDouble(String key, double fallback, {double? min, double? max}) {
    final value = (_cardAppearance()[key] as num?)?.toDouble() ?? fallback;
    if (min != null && value < min) return min;
    if (max != null && value > max) return max;
    return value;
  }

  Color _pendingCardBackground(Map<String, dynamic> data) {
    final t = context.uai;
    final ap = _cardAppearance();
    final mode = (ap['fundo_modo'] ?? 'tema').toString();
    if (mode == 'fixo') return _hexColor(ap['fundo_cor'], t.card);
    if (mode == 'etapa') {
      final stage = _texto(data['etapa_atendimento'], fallback: 'nova');
      final stageColor = _cardStageColor(stage);
      final opacity = ((ap['fundo_etapa_opacidade'] as num?)?.toDouble() ?? .09).clamp(0.02, .35);
      return Color.alphaBlend(stageColor.withAlpha((255.0 * (opacity)).round()), t.card);
    }
    return t.card;
  }

  BoxDecoration _pendingCardDecoration(Map<String, dynamic> data) {
    final t = context.uai;
    final ap = _cardAppearance();
    final bg = _pendingCardBackground(data);
    final customBorder = ap['borda_personalizada'] == true;
    final border = customBorder ? _hexColor(ap['borda_cor'], t.border) : t.border;
    final radius = _cardAppearanceDouble('raio', t.cardRadius, min: 8, max: 36);
    final shadow = ap['sombra'] is bool ? ap['sombra'] == true : true;
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: shadow ? t.softShadow : const [],
    );
  }

  Widget _buildCompactCardPhoto(String? fotoUrl, String nome, String docId) {
    final child = (fotoUrl ?? '').trim().isEmpty
        ? Container(
            color: context.uai.cardAlt,
            alignment: Alignment.center,
            child: Icon(Icons.person_rounded, size: 42, color: context.uai.textMuted),
          )
        : CachedNetworkImage(
            imageUrl: fotoUrl!,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: context.uai.cardAlt),
            errorWidget: (_, _, _) => Container(
              color: context.uai.cardAlt,
              alignment: Alignment.center,
              child: Icon(Icons.person_rounded, size: 42, color: context.uai.textMuted),
            ),
          );
    return GestureDetector(
      onTap: () => _abrirFotoTelaCheia(fotoUrl, nome),
      child: Hero(
        tag: 'foto_inscricao_$docId',
        child: ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(_cardAppearanceDouble('raio', 22, min: 8, max: 36)),
          ),
          child: SizedBox(
            width: _cardAppearanceDouble('foto_largura', 92, min: 64, max: 130),
            height: _cardAppearanceDouble('altura_minima', 118, min: 92, max: 160),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildEtapaCompacta(String docId, Map<String, dynamic> data) {
    final etapa = _texto(data['etapa_atendimento'], fallback: 'nova');
    final color = _safeAccent(_cardStageColor(etapa), context.uai.card);
    final podeRemarcar = etapa == 'aula_agendada' && (_acoes.contatarAluno || _acoes.contatarResponsavel);
    final label = _cardStageLabel(data);
    return InkWell(
      onTap: podeRemarcar ? () => _remarcarPeloCard(docId, data) : null,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: double.infinity,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withAlpha(23), context.uai.cardAlt),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withAlpha(51)),
        ),
        child: Row(children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(color: color, fontSize: 11.2, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ),
          if (podeRemarcar) ...[
            const SizedBox(width: 6),
            Icon(Icons.edit_calendar_rounded, size: 16, color: color),
          ],
        ]),
      ),
    );
  }

  Widget _buildInscricaoCard({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final nome = _texto(data['nome'], fallback: 'Nome não informado');
    final contato = _texto(data['contato_aluno'], fallback: 'Sem contato');
    final responsavel = _texto(data['nome_responsavel'], fallback: '');
    final turmaAgendada = _turmaAgendada(data);
    final diasInscricao = _textoDiasInscricao(data);
    final idade = _calcularIdade(data['data_nascimento']);
    final dataInscricao = formatarDataHoraInscricao(data['data_inscricao']);
    final fotoUrl = data['foto_url']?.toString();
    final temAssinatura = _temTexto(data['assinatura_url']);
    final blocos = <String, Widget>{
      'nome': Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              nome,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.uai.textPrimary, fontSize: 14.2, height: 1.02, fontWeight: FontWeight.w900),
            ),
          ),
          if (_cardBlockVisible('dias') && diasInscricao.isNotEmpty) ...[
            const SizedBox(width: 6),
            _buildDiasBadge(diasInscricao),
          ],
        ],
      ),
      'infos': Wrap(
        spacing: 6,
        runSpacing: 5,
        children: [
          if (_cardBlockVisible('telefone')) _buildMiniInfo(icon: Icons.phone_rounded, text: contato, color: context.uai.success),
          if (_cardBlockVisible('idade') && idade != null) _buildMiniInfo(icon: Icons.cake_rounded, text: idade == 1 ? '1 ano' : '$idade anos', color: context.uai.warning),
          if (_cardBlockVisible('turma') && turmaAgendada.isNotEmpty) _buildMiniInfo(icon: Icons.groups_2_rounded, text: turmaAgendada, color: context.uai.info),
          if (_cardBlockVisible('responsavel') && responsavel.isNotEmpty) _buildMiniInfo(icon: Icons.family_restroom_rounded, text: responsavel, color: context.uai.info),
        ],
      ),
      'data': Text(dataInscricao, style: TextStyle(color: context.uai.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
      'termo': Align(
        alignment: Alignment.centerLeft,
        child: _buildSmallStatusChip(label: temAssinatura ? 'TERMO ASSINADO' : 'TERMO ACEITO', color: temAssinatura ? context.uai.success : context.uai.warning),
      ),
      'alertas': _securityFlagsOf(data).isEmpty
          ? const SizedBox.shrink()
          : Align(alignment: Alignment.centerLeft, child: _buildSmallStatusChip(
              label: '⚠ ${_securityFlagsOf(data).length} ALERTA(S)',
              color: _securityColor(_texto(_securityOf(data)['nivel'], fallback: 'atencao')),
            )),
      'etapa': _buildEtapaCompacta(docId, data),
    };
    final order = _cardBlockOrder().where(_cardBlockVisible).toList();

    return InkWell(
      onTap: () => _mostrarDetalhesInscricao(docId, data),
      borderRadius: BorderRadius.circular(_cardAppearanceDouble('raio', 22, min: 8, max: 36)),
      child: Container(
        constraints: BoxConstraints(minHeight: _cardAppearanceDouble('altura_minima', 118, min: 92, max: 160)),
        decoration: _pendingCardDecoration(data),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (_cardBlockVisible('foto')) _buildCompactCardPhoto(fotoUrl, nome, docId),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _cardAppearanceDouble('padding_horizontal', 11, min: 6, max: 20),
                _cardAppearanceDouble('padding_vertical', 10, min: 5, max: 18),
                4,
                _cardAppearanceDouble('padding_vertical', 10, min: 5, max: 18) - 1,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < order.length; i++) ...[
                    blocos[order[i]] ?? const SizedBox.shrink(),
                    if (i != order.length - 1) SizedBox(height: _cardAppearanceDouble('espacamento_blocos', 5, min: 2, max: 12)),
                  ],
                ],
              ),
            ),
          ),
          if (_cardBlockVisible('seta'))
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: Icon(Icons.chevron_right_rounded, size: 24, color: context.uai.textMuted),
            ),
        ]),
      ),
    );
  }

  Widget _buildDiasBadge(String text) {
    final accent = _safeAccent(context.uai.textSecondary, context.uai.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(18), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(31)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse_rounded, size: 12, color: accent),
          const SizedBox(width: 3),
          Text(
            text,
            maxLines: 1,
            style: TextStyle(color: accent, fontSize: 9.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    final accent = _safeAccent(color, context.uai.card);
    final bg = Color.alphaBlend(accent.withAlpha(20), context.uai.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 74, color: context.uai.border),
              const SizedBox(height: 14),
              Text(
                'Nenhuma inscrição pendente',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Quando alguém preencher o formulário, a inscrição aparecerá aqui automaticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.uai.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 16),
              if (_permissoesCarregadas && _acoes.verHistorico)
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => InscricoesAprovadasDialog(
                        podeReativarArquivada: _acoes.reativarArquivada,
                        podeExcluirPermanente: _acoes.excluirPermanente,
                      ),
                    );
                  },
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('VER HISTÓRICO'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarExcluirInscricaoPermanentemente(
    BuildContext origemContext, {
    required String inscricaoId,
    required String nome,
    required bool arquivada,
  }) async {
    final confirmado = await showDialog<bool>(
      context: origemContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.uai.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: dialogContext.uai.error),
            const SizedBox(width: 10),
            const Expanded(child: Text('Excluir permanentemente?')),
          ],
        ),
        content: Text(
          'Esta ação apaga $nome definitivamente, incluindo dados, foto e assinatura no Storage. Não poderá ser desfeita.',
          style: TextStyle(
            color: dialogContext.uai.textSecondary,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: dialogContext.uai.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    BuildContext? loadingContext;
    showDialog<void>(
      context: origemContext,
      barrierDismissible: false,
      builder: (ctx) {
        loadingContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: ctx.uai.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: ctx.uai.error),
                  const SizedBox(height: 16),
                  const Text('Excluindo inscrição definitivamente...'),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      await _archiveService.excluirInscricaoPermanente(
        inscricaoId: inscricaoId,
        arquivada: arquivada,
      );
      if (loadingContext != null && mounted) Navigator.pop(loadingContext!);
      if (Navigator.canPop(origemContext)) Navigator.pop(origemContext);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Inscrição excluída permanentemente com sucesso.',
          ),
          backgroundColor: context.uai.success,
        ),
      );
    } catch (e) {
      if (loadingContext != null && mounted) Navigator.pop(loadingContext!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível excluir a inscrição: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  Widget _buildErrorScreen(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 70,
                color: context.uai.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar inscrições',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Tente novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.uai.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    final t = context.uai;

    return Container(
      color: t.background,
      padding: _dashboardPagePadding,
      child: Center(
        child: _dashboardWidthLimiter(
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(_isDesktopDashboard ? 30 : 24),
            decoration: _cardDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    color: _safeAccent(t.primary, t.card),
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Carregando inscrições...',
                  style: TextStyle(
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          MediaQuery.sizeOf(context).width < 460
              ? 'Inscrições'
              : 'Gerenciar Inscrições',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_permissoesCarregadas &&
              (_acoes.contatarAluno || _acoes.contatarResponsavel))
            IconButton(
              tooltip: 'Relatos de suporte',
              icon: const Icon(Icons.support_agent_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SuportesInscricaoScreen(),
                ),
              ),
            ),
          if (_permissoesCarregadas && (_acoes.verHistorico || _acoes.aprovar))
            IconButton(
              tooltip: 'Avaliações da inscrição',
              icon: const Icon(Icons.insights_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PainelAvaliacoesScreen(),
                ),
              ),
            ),

          if (_permissoesCarregadas && _acoes.verHistorico)
            IconButton(
              icon: const Icon(Icons.history_rounded),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => InscricoesAprovadasDialog(
                    podeReativarArquivada: _acoes.reativarArquivada,
                    podeExcluirPermanente: _acoes.excluirPermanente,
                  ),
                );
              },
              tooltip: 'Histórico de inscrições',
            ),
          // A engrenagem fica sempre como a última ação (extrema direita).
          // Ela só existe para admin ou usuário com a permissão específica.
          if (_permissoesCarregadas && _acoes.configurarInscricoes)
            IconButton(
              tooltip: 'Configurar inscrições',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConfigurarInscricoesScreen()),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<GerenciarInscricaoRecord>>(
        stream: _pendingRecords(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorScreen(snapshot.error);
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingScreen();
          }

          final inscricoes = snapshot.data ?? [];
          final comAlertas = inscricoes.where((doc) {
            final data = doc.data;
            return _securityFlagsOf(data).isNotEmpty;
          }).length;

          final exibidas = inscricoes.where((doc) {
            final data = doc.data;
            switch (_filtroTriagem) {
              case 'alertas':
                return _securityFlagsOf(data).isNotEmpty;
              case 'aula':
                return _texto(data['etapa_atendimento'], fallback: '') ==
                        'aula_agendada' ||
                    data['aula_experimental'] is Map;
              case 'novas':
                final etapa = _texto(
                  data['etapa_atendimento'],
                  fallback: 'nova',
                );
                return etapa == 'nova';
              default:
                return true;
            }
          }).toList();

          if (inscricoes.isEmpty) {
            return _buildEmptyScreen();
          }

          return ListView(
            padding: _dashboardPagePadding,
            children: [
              _dashboardWidthLimiter(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroResumo(inscricoes.length),
                    const SizedBox(height: 12),
                    _buildFiltrosTriagem(inscricoes.length, comAlertas),
                    const SizedBox(height: 14),
                    if (exibidas.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: _cardDecoration(),
                        child: Text(
                          'Nenhuma inscrição corresponde a este filtro.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.uai.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      _dashboardResponsiveWrap(
                        children: exibidas.map((doc) {
                          final data = doc.data;
                          return _buildInscricaoCard(docId: doc.id, data: data);
                        }).toList(),
                        minItemWidth: 410,
                        maxColumns: _isDesktopDashboard ? 2 : 2,
                        spacing: 12,
                        runSpacing: 12,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 10:47
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
