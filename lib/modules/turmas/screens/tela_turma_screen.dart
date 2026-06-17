import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/chamadas/screens/chamada_turma_screen.dart';
import 'package:uai_capoeira/modules/chamadas/screens/listas_chamada_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/alunos_turma_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/avaliacao_alunos_turma_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/dashboard_turmas_page.dart';

class TelaTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const TelaTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<TelaTurmaScreen> createState() => _TelaTurmaScreenState();
}

class _TelaTurmaScreenState extends State<TelaTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<dynamic>? _connectivitySubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permissoesSub;

  bool _isLoading = true;
  bool _isLoadingPermissoes = true;
  bool _temInternet = true;

  Map<String, dynamic> _dadosTurma = {};
  Map<String, dynamic> _permissoes = {};

  Color _corTurmaFallback = const Color(0xFFB71C1C);

  bool _carregandoAlertasIndicadores = false;
  List<_AlunoAlertaTurma> _alertasIndicadoresTurma = [];

  @override
  void initState() {
    super.initState();
    _monitorarConexao();
    _carregarDadosTurma();
    _inicializarPermissoesInteligente();
    _carregarResumoAlertasTurma();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _permissoesSub?.cancel();
    super.dispose();
  }

  void _monitorarConexao() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      final online = _isOnlineFromConnectivity(result);
      final voltou = !_temInternet && online;

      if (!mounted) return;

      setState(() => _temInternet = online);

      if (voltou) {
        _recarregarPermissoes();
      }
    });

    _verificarInternetInicial();
  }

  Future<void> _verificarInternetInicial() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (!mounted) return;
      setState(() => _temInternet = _isOnlineFromConnectivity(result));
    } catch (_) {
      if (mounted) setState(() => _temInternet = false);
    }
  }

  bool _isOnlineFromConnectivity(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.any((item) => item != ConnectivityResult.none);
    }

    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }

    return true;
  }

  bool _temPermissao(String permissao) {
    final valor = _permissoes[permissao];

    if (valor == true) return true;
    if (valor is String) {
      final normalizado = valor.toLowerCase().trim();
      return normalizado == 'true' || normalizado == '1' || normalizado == 'sim';
    }
    if (valor is num) return valor == 1;

    return false;
  }

  Future<void> _inicializarPermissoesInteligente() async {
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _isLoadingPermissoes = false);
      return;
    }

    try {
      try {
        final cacheDoc = await _firestore
            .collection('usuarios')
            .doc(user.uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(const GetOptions(source: Source.cache));

        if (cacheDoc.exists && mounted) {
          setState(() {
            _permissoes = cacheDoc.data() ?? {};
            _isLoadingPermissoes = false;
          });
        }
      } catch (_) {}

      final online = await _temInternetAgora();

      if (online) {
        _configurarStreamPermissoes(user.uid);
      } else if (mounted) {
        setState(() => _isLoadingPermissoes = false);
      }
    } catch (e) {
      debugPrint('Erro ao inicializar permissões: $e');
      if (mounted) setState(() => _isLoadingPermissoes = false);
    }
  }

  void _configurarStreamPermissoes(String uid) {
    _permissoesSub?.cancel();

    _permissoesSub = _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('permissoes_usuario')
        .doc('configuracoes')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
        if (!snapshot.exists || !mounted) return;

        setState(() {
          _permissoes = snapshot.data() ?? {};
          _isLoadingPermissoes = false;
        });
      },
      onError: (error) {
        debugPrint('Erro no stream de permissões: $error');
        if (mounted) setState(() => _isLoadingPermissoes = false);
      },
    );
  }

  Future<void> _recarregarPermissoes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(user.uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get(const GetOptions(source: Source.server));

      if (!mounted || !doc.exists) return;

      setState(() => _permissoes = doc.data() ?? {});
    } catch (e) {
      debugPrint('Erro ao recarregar permissões: $e');
    }
  }

  Future<bool> _temInternetAgora() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _isOnlineFromConnectivity(result);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _temInternetParaAcao() async {
    final online = await _temInternetAgora();

    if (!online) {
      _mostrarMensagem(
        'Modo offline. Conecte-se à internet para esta ação.',
        context.uai.warning,
        icon: Icons.wifi_off_rounded,
      );
      return false;
    }

    return true;
  }

  Future<void> _carregarDadosTurma() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      DocumentSnapshot<Map<String, dynamic>> turmaDoc;

      try {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.server));
      }

      if (!mounted) return;

      if (turmaDoc.exists) {
        final data = turmaDoc.data() ?? {};

        setState(() {
          _dadosTurma = data;
          _corTurmaFallback = _getColorFromHex(
            data['cor_turma']?.toString() ?? '#B71C1C',
            fallback: context.uai.primary,
          );
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados da turma: $e');

      if (mounted) {
        _mostrarMensagem(
          'Erro ao carregar dados da turma.',
          context.uai.error,
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getColorFromHex(String hexColor, {Color? fallback}) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return fallback ?? context.uai.primary;
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimaryText(UaiThemeTokens t) {
    // Cabeçalhos com primaryGradient precisam ficar legíveis nos 4 temas oficiais.
    // No Verde Neon, o primary pode ser claro, mas o tema inteiro é dark;
    // se usar _readableOn(primary), o texto fica escuro e perde leitura no card.
    final temaEscuro = t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;

    if (temaEscuro) return Colors.white;

    return _readableOn(t.primary);
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _turmaNome() {
    return _dadosTurma['nome']?.toString() ?? widget.turmaNome;
  }

  String _horarioDisplay() {
    final display = _dadosTurma['horario_display']?.toString() ?? '';
    if (display.isNotEmpty) return display;

    final inicio = _dadosTurma['horario_inicio']?.toString() ?? '';
    final fim = _dadosTurma['horario_fim']?.toString() ?? '';

    if (inicio.isNotEmpty && fim.isNotEmpty) {
      return '$inicio - $fim';
    }

    return '';
  }

  String _diasSemanaTexto() {
    final display = _dadosTurma['dias_semana_display'];
    final dias = _dadosTurma['dias_semana'];

    if (display is List && display.isNotEmpty) {
      return display.join(', ');
    }

    if (dias is List && dias.isNotEmpty) {
      return dias.join(', ');
    }

    return '';
  }

  Future<void> _validarEAbrirChamada() async {
    if (!_temPermissao('pode_fazer_chamada')) {
      _mostrarMensagem(
        'Você não tem permissão para realizar chamadas.',
        context.uai.error,
        icon: Icons.lock_rounded,
      );
      return;
    }

    if (!await _temInternetParaAcao()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _mostrarMensagem(
        'Usuário não logado.',
        context.uai.error,
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChamadaTurmaScreen(
          turmaId: widget.turmaId,
          turmaNome: _turmaNome(),
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
          usuarioId: user.uid,
        ),
      ),
    );
  }

  Future<void> _validarEAbrirAvaliacaoAluno() async {
    if (!_temPermissao('pode_avaliar_aluno')) {
      _mostrarMensagem(
        'Você não tem permissão para avaliar alunos.',
        context.uai.error,
        icon: Icons.lock_rounded,
      );
      return;
    }

    if (!await _temInternetParaAcao()) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AvaliacaoAlunosTurmaScreen(
          turmaId: widget.turmaId,
          turmaNome: _turmaNome(),
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
        ),
      ),
    );
  }

  void _mostrarMensagem(
      String mensagem,
      Color cor, {
        IconData icon = Icons.info_outline_rounded,
      }) {
    final onColor = _readableOn(cor);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: onColor, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                mensagem,
                style: TextStyle(
                  color: onColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final t = context.uai;

    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);

    return AppBar(
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      elevation: 0,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _turmaNome().toUpperCase(),
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: appBarFg,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            widget.academiaNome,
            style: TextStyle(
              fontSize: 12,
              color: appBarFg.withOpacity(0.82),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        if (!_temInternet)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.wifi_off_rounded, color: t.warning, size: 19),
          ),
        IconButton(
          onPressed: _carregarDadosTurma,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Atualizar',
        ),
      ],
    );
  }

  Widget _buildLogoTurma({
    required String logoUrl,
    required UaiThemeTokens t,
    double size = 74,
  }) {
    if (logoUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius - 8),
          border: Border.all(color: t.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.cardRadius - 10),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _fallbackLogo(t, size),
            placeholder: (_, __) => Center(
              child: SizedBox(
                width: size * 0.30,
                height: size * 0.30,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.primary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _fallbackLogo(t, size);
  }

  Widget _fallbackLogo(UaiThemeTokens t, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _onPrimaryText(t).withOpacity(0.14),
        borderRadius: BorderRadius.circular(t.cardRadius - 8),
        border: Border.all(color: _onPrimaryText(t).withOpacity(0.16)),
      ),
      child: Icon(
        Icons.class_rounded,
        size: size * 0.46,
        color: _onPrimaryText(t),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final t = context.uai;
    final onPrimary = _onPrimaryText(t);
    final logoUrl = _dadosTurma['logo_url']?.toString() ?? '';
    final alunosAtivos = _parseInt(_dadosTurma['alunos_ativos'], 0);
    final capacidade = _parseInt(_dadosTurma['capacidade_maxima'], 0);
    final dias = _diasSemanaTexto();
    final horario = _horarioDisplay();
    final nivel = _dadosTurma['nivel']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: t.primaryGradient,
          borderRadius: BorderRadius.circular(t.cardRadius + 2),
          boxShadow: t.cardShadow,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;

            final logo = _buildLogoTurma(logoUrl: logoUrl, t: t, size: narrow ? 70 : 78);

            final content = Column(
              crossAxisAlignment:
              narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  _turmaNome().toUpperCase(),
                  textAlign: narrow ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: narrow ? 23 : 27,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Text(
                  widget.academiaNome,
                  textAlign: narrow ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.84),
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 13),
                Wrap(
                  alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _whiteChip(
                      icon: Icons.people_rounded,
                      label: '$alunosAtivos/$capacidade alunos',
                    ),
                    if (dias.isNotEmpty)
                      _whiteChip(
                        icon: Icons.calendar_today_rounded,
                        label: dias,
                      ),
                    if (horario.isNotEmpty)
                      _whiteChip(
                        icon: Icons.access_time_rounded,
                        label: horario,
                      ),
                    if (nivel.isNotEmpty)
                      _whiteChip(
                        icon: Icons.star_rounded,
                        label: nivel,
                      ),
                  ],
                ),
              ],
            );

            if (narrow) {
              return Column(
                children: [
                  logo,
                  SizedBox(height: 14),
                  content,
                ],
              );
            }

            return Row(
              children: [
                logo,
                SizedBox(width: 16),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _whiteChip({
    required IconData icon,
    required String label,
  }) {
    final t = context.uai;
    final onPrimary = _onPrimaryText(t);

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle() {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: t.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
              child: Icon(Icons.dashboard_customize_rounded, color: t.primary),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Painel da turma',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: t.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Acesse as ações disponíveis para esta turma.',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
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


  bool _isStatusAlunoAtivo(dynamic value) {
    final status = value?.toString().trim().toUpperCase() ?? '';
    return status == 'ATIVO(A)' || status == 'ATIVO(A) ' || status == 'ATIVO';
  }

  String _limparNumeroContato(String? numero) {
    if (numero == null) return '';
    return numero.replaceAll(RegExp(r'[^0-9+]'), '').trim();
  }

  bool _temContatoValido(String? numero) {
    final limpo = _limparNumeroContato(numero);
    return limpo.replaceAll('+', '').length >= 8;
  }

  String _formatarNumeroWhatsApp(String numero) {
    String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanedPhone.startsWith('0')) {
      cleanedPhone = cleanedPhone.substring(1);
    }
    if (!cleanedPhone.startsWith('55')) {
      cleanedPhone = '55$cleanedPhone';
    }
    return cleanedPhone;
  }

  Future<void> _launchPhoneContato(String numero) async {
    try {
      String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9+]'), '');

      if (!cleanedPhone.startsWith('+')) {
        if (cleanedPhone.startsWith('0')) {
          cleanedPhone = cleanedPhone.substring(1);
        }
        cleanedPhone = '+55$cleanedPhone';
      }

      final url = Uri.parse('tel:$cleanedPhone');

      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw Exception('Não foi possível abrir o telefone');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem(
        'Não foi possível realizar a chamada.',
        context.uai.error,
        icon: Icons.phone_disabled_rounded,
      );
    }
  }

  Future<void> _abrirWhatsAppContato(String numero, String mensagem) async {
    try {
      final cleanedPhone = _formatarNumeroWhatsApp(numero);
      final url = Uri.parse(
        'https://wa.me/$cleanedPhone?text=${Uri.encodeComponent(mensagem)}',
      );

      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        final webUrl = Uri.parse(
          'https://web.whatsapp.com/send?phone=$cleanedPhone&text=${Uri.encodeComponent(mensagem)}',
        );
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem(
        'Não foi possível abrir o WhatsApp.',
        context.uai.error,
        icon: Icons.sms_failed_rounded,
      );
    }
  }

  DateTime? _dateTimeAlertaSeguro(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    if (value is String) {
      final texto = value.trim();
      if (texto.isEmpty) return null;

      final iso = DateTime.tryParse(texto);
      if (iso != null) return iso;

      final partes = texto.split('/');
      if (partes.length == 3) {
        final dia = int.tryParse(partes[0]);
        final mes = int.tryParse(partes[1]);
        final ano = int.tryParse(partes[2]);
        if (dia != null && mes != null && ano != null) {
          return DateTime(ano, mes, dia);
        }
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

  DateTime? _ultimaPresencaAlerta(Map<String, dynamic> aluno) {
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
      final data = _dateTimeAlertaSeguro(campo);
      if (data != null) return data;
    }

    return null;
  }

  int _diasSemPresencaAlerta(Map<String, dynamic> aluno) {
    final ultima = _ultimaPresencaAlerta(aluno);
    if (ultima == null) return 9999;

    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final ultimaLimpa = DateTime(ultima.year, ultima.month, ultima.day);
    final dias = hojeLimpo.difference(ultimaLimpa).inDays;
    return dias < 0 ? 0 : dias;
  }

  String _formatarDataSimples(DateTime? data) {
    if (data == null) return 'Sem registro';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  List<Map<String, dynamic>> _faixasIndicadoresPadraoTurma() {
    return [
      {
        'ate_dias': 3,
        'cor': '#2196F3',
        'label': 'Frequente',
        'gera_alerta': false,
      },
      {
        'ate_dias': 6,
        'cor': '#4CAF50',
        'label': 'Regular',
        'gera_alerta': false,
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

  String _mensagemPadraoAlerta() {
    return 'Olá! Tudo bem? Aqui é da UAI Capoeira. Sentimos falta de {nome_aluno} nos treinos da turma {turma}. '
        'A última presença registrada foi {ultima_presenca}. Podemos contar com a presença dele(a) nos próximos treinos?';
  }

  Map<String, dynamic>? _faixaAtualAlerta({
    required int dias,
    required List<Map<String, dynamic>> faixas,
  }) {
    final ordenadas = [...faixas];
    ordenadas.sort((a, b) {
      final aDias = _parseInt(a['ate_dias'], 9999);
      final bDias = _parseInt(b['ate_dias'], 9999);
      return aDias.compareTo(bDias);
    });

    for (final faixa in ordenadas) {
      final ateDias = _parseInt(faixa['ate_dias'], 9999);
      if (dias <= ateDias) return faixa;
    }

    return ordenadas.isNotEmpty ? ordenadas.last : null;
  }

  String _mensagemAlertaFormatada(_AlunoAlertaTurma alerta) {
    final template = alerta.mensagem.trim().isNotEmpty
        ? alerta.mensagem.trim()
        : _mensagemPadraoAlerta();

    final diasTexto = alerta.dias >= 9999
        ? 'sem registro'
        : '${alerta.dias} dia${alerta.dias == 1 ? '' : 's'}';

    return template
        .replaceAll('{nome_aluno}', alerta.nome)
        .replaceAll('{nome}', alerta.nome)
        .replaceAll('{turma}', _turmaNome())
        .replaceAll('{indicador}', alerta.indicador)
        .replaceAll('{dias}', diasTexto)
        .replaceAll('{ultima_presenca}', _formatarDataSimples(alerta.ultimaPresenca));
  }

  Future<void> _carregarResumoAlertasTurma() async {
    if (!mounted) return;

    setState(() => _carregandoAlertasIndicadores = true);

    try {
      DocumentSnapshot<Map<String, dynamic>> configDoc;

      try {
        configDoc = await _firestore
            .collection('configuracoes_sistema')
            .doc('indicadores_ausencia')
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        configDoc = await _firestore
            .collection('configuracoes_sistema')
            .doc('indicadores_ausencia')
            .get(const GetOptions(source: Source.cache));
      }

      final config = configDoc.data() ?? {};
      if (config['ativo'] == false) {
        if (mounted) {
          setState(() {
            _alertasIndicadoresTurma = [];
            _carregandoAlertasIndicadores = false;
          });
        }
        return;
      }

      final faixasRaw = config['faixas'];
      final faixas = faixasRaw is List
          ? faixasRaw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
          : _faixasIndicadoresPadraoTurma();

      QuerySnapshot<Map<String, dynamic>> alunosSnapshot;

      try {
        alunosSnapshot = await _firestore
            .collection('alunos')
            .where('turma_id', isEqualTo: widget.turmaId)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        alunosSnapshot = await _firestore
            .collection('alunos')
            .where('turma_id', isEqualTo: widget.turmaId)
            .get(const GetOptions(source: Source.cache));
      }

      final alertas = <_AlunoAlertaTurma>[];

      for (final doc in alunosSnapshot.docs) {
        final data = doc.data();

        if (!_isStatusAlunoAtivo(data['status_atividade'])) continue;

        final dias = _diasSemPresencaAlerta(data);
        final faixa = _faixaAtualAlerta(dias: dias, faixas: faixas);

        if (faixa == null || faixa['gera_alerta'] != true) continue;

        final nome = data['nome']?.toString().trim() ?? 'Aluno';
        final cor = _getColorFromHex(
          faixa['cor']?.toString() ?? '#F44336',
          fallback: context.uai.warning,
        );

        alertas.add(
          _AlunoAlertaTurma(
            alunoId: doc.id,
            nome: nome,
            indicador: faixa['label']?.toString().trim().isNotEmpty == true
                ? faixa['label'].toString().trim()
                : 'Alerta',
            cor: cor,
            dias: dias,
            ultimaPresenca: _ultimaPresencaAlerta(data),
            fotoUrl: data['foto_perfil_aluno']?.toString() ??
                data['foto']?.toString() ??
                data['foto_url']?.toString() ??
                '',
            contatoAluno: data['contato_aluno']?.toString() ?? '',
            contatoResponsavel: data['contato_responsavel']?.toString() ?? '',
            nomeResponsavel: data['nome_responsavel']?.toString() ??
                data['responsavel']?.toString() ??
                data['responsavel_nome']?.toString() ??
                'Responsável',
            mensagem: faixa['mensagem_alerta']?.toString() ?? '',
          ),
        );
      }

      alertas.sort((a, b) {
        final dias = b.dias.compareTo(a.dias);
        if (dias != 0) return dias;
        return a.nome.compareTo(b.nome);
      });

      if (mounted) {
        setState(() {
          _alertasIndicadoresTurma = alertas;
          _carregandoAlertasIndicadores = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar alertas de indicadores: $e');

      if (mounted) {
        setState(() {
          _alertasIndicadoresTurma = [];
          _carregandoAlertasIndicadores = false;
        });
      }
    }
  }

  Widget _buildBadgeAlertasIndicadores() {
    final total = _alertasIndicadoresTurma.length;
    final t = context.uai;

    if (_carregandoAlertasIndicadores) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: t.warning,
          ),
        ),
      );
    }

    if (total <= 0) return const SizedBox.shrink();

    return Tooltip(
      message: '$total aluno${total == 1 ? '' : 's'} em alerta',
      child: GestureDetector(
        onTap: _mostrarDialogoAlertasIndicadores,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: t.warning.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.warning.withOpacity(0.36)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: t.warning,
                  size: 25,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.error,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: t.card, width: 2),
                  ),
                  child: Text(
                    total > 99 ? '99+' : '$total',
                    style: TextStyle(
                      color: _readableOn(t.error),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<_AlunoAlertaTurma>> _alertasAgrupadosPorIndicador() {
    final grupos = <String, List<_AlunoAlertaTurma>>{};

    for (final alerta in _alertasIndicadoresTurma) {
      grupos.putIfAbsent(alerta.indicador, () => []).add(alerta);
    }

    return grupos;
  }

  Future<void> _mostrarDialogoAlertasIndicadores() async {
    if (_alertasIndicadoresTurma.isEmpty) {
      await _carregarResumoAlertasTurma();
    }

    if (!mounted) return;

    if (_alertasIndicadoresTurma.isEmpty) {
      _mostrarMensagem(
        'Nenhum aluno em alerta nesta turma.',
        context.uai.success,
        icon: Icons.check_circle_rounded,
      );
      return;
    }

    final grupos = _alertasAgrupadosPorIndicador();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.warning.withOpacity(0.10),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(t.cardRadius + 4),
                      topRight: Radius.circular(t.cardRadius + 4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: t.warning.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: t.warning),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Alunos em alerta',
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_alertasIndicadoresTurma.length} aluno${_alertasIndicadoresTurma.length == 1 ? '' : 's'} precisam de atenção nesta turma.',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: Icon(Icons.close_rounded, color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(14),
                    children: grupos.entries.map((entry) {
                      final alunos = entry.value;
                      final cor = alunos.first.cor;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(cor.withOpacity(0.07), t.card),
                          borderRadius: BorderRadius.circular(t.cardRadius),
                          border: Border.all(color: cor.withOpacity(0.20)),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: cor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${entry.key} (${alunos.length})',
                                      style: TextStyle(
                                        color: _readableOn(t.card),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: t.border),
                            ...alunos.map((aluno) {
                              final diasTexto = aluno.dias >= 9999
                                  ? 'Sem presença registrada'
                                  : aluno.dias == 0
                                  ? 'Última presença hoje'
                                  : 'Última presença há ${aluno.dias} dia${aluno.dias == 1 ? '' : 's'}';

                              return ListTile(
                                dense: true,
                                onTap: () {
                                  Navigator.pop(dialogContext);
                                  _mostrarOpcoesContatoAlerta(aluno);
                                },
                                leading: _buildAlunoAlertaAvatar(
                                  aluno,
                                  radius: 18,
                                ),
                                title: Text(
                                  aluno.nome,
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  diasTexto,
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                                trailing: Icon(Icons.contact_phone_rounded, color: cor),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _mostrarOpcoesContatoAlerta(_AlunoAlertaTurma alerta) async {
    final mensagem = _mensagemAlertaFormatada(alerta);
    final destinos = <Map<String, String>>[];

    if (_temContatoValido(alerta.contatoResponsavel)) {
      destinos.add({
        'tipo': 'Responsável',
        'nome': alerta.nomeResponsavel,
        'numero': alerta.contatoResponsavel,
      });
    }

    if (_temContatoValido(alerta.contatoAluno) &&
        _limparNumeroContato(alerta.contatoAluno) !=
            _limparNumeroContato(alerta.contatoResponsavel)) {
      destinos.add({
        'tipo': 'Aluno',
        'nome': alerta.nome,
        'numero': alerta.contatoAluno,
      });
    }

    if (destinos.isEmpty) {
      _mostrarMensagem(
        'Nenhum contato válido cadastrado para ${alerta.nome}.',
        context.uai.error,
        icon: Icons.contact_phone_rounded,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final t = context.uai;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _buildAlunoAlertaAvatar(
                      alerta,
                      radius: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alerta.nome,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${alerta.indicador} • ${alerta.dias >= 9999 ? 'sem registro' : '${alerta.dias} dias sem presença'}',
                            style: TextStyle(
                              color: alerta.cor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    mensagem,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...destinos.map((destino) {
                  final numero = destino['numero']!;
                  final tipo = destino['tipo']!;
                  final nome = destino['nome']!;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: t.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              tipo == 'Responsável'
                                  ? Icons.family_restroom_rounded
                                  : Icons.person_rounded,
                              color: tipo == 'Responsável' ? t.primary : t.info,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '$tipo • $nome',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _launchPhoneContato(numero);
                                },
                                icon: const Icon(Icons.call_rounded, size: 18),
                                label: const Text('Ligar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.primary,
                                  foregroundColor: _readableOn(t.primary),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _abrirWhatsAppContato(numero, mensagem);
                                },
                                icon: SvgPicture.asset(
                                  'assets/images/whatsapp.svg',
                                  width: 18,
                                  height: 18,
                                  color: _readableOn(t.success),
                                ),
                                label: const Text('WhatsApp'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.success,
                                  foregroundColor: _readableOn(t.success),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildAlunoAlertaAvatar(
      _AlunoAlertaTurma alerta, {
        double radius = 18,
      }) {
    final fotoUrl = alerta.fotoUrl.trim();
    final size = radius * 2;
    final inicial = alerta.nome.trim().isNotEmpty
        ? alerta.nome.trim()[0].toUpperCase()
        : '?';

    Widget fallback() {
      return Container(
        color: alerta.cor.withOpacity(0.16),
        alignment: Alignment.center,
        child: Text(
          inicial,
          style: TextStyle(
            color: alerta.cor,
            fontSize: radius * 0.78,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: alerta.cor.withOpacity(0.55),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: fotoUrl.isNotEmpty &&
            (fotoUrl.startsWith('http://') || fotoUrl.startsWith('https://'))
            ? CachedNetworkImage(
          imageUrl: fotoUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => fallback(),
          errorWidget: (_, __, ___) => fallback(),
        )
            : fallback(),
      ),
    );
  }

  Widget _buildFunctionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required String permissao,
    Widget? extraTrailing,
  }) {
    if (!_temPermissao(permissao)) {
      return SizedBox.shrink();
    }

    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: color.withOpacity(0.12),
          highlightColor: color.withOpacity(0.06),
          child: Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: color.withOpacity(0.14)),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 47,
                  height: 47,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                  child: Icon(icon, size: 25, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 11.5,
                          height: 1.24,
                        ),
                      ),
                      if (!_temInternet) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 12, color: t.warning),
                            const SizedBox(width: 4),
                            Text(
                              'offline',
                              style: TextStyle(
                                fontSize: 10,
                                color: t.warning,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                if (extraTrailing != null) ...[
                  extraTrailing,
                  SizedBox(width: 8),
                ],
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActionCards() {
    return [
      _buildFunctionCard(
        icon: Icons.person_search_rounded,
        title: 'Ver alunos',
        subtitle: 'Lista completa de alunos',
        color: context.uai.associacao,
        permissao: 'pode_visualizar_alunos',
        extraTrailing: _buildBadgeAlertasIndicadores(),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlunosTurmaScreen(
                turmaId: widget.turmaId,
                turmaNome: _turmaNome(),
                academiaId: widget.academiaId,
                academiaNome: widget.academiaNome,
              ),
            ),
          );
        },
      ),
      _buildFunctionCard(
        icon: Icons.people_alt_rounded,
        title: 'Fazer chamada',
        subtitle: 'Registrar presença dos alunos',
        color: context.uai.success,
        permissao: 'pode_fazer_chamada',
        onTap: _validarEAbrirChamada,
      ),
      _buildFunctionCard(
        icon: Icons.list_alt_rounded,
        title: 'Listas de chamada',
        subtitle: 'Histórico de presenças',
        color: context.uai.info,
        permissao: 'pode_ver_lista_de_chamada',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ListasChamadaScreen(
                turmaId: widget.turmaId,
                turmaNome: _turmaNome(),
                academiaId: widget.academiaId,
                academiaNome: widget.academiaNome,
              ),
            ),
          );
        },
      ),
      _buildFunctionCard(
        icon: Icons.summarize_rounded,
        title: 'Resumo da turma',
        subtitle: 'Estatísticas e relatórios',
        color: context.uai.warning,
        permissao: 'pode_visualizar_relatorios',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardTurmasPage(
                turmaId: widget.turmaId,
                turmaNome: _turmaNome(),
                academiaId: widget.academiaId,
              ),
            ),
          );
        },
      ),
      _buildFunctionCard(
        icon: Icons.star_rate_rounded,
        title: 'Avaliação do aluno',
        subtitle: 'Comportamento, disciplina e evolução',
        color: context.uai.associacao,
        permissao: 'pode_avaliar_aluno',
        onTap: _validarEAbrirAvaliacaoAluno,
      ),
    ].where((widget) => widget is! SizedBox).toList();
  }

  Widget _buildLoadingScreen() {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              SizedBox(height: 16),
              Text(
                _temInternet ? 'Carregando turma...' : 'Modo offline',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyActions() {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: t.textMuted),
            SizedBox(height: 10),
            Text(
              'Nenhuma ação disponível',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Seu usuário não possui permissões liberadas para esta turma.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isLoadingPermissoes) {
      return _buildLoadingScreen();
    }

    final t = context.uai;
    final actions = _buildActionCards();

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: t.primary,
        backgroundColor: t.surface,
        onRefresh: () async {
          await _carregarDadosTurma();
          await _recarregarPermissoes();
          await _carregarResumoAlertasTurma();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeaderCard()),
            SliverToBoxAdapter(child: _buildSectionTitle()),
            if (actions.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyActions(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;

                    if (width >= 900) {
                      return SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                              (context, index) => actions[index],
                          childCount: actions.length,
                        ),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 430,
                          mainAxisExtent: 100,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 10,
                        ),
                      );
                    }

                    return SliverList.builder(
                      itemCount: actions.length,
                      itemBuilder: (context, index) => actions[index],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _AlunoAlertaTurma {
  final String alunoId;
  final String nome;
  final String indicador;
  final Color cor;
  final int dias;
  final DateTime? ultimaPresenca;
  final String fotoUrl;
  final String contatoAluno;
  final String contatoResponsavel;
  final String nomeResponsavel;
  final String mensagem;

  const _AlunoAlertaTurma({
    required this.alunoId,
    required this.nome,
    required this.indicador,
    required this.cor,
    required this.dias,
    required this.ultimaPresenca,
    required this.fotoUrl,
    required this.contatoAluno,
    required this.contatoResponsavel,
    required this.nomeResponsavel,
    required this.mensagem,
  });
}
