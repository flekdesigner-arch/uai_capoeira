import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

import 'area_aluno_solicitar_alteracao_screen.dart';
import 'area_aluno_frequencia_screen.dart';
import 'area_aluno_certificados_screen.dart';

class AreaAlunoDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> config;
  final Map<String, dynamic> authPayload;

  const AreaAlunoDashboardScreen({
    super.key,
    required this.aluno,
    required this.config,
    required this.authPayload,
  });

  @override
  State<AreaAlunoDashboardScreen> createState() => _AreaAlunoDashboardScreenState();
}

class _AreaAlunoDashboardScreenState extends State<AreaAlunoDashboardScreen> {
  String? _svgContent;
  String? _cordaSvg;

  String get _nome => widget.aluno['nome']?.toString() ?? 'Aluno';
  String get _apelido => widget.aluno['apelido']?.toString() ?? '';
  String get _foto => widget.aluno['foto_perfil_aluno']?.toString() ?? '';
  String get _status => widget.aluno['status_atividade']?.toString() ?? '';

  Map<String, dynamic> get _turmaInfo {
    final data = widget.aluno['turma_info'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  String get _graduacao {
    return (widget.aluno['graduacao_nome'] ??
        widget.aluno['graduacao_atual'] ??
        'Não informada')
        .toString();
  }

  @override
  void initState() {
    super.initState();
    _loadCordaSvg();
  }

  Future<void> _loadCordaSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      if (!mounted) return;

      setState(() {
        _svgContent = content;
        _cordaSvg = _montarCordaSvg(widget.aluno);
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar corda.svg no dashboard do aluno: $e');
    }
  }

  String? _montarCordaSvg(Map<String, dynamic> aluno) {
    if (_svgContent == null) return null;

    final cor1 = _pegarCor(aluno, ['graduacao_cor1', 'hex_cor1']);
    final cor2 = _pegarCor(aluno, ['graduacao_cor2', 'hex_cor2']);
    final ponta1 = _pegarCor(aluno, ['graduacao_ponta1', 'hex_ponta1']);
    final ponta2 = _pegarCor(aluno, ['graduacao_ponta2', 'hex_ponta2']);

    if (cor1 == null && cor2 == null && ponta1 == null && ponta2 == null) {
      return null;
    }

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      void changeColor(String id, String? hexColor) {
        if (hexColor == null || hexColor.trim().isEmpty) return;

        final hex = _normalizarHex(hexColor);
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

      changeColor('cor1', cor1);
      changeColor('cor2', cor2);
      changeColor('corponta1', ponta1);
      changeColor('corponta2', ponta2);

      return document.toXmlString();
    } catch (e) {
      debugPrint('⚠️ Erro ao montar SVG da corda no dashboard: $e');
      return null;
    }
  }

  String? _pegarCor(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    return null;
  }

  String? _normalizarHex(String value) {
    var hex = value.trim();

    if (hex.isEmpty) return null;

    if (!hex.startsWith('#')) {
      hex = '#$hex';
    }

    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return null;
    }

    return hex.toLowerCase();
  }

  Color _turmaColor() {
    final cor = _normalizarHex(_turmaInfo['cor_turma']?.toString() ?? '');
    if (cor == null) return Colors.indigo;

    try {
      return Color(int.parse('FF${cor.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Minha Área',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final isMobile = maxWidth < 650;
          final contentWidth = maxWidth > 980 ? 980.0 : maxWidth;

          return RefreshIndicator(
            onRefresh: () async {},
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 24,
                    14,
                    isMobile ? 14 : 24,
                    30,
                  ),
                  children: [
                    _buildHeader(isMobile),
                    const SizedBox(height: 14),
                    _buildResumoCards(isMobile),
                    const SizedBox(height: 16),
                    _buildSectionTitle(
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Painel do aluno',
                      subtitle: 'Escolha o que deseja consultar',
                    ),
                    const SizedBox(height: 10),
                    _buildAcoesResponsive(maxWidth),
                    const SizedBox(height: 16),
                    _buildAvisoSomenteLeitura(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.18),
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAvatar(isMobile),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.config['mensagem_topo']?.toString() ??
                      'Bem-vindo(a) à Área do Aluno',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: isMobile ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _nome,
                  maxLines: isMobile ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                if (_apelido.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _apelido,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildStatusChip(_status),
                    if (widget.aluno['academia']?.toString().isNotEmpty == true)
                      _buildSmallWhiteChip(
                        widget.aluno['academia'].toString(),
                        Icons.home_work_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isMobile) {
    final size = isMobile ? 74.0 : 86.0;

    if (_foto.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.white.withOpacity(0.16),
        child: Icon(Icons.person_rounded, color: Colors.white, size: size * 0.55),
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.white.withOpacity(0.20),
      child: ClipOval(
        child: Image.network(
          _foto,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: size * 0.55,
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final ativo = status == 'ATIVO(A)' || status == 'ATIVO';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ativo ? Colors.green.withOpacity(0.20) : Colors.orange.withOpacity(0.20),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Text(
        ativo ? 'ALUNO ATIVO' : (status.isEmpty ? 'STATUS NÃO INFORMADO' : status),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSmallWhiteChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCards(bool isMobile) {
    final turmaCard = _buildTurmaResumoCard();
    final graduacaoCard = _buildGraduacaoResumoCard();

    if (isMobile) {
      return Column(
        children: [
          turmaCard,
          const SizedBox(height: 10),
          graduacaoCard,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: turmaCard),
        const SizedBox(width: 10),
        Expanded(child: graduacaoCard),
      ],
    );
  }

  Widget _buildTurmaResumoCard() {
    final color = _turmaColor();
    final turmaNome = _safeText(widget.aluno['turma'], 'Não informada');
    final horarios = _turmaHorarios();

    String subtitle = 'Toque para ver informações da turma';

    if (horarios.isNotEmpty) {
      final primeiro = horarios.first;
      subtitle =
      '${primeiro['dia_nome'] ?? primeiro['dia'] ?? ''} • ${primeiro['horario_inicio'] ?? ''} às ${primeiro['horario_fim'] ?? ''}';
    }

    return InkWell(
      onTap: _abrirInfoTurma,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildTurmaIcon(color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Turma',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    turmaNome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildTurmaIcon(Color color) {
    final logo = _turmaInfo['logo_url']?.toString() ?? '';

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: logo.isNotEmpty
          ? ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          logo,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(Icons.school_rounded, color: color, size: 30);
          },
        ),
      )
          : Icon(Icons.school_rounded, color: color, size: 30),
    );
  }

  Widget _buildGraduacaoResumoCard() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.10),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.orange,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Graduação',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _graduacao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (_cordaSvg != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              height: 52,
              child: SvgPicture.string(
                _cordaSvg!,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.red.shade900, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAcoesResponsive(double width) {
    final cards = [
      _DashboardCardData(
        icon: Icons.person_search_rounded,
        title: 'Informações do aluno',
        subtitle: 'Ver seus dados cadastrais',
        color: Colors.blue,
        onTap: _abrirInfoAluno,
      ),
      _DashboardCardData(
        icon: Icons.edit_note_rounded,
        title: 'Solicitar alterações',
        subtitle: 'Pedir correção dos dados',
        color: Colors.purple,
        onTap: _abrirEmBreveAlteracoes,
      ),
      _DashboardCardData(
        icon: Icons.fact_check_rounded,
        title: 'Frequência',
        subtitle: 'Acompanhar presenças',
        color: Colors.green,
        onTap: _abrirEmBreveFrequencia,
      ),
      _DashboardCardData(
        icon: Icons.card_membership_rounded,
        title: 'Certificados',
        subtitle: 'Eventos e certificados',
        color: Colors.orange,
        onTap: _abrirEmBreveCertificados,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        int columns;

        if (maxWidth < 390) {
          columns = 1;
        } else if (maxWidth < 760) {
          columns = 2;
        } else {
          columns = 4;
        }

        const spacing = 10.0;
        final cardWidth = (maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              child: _buildDashboardActionCard(card),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDashboardActionCard(_DashboardCardData card) {
    return InkWell(
      onTap: card.onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: card.color.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: card.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(card.icon, color: card.color, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11.5,
                      height: 1.20,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: card.color,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvisoSomenteLeitura() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: Colors.blue.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta área é somente leitura. Para alterar informações, use o card '
                  '“Solicitar alterações”. A coordenação analisará antes de atualizar o cadastro oficial.',
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirInfoTurma() {
    final turma = _turmaInfo;

    if (turma.isEmpty) {
      _mostrarEmBreve(
        titulo: 'Informações da turma',
        mensagem: 'As informações completas da turma ainda não foram encontradas.',
        icon: Icons.school_rounded,
        color: Colors.indigo,
      );
      return;
    }

    final color = _turmaColor();
    final horarios = _turmaHorarios();

    showModalBottomSheet(
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.86,
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
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTurmaModalHeader(turma, color),
                    const SizedBox(height: 14),

                    _buildTurmaSection(
                      title: 'Horários de treino',
                      icon: Icons.calendar_month_rounded,
                      color: Colors.green,
                      children: horarios.isEmpty
                          ? [
                        _buildEmptyText(
                          'Nenhum horário cadastrado para esta turma.',
                        ),
                      ]
                          : horarios.map(_buildHorarioTile).toList(),
                    ),



                    if (_safeText(turma['observacoes'], '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTurmaSection(
                        title: 'Observações',
                        icon: Icons.notes_rounded,
                        color: Colors.purple,
                        children: [
                          _buildLongText(turma['observacoes'].toString()),
                        ],
                      ),
                    ],


                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTurmaModalHeader(Map<String, dynamic> turma, Color color) {
    final logo = turma['logo_url']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color,
            color.withOpacity(0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: logo.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                logo,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Icon(Icons.school_rounded, color: Colors.white, size: 36);
                },
              ),
            )
                : const Icon(Icons.school_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _safeText(turma['nome'], 'Turma'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildWhiteMiniChip(_safeText(turma['nivel'], 'Nível')),
                    _buildWhiteMiniChip(_safeText(turma['faixa_etaria'], 'Faixa etária')),
                    _buildWhiteMiniChip(_safeText(turma['status'], 'Status')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteMiniChip(String text) {
    if (text.trim().isEmpty || text == 'Nível' || text == 'Faixa etária' || text == 'Status') {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTurmaSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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

  Widget _buildHorarioTile(Map<String, dynamic> horario) {
    final tipo = _safeText(horario['tipo_aula'], 'Aula');
    final color = _tipoAulaColor(tipo);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.sports_martial_arts_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _safeText(horario['dia_nome'], 'Dia'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_safeText(horario['horario_inicio'], '--:--')} às ${_safeText(horario['horario_fim'], '--:--')}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              tipo,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _tipoAulaColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'OBJETIVA':
        return Colors.blue;
      case 'INSTRUMENTAÇÃO':
      case 'INSTRUMENTACAO':
        return Colors.green;
      case 'RODA':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }


  Widget _buildEmptyText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
    );
  }

  Widget _buildLongText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade800, height: 1.35),
      ),
    );
  }

  List<Map<String, dynamic>> _turmaHorarios() {
    final horarios = _turmaInfo['horarios'];

    if (horarios is List) {
      return horarios
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }



  void _abrirInfoAluno() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 700
            ? 680
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              minChildSize: 0.45,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.person_search_rounded, color: Colors.red.shade900),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Informações do aluno',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _buildInfoSection(
                      title: 'Dados pessoais',
                      icon: Icons.badge_rounded,
                      children: [
                        _buildInfoTile('Nome', widget.aluno['nome']),
                        _buildInfoTile('Apelido', widget.aluno['apelido']),
                        _buildInfoTile('Data de nascimento', widget.aluno['data_nascimento']),
                        _buildInfoTile('Sexo', widget.aluno['sexo']),
                        _buildInfoTile('Cidade', widget.aluno['cidade']),
                        _buildInfoTile('Endereço', widget.aluno['endereco']),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildInfoSection(
                      title: 'Contato',
                      icon: Icons.phone_android_rounded,
                      children: [
                        _buildInfoTile('Contato do aluno', widget.aluno['contato_aluno']),
                        _buildInfoTile('Responsável', widget.aluno['nome_responsavel']),
                        _buildInfoTile(
                          'Contato do responsável',
                          widget.aluno['contato_responsavel'],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildInfoSection(
                      title: 'Capoeira',
                      icon: Icons.sports_martial_arts_rounded,
                      children: [
                        _buildInfoTile('Academia', widget.aluno['academia']),
                        _buildInfoTile('Turma', widget.aluno['turma']),
                        _buildInfoTile('Modalidade', widget.aluno['modalidade']),
                        _buildInfoTile(
                          'Graduação',
                          widget.aluno['graduacao_nome'] ??
                              widget.aluno['graduacao_atual'],
                        ),
                        _buildInfoTile(
                          'Data da graduação',
                          widget.aluno['data_graduacao_atual'],
                        ),
                        _buildInfoTile('Tempo de capoeira', widget.aluno['tempo_capoeira']),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildInfoSection(
                      title: 'Frequência',
                      icon: Icons.fact_check_rounded,
                      children: [
                        _buildInfoTile('Última presença', widget.aluno['ultima_presenca']),
                        _buildInfoTile('Último dia presente', widget.aluno['ultimo_dia_presente']),
                        _buildInfoTile('Última chamada', widget.aluno['ultima_chamada']),
                        _buildInfoTile('Status', widget.aluno['status_atividade']),
                      ],
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

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final validChildren = children.where((w) => w is! SizedBox).toList();

    if (validChildren.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.red.shade900, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...validChildren,
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, dynamic value) {
    final text = value?.toString().trim() ?? '';

    if (text.isEmpty || text == 'null') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 360;

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  text,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _abrirEmBreveAlteracoes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoSolicitarAlteracaoScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirEmBreveFrequencia() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoFrequenciaScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirEmBreveCertificados() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoCertificadosScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  void _mostrarEmBreve({
    required String titulo,
    required String mensagem,
    required IconData icon,
    required Color color,
  }) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo)),
            ],
          ),
          content: Text(mensagem),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ENTENDI'),
            ),
          ],
        );
      },
    );
  }

  String _safeText(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';

    if (text.isEmpty || text == 'null') return fallback;

    return text;
  }
}

class _DashboardCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}
