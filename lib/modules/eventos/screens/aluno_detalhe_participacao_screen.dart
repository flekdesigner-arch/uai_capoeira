import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/modules/eventos/models/participacao_model.dart';
import 'package:uai_capoeira/modules/uniformes/models/pagamento_model.dart';
import 'package:uai_capoeira/modules/eventos/services/participacao_service.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/pagamento_service.dart';
import 'package:uai_capoeira/modules/graduacoes/services/graduacao_service.dart';
import 'package:uai_capoeira/modules/eventos/widgets/registrar_pagamento_modal.dart';
import 'package:uai_capoeira/modules/eventos/widgets/editar_camisa_modal.dart';
import 'package:uai_capoeira/modules/graduacoes/widgets/editar_graduacao_modal.dart';

class DetalheParticipacaoScreen extends StatefulWidget {
  final Map<String, dynamic> participacao;
  final String participacaoId;
  final String eventoId;

  const DetalheParticipacaoScreen({
    super.key,
    required this.participacao,
    required this.participacaoId,
    required this.eventoId,
  });

  @override
  State<DetalheParticipacaoScreen> createState() =>
      _DetalheParticipacaoScreenState();
}

class _DetalheParticipacaoScreenState extends State<DetalheParticipacaoScreen> {
  String _formatarData(DateTime? data) {
    if (data == null) return '—';
    return DateFormat('dd/MM/yyyy').format(data);
  }

  String _tipoLinkCertificado(String link) {
    final lower = link.toLowerCase();

    if (lower.contains('firebasestorage.googleapis.com') ||
        lower.contains('storage.googleapis.com') ||
        lower.contains('appspot.com')) {
      return 'Firebase Storage';
    }

    if (lower.contains('drive.google.com')) {
      return 'Google Drive';
    }

    return 'Link externo';
  }

  late ParticipacaoModel _participacao;
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PagamentoService _pagamentoService = PagamentoService();
  final PermissaoService _permissaoService = PermissaoService();
  late final PermissionAccessGuard _accessGuard = PermissionAccessGuard(
    service: _permissaoService,
  );
  final GraduacaoService _graduacaoService = GraduacaoService();

  bool _registrandoPagamento = false;
  bool _isLoading = false;
  bool _carregandoPermissoes = true;
  bool _acessoNegado = false;
  bool _podeFinalizar = false;
  bool _podeEditarCamisa = false;
  bool _podeEditarGraduacao = false;
  bool _podeRegistrarPagamento = false;
  bool _podeEditarPagamento = false;
  bool _podeExcluirPagamento = false;
  bool _podeConcluirParticipacao = false;
  bool _temPatrocinio = false;

  List<PagamentoModel> _pagamentos = [];
  double _totalPago = 0;
  double _saldo = 0;

  String? _linkCertificadoServidor;

  // Dados do evento (taxas, camisas, etc)
  Map<String, dynamic>? _dadosEvento;
  Map<String, dynamic>? _contratoFinanceiro;

  // Dados do aluno para cálculo de graduação
  Map<String, dynamic>? _dadosAluno;

  // 🔥 Cache para dados do aluno (evita múltiplas chamadas)
  final Map<String, Map<String, dynamic>> _cacheAluno = {};

  // 🔥 ÚLTIMO NÍVEL INFANTIL

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

  String? _stringLimpa(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;
    return text;
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
      return 'MANGA_LONGA';
    }

    if (clean == 'REGATA') {
      return 'REGATA';
    }

    return 'MANGA';
  }

  double _asDoubleSeguro(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().replaceAll(',', '.').trim() ?? '';
    if (text.isEmpty) return fallback;

    return double.tryParse(text) ?? fallback;
  }

  double _valorCamisaEventoPorTipo(String? tipoCamisa) {
    final tipo = _normalizarTipoCamisa(tipoCamisa);

    if (_dadosEvento == null) {
      return _participacao.valorCamisa;
    }

    final rawValores =
        _dadosEvento!['valoresPorTipoCamisa'] ??
        _dadosEvento!['valores_por_tipo_camisa'] ??
        _dadosEvento!['valoresTipoCamisa'] ??
        _dadosEvento!['valores_tipo_camisa'];

    if (rawValores is Map) {
      for (final entry in rawValores.entries) {
        if (_normalizarTipoCamisa(entry.key) == tipo) {
          final valor = _asDoubleSeguro(entry.value);
          if (valor > 0) return valor;
        }
      }
    }

    final valorAntigo = _asDoubleSeguro(
      _dadosEvento!['valorCamisa'] ?? _dadosEvento!['valor_camisa'],
      fallback: _participacao.valorCamisa,
    );

    return valorAntigo;
  }

  String? _extrairLinkCertificado(Map<String, dynamic>? data) {
    if (data == null) return null;

    final candidatos = <dynamic>[
      data['link_certificado'],
      data['linkCertificado'],
      data['certificado_url'],
      data['certificadoUrl'],
      data['url_certificado'],
      data['urlCertificado'],
      data['certificado'],
      data['certificado_link'],
      data['certificadoLink'],
    ];

    for (final item in candidatos) {
      final clean = _stringLimpa(item);
      if (clean != null) return clean;
    }

    return null;
  }

  String? _certificadoAtual() {
    final candidatos = <dynamic>[
      _linkCertificadoServidor,
      _participacao.linkCertificado,
      widget.participacao['link_certificado'],
      widget.participacao['linkCertificado'],
      widget.participacao['certificado_url'],
      widget.participacao['certificadoUrl'],
      widget.participacao['url_certificado'],
      widget.participacao['urlCertificado'],
      widget.participacao['certificado'],
      widget.participacao['certificado_link'],
      widget.participacao['certificadoLink'],
    ];

    for (final item in candidatos) {
      final clean = _stringLimpa(item);
      if (clean != null) return clean;
    }

    return null;
  }

  void _showSnackTema(
    String mensagem, {
    required Color background,
    IconData? icon,
  }) {
    if (!mounted) return;

    final fg = _readableOn(background);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                mensagem,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _inicializarParticipacao();
    _inicializarComPermissao();
  }

  Future<void> _inicializarComPermissao() async {
    final podeAcessar = await _accessGuard.canAny([
      'pode_ver_detalhe_participacao_evento',
      'pode_gerenciar_participantes_evento',
    ]);

    if (!mounted) return;

    if (!podeAcessar) {
      setState(() {
        _acessoNegado = true;
        _carregandoPermissoes = false;
      });
      return;
    }

    await _verificarPermissoes();
    if (!mounted || _acessoNegado) return;
    await Future.wait([
      _carregarDados(),
      _verificarPatrocinio(),
      _carregarDadosAluno(),
    ]);
  }

  void _inicializarParticipacao() {
    _participacao = ParticipacaoModel(
      id: widget.participacaoId,
      alunoId: widget.participacao['aluno_id'] ?? '',
      alunoNome: widget.participacao['aluno_nome'] ?? '',
      alunoFoto: widget.participacao['aluno_foto'] as String?,
      eventoId: widget.eventoId,
      eventoNome: widget.participacao['evento_nome'] ?? '',
      dataEvento: widget.participacao['data_evento'] is Timestamp
          ? (widget.participacao['data_evento'] as Timestamp).toDate()
          : DateTime.now(),
      tipoEvento: widget.participacao['tipo_evento'] ?? 'EVENTO',
      graduacao: widget.participacao['graduacao'] as String?,
      graduacaoId: widget.participacao['graduacao_id'] as String?,
      tamanhoCamisa: widget.participacao['tamanho_camisa'] as String?,
      modelagemCamisa:
          widget.participacao['modelagem_camisa']?.toString() ?? 'NORMAL',
      tipoCamisa: widget.participacao['tipo_camisa']?.toString() ?? 'MANGA',
      linkCertificado: widget.participacao['link_certificado'] as String?,
      presente: widget.participacao['presente'] ?? false,
      status: widget.participacao['status'] ?? 'pendente',
      graduacaoNova: widget.participacao['graduacao_nova'] as String?,
      graduacaoNovaId: widget.participacao['graduacao_nova_id'] as String?,
      camisaEntregue: widget.participacao['camisa_entregue'] ?? false,
      valorInscricao: (widget.participacao['valor_inscricao'] ?? 0).toDouble(),
      valorCamisa: (widget.participacao['valor_camisa'] ?? 0).toDouble(),
    );

    debugPrint('📊 Participacao inicializada:');
    debugPrint('   - valorInscricao: ${_participacao.valorInscricao}');
    debugPrint('   - valorCamisa: ${_participacao.valorCamisa}');
    debugPrint('   - valorTotal: ${_participacao.valorTotal}');
    debugPrint('   - camisa: ${_participacao.descricaoCamisa}');
  }

  // 🔥 NOVO MÉTODO: Buscar dados atualizados do aluno com cache
  Future<Map<String, dynamic>> _buscarDadosAlunoAtualizados() async {
    final alunoId = _participacao.alunoId;

    // Verifica cache
    if (_cacheAluno.containsKey(alunoId)) {
      return _cacheAluno[alunoId]!;
    }

    try {
      final alunoDoc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(alunoId)
          .get();

      if (alunoDoc.exists) {
        final data = alunoDoc.data()!;
        final dadosAluno = {
          'foto': data['foto_perfil_aluno'] as String?,
          'nome': data['nome'] ?? '',
          'graduacao': data['graduacao_atual'] ?? '',
          'turma': data['turma'] as String?,
          'nivel_graduacao': data['nivel_graduacao'],
          'graduacao_id': data['graduacao_atual_id'],
          'data_nascimento': data['data_nascimento'],
          'tipo_publico': data['tipo_publico'],
          'contato_aluno': data['contato_aluno'] as String? ?? '',
          'contato_responsavel': data['contato_responsavel'] as String?,
        };

        // Armazena no cache
        _cacheAluno[alunoId] = dadosAluno;
        return dadosAluno;
      }
    } catch (e) {
      debugPrint('❌ Erro ao buscar dados do aluno: $e');
    }

    return {'foto': null, 'contato_aluno': '', 'contato_responsavel': null};
  }

  Future<void> _carregarDadosAluno() async {
    try {
      final alunoDoc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(_participacao.alunoId)
          .get();

      if (alunoDoc.exists) {
        _dadosAluno = alunoDoc.data();
        debugPrint('🎯 Dados do aluno carregados:');
        debugPrint('   - Nível atual: ${_dadosAluno?['nivel_graduacao']}');
        debugPrint('   - Graduação: ${_dadosAluno?['graduacao']}');
        debugPrint('   - Data nascimento: ${_dadosAluno?['data_nascimento']}');
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados do aluno: $e');
    }
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    try {
      // 🔥 DEBUG: Verifica o que tem no Firestore
      final docSnapshot = await FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .doc(widget.participacaoId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        _linkCertificadoServidor = _extrairLinkCertificado(data);
        debugPrint('🔍 DADOS NO FIRESTORE:');
        debugPrint('   - valorInscricao: ${data['valor_inscricao']}');
        debugPrint('   - valorCamisa: ${data['valor_camisa']}');
        debugPrint('   - total_pago: ${data['total_pago']}');
        debugPrint('   - linkCertificado: $_linkCertificadoServidor');
      }

      // 🔥 1º - Carrega a participação ATUALIZADA do Firestore
      final participacaoAtualizada = await _participacaoService.buscarPorId(
        widget.participacaoId,
      );

      if (participacaoAtualizada != null) {
        setState(() {
          final contrato = participacaoAtualizada['contrato_financeiro'];
          _contratoFinanceiro = contrato is Map
              ? Map<String, dynamic>.from(contrato)
              : null;
          _participacao = ParticipacaoModel.fromMap(
            widget.participacaoId,
            participacaoAtualizada,
          );
          _linkCertificadoServidor =
              _extrairLinkCertificado(participacaoAtualizada) ??
              _linkCertificadoServidor;
        });

        debugPrint('📊 Participação carregada:');
        debugPrint('   - valorInscricao: ${_participacao.valorInscricao}');
        debugPrint('   - valorCamisa: ${_participacao.valorCamisa}');
        debugPrint('   - valorTotal: ${_participacao.valorTotal}');
        debugPrint('   - totalPago (model): ${_participacao.totalPago}');
        debugPrint('   - camisa: ${_participacao.descricaoCamisa}');
      }

      // 🔥 2º - Carrega dados do evento
      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      if (eventoDoc.exists) {
        _dadosEvento = eventoDoc.data();
      }

      // 🔥 3º - Carrega pagamentos (apenas para histórico)
      final pagamentosSnapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .collection('participacoes')
          .doc(widget.participacaoId)
          .collection('pagamentos')
          .orderBy('data_pagamento', descending: true)
          .get();

      _pagamentos = pagamentosSnapshot.docs
          .map((doc) => PagamentoModel.fromMap(doc.id, doc.data()))
          .toList();

      // 🔥 4º - Recalcula totais usando o MODEL
      _calcularTotais();

      // 🔥 Limpa o cache do aluno para forçar recarregar
      _cacheAluno.remove(_participacao.alunoId);
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calcularTotais() {
    // 🔥 USA O totalPago DO MODEL, não recalcula dos pagamentos
    _totalPago = _participacao.totalPago;
    _saldo = _participacao.valorTotal - _totalPago;

    debugPrint('💰 Cálculo de totais:');
    debugPrint('   - Total evento: ${_participacao.valorTotal}');
    debugPrint('   - Total pago (model): ${_participacao.totalPago}');
    debugPrint('   - Saldo devedor: $_saldo');
  }

  void _mostrarSemPermissao([
    String mensagem = 'Você não tem permissão para executar esta ação.',
  ]) {
    _showSnackTema(
      mensagem,
      background: context.uai.error,
      icon: Icons.lock_rounded,
    );
  }

  Future<void> _recarregarTudo() async {
    await Future.wait([
      _carregarDados(),
      _verificarPermissoes(),
      _verificarPatrocinio(),
      _carregarDadosAluno(),
    ]);
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final permissoes = await Future.wait<bool>([
        _permissaoService.temQualquerPermissaoDireta([
          'pode_concluir_participacao_evento',
          'pode_finalizar_participacao',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_editar_camisa_participacao_evento',
          'pode_editar_camisa_evento',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_editar_graduacao_participacao_evento',
          'pode_editar_graduacao_evento',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_registrar_pagamento_evento',
          'pode_registrar_pagamento',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_editar_pagamento_evento',
          'pode_editar_pagamento',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_excluir_pagamento_evento',
          'pode_excluir_pagamento',
        ]),
      ]);

      if (!mounted) return;

      setState(() {
        _podeFinalizar = permissoes[0];
        _podeConcluirParticipacao = permissoes[0];
        _podeEditarCamisa = permissoes[1];
        _podeEditarGraduacao = permissoes[2];
        _podeRegistrarPagamento = permissoes[3];
        _podeEditarPagamento = permissoes[4];
        _podeExcluirPagamento = permissoes[5];
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões do detalhe da participação: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  Future<void> _verificarPatrocinio() async {
    try {
      final patrocinadoresSnapshot = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .where('saldo_disponivel', isGreaterThan: 0)
          .get();

      _temPatrocinio = patrocinadoresSnapshot.docs.isNotEmpty;

      if (_temPatrocinio) {
        debugPrint('🎯 Patrocínio disponível para este evento!');
      }
    } catch (e) {
      debugPrint('Erro ao verificar patrocínio: $e');
    }
  }

  bool _podeFinalizarAgora() {
    final hoje = DateTime.now();
    final dataEvento = _participacao.dataEvento;

    return (_podeFinalizar || _podeConcluirParticipacao) &&
        hoje.isAfter(dataEvento) &&
        !_participacao.estaFinalizado;
  }

  // 🔥 CONVERSÃO DE DATA (copiado do modal)

  // 🔥 PARSER DE DATA BRASILEIRA (copiado do modal)

  // 🔥 CALCULAR IDADE (copiado do modal)

  // 🔥 DETERMINAR CATEGORIA POR IDADE (copiado do modal)

  // 🔥 VERIFICAR SE PODE MUDAR PARA ADULTO (copiado do modal)

  Future<void> _registrarPagamento([Map<String, dynamic>? tentativa]) async {
    if (_isLoading) {
        return;
      }
    final podeRegistrar = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_registrar_pagamento_evento',
        'pode_registrar_pagamento',
      ],
      message: 'Você não tem permissão para registrar pagamentos.',
    );
    if (!podeRegistrar || !mounted) {
        return;
      }

    final result =
        tentativa ??
        await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => RegistrarPagamentoModal(
            saldoAtual: _saldo,
            valorTotal: _participacao.valorTotal,
            sugestoes: _gerarSugestoesPagamento(),
            temPatrocinio: _temPatrocinio,
            permiteParcelamento:
                (_contratoFinanceiro?['permite_parcelamento'] ??
                    _dadosEvento?['permiteParcelamento'] ??
                    _dadosEvento?['permite_parcelamento']) ==
                true,
            maxParcelas:
                ((_contratoFinanceiro?['max_parcelas'] ??
                            _dadosEvento?['maxParcelas'] ??
                            _dadosEvento?['max_parcelas'])
                        as num?)
                    ?.toInt() ??
                1,
          ),
        );

    if (result != null) {
      if (!mounted) return;
      if (result['formaPagamento'] == 'PATROCÍNIO') {
        final podeMarcarPatrocinio = await _accessGuard.revalidateAnyDirect(
          context,
          permissions: const [
            'pode_marcar_patrocinio_evento',
            'pode_marcar_patrocinio',
          ],
          message: 'Você não tem permissão para marcar patrocínio.',
        );
        if (!podeMarcarPatrocinio) {
        return;
      }
      }

      setState(() {
        _isLoading = true;
        _registrandoPagamento = true;
      });

      var confirmado = false;
      try {
        if (result['formaPagamento'] == 'PATROCÍNIO') {
          await _registrarPagamentoComPatrocinio(result);
        } else {
          await _registrarPagamentoNormal(result);
        }

        confirmado = true;
        await _carregarDados(); // Recarrega tudo

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Pagamento registrado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                confirmado
                    ? 'Pagamento registrado. Não foi possível atualizar a tela; recarregue os dados.'
                    : 'Pagamento não confirmado: $e',
              ),
              action: confirmado
                  ? null
                  : SnackBarAction(
                      label: 'Tentar novamente',
                      onPressed: () => _registrarPagamento(result),
                    ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _registrandoPagamento = false;
          });
        }
      }
    }
  }

  Future<void> _registrarPagamentoNormal(Map<String, dynamic> result) async {
    final pagamento = PagamentoModel(
      id: '',
      valor: result['valor'],
      formaPagamento: result['formaPagamento'],
      dataPagamento: DateTime.now(),
      observacoes: result['observacoes'],
      registroPor: FirebaseAuth.instance.currentUser?.uid ?? '',
      registroPorNome:
          FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário',
      anexo: result['anexo'],
      status: 'confirmado',
      parcela: result['parcela'],
    );

    await _pagamentoService.registrarPagamento(
      eventoId: widget.eventoId,
      participacaoId: widget.participacaoId,
      pagamento: pagamento,
    );

    // 🔥 ATUALIZA O MODEL COM O NOVO TOTAL PAGO
    final novoTotalPago = _participacao.totalPago + pagamento.valor;

    setState(() {
      _participacao = _participacao.copyWith(totalPago: novoTotalPago);
      _totalPago = novoTotalPago;
      _saldo = _participacao.valorTotal - novoTotalPago;
    });

    debugPrint('💰 NOVO SALDO CALCULADO:');
    debugPrint('   - Total evento: ${_participacao.valorTotal}');
    debugPrint('   - Total pago: ${_participacao.totalPago}');
    debugPrint('   - Saldo devedor: $_saldo');

    if (_saldo <= 0.01) {
      setState(() {
        _participacao = _participacao.copyWith(status: 'quitado');
      });
    }
  }

  Future<void> _registrarPagamentoComPatrocinio(
    Map<String, dynamic> result,
  ) async {
    final pagamento = PagamentoModel(
      id: '',
      valor: result['valor'],
      formaPagamento: 'PATROCÍNIO',
      dataPagamento: DateTime.now(),
      observacoes: 'Coberto por patrocínio: ${result['observacoes']}',
      registroPor: FirebaseAuth.instance.currentUser?.uid ?? '',
      registroPorNome:
          FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário',
      status: 'confirmado',
    );

    await _pagamentoService.registrarPagamento(
      eventoId: widget.eventoId,
      participacaoId: widget.participacaoId,
      pagamento: pagamento,
    );

    // ATUALIZA O MODEL COM O NOVO TOTAL PAGO
    final novoTotalPago = _participacao.totalPago + pagamento.valor;

    setState(() {
      _participacao = _participacao.copyWith(totalPago: novoTotalPago);
      _totalPago = novoTotalPago;
      _saldo = _participacao.valorTotal - novoTotalPago;
    });

    // 🔥 FIX: VERIFICA SE ZEROU O SALDO E ATUALIZA O STATUS
    if (_saldo <= 0.01) {
      setState(() {
        _participacao = _participacao.copyWith(status: 'quitado');
      });
    }

    // Reserva de patrocínio realizada na transação autenticada do pagamento.
  }

  Future<void> _recalcularTotalPagoDaParticipacao() async {
    final pagamentosSnapshot = await FirebaseFirestore.instance
        .collection('eventos')
        .doc(widget.eventoId)
        .collection('participacoes')
        .doc(widget.participacaoId)
        .collection('pagamentos')
        .where('status', isEqualTo: 'confirmado')
        .get();

    double totalConfirmado = 0;

    for (final doc in pagamentosSnapshot.docs) {
      final data = doc.data();
      totalConfirmado += (data['valor'] as num?)?.toDouble() ?? 0;
    }

    final novoStatus = totalConfirmado >= _participacao.valorTotal - 0.01
        ? 'quitado'
        : 'pendente';

    if (mounted) {
      setState(() {
        _participacao = _participacao.copyWith(
          totalPago: totalConfirmado,
          status: novoStatus,
        );
        _totalPago = totalConfirmado;
        _saldo = _participacao.valorTotal - totalConfirmado;
      });
    }
  }

  Future<void> _editarPagamento(PagamentoModel pagamento) async {
    final permitido = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_editar_pagamento_evento',
        'pode_editar_pagamento',
      ],
      message: 'Você não tem permissão para editar pagamentos.',
    );
    if (!permitido) {
      return;
    }

    if (!mounted) return;
    if (_participacao.estaFinalizado) {
      _mostrarSemPermissao(
        'Participação finalizada não permite editar pagamentos.',
      );
      return;
    }

    final valorController = TextEditingController(
      text: pagamento.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    final observacoesController = TextEditingController(
      text: pagamento.observacoes ?? '',
    );

    String formaSelecionada = pagamento.formaPagamento;
    String statusSelecionado = pagamento.status;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        final formas = <String>[
          'PIX',
          'DINHEIRO',
          'CARTÃO',
          'DÉBITO',
          'CRÉDITO',
          'PATROCÍNIO',
        ];

        final statuses = <String>['confirmado', 'pendente', 'cancelado'];

        if (!formas.contains(formaSelecionada)) {
          formas.add(formaSelecionada);
        }

        if (!statuses.contains(statusSelecionado)) {
          statuses.add(statusSelecionado);
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar pagamento'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: valorController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: formaSelecionada,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pagamento',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payment_rounded),
                      ),
                      items: formas
                          .map(
                            (forma) => DropdownMenuItem(
                              value: forma,
                              child: Text(forma),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => formaSelecionada = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: statusSelecionado,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.verified_rounded),
                      ),
                      items: statuses
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => statusSelecionado = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: observacoesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final valor =
                        double.tryParse(
                          valorController.text
                              .trim()
                              .replaceAll('R\$', '')
                              .replaceAll('.', '')
                              .replaceAll(',', '.'),
                        ) ??
                        0;

                    if (valor <= 0) {
                      Navigator.pop(context, {
                        'erro': 'Informe um valor válido.',
                      });
                      return;
                    }

                    Navigator.pop(context, {
                      'valor': valor,
                      'formaPagamento': formaSelecionada,
                      'status': statusSelecionado,
                      'observacoes': observacoesController.text.trim(),
                    });
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('SALVAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    if (result['erro'] != null) {
      _mostrarSemPermissao(result['erro'].toString());
      return;
    }

    setState(() => _isLoading = true);

    try {
      final novoValor = (result['valor'] as num).toDouble();
      final novasObservacoes = result['observacoes']?.toString() ?? '';

      await _pagamentoService.editarPagamento(
        eventoId: widget.eventoId,
        participacaoId: widget.participacaoId,
        pagamentoId: pagamento.id,
        valor: novoValor,
        formaPagamento: result['formaPagamento'].toString(),
        status: result['status'].toString(),
        observacoes: novasObservacoes,
      );

      await _recalcularTotalPagoDaParticipacao();
      await _carregarDados();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pagamento editado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Erro ao editar pagamento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao editar pagamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _excluirPagamento(PagamentoModel pagamento) async {
    final permitido = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_excluir_pagamento_evento',
        'pode_excluir_pagamento',
      ],
      message: 'Você não tem permissão para excluir pagamentos.',
    );
    if (!permitido) {
      return;
    }

    if (!mounted) return;
    if (_participacao.estaFinalizado) {
      _mostrarSemPermissao(
        'Participação finalizada não permite excluir pagamentos.',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir pagamento'),
        content: Text(
          'Deseja excluir o pagamento de ${_formatarMoeda(pagamento.valor)}?\\n\\n'
          'O total pago e o status da participação serão recalculados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('EXCLUIR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _pagamentoService.excluirPagamento(
        eventoId: widget.eventoId,
        participacaoId: widget.participacaoId,
        pagamentoId: pagamento.id,
      );

      await _recalcularTotalPagoDaParticipacao();
      await _carregarDados();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ Pagamento excluído e participação recalculada!'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      debugPrint('Erro ao excluir pagamento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir pagamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<double> _gerarSugestoesPagamento() {
    final sugestoes = <double>[];

    if (_saldo > 0) {
      sugestoes.add(_saldo);

      if (_saldo > 50) sugestoes.add(50.0);
      if (_saldo > 100) sugestoes.add(100.0);
      if (_saldo > 150) sugestoes.add(150.0);

      if (_participacao.valorCamisa > 0 &&
          _participacao.valorCamisa <= _saldo) {
        sugestoes.add(_participacao.valorCamisa);
      }

      if (_participacao.valorInscricao > 0 &&
          _participacao.valorInscricao <= _saldo) {
        sugestoes.add(_participacao.valorInscricao);
      }
    }

    return sugestoes.toSet().toList()..sort();
  }

  Future<void> _editarCamisa() async {
    final permitido = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_editar_camisa_participacao_evento',
        'pode_editar_camisa_evento',
      ],
      message: 'Você não tem permissão para editar camisa.',
    );
    if (!permitido) {
      return;
    }

    List<String> lerListaEvento({
      required List<String> chaves,
      required List<String> fallback,
    }) {
      try {
        if (_dadosEvento == null) return List<String>.from(fallback);

        for (final chave in chaves) {
          if (!_dadosEvento!.containsKey(chave)) continue;

          final rawValue = _dadosEvento![chave];

          if (rawValue is List) {
            final lista = rawValue
                .where((item) => item != null)
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList();

            if (lista.isNotEmpty) return lista;
          }

          if (rawValue is String && rawValue.trim().isNotEmpty) {
            final lista = rawValue
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList();

            if (lista.isNotEmpty) return lista;
          }
        }

        return List<String>.from(fallback);
      } catch (e) {
        debugPrint('❌ Erro ao processar lista do evento: $e');
        return List<String>.from(fallback);
      }
    }

    final tamanhosDisponiveis = lerListaEvento(
      chaves: const ['tamanhosDisponiveis', 'tamanhos_disponiveis'],
      fallback: const [
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
      ],
    );

    final modelagensDisponiveis = lerListaEvento(
      chaves: const [
        'modelagensCamisaDisponiveis',
        'modelagens_camisa_disponiveis',
        'modelagensDisponiveis',
        'modelagens_disponiveis',
      ],
      fallback: const ['NORMAL', 'BABY_LOOK'],
    );

    final tiposDisponiveis = lerListaEvento(
      chaves: const [
        'tiposCamisaDisponiveis',
        'tipos_camisa_disponiveis',
        'tiposDisponiveis',
        'tipos_disponiveis',
      ],
      fallback: const ['MANGA', 'MANGA_LONGA', 'REGATA'],
    );

    debugPrint('📏 Tamanhos disponíveis processados: $tamanhosDisponiveis');
    debugPrint('👕 Modelagens disponíveis processadas: $modelagensDisponiveis');
    debugPrint('🧵 Tipos disponíveis processados: $tiposDisponiveis');

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditarCamisaModal(
        tamanhoAtual: _participacao.tamanhoCamisa,
        modelagemAtual: _participacao.modelagemCamisa,
        tipoAtual: _participacao.tipoCamisa,
        entregue: _participacao.camisaEntregue,
        tamanhosDisponiveis: tamanhosDisponiveis,
        modelagensDisponiveis: modelagensDisponiveis,
        tiposDisponiveis: tiposDisponiveis,
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      try {
        final novoTamanho = result['tamanho']?.toString();
        final novaModelagem =
            (result['modelagem_camisa'] ??
                    result['modelagemCamisa'] ??
                    'NORMAL')
                .toString();
        final novoTipo =
            (result['tipo_camisa'] ?? result['tipoCamisa'] ?? 'MANGA')
                .toString();
        final entregue = result['entregue'] == true;
        final novoValorCamisa = _valorCamisaEventoPorTipo(novoTipo);

        await _participacaoService.atualizarCamisa(
          participacaoId: widget.participacaoId,
          tamanho: novoTamanho,
          entregue: entregue,
          modelagemCamisa: novaModelagem,
          tipoCamisa: novoTipo,
          valorCamisa: novoValorCamisa,
        );

        setState(() {
          _participacao = _participacao.copyWith(
            tamanhoCamisa: novoTamanho,
            modelagemCamisa: novaModelagem,
            tipoCamisa: novoTipo,
            camisaEntregue: entregue,
            valorCamisa: novoValorCamisa,
          );
          _calcularTotais();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Camisa atualizada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _editarGraduacao() async {
    final permitido = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_editar_graduacao_participacao_evento',
        'pode_editar_graduacao_evento',
      ],
      message: 'Você não tem permissão para editar graduação.',
    );
    if (!permitido) {
      return;
    }

    // 🔥 Garantir que temos os dados do aluno
    if (_dadosAluno == null) {
      await _carregarDadosAluno();
    }

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => EditarGraduacaoModal(
        graduacaoAtualId: _participacao.graduacaoId,
        graduacaoNovaId: _participacao.graduacaoNovaId,
        eventoId: widget.eventoId,
        aluno: _dadosAluno, // 👈 CORRIGIDO: era 'dadosAluno', agora é 'aluno'
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      try {
        final graduacao = await _graduacaoService.buscarPorId(result);

        if (graduacao != null) {
          await _participacaoService.atualizarGraduacaoNova(
            participacaoId: widget.participacaoId,
            graduacaoNovaId: result,
            graduacaoNovaNome: graduacao['nome_graduacao'] ?? '',
          );

          setState(() {
            _participacao = _participacao.copyWith(
              graduacaoNovaId: result,
              graduacaoNova: graduacao['nome_graduacao'],
            );
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ Graduação atualizada para: ${graduacao['nome_graduacao']}',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _finalizarParticipacao() async {
    final permitido = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_concluir_participacao_evento',
        'pode_finalizar_participacao',
      ],
      message: 'Você não tem permissão para concluir participação.',
    );
    if (!permitido) return;

    if (!mounted || !_podeFinalizarAgora()) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar Participação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja finalizar esta participação?'),
            if (_participacao.isBatizado) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A graduação do aluno será atualizada para: ${_participacao.graduacaoNova ?? 'NÃO DEFINIDA'}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_saldo > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saldo pendente: ${_formatarMoeda(_saldo)}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('FINALIZAR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        final linkCertificado = await _obterLinkCertificadoReal();

        await _participacaoService.finalizarParticipacao(
          participacaoId: widget.participacaoId,
          linkCertificado: linkCertificado,
          novaGraduacao: _participacao.graduacaoNova,
          novaGraduacaoId: _participacao.graduacaoNovaId,
        );

        if (_participacao.isBatizado && _participacao.graduacaoNovaId != null) {
          await _graduacaoService.atualizarGraduacaoAluno(
            alunoId: _participacao.alunoId,
            novaGraduacaoId: _participacao.graduacaoNovaId!,
            novaGraduacaoNome: _participacao.graduacaoNova!,
            dataGraduacao: _participacao.dataEvento,
            eventoId: widget.eventoId,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Participação finalizada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        debugPrint('Erro ao finalizar: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao finalizar: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _obterLinkCertificadoReal() async {
    // 🔥 PRIORIDADE 1: qualquer link que já veio no model/tela/servidor.
    final linkAtual = _certificadoAtual();
    if (linkAtual != null && linkAtual.isNotEmpty) {
      debugPrint(
        '📄 Certificado usado ao finalizar (${_tipoLinkCertificado(linkAtual)}): $linkAtual',
      );
      return linkAtual;
    }

    // 🔥 PRIORIDADE 2: busca direto no documento em andamento.
    // Híbrido: aceita Firebase Storage, Google Drive ou link externo.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .doc(widget.participacaoId)
          .get();

      final linkFirestore = _extrairLinkCertificado(doc.data());

      if (linkFirestore != null && linkFirestore.isNotEmpty) {
        debugPrint(
          '📄 Certificado encontrado no Firestore (${_tipoLinkCertificado(linkFirestore)}): $linkFirestore',
        );
        return linkFirestore;
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar link real do certificado: $e');
    }

    // 🔥 Se não tiver certificado ainda, retorna null.
    // O service não vai gravar link falso nem apagar link existente.
    return null;
  }

  String _formatarMoeda(double valor) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
  }

  Color _getCorGraduacao(String? graduacao) {
    if (graduacao == null) return Colors.grey;
    if (graduacao.contains('BRANCA')) return Colors.grey;
    if (graduacao.contains('AMARELA')) return Colors.amber;
    if (graduacao.contains('LARANJA')) return Colors.orange;
    if (graduacao.contains('AZUL')) return Colors.blue;
    if (graduacao.contains('VERDE')) return Colors.green;
    if (graduacao.contains('ROXA')) return Colors.purple;
    if (graduacao.contains('MARROM')) return Colors.brown;
    if (graduacao.contains('VERMELHA')) return Colors.red;
    return Colors.grey;
  }

  // 📞 FUNÇÕES DE WHATSAPP COM SVG (IGUAL AO DA REFERÊNCIA)
  Widget _buildWhatsAppIcon({required bool enabled, required Color color}) {
    return SvgPicture.asset(
      'assets/images/whatsapp.svg',
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(
        enabled ? color : Colors.grey.shade400,
        BlendMode.srcIn,
      ),
    );
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

  Future<void> _abrirWhatsApp(String numero, {String? mensagem}) async {
    try {
      String cleanedPhone = _formatarNumeroWhatsApp(numero);
      String url = 'https://wa.me/$cleanedPhone';

      if (mensagem != null && mensagem.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(mensagem);
        url += '?text=$encodedMessage';
      }

      final uri = Uri.parse(url);

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
          'https://web.whatsapp.com/send?phone=$cleanedPhone${mensagem != null && mensagem.isNotEmpty ? '&text=${Uri.encodeComponent(mensagem)}' : ''}',
        );

        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o WhatsApp.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 🔥 MÉTODO: Widget da foto do aluno
  Widget _buildFotoAluno() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarDadosAlunoAtualizados(),
      builder: (context, snapshot) {
        final fotoUrl = snapshot.data?['foto'];

        final inicial = _participacao.alunoNome.trim().isNotEmpty
            ? _participacao.alunoNome.trim()[0].toUpperCase()
            : '?';

        return CircleAvatar(
          radius: 40,
          backgroundColor: context.uai.card,
          backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
              ? NetworkImage(fotoUrl)
              : null,
          child: fotoUrl == null || fotoUrl.isEmpty
              ? Text(
                  inicial,
                  style: TextStyle(
                    fontSize: 32,
                    color: context.uai.primary,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final certificado = _certificadoAtual();

    if (_carregandoPermissoes) {
      return PermissionAccessGuard.loadingScaffold(
        context,
        title: 'Detalhe da participação',
      );
    }

    if (_acessoNegado) {
      return PermissionAccessGuard.deniedScaffold(
        context,
        title: 'Detalhe da participação',
        message:
            'Você não tem permissão para acessar o detalhe da participação.',
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          _participacao.alunoNome,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _recarregarTudo,
            tooltip: 'Recarregar dados e permissões',
          ),
          if (_podeFinalizarAgora())
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Icon(Icons.check_circle, color: t.success),
                onPressed: _isLoading ? null : _finalizarParticipacao,
                tooltip: 'Finalizar participação',
              ),
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingTema()
          : RefreshIndicator(
              onRefresh: _recarregarTudo,
              color: t.primary,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth < 620 ? 14.0 : 22.0;

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      16,
                      horizontal,
                      30,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildAlunoHeaderTema(),
                              const SizedBox(height: 14),
                              _buildContatosRapidosTema(),
                              const SizedBox(height: 14),
                              if (_dadosEvento?['temCobrancaInscricao'] !=
                                  false) ...[
                                _buildResumoFinanceiroTema(),
                                const SizedBox(height: 14),
                                _buildPagamentosSectionTema(),
                              ],
                              if (_dadosEvento?['temCobrancaInscricao'] !=
                                      false &&
                                  _podeRegistrarPagamento &&
                                  !_participacao.estaFinalizado &&
                                  _saldo > 0) ...[
                                const SizedBox(height: 12),
                                _buildNovoPagamentoButtonTema(),
                              ],
                              const SizedBox(height: 14),
                              if (_dadosEvento?['temCamisa'] == true ||
                                  _dadosEvento?['tem_camisa'] == true)
                                _buildCamisaSectionTema(),
                              if (_participacao.isBatizado) ...[
                                const SizedBox(height: 14),
                                _buildGraduacaoSectionTema(),
                              ],
                              const SizedBox(height: 14),
                              if (_dadosEvento?['tem_certificado'] == true ||
                                  _dadosEvento?['temCertificado'] == true)
                                _buildCertificadoHibridoCardTema(certificado),
                              const SizedBox(height: 14),
                              if (_podeFinalizarAgora())
                                _buildFinalizarButtonTema(),
                              if (!_participacao.estaFinalizado &&
                                  !_podeFinalizarAgora())
                                _buildAvisoAguardandoEventoTema(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildLoadingTema() {
    final t = context.uai;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius + 2),
          border: Border.all(color: t.border),
          boxShadow: t.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 14),
            Text(
              _registrandoPagamento
                  ? 'Registrando pagamento...'
                  : 'Carregando participação...',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlunoHeaderTema() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 4),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          _buildFotoAluno(),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _participacao.alunoNome,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: onPrimary,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _heroChipTema(
                      icon: Icons.verified_rounded,
                      label: _participacao.textoStatus,
                      color: onPrimary,
                    ),
                    if (_participacao.presente)
                      _heroChipTema(
                        icon: Icons.how_to_reg_rounded,
                        label: 'Presente',
                        color: onPrimary,
                      ),
                    if (_carregandoPermissoes)
                      _heroChipTema(
                        icon: Icons.sync_rounded,
                        label: 'Permissões...',
                        color: onPrimary,
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

  Widget _heroChipTema({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withAlpha(46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContatosRapidosTema() {
    final t = context.uai;

    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarDadosAlunoAtualizados(),
      builder: (context, snapshot) {
        final dadosAluno = snapshot.data ?? {};
        final contatoAluno = dadosAluno['contato_aluno'] as String? ?? '';
        final contatoResponsavel = dadosAluno['contato_responsavel'] as String?;

        return _sectionCardTema(
          icon: Icons.chat_rounded,
          title: 'Contatos rápidos',
          subtitle: 'WhatsApp do aluno ou responsável',
          color: t.success,
          slim: true,
          child: Row(
            children: [
              Expanded(
                child: _whatsButtonTema(
                  label: 'Aluno',
                  onPressed: contatoAluno.isNotEmpty
                      ? () => _abrirWhatsApp(contatoAluno)
                      : null,
                  color: t.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _whatsButtonTema(
                  label: 'Responsável',
                  onPressed:
                      contatoResponsavel != null &&
                          contatoResponsavel.isNotEmpty
                      ? () => _abrirWhatsApp(contatoResponsavel)
                      : null,
                  color: t.info,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _whatsButtonTema({
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    final enabled = onPressed != null;

    return Material(
      color: Color.alphaBlend(accent.withAlpha(enabled ? 20 : 8), t.card),
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(
              color: enabled ? accent.withAlpha(46) : t.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildWhatsAppIcon(enabled: enabled, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: enabled ? t.textPrimary : t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoFinanceiroTema() {
    final t = context.uai;

    return _sectionCardTema(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Resumo financeiro',
      subtitle: 'Valor devido, já pago e quanto falta quitar',
      color: t.info,
      slim: true,
      child: Row(
        children: [
          Expanded(
            child: _miniInfoCardTema(
              'Dívida total',
              _formatarMoeda(_participacao.valorTotal),
              Icons.receipt_rounded,
              t.info,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniInfoCardTema(
              'Já pago',
              _formatarMoeda(_totalPago),
              Icons.check_circle_rounded,
              t.success,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniInfoCardTema(
              _saldo > 0 ? 'Falta pagar' : 'Quitado',
              _formatarMoeda(_saldo > 0 ? _saldo : 0),
              _saldo > 0
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              _saldo > 0 ? t.error : t.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInfoCardTema(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withAlpha(20),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withAlpha(41)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              color: t.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagamentosSectionTema() {
    final t = context.uai;

    return _sectionCardTema(
      icon: Icons.payments_rounded,
      title: 'Pagamentos',
      subtitle: _pagamentos.isEmpty
          ? 'Nenhum pagamento registrado'
          : '${_pagamentos.length} pagamento(s) no histórico',
      color: t.success,
      trailing:
          _podeRegistrarPagamento && !_participacao.estaFinalizado && _saldo > 0
          ? TextButton.icon(
              onPressed: _registrarPagamento,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Novo'),
              style: TextButton.styleFrom(
                foregroundColor: t.success,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      child: Column(
        children: [
          if (_pagamentos.isEmpty)
            _emptyBoxTema(
              icon: Icons.payment_rounded,
              title: 'Nenhum pagamento registrado',
              subtitle: 'Quando houver pagamento, ele aparecerá aqui.',
              color: t.textMuted,
            )
          else
            ..._pagamentos.map(_buildPagamentoCardTema),
          if (_participacao.parcelas > 0 && _saldo > 0) ...[
            const SizedBox(height: 12),
            Divider(color: t.border),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Parcelas pendentes',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ..._buildParcelasPendentesTema(),
          ],
        ],
      ),
    );
  }

  Widget _buildNovoPagamentoButtonTema() {
    final t = context.uai;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _registrarPagamento,
        icon: const Icon(Icons.pix_rounded),
        label: Text(
          'NOVO PAGAMENTO (${_formatarMoeda(_saldo)})',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: t.success,
          foregroundColor: _readableOn(t.success),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
        ),
      ),
    );
  }

  Widget _buildCamisaSectionTema() {
    final t = context.uai;

    return _sectionCardTema(
      icon: Icons.shopping_bag_rounded,
      title: 'Camisa',
      subtitle: 'Modelagem, tipo, tamanho e entrega',
      color: t.info,
      trailing: _podeEditarCamisa
          ? IconButton(
              onPressed: _editarCamisa,
              icon: Icon(Icons.edit_rounded, color: t.info),
              tooltip: 'Editar camisa',
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final modelagem = _infoTileTema(
            'Modelagem',
            _participacao.modelagemCamisaLabel,
            Icons.style_rounded,
            t.associacao,
          );

          final tipo = _infoTileTema(
            'Tipo',
            _participacao.tipoCamisaLabel,
            Icons.design_services_rounded,
            t.info,
          );

          final tamanho = _infoTileTema(
            'Tamanho',
            _participacao.tamanhoCamisa ?? 'Não definido',
            Icons.straighten_rounded,
            t.info,
          );

          final status = _infoTileTema(
            'Status',
            _participacao.camisaEntregue ? 'Entregue' : 'Pendente',
            _participacao.camisaEntregue
                ? Icons.check_circle_rounded
                : Icons.access_time_rounded,
            _participacao.camisaEntregue ? t.success : t.warning,
          );

          if (narrow) {
            return Column(
              children: [
                modelagem,
                const SizedBox(height: 10),
                tipo,
                const SizedBox(height: 10),
                tamanho,
                const SizedBox(height: 10),
                status,
              ],
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: modelagem),
                  const SizedBox(width: 12),
                  Expanded(child: tipo),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: tamanho),
                  const SizedBox(width: 12),
                  Expanded(child: status),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGraduacaoSectionTema() {
    final t = context.uai;
    final atualColor = _ensureVisible(
      _getCorGraduacao(_participacao.graduacao),
      t.card,
    );
    final novaColor = _ensureVisible(
      _getCorGraduacao(_participacao.graduacaoNova),
      t.card,
    );

    return _sectionCardTema(
      icon: Icons.school_rounded,
      title: 'Graduação',
      subtitle: 'Graduação atual e nova graduação no evento',
      color: t.associacao,
      trailing: _podeEditarGraduacao && !_participacao.estaFinalizado
          ? IconButton(
              onPressed: _editarGraduacao,
              icon: Icon(Icons.edit_rounded, color: t.info),
              tooltip: 'Editar graduação',
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final atual = _infoTileTema(
            'Atual',
            _participacao.graduacao ?? '—',
            Icons.circle_rounded,
            atualColor,
          );

          final nova = _infoTileTema(
            'Nova',
            _participacao.graduacaoNova ?? '—',
            Icons.circle_rounded,
            novaColor,
          );

          if (narrow) {
            return Column(
              children: [
                atual,
                const SizedBox(height: 10),
                Icon(Icons.arrow_downward_rounded, color: t.textMuted),
                const SizedBox(height: 10),
                nova,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: atual),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: t.textMuted),
              const SizedBox(width: 10),
              Expanded(child: nova),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCertificadoHibridoCardTema(String? link) {
    final t = context.uai;
    final temCertificado = link != null && link.isNotEmpty;
    final accent = temCertificado
        ? _ensureVisible(t.success, t.card)
        : _ensureVisible(t.warning, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: temCertificado ? () => _abrirLink(link) : null,
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withAlpha(18), t.card),
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: accent.withAlpha(51)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBoxTema(
                temCertificado
                    ? Icons.picture_as_pdf_rounded
                    : Icons.hourglass_empty_rounded,
                accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      temCertificado
                          ? 'Certificado vinculado'
                          : 'Certificado ainda não vinculado',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      temCertificado
                          ? 'Origem: ${_tipoLinkCertificado(link)} • toque para abrir'
                          : 'Gere ou envie o PDF pronto no gerador de certificados antes de finalizar.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (temCertificado) ...[
                      const SizedBox(height: 8),
                      Text(
                        link,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10.8,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (temCertificado) ...[
                const SizedBox(width: 8),
                Icon(Icons.open_in_new_rounded, color: accent, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinalizarButtonTema() {
    final t = context.uai;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _finalizarParticipacao,
        icon: const Icon(Icons.check_circle_rounded),
        label: Text(
          _participacao.isBatizado
              ? 'FINALIZAR PARTICIPAÇÃO (atualiza graduação)'
              : 'FINALIZAR PARTICIPAÇÃO',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: t.success,
          foregroundColor: _readableOn(t.success),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoAguardandoEventoTema() {
    final t = context.uai;
    final warning = _ensureVisible(t.warning, t.card);

    return _alertBoxTema(
      icon: Icons.info_rounded,
      color: warning,
      title: 'Aguardando data do evento',
      text:
          'A finalização estará disponível a partir de ${_formatarData(_participacao.dataEvento)}',
    );
  }

  Widget _buildPagamentoCardTema(PagamentoModel pagamento) {
    final t = context.uai;
    final confirmed = pagamento.status == 'confirmado';
    final cor = _ensureVisible(confirmed ? t.success : t.warning, t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withAlpha(18),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: cor.withAlpha(38)),
      ),
      child: Row(
        children: [
          _iconBoxTema(
            confirmed ? Icons.check_circle_rounded : Icons.schedule_rounded,
            cor,
            size: 42,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatarMoeda(pagamento.valor),
                  style: TextStyle(
                    color: cor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pagamento.formaPagamento} • ${_formatarData(pagamento.dataPagamento)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textSecondary, fontSize: 11.5),
                ),
                if ((pagamento.observacoes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    pagamento.observacoes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _statusChipTema(pagamento.status.toUpperCase(), cor),
              if ((_podeEditarPagamento || _podeExcluirPagamento) &&
                  !_participacao.estaFinalizado) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_podeEditarPagamento)
                      _smallIconButtonTema(
                        icon: Icons.edit_rounded,
                        color: t.info,
                        onTap: () => _editarPagamento(pagamento),
                      ),
                    if (_podeExcluirPagamento)
                      _smallIconButtonTema(
                        icon: Icons.delete_outline_rounded,
                        color: t.error,
                        onTap: () => _excluirPagamento(pagamento),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildParcelasPendentesTema() {
    final t = context.uai;
    final parcelas = <Widget>[];

    if (_saldo <= 0) return parcelas;

    final sugestoes = _gerarSugestoesPagamento();

    if (sugestoes.isEmpty) {
      parcelas.add(
        _alertBoxTema(
          icon: Icons.warning_amber_rounded,
          color: t.warning,
          title: 'Saldo pendente',
          text: 'Ainda existe saldo pendente.',
        ),
      );
      return parcelas;
    }

    for (final valor in sugestoes) {
      parcelas.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.warning.withAlpha(18),
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.warning.withAlpha(41)),
          ),
          child: Row(
            children: [
              _iconBoxTema(Icons.payments_rounded, t.warning, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  valor >= _saldo - 0.01
                      ? 'Quitar saldo restante'
                      : 'Pagamento sugerido',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _formatarMoeda(valor),
                style: TextStyle(
                  color: _ensureVisible(t.warning, t.card),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return parcelas;
  }

  Widget _sectionCardTema({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
    Widget? trailing,
    bool slim = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: EdgeInsets.all(slim ? 13 : 15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withAlpha(41)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _iconBoxTema(icon, accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: slim ? 10 : 14),
          child,
        ],
      ),
    );
  }

  Widget _infoTileTema(String label, String value, IconData icon, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.8,
                    color: t.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                    height: 1.18,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBoxTema(IconData icon, Color color, {double size = 42}) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withAlpha(31),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: accent.withAlpha(51)),
      ),
      child: Icon(icon, color: accent, size: size * 0.52),
    );
  }

  Widget _smallIconButtonTema({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 18, color: accent),
      ),
    );
  }

  Widget _statusChipTema(String label, Color color) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(36)),
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

  Widget _emptyBoxTema({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: accent),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertBoxTema({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent.withAlpha(20),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withAlpha(46)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    height: 1.25,
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

  Future<void> _abrirLink(String? url) async {
    final cleaned = _stringLimpa(url);
    if (cleaned == null) return;

    try {
      var finalUrl = cleaned;

      // Drive antigo/compartilhado: abre em modo preview.
      if (cleaned.contains('drive.google.com')) {
        final regex = RegExp(r'/d/([a-zA-Z0-9_-]+)');
        final match = regex.firstMatch(cleaned);

        if (match != null && match.groupCount >= 1) {
          final fileId = match.group(1);
          finalUrl = 'https://drive.google.com/file/d/$fileId/preview';
        }
      }

      final uri = Uri.parse(finalUrl);

      // Não usa canLaunchUrl como bloqueio, porque em alguns Android ele retorna
      // false mesmo tendo navegador instalado, gerando log "component name is null".
      final openedExternal = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (openedExternal) return;

      final openedDefault = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );

      if (!mounted) return;
      if (!openedDefault) {
        _showSnackTema(
          'Não foi possível abrir o certificado.',
          background: context.uai.error,
          icon: Icons.error_outline_rounded,
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
      if (!mounted) return;
      _showSnackTema(
        'Erro ao abrir certificado: $e',
        background: context.uai.error,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  @override
  void dispose() {
    _cacheAluno.clear();
    super.dispose();
  }
}
