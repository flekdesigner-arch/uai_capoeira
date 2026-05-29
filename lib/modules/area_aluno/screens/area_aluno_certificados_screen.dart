import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/theme/app_theme.dart';

class AreaAlunoCertificadosScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> authPayload;

  const AreaAlunoCertificadosScreen({
    super.key,
    required this.aluno,
    required this.authPayload,
  });

  @override
  State<AreaAlunoCertificadosScreen> createState() =>
      _AreaAlunoCertificadosScreenState();
}

class _AreaAlunoCertificadosScreenState
    extends State<AreaAlunoCertificadosScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _longDateFormat =
  DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR');

  bool _loading = true;
  String? _erro;
  String? _svgContent;
  List<_ParticipacaoTimeline> _participacoes = [];

  final Map<String, Map<String, dynamic>> _graduacoesCache = {};
  final Map<String, String?> _cordasCache = {};

  String get _alunoId {
    final value = widget.aluno['aluno_id'] ??
        widget.aluno['id'] ??
        widget.aluno['doc_id'] ??
        widget.aluno['docId'] ??
        widget.aluno['uid'] ??
        '';
    return value.toString();
  }

  String get _alunoNome => widget.aluno['nome']?.toString() ?? 'Aluno';
  String get _fotoAluno => widget.aluno['foto_perfil_aluno']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _iniciar();
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

  Future<void> _iniciar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      await _carregarSvg();
      await _carregarParticipacoes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar certificados: $e';
        _loading = false;
      });
    }
  }

  Future<void> _carregarSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      _svgContent = content;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar corda.svg em certificados: $e');
    }
  }

  Future<void> _carregarParticipacoes() async {
    if (_alunoId.isEmpty) {
      setState(() {
        _loading = false;
        _erro = 'Aluno não identificado.';
      });
      return;
    }

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final principal = await _firestore
        .collection('participacoes_eventos')
        .where('aluno_id', isEqualTo: _alunoId)
        .get(const GetOptions(source: Source.server));
    docs.addAll(principal.docs);

    // Fallback para bases antigas que possam ter usado outro nome de campo.
    if (docs.isEmpty) {
      final antigo = await _firestore
          .collection('participacoes_eventos')
          .where('alunoId', isEqualTo: _alunoId)
          .get(const GetOptions(source: Source.server));
      docs.addAll(antigo.docs);
    }

    final lista = <_ParticipacaoTimeline>[];

    for (final doc in docs) {
      final participacao = Map<String, dynamic>.from(doc.data());
      final eventoId = participacao['evento_id']?.toString() ?? '';
      Map<String, dynamic> evento = {};

      if (eventoId.isNotEmpty) {
        try {
          final eventoDoc =
          await _firestore.collection('eventos').doc(eventoId).get();

          if (eventoDoc.exists) {
            evento = Map<String, dynamic>.from(eventoDoc.data() ?? {});
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao buscar evento $eventoId: $e');
        }
      }

      final graduacao = _textoPrimeiro([
        participacao['graduacao'],
        participacao['graduacao_nome'],
        participacao['graduacao_atual'],
        evento['graduacao'],
      ], fallback: '');

      final temGraduacao = _temGraduacaoReal(graduacao);
      final cores = temGraduacao
          ? await _buscarCoresGraduacao(graduacao, participacao)
          : <String, dynamic>{};
      final cordaSvg = temGraduacao ? _montarCordaSvg(cores) : null;

      lista.add(
        _ParticipacaoTimeline(
          id: doc.id,
          participacao: participacao,
          evento: evento,
          nomeEvento: _textoPrimeiro([
            evento['nome'],
            evento['titulo'],
            participacao['evento_nome'],
            participacao['nome_evento'],
          ], fallback: 'Evento'),
          tipoEvento: _textoPrimeiro([
            evento['tipo_evento'],
            evento['tipo'],
            participacao['tipo_evento'],
          ], fallback: ''),
          graduacao: graduacao,
          dataEvento: _extrairData([
            evento['data'],
            evento['data_evento'],
            participacao['data_evento'],
            participacao['data'],
            participacao['createdAt'],
          ]),
          logoUrl: _textoPrimeiro([
            evento['logo_url'],
            evento['logo'],
            evento['imagem_url'],
            evento['banner_url'],
            participacao['evento_logo'],
            participacao['logo_url'],
          ], fallback: ''),
          certificadoUrl: _textoPrimeiro([
            participacao['link_certificado'],
            participacao['certificado_url'],
            participacao['url_certificado'],
            participacao['pdf_certificado'],
          ], fallback: ''),
          status: _textoPrimeiro([
            participacao['status'],
            participacao['status_participacao'],
            participacao['situacao'],
          ], fallback: 'Participou'),
          cordaSvg: cordaSvg,
          cores: cores,
        ),
      );
    }

    lista.sort((a, b) {
      final da = a.dataEvento ?? DateTime(1900);
      final db = b.dataEvento ?? DateTime(1900);
      return da.compareTo(db);
    });

    if (!mounted) return;

    setState(() {
      _participacoes = lista;
      _loading = false;
      _erro = null;
    });
  }

  bool _temGraduacaoReal(String value) {
    final text = value.trim().toLowerCase();

    if (text.isEmpty) return false;

    const invalidos = {
      'null',
      'graduação não informada',
      'graduacao não informada',
      'graduacao nao informada',
      'graduação nao informada',
      'não informada',
      'nao informada',
      'não informado',
      'nao informado',
      'sem graduação',
      'sem graduacao',
      'sem troca',
      'sem corda',
      'evento comum',
      '-',
      '--',
    };

    if (invalidos.contains(text)) return false;

    return true;
  }

  String _textoPrimeiro(List<dynamic> values, {required String fallback}) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty && text != 'null') return text;
    }

    return fallback;
  }

  DateTime? _extrairData(List<dynamic> values) {
    for (final value in values) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;

      if (value is String && value.trim().isNotEmpty) {
        final parsedIso = DateTime.tryParse(value.trim());
        if (parsedIso != null) return parsedIso;

        try {
          return _dateFormat.parseStrict(value.trim());
        } catch (_) {}
      }
    }

    return null;
  }

  Future<Map<String, dynamic>> _buscarCoresGraduacao(
      String nomeGraduacao,
      Map<String, dynamic> participacao,
      ) async {
    final direto = _coresDiretas(participacao);

    if (direto.isNotEmpty) return direto;

    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      return _graduacoesCache[nomeGraduacao]!;
    }

    Map<String, dynamic>? encontrado;

    try {
      final exact = await _firestore
          .collection('graduacoes')
          .where('nome_graduacao', isEqualTo: nomeGraduacao)
          .limit(1)
          .get();

      if (exact.docs.isNotEmpty) {
        encontrado = exact.docs.first.data();
      } else {
        final all = await _firestore.collection('graduacoes').get();
        final alvo = nomeGraduacao.toLowerCase().trim();

        for (final doc in all.docs) {
          final data = doc.data();
          final nome =
              data['nome_graduacao']?.toString().toLowerCase().trim() ?? '';

          if (nome == alvo || nome.contains(alvo) || alvo.contains(nome)) {
            encontrado = data;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar cores da graduação: $e');
    }

    final cores = encontrado != null
        ? {
      'hex_cor1':
      encontrado['hex_cor1'] ?? encontrado['graduacao_cor1'] ?? '#BDBDBD',
      'hex_cor2':
      encontrado['hex_cor2'] ?? encontrado['graduacao_cor2'] ?? '#9E9E9E',
      'hex_ponta1': encontrado['hex_ponta1'] ??
          encontrado['graduacao_ponta1'] ??
          '#757575',
      'hex_ponta2': encontrado['hex_ponta2'] ??
          encontrado['graduacao_ponta2'] ??
          '#616161',
      'nome_graduacao': encontrado['nome_graduacao'] ?? nomeGraduacao,
    }
        : _coresPadraoPorNome(nomeGraduacao);

    _graduacoesCache[nomeGraduacao] = cores;
    return cores;
  }

  Map<String, dynamic> _coresDiretas(Map<String, dynamic> data) {
    final cor1 = _pegarCor(data, ['hex_cor1', 'graduacao_cor1', 'cor1']);
    final cor2 = _pegarCor(data, ['hex_cor2', 'graduacao_cor2', 'cor2']);
    final ponta1 =
    _pegarCor(data, ['hex_ponta1', 'graduacao_ponta1', 'ponta1']);
    final ponta2 =
    _pegarCor(data, ['hex_ponta2', 'graduacao_ponta2', 'ponta2']);

    if ([cor1, cor2, ponta1, ponta2].every((e) => e == null)) return {};

    return {
      'hex_cor1': cor1 ?? '#BDBDBD',
      'hex_cor2': cor2 ?? cor1 ?? '#9E9E9E',
      'hex_ponta1': ponta1 ?? cor1 ?? '#757575',
      'hex_ponta2': ponta2 ?? cor2 ?? '#616161',
    };
  }

  String? _pegarCor(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value != 'null') return value;
    }

    return null;
  }

  Map<String, dynamic> _coresPadraoPorNome(String nome) {
    final n = nome.toLowerCase();

    if (n.contains('amarel')) {
      return _cores('#FFEB3B', '#FDD835', '#FBC02D', '#F9A825');
    }

    if (n.contains('laranja')) {
      return _cores('#FF9800', '#FB8C00', '#F57C00', '#EF6C00');
    }

    if (n.contains('azul')) {
      return _cores('#2196F3', '#1E88E5', '#1976D2', '#1565C0');
    }

    if (n.contains('verde')) {
      return _cores('#4CAF50', '#43A047', '#388E3C', '#2E7D32');
    }

    if (n.contains('roxo') || n.contains('roxa')) {
      return _cores('#9C27B0', '#8E24AA', '#7B1FA2', '#6A1B9A');
    }

    if (n.contains('vermelh')) {
      return _cores('#F44336', '#E53935', '#D32F2F', '#C62828');
    }

    if (n.contains('marrom')) {
      return _cores('#8D6E63', '#7B5E57', '#6D4C41', '#5D4037');
    }

    if (n.contains('preta') || n.contains('preto')) {
      return _cores('#212121', '#1E1E1E', '#1A1A1A', '#151515');
    }

    if (n.contains('branc') || n.contains('crua')) {
      return _cores('#FFFFFF', '#F5F5F5', '#E0E0E0', '#BDBDBD');
    }

    return _cores('#BDBDBD', '#9E9E9E', '#757575', '#616161');
  }

  Map<String, dynamic> _cores(String c1, String c2, String p1, String p2) {
    return {
      'hex_cor1': c1,
      'hex_cor2': c2,
      'hex_ponta1': p1,
      'hex_ponta2': p2,
    };
  }

  String? _montarCordaSvg(Map<String, dynamic> cores) {
    if (_svgContent == null || cores.isEmpty) return null;

    final cacheKey = [
      cores['hex_cor1'],
      cores['hex_cor2'],
      cores['hex_ponta1'],
      cores['hex_ponta2'],
    ].join('_');

    if (_cordasCache.containsKey(cacheKey)) return _cordasCache[cacheKey];

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      void changeColor(String id, String? hexColor) {
        final hex = _normalizarHex(hexColor ?? '');

        if (hex == null) return;

        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isEmpty) return;

        final style = element.getAttribute('style') ?? '';
        final newStyle = style.replaceAll(
          RegExp(r'fill:#[0-9a-fA-F]{6}'),
          '',
        );
        element.setAttribute('style', 'fill:$hex;$newStyle');
      }

      changeColor('cor1', cores['hex_cor1']?.toString());
      changeColor('cor2', cores['hex_cor2']?.toString());
      changeColor('corponta1', cores['hex_ponta1']?.toString());
      changeColor('corponta2', cores['hex_ponta2']?.toString());

      final svg = document.toXmlString();
      _cordasCache[cacheKey] = svg;
      return svg;
    } catch (e) {
      debugPrint('⚠️ Erro ao montar SVG da corda: $e');
      return null;
    }
  }

  String? _normalizarHex(String value) {
    var hex = value.trim();

    if (hex.isEmpty) return null;
    if (!hex.startsWith('#')) hex = '#$hex';
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;

    return hex.toLowerCase();
  }

  Future<void> _abrirCertificado(String url) async {
    if (url.trim().isEmpty) return;

    final uri = Uri.tryParse(url);

    if (uri == null) {
      _snack('Link do certificado inválido.', context.uai.error);
      return;
    }

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!ok) {
        _snack('Não foi possível abrir o certificado.', context.uai.error);
      }
    } catch (e) {
      _snack('Erro ao abrir certificado: $e', context.uai.error);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatarData(DateTime? date) {
    if (date == null) return 'Data não informada';
    return _dateFormat.format(date);
  }

  String _formatarDataLonga(DateTime? date) {
    if (date == null) return 'Data não informada';
    return _longDateFormat.format(date);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Meus Certificados',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _iniciar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
          constraints.maxWidth > 980 ? 980.0 : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: _buildBody(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    final t = context.uai;

    if (_loading) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          margin: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              const SizedBox(height: 14),
              Text(
                'Carregando certificados...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_erro != null) {
      return _buildErrorState(_erro!);
    }

    if (_participacoes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _iniciar,
        color: t.primary,
        backgroundColor: t.surface,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 70),
            Icon(
              Icons.card_membership_rounded,
              size: 96,
              color: t.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum certificado encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Quando suas participações forem lançadas, elas aparecerão aqui em uma linha do tempo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, height: 1.3),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _iniciar,
      color: t.primary,
      backgroundColor: t.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildHeader(),
          const SizedBox(height: 18),
          _buildTimelineTitle(),
          const SizedBox(height: 8),
          ...List.generate(_participacoes.length, (index) {
            return _buildTimelineItem(
              item: _participacoes[index],
              index: index,
              isFirst: index == 0,
              isLast: index == _participacoes.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(borderColor: danger.withOpacity(0.18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 78, color: danger),
              const SizedBox(height: 12),
              Text(
                'Ops! Algo deu errado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _iniciar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    final totalCertificados =
        _participacoes.where((e) => e.certificadoUrl.trim().isNotEmpty).length;
    final ultima = _participacoes.isNotEmpty ? _participacoes.last : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.cardRadius + 6),
        gradient: t.primaryGradient,
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final avatar = _buildAlunoAvatar();
          final info = Expanded(
            child: Column(
              crossAxisAlignment:
              narrow ? CrossAxisAlignment.start : CrossAxisAlignment.start,
              children: [
                Text(
                  'Linha do tempo de graduações',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.82),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _alunoNome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _whiteChip(
                      '${_participacoes.length} evento(s)',
                      Icons.event_available_rounded,
                    ),
                    _whiteChip(
                      '$totalCertificados certificado(s)',
                      Icons.picture_as_pdf_rounded,
                    ),
                    if (ultima != null && _temGraduacaoReal(ultima.graduacao))
                      _whiteChip(
                        'Atual: ${ultima.graduacao}',
                        Icons.workspace_premium_rounded,
                      ),
                  ],
                ),
              ],
            ),
          );

          if (narrow) {
            return Row(
              children: [
                avatar,
                const SizedBox(width: 13),
                info,
              ],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(width: 16),
              info,
              const SizedBox(width: 12),
              _buildMiniCordaAtual(ultima),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlunoAvatar() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    if (_fotoAluno.isEmpty) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: onPrimary.withOpacity(0.16),
        child: Icon(Icons.person_rounded, color: onPrimary, size: 38),
      );
    }

    return CircleAvatar(
      radius: 34,
      backgroundColor: onPrimary.withOpacity(0.18),
      child: ClipOval(
        child: Image.network(
          _fotoAluno,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(Icons.person_rounded, color: onPrimary, size: 38);
          },
        ),
      ),
    );
  }

  Widget _buildMiniCordaAtual(_ParticipacaoTimeline? item) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    if (item?.cordaSvg == null) return const SizedBox.shrink();

    return Container(
      width: 120,
      height: 76,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: SvgPicture.string(item!.cordaSvg!, fit: BoxFit.contain),
    );
  }

  Widget _whiteChip(String text, IconData icon) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineTitle() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.background);

    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.12)),
          ),
          child: Icon(Icons.timeline_rounded, color: accent, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Evolução do aluno',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: t.textPrimary,
                ),
              ),
              Text(
                'Toque em um evento para ver os detalhes da participação',
                style: TextStyle(color: t.textSecondary, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required _ParticipacaoTimeline item,
    required int index,
    required bool isFirst,
    required bool isLast,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;

        if (wide) {
          final leftSide = index.isEven;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: leftSide
                      ? _buildEventCard(item, alignRight: true)
                      : const SizedBox.shrink(),
                ),
                _buildCenterLine(item, isFirst, isLast),
                Expanded(
                  child: leftSide
                      ? const SizedBox.shrink()
                      : _buildEventCard(item, alignRight: false),
                ),
              ],
            ),
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCenterLine(item, isFirst, isLast),
              Expanded(child: _buildEventCard(item, alignRight: false)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenterLine(
      _ParticipacaoTimeline item,
      bool isFirst,
      bool isLast,
      ) {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.background);

    return SizedBox(
      width: 74,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 3,
              color: isFirst ? Colors.transparent : accent.withOpacity(0.18),
            ),
          ),
          GestureDetector(
            onTap: () => _abrirDetalhes(item),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: t.card, width: 4),
              ),
              child: ClipOval(
                child: item.logoUrl.isNotEmpty
                    ? Image.network(
                  item.logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Icon(
                      Icons.emoji_events_rounded,
                      color: _readableOn(accent),
                    );
                  },
                )
                    : Icon(
                  Icons.emoji_events_rounded,
                  color: _readableOn(accent),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: 3,
              color: isLast ? Colors.transparent : accent.withOpacity(0.18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(
      _ParticipacaoTimeline item, {
        required bool alignRight,
      }) {
    final t = context.uai;
    final hasCertificado = item.certificadoUrl.trim().isNotEmpty;
    final accent = _ensureVisible(t.warning, t.card);
    final primary = _ensureVisible(t.primary, t.card);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(t.cardRadius + 2),
          onTap: () => _abrirDetalhes(item),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              border: Border.all(color: accent.withOpacity(0.10)),
              boxShadow: t.softShadow,
            ),
            child: Column(
              crossAxisAlignment:
              alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection:
                  alignRight ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                  children: [
                    _buildLogoBox(item),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: alignRight
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nomeEvento,
                            textAlign:
                            alignRight ? TextAlign.right : TextAlign.left,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              height: 1.1,
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            alignment: alignRight
                                ? WrapAlignment.end
                                : WrapAlignment.start,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _smallChip(
                                _formatarData(item.dataEvento),
                                Icons.calendar_month_rounded,
                                t.primary,
                              ),
                              if (item.tipoEvento.isNotEmpty)
                                _smallChip(
                                  item.tipoEvento,
                                  Icons.event_rounded,
                                  t.info,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_temGraduacaoReal(item.graduacao)) ...[
                  _buildGraduacaoBlock(item, alignRight),
                  const SizedBox(height: 12),
                ] else ...[
                  _buildEventoComumBlock(item, alignRight),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment:
                  alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _abrirDetalhes(item),
                        icon: const Icon(Icons.visibility_rounded, size: 18),
                        label: const Text('Detalhes'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(color: accent.withOpacity(0.26)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: hasCertificado
                            ? () => _abrirCertificado(item.certificadoUrl)
                            : null,
                        icon: Icon(
                          hasCertificado
                              ? Icons.download_rounded
                              : Icons.lock_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          hasCertificado ? 'Certificado' : 'Indisponível',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: _readableOn(primary),
                          disabledBackgroundColor: t.cardAlt,
                          disabledForegroundColor: t.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoBox(_ParticipacaoTimeline item) {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: item.logoUrl.isNotEmpty
            ? Image.network(
          item.logoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(
              Icons.emoji_events_rounded,
              color: accent,
              size: 30,
            );
          },
        )
            : Icon(Icons.emoji_events_rounded, color: accent, size: 30),
      ),
    );
  }

  Widget _buildEventoComumBlock(
      _ParticipacaoTimeline item,
      bool alignRight,
      ) {
    final t = context.uai;
    final accent = _ensureVisible(t.info, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.13)),
      ),
      child: Row(
        textDirection: alignRight ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        children: [
          Icon(
            Icons.event_available_rounded,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Participação em evento',
              textAlign: alignRight ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraduacaoBlock(
      _ParticipacaoTimeline item,
      bool alignRight,
      ) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment:
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            'Graduação no evento',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.graduacao,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: t.textPrimary,
            ),
          ),
          if (item.cordaSvg != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: SvgPicture.string(item.cordaSvg!, fit: BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallChip(String text, IconData icon, Color color) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  void _abrirDetalhes(_ParticipacaoTimeline item) {
    final t = context.uai;
    final hasCertificado = item.certificadoUrl.trim().isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 720
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 6),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              minChildSize: 0.45,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
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
                    const SizedBox(height: 16),
                    _buildDetalheHeader(item),
                    const SizedBox(height: 14),
                    _detailSection(
                      title: 'Participação',
                      icon: Icons.event_available_rounded,
                      children: [
                        _detailTile('Evento', item.nomeEvento),
                        _detailTile('Data', _formatarDataLonga(item.dataEvento)),
                        _detailTile('Tipo', item.tipoEvento),
                        _detailTile('Status', item.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_temGraduacaoReal(item.graduacao)) ...[
                      _detailSection(
                        title: 'Graduação recebida',
                        icon: Icons.workspace_premium_rounded,
                        children: [
                          _detailTile('Graduação', item.graduacao),
                          if (item.cordaSvg != null)
                            Container(
                              height: 92,
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: t.cardAlt,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: t.border),
                              ),
                              child: SvgPicture.string(
                                item.cordaSvg!,
                                fit: BoxFit.contain,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: hasCertificado
                            ? () => _abrirCertificado(item.certificadoUrl)
                            : null,
                        icon: Icon(
                          hasCertificado
                              ? Icons.download_rounded
                              : Icons.lock_outline_rounded,
                        ),
                        label: Text(
                          hasCertificado
                              ? 'BAIXAR / ABRIR CERTIFICADO'
                              : 'CERTIFICADO INDISPONÍVEL',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: _readableOn(t.primary),
                          disabledBackgroundColor: t.cardAlt,
                          disabledForegroundColor: t.textMuted,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetalheHeader(_ParticipacaoTimeline item) {
    final t = context.uai;
    final color = _ensureVisible(t.warning, t.surface);
    final onColor = _readableOn(color);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _buildLogoBoxOnColor(item, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nomeEvento,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatarDataLonga(item.dataEvento),
                  style: TextStyle(
                    color: onColor.withOpacity(0.82),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoBoxOnColor(_ParticipacaoTimeline item, Color color) {
    final onColor = _readableOn(color);

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: onColor.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onColor.withOpacity(0.16)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: item.logoUrl.isNotEmpty
            ? Image.network(
          item.logoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(
              Icons.emoji_events_rounded,
              color: onColor,
              size: 30,
            );
          },
        )
            : Icon(Icons.emoji_events_rounded, color: onColor, size: 30),
      ),
    );
  }

  Widget _detailSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
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
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _detailTile(String label, String value) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
}

class _ParticipacaoTimeline {
  final String id;
  final Map<String, dynamic> participacao;
  final Map<String, dynamic> evento;
  final String nomeEvento;
  final String tipoEvento;
  final String graduacao;
  final DateTime? dataEvento;
  final String logoUrl;
  final String certificadoUrl;
  final String status;
  final String? cordaSvg;
  final Map<String, dynamic> cores;

  const _ParticipacaoTimeline({
    required this.id,
    required this.participacao,
    required this.evento,
    required this.nomeEvento,
    required this.tipoEvento,
    required this.graduacao,
    required this.dataEvento,
    required this.logoUrl,
    required this.certificadoUrl,
    required this.status,
    required this.cordaSvg,
    required this.cores,
  });
}
