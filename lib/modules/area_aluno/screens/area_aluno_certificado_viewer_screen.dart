// lib/modules/area_aluno/screens/area_aluno_certificado_viewer_screen.dart
//
// Tela pública da Área do Aluno para visualizar uma PRÉVIA REAL do certificado,
// usando o mesmo CertificadoPreviewWidget do módulo oficial de certificados.
//
// IMPORTANTE:
// - Não abre PDF real.
// - Não usa iframe.
// - Não mostra botão de download.
// - Usa os SVGs reais do projeto.
// - Usa os slots do SVG guia para posicionar os textos.
// - O PDF oficial/download continua sendo liberado somente após a finalização
//   do evento, conforme regra da coordenação.
//
// AJUSTE V4:
// - Corrige erro Web: "Cannot read properties of undefined (reading trim)".
// - Blindagem extra contra campos antigos/nulos vindos do objeto de evento.
// - Usa fallback pela participação quando campos novos ainda não vierem no resumo.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_eventos_service.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_preview_widget.dart';

class AreaAlunoCertificadoViewerScreen extends StatelessWidget {
  final AreaAlunoEventoResumo evento;

  const AreaAlunoCertificadoViewerScreen({
    super.key,
    required this.evento,
  });

  static const CertificadoSvgService _svgService = CertificadoSvgService();

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

  String _safe(dynamic value, {String fallback = 'Não informado'}) {
    try {
      final raw = value?.toString();
      final text = (raw ?? '').trim();

      if (text.isEmpty) return fallback;
      if (text.toLowerCase() == 'null') return fallback;
      if (text.toLowerCase() == 'undefined') return fallback;

      return text;
    } catch (_) {
      return fallback;
    }
  }

  String _fromParticipacao(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = _safe(evento.participacao[key], fallback: '');
      if (value.isNotEmpty) return value;
    }

    return fallback;
  }

  String _alunoNome() {
    final direto = _safe(evento.alunoNome, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      ['aluno_nome', 'nome_aluno', 'nome'],
      fallback: 'Aluno',
    );
  }

  String _alunoCpf() {
    final direto = _safe(evento.alunoCpf, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      ['cpf', 'aluno_cpf', 'cpf_aluno'],
      fallback: '',
    );
  }

  String _alunoSexo() {
    final direto = _safe(evento.alunoSexo, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      ['sexo', 'aluno_sexo', 'sexo_aluno', 'genero'],
      fallback: '',
    );
  }

  String _certificadoOuDiploma() {
    final direto = _safe(evento.certificadoOuDiploma, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      [
        'certificado_ou_diploma',
        'certificadoOuDiploma',
        'tipo_certificado',
        'tipoCertificado',
      ],
      fallback: 'CERTIFICADO',
    );
  }

  String _fraseGraduacao() {
    final direto = _safe(evento.graduacaoNovaFrase, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      ['frase', 'frase_certificado', 'fraseCertificado'],
      fallback: '',
    );
  }

  String _graduacaoNovaCor1() {
    final direto = _safe(evento.graduacaoNovaCor1, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      ['graduacao_nova_cor1', 'hex_cor1', 'graduacao_cor1'],
      fallback: '',
    );
  }

  String _graduacaoNovaCor2() {
    final direto = _safe(evento.graduacaoNovaCor2, fallback: '');
    if (direto.isNotEmpty) return direto;

    return _fromParticipacao(
      ['graduacao_nova_cor2', 'hex_cor2', 'graduacao_cor2'],
      fallback: '',
    );
  }

  Color _cor(
      String? hex, {
        Color fallback = const Color(0xFF9E9E9E),
      }) {
    return _svgService.colorFromHex(hex, fallback: fallback);
  }

  CertificadoTemplateTipo _tipoTemplate() {
    return CertificadoTemplateTipoX.fromCodigo(_certificadoOuDiploma());
  }

  String _localData() {
    final cidade = _safe(evento.cidade, fallback: 'BOCAIUVA - MG');

    if (evento.dataEvento == null) {
      return cidade.toUpperCase();
    }

    final data = DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR')
        .format(evento.dataEvento!)
        .toUpperCase();

    return '${cidade.toUpperCase()}, $data';
  }

  String _graduacaoExibida() {
    final nova = _safe(evento.graduacaoNova, fallback: '');
    if (nova.isNotEmpty) return nova;

    final novaParticipacao = _fromParticipacao(
      ['graduacao_nova', 'graduacaoNova'],
      fallback: '',
    );
    if (novaParticipacao.isNotEmpty) return novaParticipacao;

    final atual = _safe(evento.graduacaoAtual, fallback: '');
    if (atual.isNotEmpty) return atual;

    return 'GRADUAÇÃO NÃO DEFINIDA';
  }

  String _fraseCertificado() {
    final frase = _fraseGraduacao();

    if (frase.isNotEmpty) return frase;

    return 'CERTIFICAMOS QUE O(A) ALUNO(A) ACIMA ESTÁ APTO(A) E APROVADO(A) '
        'PARA RECEBER A GRADUAÇÃO EM CAPOEIRA, POR DEMONSTRAR INTERESSE '
        'NA ARTE E CULTURA BRASILEIRA, SENDO RECONHECIDO(A) PELOS MESTRES, '
        'CONTRAMESTRES, PROFESSORES E FORMADOS DO GRUPO.';
  }

  List<CertificadoAssinaturaData> _assinaturas() {
    final raw = evento.evento['assinaturas'];

    if (raw is List) {
      final lista = raw
          .whereType<Map>()
          .map((item) {
        final map = Map<String, dynamic>.from(item);
        final nome = _safe(
          map['nome'] ?? map['nome_assinatura'] ?? map['responsavel'],
          fallback: '',
        );
        final apelido = _safe(
          map['apelido'] ?? map['cargo'] ?? map['titulo'],
          fallback: '',
        );

        if (nome.isEmpty) return null;

        return CertificadoAssinaturaData(
          nome: nome,
          apelido: apelido,
        );
      })
          .whereType<CertificadoAssinaturaData>()
          .toList();

      if (lista.isNotEmpty) return lista;
    }

    return const [
      CertificadoAssinaturaData(
        nome: 'JOÃO LUCAS SILVA RABELO',
        apelido: 'TICO-TICO',
      ),
      CertificadoAssinaturaData(
        nome: 'ASSOCIAÇÃO UAI CAPOEIRA',
        apelido: 'ORGANIZAÇÃO',
      ),
      CertificadoAssinaturaData(
        nome: 'COORDENAÇÃO DO EVENTO',
        apelido: 'UAI CAPOEIRA',
      ),
    ];
  }

  CertificadoPreviewData _previewData() {
    final cpf = _alunoCpf();

    return CertificadoPreviewData(
      alunoNome: _alunoNome(),
      cpf: cpf.isEmpty ? null : cpf,
      sexo: _alunoSexo(),
      graduacaoNova: _graduacaoExibida(),
      frase: _fraseCertificado(),
      localData: _localData(),
      assinaturas: _assinaturas(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    final tipo = _tipoTemplate();
    final data = _previewData();
    final cor1 = _cor(
      _graduacaoNovaCor1(),
      fallback: const Color(0xFF9E9E9E),
    );
    final cor2 = _cor(
      _graduacaoNovaCor2(),
      fallback: cor1,
    );
    final contorno = const Color(0xFF1A0202);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Prévia do certificado',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
          constraints.maxWidth > 1260 ? 1260.0 : constraints.maxWidth;
          final isMobile = constraints.maxWidth < 650;
          final isWide = constraints.maxWidth >= 1050;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 14 : 24,
                  14,
                  isMobile ? 14 : 24,
                  28,
                ),
                children: [
                  _buildHeader(context, tipo),
                  const SizedBox(height: 14),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 330,
                          child: Column(
                            children: [
                              _buildInfoCard(context, tipo),
                              const SizedBox(height: 12),
                              _buildNotice(context),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildPreviewReal(
                            tipo: tipo,
                            data: data,
                            cor1: cor1,
                            cor2: cor2,
                            contorno: contorno,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildInfoCard(context, tipo),
                    const SizedBox(height: 12),
                    _buildPreviewReal(
                      tipo: tipo,
                      data: data,
                      cor1: cor1,
                      cor2: cor2,
                      contorno: contorno,
                    ),
                    const SizedBox(height: 12),
                    _buildNotice(context),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CertificadoTemplateTipo tipo) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          _buildLogoEvento(
            context,
            size: 58,
            background: onPrimary.withOpacity(0.16),
            foreground: onPrimary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  evento.nomeEvento,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 17,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${tipo.nome} • prévia real do certificado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoEvento(
      BuildContext context, {
        required double size,
        required Color background,
        required Color foreground,
      }) {
    final logo = _safe(evento.logoEventoUrl, fallback: '');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: foreground.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo.isNotEmpty
          ? Image.network(
        logo,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Icon(
            Icons.workspace_premium_rounded,
            color: foreground,
            size: size * 0.52,
          );
        },
      )
          : Icon(
        Icons.workspace_premium_rounded,
        color: foreground,
        size: size * 0.52,
      ),
    );
  }

  Widget _buildPreviewReal({
    required CertificadoTemplateTipo tipo,
    required CertificadoPreviewData data,
    required Color cor1,
    required Color cor2,
    required Color contorno,
  }) {
    return CertificadoPreviewWidget(
      tipo: tipo,
      cor1: cor1,
      cor2: cor2,
      corContorno: contorno,
      data: data,
      textosConfig: null,
      exportKey: null,
      showHeader: true,
      showDebugInfo: false,
      showTextOverlay: true,
      maxHeight: 720,
    );
  }

  Widget _buildInfoCard(BuildContext context, CertificadoTemplateTipo tipo) {
    final t = context.uai;
    final accent = _ensureVisible(t.info, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.info_rounded, color: accent, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Dados usados na prévia',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoLine(context, 'Aluno', _alunoNome()),
          _infoLine(
            context,
            'CPF',
            _alunoCpf().trim().isEmpty ? 'Não informado' : _alunoCpf(),
          ),
          _infoLine(
            context,
            'Sexo',
            _alunoSexo().trim().isEmpty ? 'Não informado' : _alunoSexo(),
          ),
          _infoLine(context, 'Modelo', tipo.nome),
          _infoLine(context, 'Graduação', _graduacaoExibida()),
          _infoLine(context, 'Cidade/Data', _localData()),
          _infoLine(
            context,
            'Status',
            evento.temCertificado
                ? 'Certificado vinculado'
                : 'Prévia aguardando liberação oficial',
          ),
        ],
      ),
    );
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.7,
                height: 1.18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta tela mostra apenas a prévia real do certificado usando o template oficial. '
                  'O PDF oficial e a opção de download devem ser liberados somente após a finalização do evento.',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
