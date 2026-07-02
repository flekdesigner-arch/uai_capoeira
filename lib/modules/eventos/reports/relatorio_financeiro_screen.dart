// lib/screens/relatorios/relatorio_financeiro_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// 👈 ALIAS PARA EVITAR CONFLITO DE NOMES
import 'package:flutter/material.dart' as material;

// 🔥 SERVIÇO DE PDFs DO EVENTO (Confecção, Relatório Geral, Lista de Participantes)
import 'evento_financeiro_pdf_service.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/responsive/uai_responsive.dart';

class RelatorioFinanceiroScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  RelatorioFinanceiroScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<RelatorioFinanceiroScreen> createState() =>
      _RelatorioFinanceiroScreenState();
}

class _RelatorioFinanceiroScreenState extends State<RelatorioFinanceiroScreen> {
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  bool _isLoading = false;
  String _loadingEtapa = 'Preparando relatório...';
  final List<String> _loadingLogs = [];

  final PermissaoService _permissaoService = PermissaoService();
  bool _carregandoPermissoes = true;
  bool _podeVerRelatorio = false;
  bool _podeExportarRelatorio = false;
  bool _podeGerarCertificados = false;

  // Valores oficiais configurados no evento para confecção.
  // O relatório usa estes valores como prioridade para não cair em valores antigos
  // que já estavam salvos nas participações/camisas antes da refatoração.
  Map<String, double> _valoresPorTipoCamisaEvento = {
    'MANGA': 0,
    'MANGA_LONGA': 0,
    'REGATA': 0,
  };

  // Dados consolidados
  double _totalReceitas = 0;
  double _totalGastos = 0;
  double _saldoLiquido = 0;
  int _totalParticipantes = 0;

  // STATUS DAS PARTICIPAÇÕES
  int _quitados = 0;
  int _inadimplentes = 0;
  int _cobertosPorPatrocinio = 0;

  // RECEITAS POR TIPO
  double _totalInscricoes = 0;
  double _totalCamisas = 0;
  double _totalPatrocinios = 0;

  // RECEITAS POR FORMA DE PAGAMENTO
  Map<String, double> _receitasPorForma = {};

  // GASTOS POR CATEGORIA
  Map<String, double> _gastosPorCategoria = {};

  // DETALHAMENTO DE CAMISAS
  Map<String, dynamic> _detalhesCamisas = {
    'total_camisas': 0,
    'camisas_pagas': 0,
    'valor_total_camisas': 0,
    'valor_total_pedido': 0.0,
    'por_tamanho': <String, int>{},
    'por_detalhe': <String, int>{},
    'por_detalhe_valor_unitario': <String, double>{},
    'por_detalhe_total': <String, double>{},
  };

  // CAMISAS DOS ALUNOS (participações)
  Map<String, dynamic> _camisasParticipacoes = {
    'total': 0,
    'pagas': 0,
    'valor': 0,
    'valor_total_pedido': 0.0,
    'por_tamanho': <String, int>{},
    'por_detalhe': <String, int>{},
    'por_detalhe_valor_unitario': <String, double>{},
    'por_detalhe_total': <String, double>{},
  };

  // CAMISAS AVULSAS
  Map<String, dynamic> _camisasAvulsas = {
    'total': 0,
    'pagas': 0,
    'valor': 0,
    'valor_total_pedido': 0.0,
    'por_tamanho': <String, int>{},
    'por_detalhe': <String, int>{},
    'por_detalhe_valor_unitario': <String, double>{},
    'por_detalhe_total': <String, double>{},
  };

  // DETALHAMENTO DE PATROCÍNIOS
  Map<String, dynamic> _detalhesPatrocinios = {
    'total_patrocinadores': 0,
    'patrocinios_pagos': 0,
    'valor_total_patrocinios': 0,
    'patrocinios_pendentes': 0,
  };

  // USOS DE PATROCÍNIO (alunos beneficiados)
  List<Map<String, dynamic>> _usosPatrocinio = [];

  // 🔥 CONSISTÊNCIA / LIMPEZA AUTOMÁTICA
  int _participacoesDuplicadasIgnoradas = 0;
  int _participacoesRemovidasIgnoradas = 0;
  int _usosPatrocinioOrfaosIgnorados = 0;
  int _usosPatrocinioDuplicadosIgnorados = 0;
  Set<String> _chavesParticipantesValidos = {};
  Set<String> _nomesParticipantesValidos = {};
  Set<String> _chavesParticipantesPatrocinados = {};

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
  Color _onError() => _readableOn(context.uai.error);
  Color _onInfo() => _readableOn(context.uai.info);
  Color _onWarning() => _readableOn(context.uai.warning);
  Color _onAssociacao() => _readableOn(context.uai.associacao);

  Color _shadowColor([double opacity = 0.08]) {
    final isDark = context.uai.background.computeLuminance() < 0.35;
    return Color(0xFF000000).withOpacity(isDark ? opacity * 2.1 : opacity);
  }

  BoxShadow _softBoxShadow([double opacity = 0.06]) {
    return BoxShadow(
      color: _shadowColor(opacity),
      blurRadius: 10,
      offset: const Offset(0, 4),
    );
  }

  BoxDecoration _themedCardDecoration({
    Color? borderColor,
    Color? backgroundColor,
    double? radius,
    bool strongShadow = false,
  }) {
    final t = context.uai;

    return BoxDecoration(
      color: backgroundColor ?? t.card,
      borderRadius: BorderRadius.circular(radius ?? t.cardRadius),
      border: material.Border.all(color: borderColor ?? t.border),
      boxShadow: strongShadow ? t.cardShadow : t.softShadow,
    );
  }

  Color _statusColor(Color color) => _ensureVisible(color, context.uai.card);

  // ==================== CAMISAS: MODELAGEM / TIPO / TAMANHO ====================
  String _normalizarModelagemCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return 'BABY_LOOK';
    }

    return 'NORMAL';
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

    if (clean == 'REGATA') return 'REGATA';

    return 'MANGA';
  }

  String _modelagemCamisaLabel(dynamic value) {
    switch (_normalizarModelagemCamisa(value)) {
      case 'BABY_LOOK':
        return 'Baby Look';
      case 'NORMAL':
      default:
        return 'Normal';
    }
  }

  String _tipoCamisaLabel(dynamic value) {
    switch (_normalizarTipoCamisa(value)) {
      case 'MANGA_LONGA':
        return 'Manga Longa';
      case 'REGATA':
        return 'Regata';
      case 'MANGA':
      default:
        return 'Manga';
    }
  }

  String _normalizarTamanhoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'null') return 'OUTRO';

    return raw
        .replaceAll(' ', '')
        .replaceAll('ANOS', 'A')
        .replaceAll('ANO', 'A');
  }

  String _chaveGradeCamisa(Map<String, dynamic> data) {
    final modelagem = _normalizarModelagemCamisa(
      data['modelagem_camisa'] ??
          data['modelagemCamisa'] ??
          data['modelagem'] ??
          'NORMAL',
    );

    final tipo = _normalizarTipoCamisa(
      data['tipo_camisa'] ?? data['tipoCamisa'] ?? data['tipo'] ?? 'MANGA',
    );

    final tamanho = _normalizarTamanhoCamisa(
      data['tamanho_camisa'] ?? data['tamanho'] ?? data['tamanhoCamisa'],
    );

    return '$modelagem|$tipo|$tamanho';
  }

  double _asDoubleSeguro(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().replaceAll(',', '.').trim() ?? '';
    if (text.isEmpty) return fallback;

    return double.tryParse(text) ?? fallback;
  }

  Map<String, double> _normalizarValoresPorTipoCamisaEvento(
    dynamic raw, {
    double fallback = 0,
  }) {
    final result = <String, double>{
      'MANGA': fallback,
      'MANGA_LONGA': fallback,
      'REGATA': fallback,
    };

    if (raw is Map) {
      raw.forEach((key, value) {
        final tipo = _normalizarTipoCamisa(key);
        result[tipo] = _asDoubleSeguro(value, fallback: fallback);
      });
    }

    return result;
  }

  Future<void> _carregarValoresCamisaDoEvento() async {
    try {
      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      final data = eventoDoc.data();

      if (data == null) return;

      final fallback = _asDoubleSeguro(
        data['valorCamisa'] ?? data['valor_camisa'],
      );

      final valores = _normalizarValoresPorTipoCamisaEvento(
        data['valoresPorTipoCamisa'] ??
            data['valores_por_tipo_camisa'] ??
            data['valoresTipoCamisa'] ??
            data['valores_tipo_camisa'],
        fallback: fallback,
      );

      _valoresPorTipoCamisaEvento = valores;

      debugPrint(
        '👕 Valores oficiais de camisa do evento: $_valoresPorTipoCamisaEvento',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar valores oficiais das camisas: $e');
    }
  }

  double _valorOficialPorTipoCamisa(dynamic tipoCamisa) {
    final tipo = _normalizarTipoCamisa(tipoCamisa);
    return _valoresPorTipoCamisaEvento[tipo] ?? 0;
  }

  double _valorUnitarioCamisa(Map<String, dynamic> data) {
    final tipo = _normalizarTipoCamisa(
      data['tipo_camisa'] ?? data['tipoCamisa'] ?? data['tipo'] ?? 'MANGA',
    );

    // Prioridade 1: valor oficial configurado no evento.
    // Isso corrige camisas antigas que ficaram com R$ 30,00, R$ 3,00,
    // ou sem valor salvo antes da refatoração.
    final valorOficial = _valorOficialPorTipoCamisa(tipo);
    if (valorOficial > 0) return valorOficial;

    // Prioridade 2: valor salvo no próprio documento, para compatibilidade
    // com eventos antigos que ainda não têm valoresPorTipoCamisa.
    final candidatos = [
      data['valor_unitario'],
      data['valorUnitario'],
      data['valor_camisa'],
      data['valorCamisa'],
      data['valor'],
    ];

    for (final item in candidatos) {
      final valor = _asDoubleSeguro(item);
      if (valor > 0) return valor;
    }

    return 0;
  }

  void _somarValorGrade({
    required Map<String, double> unitarios,
    required Map<String, double> totais,
    required String chave,
    required double valorUnitario,
  }) {
    if (chave.trim().isEmpty || valorUnitario <= 0) return;

    unitarios[chave] = valorUnitario;
    totais[chave] = (totais[chave] ?? 0) + valorUnitario;
  }

  String _labelGradeCamisa(String chave) {
    final partes = chave.split('|');
    final modelagem = partes.isNotEmpty ? partes[0] : 'NORMAL';
    final tipo = partes.length > 1 ? partes[1] : 'MANGA';
    final tamanho = partes.length > 2 ? partes[2] : 'OUTRO';

    return '${_modelagemCamisaLabel(modelagem)} • ${_tipoCamisaLabel(tipo)} • $tamanho';
  }

  int _ordemTamanhoCamisa(String value) {
    final clean = _normalizarTamanhoCamisa(value);

    const ordem = {
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

    return ordem[clean] ?? 999;
  }

  int _ordemGradeCamisa(String chave) {
    final partes = chave.split('|');
    final modelagem = _normalizarModelagemCamisa(
      partes.isNotEmpty ? partes[0] : 'NORMAL',
    );
    final tipo = _normalizarTipoCamisa(partes.length > 1 ? partes[1] : 'MANGA');
    final tamanho = partes.length > 2 ? partes[2] : 'OUTRO';

    final ordemModelagem = modelagem == 'NORMAL' ? 0 : 1;
    final ordemTipo = switch (tipo) {
      'MANGA' => 0,
      'MANGA_LONGA' => 1,
      'REGATA' => 2,
      _ => 99,
    };

    return (ordemModelagem * 100000) +
        (ordemTipo * 10000) +
        _ordemTamanhoCamisa(tamanho);
  }

  Map<String, int> _ordenarGradeCamisas(Map<dynamic, dynamic> origem) {
    final result = <String, int>{};

    origem.forEach((key, value) {
      final chave = key.toString();
      final quantidade = (value as num?)?.toInt() ?? 0;
      if (quantidade <= 0) return;
      result[chave] = quantidade;
    });

    final entries = result.entries.toList()
      ..sort((a, b) {
        final ordem = _ordemGradeCamisa(
          a.key,
        ).compareTo(_ordemGradeCamisa(b.key));
        if (ordem != 0) return ordem;
        return a.key.compareTo(b.key);
      });

    return Map<String, int>.fromEntries(entries);
  }

  @override
  void initState() {
    super.initState();
    _inicializarTela();
  }

  Future<void> _inicializarTela() async {
    await _verificarPermissoes();
    if (!mounted) return;

    if (_podeVerRelatorio || _podeExportarRelatorio) {
      await _carregarDados();
    }
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final permissoes = await Future.wait<bool>([
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
        _podeVerRelatorio = permissoes[0];
        _podeExportarRelatorio = permissoes[0];
        _podeGerarCertificados = permissoes[1];
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões do relatório: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  Future<void> _recarregarTudo() async {
    await _verificarPermissoes();
    if (!mounted) return;

    if (_podeVerRelatorio || _podeExportarRelatorio) {
      await _carregarDados();
    }
  }

  void _mostrarSemPermissao([
    String mensagem =
        'Você não tem permissão para acessar/gerar relatórios deste evento.',
  ]) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _carregarDados() async {
    if (!_podeVerRelatorio && !_podeExportarRelatorio) {
      _mostrarSemPermissao();
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadingEtapa = 'Preparando relatório...';
        _loadingLogs.clear();
      });
    }

    try {
      _logCarregamento('🧹 Limpando contadores antigos...');
      _resetarVariaveis();

      _logCarregamento('👕 Carregando valores oficiais das camisas...');
      await _carregarValoresCamisaDoEvento();

      _logCarregamento('📌 Buscando participações do evento...');
      final participacoesValidas = await _buscarParticipacoesValidas();
      _logCarregamento(
        '✅ Participações válidas: ${participacoesValidas.length}',
      );

      _logCarregamento(
        '🤝 Carregando patrocínios e cruzando com alunos válidos...',
      );
      await _carregarPatrocinios(participacoesValidas);
      _logCarregamento('✅ Patrocínios válidos: ${_usosPatrocinio.length} usos');

      _logCarregamento(
        '📊 Processando pagamentos, quitados e inadimplentes...',
      );
      await _carregarParticipacoes(participacoesValidas);
      _logCarregamento(
        '✅ Participantes: $_totalParticipantes | Quitados: $_quitados | Patrocinados: $_cobertosPorPatrocinio',
      );

      _logCarregamento('👕 Carregando camisas avulsas...');
      await _carregarCamisasAvulsas();
      _logCarregamento(
        '✅ Camisas totais: ${_detalhesCamisas['total_camisas'] ?? 0}',
      );

      _logCarregamento('💰 Carregando gastos do evento...');
      await _carregarGastos();

      if (mounted) {
        setState(() {
          _saldoLiquido = _totalReceitas - _totalGastos;
        });
      }

      _logCarregamento(
        '🏁 Relatório pronto. Saldo: ${_formatarMoeda(_saldoLiquido)}',
      );
    } catch (e) {
      _logCarregamento('❌ Erro ao carregar dados: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar relatório: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logCarregamento(String mensagem) {
    debugPrint(mensagem);

    if (!mounted) return;

    setState(() {
      _loadingEtapa = _limparLogVisual(mensagem);
      _loadingLogs.add(mensagem);

      if (_loadingLogs.length > 80) {
        _loadingLogs.removeAt(0);
      }
    });
  }

  String _limparLogVisual(String mensagem) {
    return mensagem.replaceAll(RegExp(r'^[^A-Za-zÀ-ÖØ-öø-ÿ0-9]+'), '').trim();
  }

  // 🔥 NOVO MÉTODO PARA RESETAR VARIÁVEIS
  void _resetarVariaveis() {
    _totalReceitas = 0;
    _totalGastos = 0;
    _saldoLiquido = 0;
    _totalParticipantes = 0;

    _quitados = 0;
    _inadimplentes = 0;
    _cobertosPorPatrocinio = 0;

    _totalInscricoes = 0;
    _totalCamisas = 0;
    _totalPatrocinios = 0;

    _receitasPorForma = {};
    _gastosPorCategoria = {};

    _valoresPorTipoCamisaEvento = {'MANGA': 0, 'MANGA_LONGA': 0, 'REGATA': 0};

    _detalhesCamisas = {
      'total_camisas': 0,
      'camisas_pagas': 0,
      'valor_total_camisas': 0.0,
      'valor_total_pedido': 0.0,
      'por_tamanho': <String, int>{},
      'por_detalhe': <String, int>{},
      'por_detalhe_valor_unitario': <String, double>{},
      'por_detalhe_total': <String, double>{},
    };

    _camisasParticipacoes = {
      'total': 0,
      'pagas': 0,
      'valor': 0.0,
      'valor_total_pedido': 0.0,
      'por_tamanho': <String, int>{},
      'por_detalhe': <String, int>{},
      'por_detalhe_valor_unitario': <String, double>{},
      'por_detalhe_total': <String, double>{},
    };

    _camisasAvulsas = {
      'total': 0,
      'pagas': 0,
      'valor': 0.0,
      'valor_total_pedido': 0.0,
      'por_tamanho': <String, int>{},
      'por_detalhe': <String, int>{},
      'por_detalhe_valor_unitario': <String, double>{},
      'por_detalhe_total': <String, double>{},
    };

    _detalhesPatrocinios = {
      'total_patrocinadores': 0,
      'patrocinios_pagos': 0,
      'valor_total_patrocinios': 0.0,
      'patrocinios_pendentes': 0,
    };

    _usosPatrocinio = [];
    _participacoesDuplicadasIgnoradas = 0;
    _participacoesRemovidasIgnoradas = 0;
    _usosPatrocinioOrfaosIgnorados = 0;
    _usosPatrocinioDuplicadosIgnorados = 0;
    _chavesParticipantesValidos = {};
    _nomesParticipantesValidos = {};
    _chavesParticipantesPatrocinados = {};
  }

  // ==================== LIMPEZA / DEDUPLICAÇÃO ====================
  String _normalizarTexto(dynamic value) {
    final text = value?.toString().trim().toUpperCase() ?? '';

    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ç', 'C');
  }

  String _chaveParticipante(Map<String, dynamic> data) {
    final idCampos = [
      data['aluno_id'],
      data['alunoId'],
      data['aluno_uid'],
      data['aluno_doc_id'],
      data['aluno_ref_id'],
      data['uid_aluno'],
    ];

    for (final id in idCampos) {
      final value = id?.toString().trim() ?? '';

      if (value.isNotEmpty && value != '0' && value.toLowerCase() != 'null') {
        return 'id:$value';
      }
    }

    return 'nome:${_normalizarTexto(data['aluno_nome'] ?? data['nome'])}';
  }

  bool _participacaoFoiRemovida(Map<String, dynamic> data) {
    final status = _normalizarTexto(
      data['status'] ??
          data['status_participacao'] ??
          data['situacao'] ??
          data['status_evento'],
    );

    final removida =
        data['removido'] == true ||
        data['removido_evento'] == true ||
        data['excluido'] == true ||
        data['cancelado'] == true ||
        data['ativo'] == false;

    return removida ||
        status == 'REMOVIDO' ||
        status == 'REMOVIDA' ||
        status == 'CANCELADO' ||
        status == 'CANCELADA' ||
        status == 'EXCLUIDO' ||
        status == 'EXCLUIDA' ||
        status == 'INATIVO' ||
        status == 'INATIVA';
  }

  int _timestampScore(dynamic value) {
    if (value is Timestamp) return value.toDate().millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return 0;
  }

  int _pontuacaoParticipacao(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    int score = 0;

    final totalPago = (data['total_pago'] as num?)?.toDouble() ?? 0;
    final valorInscricao = (data['valor_inscricao'] as num?)?.toDouble() ?? 0;
    final valorCamisa = (data['valor_camisa'] as num?)?.toDouble() ?? 0;

    if (totalPago > 0) score += 1000000;
    if (valorInscricao > 0 || valorCamisa > 0) score += 100000;
    if ((data['tamanho_camisa']?.toString().trim() ?? '').isNotEmpty) {
      score += 10000;
    }

    score += _timestampScore(data['atualizado_em']) ~/ 100000;
    score += _timestampScore(data['data_atualizacao']) ~/ 100000;
    score += _timestampScore(data['criado_em']) ~/ 100000;
    score += _timestampScore(data['data_inscricao']) ~/ 100000;

    return score;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _buscarParticipacoesValidas() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('participacoes_eventos_em_andamento')
        .where('evento_id', isEqualTo: widget.eventoId)
        .get();

    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> unicas = {};
    int removidas = 0;
    int duplicadas = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();

      if (_participacaoFoiRemovida(data)) {
        removidas++;
        continue;
      }

      final chave = _chaveParticipante(data);

      if (chave == 'nome:') {
        continue;
      }

      if (!unicas.containsKey(chave)) {
        unicas[chave] = doc;
      } else {
        duplicadas++;

        final atual = unicas[chave]!;
        final scoreAtual = _pontuacaoParticipacao(atual);
        final scoreNovo = _pontuacaoParticipacao(doc);

        if (scoreNovo > scoreAtual) {
          unicas[chave] = doc;
        }
      }
    }

    final lista = unicas.values.toList()
      ..sort((a, b) {
        final nomeA = _normalizarTexto(a.data()['aluno_nome']);
        final nomeB = _normalizarTexto(b.data()['aluno_nome']);

        return nomeA.compareTo(nomeB);
      });

    _participacoesRemovidasIgnoradas = removidas;
    _participacoesDuplicadasIgnoradas = duplicadas;
    _chavesParticipantesValidos = lista
        .map((doc) => _chaveParticipante(doc.data()))
        .toSet();
    _nomesParticipantesValidos = lista
        .map((doc) => _normalizarTexto(doc.data()['aluno_nome']))
        .where((nome) => nome.isNotEmpty)
        .toSet();

    debugPrint('🧹 ===== PARTICIPAÇÕES LIMPAS =====');
    debugPrint('📌 Lidas no Firestore: ${snapshot.docs.length}');
    debugPrint('✅ Válidas únicas: ${lista.length}');
    debugPrint('🗑️ Removidas ignoradas: $removidas');
    debugPrint('♻️ Duplicadas ignoradas: $duplicadas');

    return lista;
  }

  bool _usoPertenceAoEventoAtual(Map<String, dynamic> usoData) {
    final usoEventoId = usoData['evento_id']?.toString().trim();

    if (usoEventoId != null &&
        usoEventoId.isNotEmpty &&
        usoEventoId != widget.eventoId) {
      return false;
    }

    final chave = _chaveParticipante({
      'aluno_id':
          usoData['aluno_id'] ??
          usoData['alunoId'] ??
          usoData['aluno_doc_id'] ??
          usoData['aluno_ref_id'],
      'aluno_nome': usoData['aluno_nome'] ?? usoData['nome_aluno'],
    });

    final nome = _normalizarTexto(
      usoData['aluno_nome'] ?? usoData['nome_aluno'],
    );

    return _chavesParticipantesValidos.contains(chave) ||
        (nome.isNotEmpty && _nomesParticipantesValidos.contains(nome));
  }

  String _chaveUsoPatrocinio(
    String patrocinadorId,
    Map<String, dynamic> usoData,
  ) {
    final chaveAluno = _chaveParticipante({
      'aluno_id':
          usoData['aluno_id'] ??
          usoData['alunoId'] ??
          usoData['aluno_doc_id'] ??
          usoData['aluno_ref_id'],
      'aluno_nome': usoData['aluno_nome'] ?? usoData['nome_aluno'],
    });

    final valor = ((usoData['valor'] as num?)?.toDouble() ?? 0).toStringAsFixed(
      2,
    );

    DateTime? data;
    final rawData = usoData['data'];
    if (rawData is Timestamp) data = rawData.toDate();
    if (rawData is DateTime) data = rawData;

    final dataKey = data == null
        ? ''
        : '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';

    final observacao = _normalizarTexto(usoData['observacao']);

    return '$patrocinadorId|$chaveAluno|$valor|$dataKey|$observacao';
  }

  String _chaveParticipanteUso(Map<String, dynamic> usoData) {
    final chave = _chaveParticipante({
      'aluno_id':
          usoData['aluno_id'] ??
          usoData['alunoId'] ??
          usoData['aluno_doc_id'] ??
          usoData['aluno_ref_id'],
      'aluno_nome': usoData['aluno_nome'] ?? usoData['nome_aluno'],
    });

    if (_chavesParticipantesValidos.contains(chave)) return chave;

    final nome = _normalizarTexto(
      usoData['aluno_nome'] ?? usoData['nome_aluno'],
    );

    return 'nome:$nome';
  }

  // ==================== PATROCÍNIOS ====================
  Future<void> _carregarPatrocinios(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> participacoesValidas,
  ) async {
    try {
      final patrocinadoresSnapshot = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      debugPrint('🤝 ===== CARREGANDO PATROCÍNIOS =====');
      debugPrint(
        '🤝 Total de patrocinadores: ${patrocinadoresSnapshot.docs.length}',
      );

      double totalPatrocinios = 0;
      int pagos = 0;
      int pendentes = 0;

      final usos = <Map<String, dynamic>>[];
      final usosUnicos = <String>{};
      final participantesPatrocinados = <String>{};

      int usosOrfaos = 0;
      int usosDuplicados = 0;

      for (final patrocinador in patrocinadoresSnapshot.docs) {
        final data = patrocinador.data();
        final status = data['status']?.toString() ?? 'PENDENTE';
        final nomePatrocinador = data['nome'] ?? 'Patrocinador';

        double valorPago = (data['valor_pago'] as num?)?.toDouble() ?? 0;

        if (valorPago == 0) {
          final saldoInicial = (data['saldo_inicial'] as num?)?.toDouble() ?? 0;
          final saldoDisponivel =
              (data['saldo_disponivel'] as num?)?.toDouble() ?? 0;
          valorPago = saldoInicial - saldoDisponivel;
        }

        final usosSnapshot = await patrocinador.reference
            .collection('usos')
            .orderBy('data', descending: true)
            .get();

        double totalUsosValidos = 0;

        for (final uso in usosSnapshot.docs) {
          final usoData = uso.data();

          if (!_usoPertenceAoEventoAtual(usoData)) {
            usosOrfaos++;
            continue;
          }

          final dedupeKey = _chaveUsoPatrocinio(patrocinador.id, usoData);

          if (usosUnicos.contains(dedupeKey)) {
            usosDuplicados++;
            continue;
          }

          usosUnicos.add(dedupeKey);

          final valorUso = (usoData['valor'] as num?)?.toDouble() ?? 0;
          totalUsosValidos += valorUso;

          final chaveParticipante = _chaveParticipanteUso(usoData);
          participantesPatrocinados.add(chaveParticipante);

          usos.add({
            'patrocinador': nomePatrocinador,
            'patrocinador_id': patrocinador.id,
            'aluno_nome':
                usoData['aluno_nome'] ?? usoData['nome_aluno'] ?? 'Aluno',
            'aluno_chave': chaveParticipante,
            'valor': valorUso,
            'data': usoData['data'] is Timestamp
                ? (usoData['data'] as Timestamp).toDate()
                : usoData['data'] is DateTime
                ? usoData['data']
                : DateTime.now(),
            'observacao': usoData['observacao'] ?? '',
          });
        }

        if (valorPago == 0 && totalUsosValidos > 0) {
          valorPago = totalUsosValidos;
        }

        if (valorPago > 0 || totalUsosValidos > 0) {
          totalPatrocinios += valorPago;
          pagos++;
        } else if (status == 'PENDENTE' || status == 'ATRASADO') {
          pendentes++;
        }
      }

      usos.sort((a, b) {
        final nomeA = _normalizarTexto(a['aluno_nome']);
        final nomeB = _normalizarTexto(b['aluno_nome']);
        return nomeA.compareTo(nomeB);
      });

      if (mounted) {
        setState(() {
          _totalPatrocinios = totalPatrocinios;
          _detalhesPatrocinios = {
            'total_patrocinadores': patrocinadoresSnapshot.docs.length,
            'patrocinios_pagos': pagos,
            'valor_total_patrocinios': totalPatrocinios,
            'patrocinios_pendentes': pendentes,
          };
          _usosPatrocinio = usos;
          _chavesParticipantesPatrocinados = participantesPatrocinados;
          _usosPatrocinioOrfaosIgnorados = usosOrfaos;
          _usosPatrocinioDuplicadosIgnorados = usosDuplicados;
        });
      }

      debugPrint('\n✅ RESUMO PATROCÍNIOS LIMPOS:');
      debugPrint('   - Participações válidas: ${participacoesValidas.length}');
      debugPrint(
        '   - Total recebido: R\$ ${totalPatrocinios.toStringAsFixed(2)}',
      );
      debugPrint('   - Usos válidos: ${usos.length}');
      debugPrint('   - Usos órfãos ignorados: $usosOrfaos');
      debugPrint('   - Usos duplicados ignorados: $usosDuplicados');
    } catch (e) {
      debugPrint('❌ Erro ao carregar patrocínios: $e');
    }
  }

  // ==================== PARTICIPAÇÕES ====================
  Future<void> _carregarParticipacoes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> participacoesDocs,
  ) async {
    try {
      debugPrint('\n📊 ===== CARREGANDO PARTICIPAÇÕES VÁLIDAS =====');
      debugPrint('📊 Total válido único: ${participacoesDocs.length}');

      double totalInscricoes = 0;
      double totalCamisasParticipacoes = 0;
      final porForma = <String, double>{};
      final camisasPorTamanho = <String, int>{};
      final camisasPorDetalhe = <String, int>{};
      final camisasValorUnitarioPorDetalhe = <String, double>{};
      final camisasTotalPorDetalhe = <String, double>{};
      double valorTotalPedidoCamisasParticipacoes = 0;

      int totalCamisasParticipacoesCount = 0;
      int camisasPagasParticipacoesCount = 0;

      int quitados = 0;
      int inadimplentes = 0;
      int cobertosPatrocinio = 0;

      for (final participacao in participacoesDocs) {
        final data = participacao.data();

        final totalPago = (data['total_pago'] as num?)?.toDouble() ?? 0;
        final valorInscricao =
            (data['valor_inscricao'] as num?)?.toDouble() ?? 0;
        final valorCamisa = (data['valor_camisa'] as num?)?.toDouble() ?? 0;
        final totalDevido = valorInscricao + valorCamisa;
        final tamanhoCamisaRaw = data['tamanho_camisa'];
        final tamanhoCamisa = tamanhoCamisaRaw?.toString();
        final alunoNome = data['aluno_nome'] as String? ?? '';
        final chaveParticipante = _chaveParticipante(data);

        final temPatrocinio =
            _chavesParticipantesPatrocinados.contains(chaveParticipante) ||
            _chavesParticipantesPatrocinados.contains(
              'nome:${_normalizarTexto(alunoNome)}',
            );

        debugPrint('\n📌 Aluno válido: $alunoNome');
        debugPrint('   - Total devido: R\$ $totalDevido');
        debugPrint('   - Total pago: R\$ $totalPago');
        debugPrint('   - Tem patrocínio válido: $temPatrocinio');

        if (temPatrocinio) {
          cobertosPatrocinio++;
        } else if (totalPago >= totalDevido - 1) {
          quitados++;
        } else {
          inadimplentes++;
        }

        if (totalPago > 0) {
          final todosPagamentos = await FirebaseFirestore.instance
              .collection('eventos')
              .doc(widget.eventoId)
              .collection('participacoes')
              .doc(participacao.id)
              .collection('pagamentos')
              .where('status', isEqualTo: 'confirmado')
              .get();

          for (final pag in todosPagamentos.docs) {
            final pagData = pag.data();
            final valor = (pagData['valor'] as num?)?.toDouble() ?? 0;
            final forma = pagData['forma_pagamento'] as String? ?? 'OUTROS';
            final observacoes =
                pagData['observacoes']?.toString().toLowerCase() ?? '';

            if (forma.toUpperCase() == 'PATROCÍNIO' ||
                forma.toUpperCase() == 'PATROCINIO') {
              continue;
            }

            if (valorCamisa > 0 && observacoes.contains('camisa')) {
              totalCamisasParticipacoes += valor;
            } else {
              totalInscricoes += valor;
            }

            porForma[forma] = (porForma[forma] ?? 0) + valor;
          }
        }

        if (tamanhoCamisa != null && tamanhoCamisa.trim().isNotEmpty) {
          final tamanho = _normalizarTamanhoCamisa(tamanhoCamisa);
          final chaveGrade = _chaveGradeCamisa(data);

          totalCamisasParticipacoesCount++;
          camisasPorTamanho[tamanho] = (camisasPorTamanho[tamanho] ?? 0) + 1;
          camisasPorDetalhe[chaveGrade] =
              (camisasPorDetalhe[chaveGrade] ?? 0) + 1;

          final valorUnitario = _valorUnitarioCamisa(data);
          valorTotalPedidoCamisasParticipacoes += valorUnitario;
          _somarValorGrade(
            unitarios: camisasValorUnitarioPorDetalhe,
            totais: camisasTotalPorDetalhe,
            chave: chaveGrade,
            valorUnitario: valorUnitario,
          );

          if (totalPago >= valorCamisa - 1 || temPatrocinio) {
            camisasPagasParticipacoesCount++;
          }
        }
      }

      final totalReceitasParticipacoes =
          totalInscricoes + totalCamisasParticipacoes;

      if (mounted) {
        setState(() {
          _totalParticipantes = participacoesDocs.length;
          _quitados = quitados;
          _inadimplentes = inadimplentes;
          _cobertosPorPatrocinio = cobertosPatrocinio;

          _totalInscricoes = totalInscricoes;
          _totalCamisas = totalCamisasParticipacoes;
          _totalReceitas = totalReceitasParticipacoes + _totalPatrocinios;

          _camisasParticipacoes = {
            'total': totalCamisasParticipacoesCount,
            'pagas': camisasPagasParticipacoesCount,
            'valor': totalCamisasParticipacoes,
            'valor_total_pedido': valorTotalPedidoCamisasParticipacoes,
            'por_tamanho': camisasPorTamanho,
            'por_detalhe': _ordenarGradeCamisas(camisasPorDetalhe),
            'por_detalhe_valor_unitario': camisasValorUnitarioPorDetalhe,
            'por_detalhe_total': camisasTotalPorDetalhe,
          };

          porForma.forEach((key, value) {
            _receitasPorForma[key] = (_receitasPorForma[key] ?? 0) + value;
          });
        });
      }

      debugPrint('\n✅ RESUMO PARTICIPAÇÕES LIMPAS:');
      debugPrint('   - Participantes únicos: ${participacoesDocs.length}');
      debugPrint(
        '   - Duplicadas ignoradas: $_participacoesDuplicadasIgnoradas',
      );
      debugPrint('   - Removidas ignoradas: $_participacoesRemovidasIgnoradas');
      debugPrint('   - Quitados: $quitados');
      debugPrint('   - Patrocínio: $cobertosPatrocinio');
      debugPrint('   - Inadimplentes: $inadimplentes');
    } catch (e) {
      debugPrint('❌ Erro ao carregar participações: $e');
    }
  }

  // ==================== CAMISAS AVULSAS ====================
  Future<void> _carregarCamisasAvulsas() async {
    try {
      final camisasSnapshot = await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      debugPrint('\n👕 ===== CAMISAS AVULSAS =====');
      debugPrint('👕 Total: ${camisasSnapshot.docs.length}');

      double totalValor = 0;
      int pagas = 0;
      final porTamanho = <String, int>{};
      final porDetalhe = <String, int>{};
      final valorUnitarioPorDetalhe = <String, double>{};
      final valorTotalPorDetalhe = <String, double>{};
      double valorTotalPedidoAvulsas = 0;

      for (var camisa in camisasSnapshot.docs) {
        final data = camisa.data();
        final valor = _valorUnitarioCamisa(data);
        final pago = data['pago'] as bool? ?? false;
        final tamanho = _normalizarTamanhoCamisa(
          data['tamanho'] ?? data['tamanho_camisa'],
        );
        final chaveGrade = _chaveGradeCamisa(data);

        porTamanho[tamanho] = (porTamanho[tamanho] ?? 0) + 1;
        porDetalhe[chaveGrade] = (porDetalhe[chaveGrade] ?? 0) + 1;

        valorTotalPedidoAvulsas += valor;
        _somarValorGrade(
          unitarios: valorUnitarioPorDetalhe,
          totais: valorTotalPorDetalhe,
          chave: chaveGrade,
          valorUnitario: valor,
        );

        if (pago && valor > 0) {
          totalValor += valor;
          pagas++;
        }
      }

      setState(() {
        // 🔥 CORREÇÃO: USAR SOMA ACUMULADA, NÃO ATRIBUIÇÃO!
        _totalReceitas += totalValor;
        _totalCamisas += totalValor;

        _camisasAvulsas = {
          'total': camisasSnapshot.docs.length,
          'pagas': pagas,
          'valor': totalValor,
          'valor_total_pedido': valorTotalPedidoAvulsas,
          'por_tamanho': porTamanho,
          'por_detalhe': _ordenarGradeCamisas(porDetalhe),
          'por_detalhe_valor_unitario': valorUnitarioPorDetalhe,
          'por_detalhe_total': valorTotalPorDetalhe,
        };

        _detalhesCamisas = {
          'total_camisas':
              _camisasParticipacoes['total'] + _camisasAvulsas['total'],
          'camisas_pagas':
              _camisasParticipacoes['pagas'] + _camisasAvulsas['pagas'],
          'valor_total_camisas':
              _camisasParticipacoes['valor'] + _camisasAvulsas['valor'],
          'valor_total_pedido':
              (_camisasParticipacoes['valor_total_pedido'] ?? 0.0) +
              (_camisasAvulsas['valor_total_pedido'] ?? 0.0),
          'por_tamanho': _combinarMapas(
            _camisasParticipacoes['por_tamanho'],
            _camisasAvulsas['por_tamanho'],
          ),
          'por_detalhe': _combinarMapasDetalhados(
            _camisasParticipacoes['por_detalhe'],
            _camisasAvulsas['por_detalhe'],
          ),
          'por_detalhe_valor_unitario': _combinarValoresUnitariosDetalhados(
            _camisasParticipacoes['por_detalhe_valor_unitario'],
            _camisasAvulsas['por_detalhe_valor_unitario'],
          ),
          'por_detalhe_total': _combinarTotaisDetalhados(
            _camisasParticipacoes['por_detalhe_total'],
            _camisasAvulsas['por_detalhe_total'],
          ),
        };
      });

      debugPrint('✅ Total arrecadado: R\$ ${totalValor.toStringAsFixed(2)}');
    } catch (e) {
      debugPrint('❌ Erro ao carregar camisas avulsas: $e');
    }
  }

  // ==================== GASTOS ====================
  Future<void> _carregarGastos() async {
    try {
      final gastosSnapshot = await FirebaseFirestore.instance
          .collection('gastos_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      double total = 0;
      Map<String, double> porCategoria = {};

      for (var gasto in gastosSnapshot.docs) {
        final data = gasto.data();
        final valor = (data['valor'] as num?)?.toDouble() ?? 0;
        final categoria = data['categoria']?.toString() ?? 'Outros';
        final pago = data['pago'] as bool? ?? true;

        if (pago) {
          total += valor;
          porCategoria[categoria] = (porCategoria[categoria] ?? 0) + valor;
        }
      }

      setState(() {
        _totalGastos = total;
        _gastosPorCategoria = porCategoria;
      });

      debugPrint('\n💰 ===== GASTOS =====');
      debugPrint('💰 Total: R\$ ${total.toStringAsFixed(2)}');
    } catch (e) {
      debugPrint('❌ Erro ao carregar gastos: $e');
    }
  }

  // 🔥 Combina dois mapas de contagem
  Map<String, int> _combinarMapas(dynamic a, dynamic b) {
    final result = <String, int>{};

    if (a is Map) {
      a.forEach((key, value) {
        final chave = _normalizarTamanhoCamisa(key);
        final quantidade = (value as num?)?.toInt() ?? 0;
        result[chave] = (result[chave] ?? 0) + quantidade;
      });
    }

    if (b is Map) {
      b.forEach((key, value) {
        final chave = _normalizarTamanhoCamisa(key);
        final quantidade = (value as num?)?.toInt() ?? 0;
        result[chave] = (result[chave] ?? 0) + quantidade;
      });
    }

    final entries = result.entries.toList()
      ..sort((x, y) {
        final ordem = _ordemTamanhoCamisa(
          x.key,
        ).compareTo(_ordemTamanhoCamisa(y.key));
        if (ordem != 0) return ordem;
        return x.key.compareTo(y.key);
      });

    return Map<String, int>.fromEntries(entries);
  }

  Map<String, int> _combinarMapasDetalhados(dynamic a, dynamic b) {
    final result = <String, int>{};

    if (a is Map) {
      a.forEach((key, value) {
        final chave = key.toString();
        final quantidade = (value as num?)?.toInt() ?? 0;
        result[chave] = (result[chave] ?? 0) + quantidade;
      });
    }

    if (b is Map) {
      b.forEach((key, value) {
        final chave = key.toString();
        final quantidade = (value as num?)?.toInt() ?? 0;
        result[chave] = (result[chave] ?? 0) + quantidade;
      });
    }

    return _ordenarGradeCamisas(result);
  }

  Map<String, double> _combinarValoresUnitariosDetalhados(
    dynamic a,
    dynamic b,
  ) {
    final result = <String, double>{};

    void add(dynamic origem) {
      if (origem is! Map) return;

      origem.forEach((key, value) {
        final chave = key.toString();
        final valor = _asDoubleSeguro(value);
        if (valor <= 0) return;

        // Se alunos e avulsas tiverem o mesmo tipo/tamanho, o valor unitário
        // deve ser o mesmo. Caso tenha divergência, mantém o maior para evitar
        // subvalorizar o pedido de confecção.
        final atual = result[chave] ?? 0;
        result[chave] = valor > atual ? valor : atual;
      });
    }

    add(a);
    add(b);

    return Map<String, double>.fromEntries(
      result.entries.toList()..sort((x, y) {
        final ordem = _ordemGradeCamisa(
          x.key,
        ).compareTo(_ordemGradeCamisa(y.key));
        if (ordem != 0) return ordem;
        return x.key.compareTo(y.key);
      }),
    );
  }

  Map<String, double> _combinarTotaisDetalhados(dynamic a, dynamic b) {
    final result = <String, double>{};

    void add(dynamic origem) {
      if (origem is! Map) return;

      origem.forEach((key, value) {
        final chave = key.toString();
        final valor = _asDoubleSeguro(value);
        if (valor <= 0) return;
        result[chave] = (result[chave] ?? 0) + valor;
      });
    }

    add(a);
    add(b);

    return Map<String, double>.fromEntries(
      result.entries.toList()..sort((x, y) {
        final ordem = _ordemGradeCamisa(
          x.key,
        ).compareTo(_ordemGradeCamisa(y.key));
        if (ordem != 0) return ordem;
        return x.key.compareTo(y.key);
      }),
    );
  }

  // ==================== NOVO: MÉTODO AUXILIAR PARA LISTA COMPLETA DE PARTICIPANTES ====================
  /// Retorna uma lista de mapas com todos os campos necessários para os PDFs de participantes,
  /// incluindo cores da graduação buscadas na coleção `graduacoes`.
  Future<List<Map<String, dynamic>>> _obterListaParticipantesCompleta() async {
    final participacoesValidas = await _buscarParticipacoesValidas();

    if (_usosPatrocinio.isEmpty && _chavesParticipantesPatrocinados.isEmpty) {
      await _carregarPatrocinios(participacoesValidas);
    }

    final lista = <Map<String, dynamic>>[];
    final idsGraduacoes = <String>{};

    for (final doc in participacoesValidas) {
      final d = doc.data();
      final nome = d['aluno_nome'] ?? '';
      final totalPago = (d['total_pago'] as num?)?.toDouble() ?? 0;
      final valorInscricao = (d['valor_inscricao'] as num?)?.toDouble() ?? 0;
      final valorCamisa = (d['valor_camisa'] as num?)?.toDouble() ?? 0;
      final totalDevido = valorInscricao + valorCamisa;
      final chaveParticipante = _chaveParticipante(d);

      final temPatrocinio =
          _chavesParticipantesPatrocinados.contains(chaveParticipante) ||
          _chavesParticipantesPatrocinados.contains(
            'nome:${_normalizarTexto(nome)}',
          );

      final status = temPatrocinio
          ? 'Patrocinado'
          : (totalPago >= totalDevido - 1 ? 'Quitado' : 'Inadimplente');

      final tamanhoCamisa = d['tamanho_camisa'] ?? '---';
      final graduacaoNova = d['graduacao_nova'] ?? '---';
      final graduacaoNovaId = d['graduacao_nova_id'] as String?;

      if (graduacaoNovaId != null &&
          graduacaoNovaId.isNotEmpty &&
          graduacaoNovaId != '0') {
        idsGraduacoes.add(graduacaoNovaId);
      }

      lista.add({
        'nome': nome,
        'status': status,
        'tamanho_camisa': tamanhoCamisa,
        'modelagem_camisa': _normalizarModelagemCamisa(d['modelagem_camisa']),
        'tipo_camisa': _normalizarTipoCamisa(d['tipo_camisa']),
        'valor_pago': totalPago,
        'graduacao_nova': graduacaoNova,
        'graduacao_nova_id': graduacaoNovaId,
        'hex_cor1': null,
        'hex_cor2': null,
      });
    }

    if (idsGraduacoes.isNotEmpty) {
      final futures = idsGraduacoes.map(
        (id) =>
            FirebaseFirestore.instance.collection('graduacoes').doc(id).get(),
      );
      final docs = await Future.wait(futures);
      final coresMap = <String, Map<String, dynamic>>{};

      for (final doc in docs) {
        if (doc.exists) {
          coresMap[doc.id] = doc.data()!;
        }
      }

      for (final p in lista) {
        final gId = p['graduacao_nova_id'] as String?;

        if (gId != null && coresMap.containsKey(gId)) {
          final gradData = coresMap[gId]!;
          p['hex_cor1'] = gradData['hex_cor1'] as String?;
          p['hex_cor2'] = gradData['hex_cor2'] as String?;
        }
      }
    }

    return lista;
  }

  // ==================== PDF LISTA DE ENTREGA DE CAMISAS ====================
  String _safeTexto(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }

  String _nomeCamisaAvulsa(Map<String, dynamic> data, int index) {
    final candidatos = [
      data['nome_participante'],
      data['nomeParticipante'],
      data['aluno_nome'],
      data['nome_aluno'],
      data['nome'],
      data['responsavel'],
    ];

    for (final item in candidatos) {
      final nome = _safeTexto(item);
      if (nome.isNotEmpty) return nome;
    }

    return 'Camisa avulsa ${index.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _itemEntregaCamisa({
    required String nome,
    required String origem,
    required dynamic tamanho,
    required dynamic modelagem,
    required dynamic tipo,
    required bool entregue,
  }) {
    return {
      'nome': nome,
      'origem': origem,
      'tamanho_camisa': _normalizarTamanhoCamisa(tamanho),
      'modelagem_camisa': _normalizarModelagemCamisa(modelagem),
      'tipo_camisa': _normalizarTipoCamisa(tipo),
      'entregue': entregue,
    };
  }

  Future<List<Map<String, dynamic>>> _obterListaEntregaCamisasCompleta() async {
    final itens = <Map<String, dynamic>>[];

    // 1) Alunos participantes válidos do evento
    final participacoesValidas = await _buscarParticipacoesValidas();

    for (final doc in participacoesValidas) {
      final data = doc.data();

      final tamanhoRaw = data['tamanho_camisa'] ?? data['tamanhoCamisa'];
      final tamanho = _safeTexto(tamanhoRaw);

      if (tamanho.isEmpty) {
        continue;
      }

      itens.add(
        _itemEntregaCamisa(
          nome: _safeTexto(
            data['aluno_nome'] ?? data['nome_aluno'] ?? data['nome'],
            fallback: 'Aluno sem nome',
          ),
          origem: 'Aluno',
          tamanho: tamanho,
          modelagem:
              data['modelagem_camisa'] ??
              data['modelagemCamisa'] ??
              data['modelagem'] ??
              'NORMAL',
          tipo:
              data['tipo_camisa'] ??
              data['tipoCamisa'] ??
              data['tipo'] ??
              'MANGA',
          entregue:
              data['camisa_entregue'] == true ||
              data['entregue'] == true ||
              data['camisaEntregue'] == true,
        ),
      );
    }

    // 2) Camisas avulsas do evento
    final camisasSnapshot = await FirebaseFirestore.instance
        .collection('camisas_eventos')
        .where('evento_id', isEqualTo: widget.eventoId)
        .get();

    var avulsaIndex = 1;

    for (final doc in camisasSnapshot.docs) {
      final data = doc.data();

      final tamanhoRaw =
          data['tamanho'] ?? data['tamanho_camisa'] ?? data['tamanhoCamisa'];
      final tamanho = _safeTexto(tamanhoRaw);

      if (tamanho.isEmpty) {
        continue;
      }

      itens.add(
        _itemEntregaCamisa(
          nome: _nomeCamisaAvulsa(data, avulsaIndex),
          origem: 'Avulsa',
          tamanho: tamanho,
          modelagem:
              data['modelagem_camisa'] ??
              data['modelagemCamisa'] ??
              data['modelagem'] ??
              'NORMAL',
          tipo:
              data['tipo_camisa'] ??
              data['tipoCamisa'] ??
              data['tipo'] ??
              'MANGA',
          entregue:
              data['entregue'] == true ||
              data['camisa_entregue'] == true ||
              data['camisaEntregue'] == true,
        ),
      );

      avulsaIndex++;
    }

    itens.sort((a, b) {
      final origemA = _safeTexto(a['origem']).toUpperCase();
      final origemB = _safeTexto(b['origem']).toUpperCase();

      // Alunos primeiro, avulsas depois.
      final ordemA = origemA.contains('ALUNO') ? 0 : 1;
      final ordemB = origemB.contains('ALUNO') ? 0 : 1;

      if (ordemA != ordemB) return ordemA.compareTo(ordemB);

      final nomeA = _normalizarTexto(a['nome']);
      final nomeB = _normalizarTexto(b['nome']);
      return nomeA.compareTo(nomeB);
    });

    return itens;
  }

  // ==================== DIÁLOGO DE ORDENAÇÃO ====================
  Future<Map<String, dynamic>?> _mostrarDialogoOrdenacao() async {
    String campoSelecionado = 'nome';
    bool crescente = true;

    final Map<String, String> campos = {
      'nome': 'Nome',
      'status': 'Status',
      'tamanho_camisa': 'Tamanho Camisa',
      'valor_pago': 'Valor Pago',
      'graduacao_nova': 'Graduação',
    };

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Ordenar lista'),
          content: StatefulBuilder(
            builder: (BuildContext context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: campoSelecionado,
                    decoration: InputDecoration(
                      labelText: 'Campo de ordenação',
                    ),
                    items: campos.entries.map((entry) {
                      return DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => campoSelecionado = value!);
                    },
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Direção:'),
                      SizedBox(width: 12),
                      Expanded(
                        child: ToggleButtons(
                          isSelected: [crescente, !crescente],
                          onPressed: (index) {
                            setState(() => crescente = index == 0);
                          },
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Crescente'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Decrescente'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'campo': campoSelecionado,
                'crescente': crescente,
              }),
              child: Text('Gerar PDF'),
            ),
          ],
        );
      },
    );
  }

  // Aplica ordenação a uma lista de participantes
  List<Map<String, dynamic>> _ordenarLista(
    List<Map<String, dynamic>> lista,
    String campo,
    bool crescente,
  ) {
    final copia = List<Map<String, dynamic>>.from(lista);
    copia.sort((a, b) {
      final valA = a[campo];
      final valB = b[campo];
      int cmp = 0;

      if (valA is String && valB is String) {
        cmp = valA.compareTo(valB);
      } else if (valA is num && valB is num) {
        cmp = valA.compareTo(valB);
      } else {
        // fallback: string
        cmp = (valA?.toString() ?? '').compareTo(valB?.toString() ?? '');
      }
      return crescente ? cmp : -cmp;
    });
    return copia;
  }

  // Método comum para PDFs que usam participantes
  Future<void> _executarComOrdenacao(
    Function(List<Map<String, dynamic>>) gerarPdf,
  ) async {
    if (!_podeExportarRelatorio && !_podeGerarCertificados) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar PDFs de participantes.',
      );
      return;
    }

    final opcoes = await _mostrarDialogoOrdenacao();
    if (opcoes == null) return; // cancelou

    final lista = await _obterListaParticipantesCompleta();
    final listaOrdenada = _ordenarLista(
      lista,
      opcoes['campo'] as String,
      opcoes['crescente'] as bool,
    );

    try {
      await gerarPdf(listaOrdenada);
    } catch (e) {
      _mostrarErro('Erro ao gerar PDF: $e');
    }
  }

  void _mostrarErro(String mensagem) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), backgroundColor: context.uai.error),
      );
    }
  }

  // ==================== EXPORTAR EXCEL ====================
  Future<void> _exportarExcel() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao('Você não tem permissão para exportar relatórios.');
      return;
    }

    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Relatório Financeiro'];

      sheet.appendRow(['RELATÓRIO FINANCEIRO - ${widget.eventoNome}']);
      sheet.appendRow(['Gerado em: ${_formatter.format(DateTime.now())}']);
      sheet.appendRow([]);

      sheet.appendRow(['📊 RESUMO GERAL']);
      sheet.appendRow([
        'Receitas Totais:',
        'R\$ ${_totalReceitas.toStringAsFixed(2)}',
      ]);
      sheet.appendRow([
        'Gastos Totais:',
        'R\$ ${_totalGastos.toStringAsFixed(2)}',
      ]);
      sheet.appendRow([
        'Saldo Líquido:',
        'R\$ ${_saldoLiquido.toStringAsFixed(2)}',
      ]);
      sheet.appendRow([]);

      sheet.appendRow(['💰 RECEITAS POR TIPO']);
      sheet.appendRow([
        'Inscrições:',
        'R\$ ${_totalInscricoes.toStringAsFixed(2)}',
      ]);
      sheet.appendRow(['Camisas:', 'R\$ ${_totalCamisas.toStringAsFixed(2)}']);
      sheet.appendRow([
        'Patrocínios:',
        'R\$ ${_totalPatrocinios.toStringAsFixed(2)}',
      ]);
      sheet.appendRow([]);

      sheet.appendRow(['👥 PARTICIPAÇÕES']);
      sheet.appendRow(['Total de participantes:', '$_totalParticipantes']);
      sheet.appendRow(['Quitados (pagamento próprio):', '$_quitados']);
      sheet.appendRow(['Cobertos por patrocínio:', '$_cobertosPorPatrocinio']);
      sheet.appendRow(['Inadimplentes:', '$_inadimplentes']);
      sheet.appendRow([]);

      sheet.appendRow(['👕 CAMISAS DOS ALUNOS']);
      sheet.appendRow(['Total:', '${_camisasParticipacoes['total']}']);
      sheet.appendRow(['Pagas:', '${_camisasParticipacoes['pagas']}']);
      sheet.appendRow([
        'Valor:',
        'R\$ ${_camisasParticipacoes['valor'].toStringAsFixed(2)}',
      ]);

      final distAlunos = Map<String, int>.from(
        _camisasParticipacoes['por_detalhe'] ?? {},
      );
      if (distAlunos.isNotEmpty) {
        sheet.appendRow(['Distribuição detalhada:']);
        sheet.appendRow(['Modelagem', 'Tipo', 'Tamanho', 'Quantidade']);
        distAlunos.forEach((chave, qtd) {
          final partes = chave.split('|');
          sheet.appendRow([
            _modelagemCamisaLabel(partes.isNotEmpty ? partes[0] : 'NORMAL'),
            _tipoCamisaLabel(partes.length > 1 ? partes[1] : 'MANGA'),
            partes.length > 2 ? partes[2] : 'OUTRO',
            '$qtd',
          ]);
        });
      }
      sheet.appendRow([]);

      sheet.appendRow(['👕 CAMISAS AVULSAS']);
      sheet.appendRow(['Total:', '${_camisasAvulsas['total']}']);
      sheet.appendRow(['Pagas:', '${_camisasAvulsas['pagas']}']);
      sheet.appendRow([
        'Valor:',
        'R\$ ${_camisasAvulsas['valor'].toStringAsFixed(2)}',
      ]);

      final distAvulsas = Map<String, int>.from(
        _camisasAvulsas['por_detalhe'] ?? {},
      );
      if (distAvulsas.isNotEmpty) {
        sheet.appendRow(['Distribuição detalhada:']);
        sheet.appendRow(['Modelagem', 'Tipo', 'Tamanho', 'Quantidade']);
        distAvulsas.forEach((chave, qtd) {
          final partes = chave.split('|');
          sheet.appendRow([
            _modelagemCamisaLabel(partes.isNotEmpty ? partes[0] : 'NORMAL'),
            _tipoCamisaLabel(partes.length > 1 ? partes[1] : 'MANGA'),
            partes.length > 2 ? partes[2] : 'OUTRO',
            '$qtd',
          ]);
        });
      }
      sheet.appendRow([]);

      sheet.appendRow(['👕 RESUMO TOTAL DE CAMISAS']);
      sheet.appendRow(['Total:', '${_detalhesCamisas['total_camisas']}']);
      sheet.appendRow(['Pagas:', '${_detalhesCamisas['camisas_pagas']}']);
      sheet.appendRow([
        'Valor total:',
        'R\$ ${_detalhesCamisas['valor_total_camisas'].toStringAsFixed(2)}',
      ]);

      final distTotal = Map<String, int>.from(
        _detalhesCamisas['por_detalhe'] ?? {},
      );
      if (distTotal.isNotEmpty) {
        sheet.appendRow(['Distribuição total detalhada:']);
        sheet.appendRow(['Modelagem', 'Tipo', 'Tamanho', 'Quantidade']);
        distTotal.forEach((chave, qtd) {
          final partes = chave.split('|');
          sheet.appendRow([
            _modelagemCamisaLabel(partes.isNotEmpty ? partes[0] : 'NORMAL'),
            _tipoCamisaLabel(partes.length > 1 ? partes[1] : 'MANGA'),
            partes.length > 2 ? partes[2] : 'OUTRO',
            '$qtd',
          ]);
        });
      }
      sheet.appendRow([]);

      sheet.appendRow(['🤝 DETALHES DOS PATROCÍNIOS']);
      sheet.appendRow([
        'Total de patrocinadores:',
        '${_detalhesPatrocinios['total_patrocinadores']}',
      ]);
      sheet.appendRow([
        'Patrocínios pagos:',
        '${_detalhesPatrocinios['patrocinios_pagos']}',
      ]);
      sheet.appendRow([
        'Patrocínios pendentes:',
        '${_detalhesPatrocinios['patrocinios_pendentes']}',
      ]);
      sheet.appendRow([
        'Valor total patrocínios:',
        'R\$ ${_detalhesPatrocinios['valor_total_patrocinios'].toStringAsFixed(2)}',
      ]);
      sheet.appendRow([]);

      if (_usosPatrocinio.isNotEmpty) {
        sheet.appendRow(['📋 ALUNOS BENEFICIADOS POR PATROCÍNIO']);
        sheet.appendRow([
          'Patrocinador',
          'Aluno',
          'Valor',
          'Data',
          'Observação',
        ]);
        for (var uso in _usosPatrocinio) {
          sheet.appendRow([
            uso['patrocinador'],
            uso['aluno_nome'],
            'R\$ ${uso['valor'].toStringAsFixed(2)}',
            _formatter.format(uso['data']),
            uso['observacao'],
          ]);
        }
        sheet.appendRow([]);
      }

      if (_receitasPorForma.isNotEmpty) {
        sheet.appendRow(['💳 RECEITAS POR FORMA DE PAGAMENTO']);
        _receitasPorForma.forEach((forma, valor) {
          double percentual = _totalReceitas > 0
              ? (valor / _totalReceitas * 100)
              : 0;
          sheet.appendRow([
            forma,
            'R\$ ${valor.toStringAsFixed(2)}',
            '${percentual.toStringAsFixed(1)}%',
          ]);
        });
        sheet.appendRow([]);
      }

      if (_gastosPorCategoria.isNotEmpty) {
        sheet.appendRow(['💸 GASTOS POR CATEGORIA']);
        _gastosPorCategoria.forEach((categoria, valor) {
          double percentual = _totalGastos > 0
              ? (valor / _totalGastos * 100)
              : 0;
          sheet.appendRow([
            categoria,
            'R\$ ${valor.toStringAsFixed(2)}',
            '${percentual.toStringAsFixed(1)}%',
          ]);
        });
        sheet.appendRow([]);
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/relatorio_financeiro_${widget.eventoId}.xlsx',
      );
      await file.writeAsBytes(excel.encode()!);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Relatório Financeiro - ${widget.eventoNome}');
    } catch (e) {
      debugPrint('❌ Erro ao exportar Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ==================== EXPORTAÇÃO DE PDFs ====================
  Future<void> _gerarPdfConfeccao() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar PDF de confecção.',
      );
      return;
    }

    try {
      await EventoFinanceiroPdfService.gerarPdfConfeccaoCamisas(
        detalhesCamisas: _detalhesCamisas,
        eventoNome: widget.eventoNome,
      );
    } catch (e) {
      _mostrarErro('Erro ao gerar PDF: $e');
    }
  }

  // 🔥 NOVO: PDF Confecção Completo (alunos + avulsas separados)
  Future<void> _gerarPdfConfeccaoCompleto() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar PDF de confecção completo.',
      );
      return;
    }

    try {
      await EventoFinanceiroPdfService.gerarPdfConfeccaoCompleto(
        camisasAlunos: _camisasParticipacoes,
        camisasAvulsas: _camisasAvulsas,
        totalGeral: _detalhesCamisas,
        eventoNome: widget.eventoNome,
      );
    } catch (e) {
      _mostrarErro('Erro ao gerar PDF: $e');
    }
  }

  Future<void> _gerarPdfListaEntregaCamisas() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar lista de entrega de camisas.',
      );
      return;
    }

    try {
      final itens = await _obterListaEntregaCamisasCompleta();

      await EventoFinanceiroPdfService.gerarPdfListaEntregaCamisasCompleta(
        itens: itens,
        eventoNome: widget.eventoNome,
      );
    } catch (e) {
      _mostrarErro('Erro ao gerar lista de entrega de camisas: $e');
    }
  }

  Future<void> _gerarPdfGeral() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar relatório geral.',
      );
      return;
    }

    try {
      await EventoFinanceiroPdfService.gerarPdfRelatorioGeral(
        totalReceitas: _totalReceitas,
        totalGastos: _totalGastos,
        saldoLiquido: _saldoLiquido,
        totalParticipantes: _totalParticipantes,
        quitados: _quitados,
        inadimplentes: _inadimplentes,
        cobertosPorPatrocinio: _cobertosPorPatrocinio,
        totalInscricoes: _totalInscricoes,
        totalCamisas: _totalCamisas,
        totalPatrocinios: _totalPatrocinios,
        receitasPorForma: _receitasPorForma,
        gastosPorCategoria: _gastosPorCategoria,
        detalhesCamisas: _detalhesCamisas,
        detalhesPatrocinios: _detalhesPatrocinios,
        usosPatrocinio: _usosPatrocinio,
        eventoNome: widget.eventoNome,
      );
    } catch (e) {
      _mostrarErro('Erro ao gerar PDF: $e');
    }
  }

  // ✅ PDF Lista de Participantes (básico, já existente) – agora com diálogo de ordenação
  Future<void> _gerarPdfParticipantes() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar lista de participantes.',
      );
      return;
    }

    await _executarComOrdenacao((lista) async {
      await EventoFinanceiroPdfService.gerarPdfListaParticipantes(
        participantes: lista,
        eventoNome: widget.eventoNome,
      );
    });
  }

  // 🔥 NOVO: PDF Conferência de Nomes (pais verificarem) – com diálogo de ordenação
  Future<void> _gerarPdfConferenciaNomes() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao(
        'Você não tem permissão para gerar conferência de nomes.',
      );
      return;
    }

    await _executarComOrdenacao((lista) async {
      await EventoFinanceiroPdfService.gerarPdfConferenciaNomes(
        participantes: lista,
        eventoNome: widget.eventoNome,
      );
    });
  }

  // 🔥 NOVO: PDF Lista Completa com Corda Cortada e Graduação (cores) – com diálogo de ordenação
  Future<void> _gerarPdfListaCompleta() async {
    if (!_podeExportarRelatorio) {
      _mostrarSemPermissao('Você não tem permissão para gerar lista completa.');
      return;
    }

    await _executarComOrdenacao((lista) async {
      await EventoFinanceiroPdfService.gerarPdfListaCompleta(
        participantes: lista,
        eventoNome: widget.eventoNome,
      );
    });
  }

  Widget _buildPermissoesRelatorioCard() {
    if (_carregandoPermissoes) {
      return Container(
        padding: EdgeInsets.all(14),
        decoration: _relatorioCardDecoration(context.uai.cardAlt),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _ensureVisible(context.uai.success, context.uai.card),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Conferindo permissões do relatório...',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final liberado = _podeVerRelatorio || _podeExportarRelatorio;
    final color = liberado ? context.uai.success : context.uai.warning;

    return Container(
      padding: EdgeInsets.all(14),
      decoration: _relatorioCardDecoration(color.withOpacity(0.22)),
      child: Row(
        children: [
          Icon(
            liberado ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: _ensureVisible(color, context.uai.card),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              liberado
                  ? 'Relatório liberado para visualização e exportação conforme suas permissões.'
                  : 'Você não tem permissão para visualizar ou exportar este relatório.',
              style: TextStyle(
                color: _ensureVisible(color, context.uai.card),
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _relatorioCardDecoration(Color borderColor) {
    return BoxDecoration(
      color: context.uai.card,
      borderRadius: BorderRadius.circular(18),
      border: material.Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: _shadowColor(0.025),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildSemAcessoRelatorio() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460),
          child: Container(
            padding: EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.uai.card,
              borderRadius: BorderRadius.circular(26),
              border: material.Border.all(
                color: context.uai.warning.withOpacity(0.16),
              ),
              boxShadow: [
                BoxShadow(
                  color: _shadowColor(0.035),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: _ensureVisible(context.uai.warning, context.uai.card),
                ),
                SizedBox(height: 12),
                Text(
                  'Relatório bloqueado',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Peça para o administrador liberar “Ver relatórios do evento” nas permissões do usuário.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _recarregarTudo,
                  icon: Icon(Icons.refresh_rounded),
                  label: Text('Recarregar permissões'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ensureVisible(
                      context.uai.success,
                      context.uai.card,
                    ),
                    side: BorderSide(
                      color: context.uai.success.withOpacity(0.25),
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

  Widget _buildLoadingComLogs() {
    final ultimosLogs = _loadingLogs.reversed
        .take(12)
        .toList()
        .reversed
        .toList();

    return Container(
      color: context.uai.background,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 620),
            child: Container(
              padding: EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.circular(26),
                border: material.Border.all(
                  color: context.uai.success.withOpacity(0.16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _shadowColor(0.04),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: context.uai.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _ensureVisible(
                              context.uai.success,
                              context.uai.card,
                            ),
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Atualizando relatório...',
                              style: TextStyle(
                                color: context.uai.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _loadingEtapa,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.uai.textSecondary,
                                fontSize: 12.5,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.uai.cardAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: material.Border.all(color: context.uai.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              color: context.uai.textPrimary,
                              size: 18,
                            ),
                            SizedBox(width: 7),
                            Text(
                              'Logs do carregamento',
                              style: TextStyle(
                                color: _ensureVisible(
                                  context.uai.success,
                                  context.uai.cardAlt,
                                ),
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 9),
                        if (ultimosLogs.isEmpty)
                          Text(
                            '> iniciando...',
                            style: TextStyle(
                              color: context.uai.textSecondary,
                              fontSize: 11,
                            ),
                          )
                        else
                          ...ultimosLogs.map((log) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 5),
                              child: Text(
                                '> $log',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.uai.textSecondary,
                                  fontSize: 11,
                                  height: 1.25,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroRelatorioTela() {
    final r = context.uaiResponsive;

    return Container(
      padding: EdgeInsets.all(r.isPhone ? 16 : 20),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.18),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: _onPrimary().withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: material.Border.all(
                color: _onPrimary().withOpacity(0.16),
              ),
            ),
            child: Icon(
              Icons.assessment_rounded,
              color: _onPrimary(),
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                widget.eventoNome,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _onPrimary(),
                  fontSize: narrow ? 21 : 26,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Resumo financeiro, participantes, camisas, patrocínios e relatórios do evento.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _onPrimary().withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHeroChip(
                    Icons.groups_rounded,
                    '$_totalParticipantes participantes',
                  ),
                  _buildHeroChip(
                    Icons.trending_up_rounded,
                    _formatarMoeda(_totalReceitas),
                  ),
                  _buildHeroChip(
                    _saldoLiquido >= 0
                        ? Icons.check_circle_rounded
                        : Icons.warning_rounded,
                    'Saldo ${_formatarMoeda(_saldoLiquido)}',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, SizedBox(height: 14), text]);
          }

          return Row(
            children: [
              icon,
              SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _onPrimary().withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: material.Border.all(color: _onPrimary().withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _onPrimary(), size: 14),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: _onPrimary(),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  double _relatorioMaxWidth(UaiResponsive r) {
    if (r.isPhone) return double.infinity;
    if (r.isTablet) return 920;
    if (r.isDesktop) return 1120;
    return 1180;
  }

  EdgeInsets _relatorioPadding(UaiResponsive r) {
    if (r.isPhone) return r.listInsets;
    return EdgeInsets.fromLTRB(r.pagePadding, r.pagePadding, r.pagePadding, 34);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          'Relatório Financeiro',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ??
            context.uai.primary,
        foregroundColor:
            Theme.of(context).appBarTheme.foregroundColor ?? _onPrimary(),
        elevation: 0,
        actions: [
          // 🔥 MENU DE EXPORTAÇÃO (Excel + PDFs)
          if (_podeExportarRelatorio)
            PopupMenuButton<String>(
              icon: Icon(Icons.download),
              tooltip: 'Exportar relatórios',
              onSelected: (value) {
                if (value == 'excel') _exportarExcel();
                if (value == 'confeccao') _gerarPdfConfeccao();
                if (value == 'confeccao_completo') _gerarPdfConfeccaoCompleto();
                if (value == 'lista_entrega_camisas')
                  _gerarPdfListaEntregaCamisas();
                if (value == 'geral') _gerarPdfGeral();
                if (value == 'participantes') _gerarPdfParticipantes();
                // 🔥 NOVOS PDFs
                if (value == 'conferencia_nomes') _gerarPdfConferenciaNomes();
                if (value == 'lista_completa') _gerarPdfListaCompleta();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'excel', child: Text('📊 Exportar Excel')),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'confeccao',
                  child: Text('👕 PDF Confecção Camisas (Total)'),
                ),
                PopupMenuItem(
                  value: 'confeccao_completo',
                  child: Text('👕 PDF Confecção Completo (Alunos + Avulsos)'),
                ),
                PopupMenuItem(
                  value: 'lista_entrega_camisas',
                  child: Text('✅ PDF Lista de Entrega de Camisas'),
                ),
                PopupMenuItem(
                  value: 'geral',
                  child: Text('📄 PDF Relatório Geral'),
                ),
                PopupMenuItem(
                  value: 'participantes',
                  child: Text('👥 PDF Lista Participantes'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'conferencia_nomes',
                  child: Text('📋 PDF Conferência de Nomes (Pais)'),
                ),
                PopupMenuItem(
                  value: 'lista_completa',
                  child: Text('📋 PDF Lista Completa (Corda/Graduação)'),
                ),
              ],
            ),
          IconButton(icon: Icon(Icons.refresh), onPressed: _recarregarTudo),
        ],
      ),
      body: _carregandoPermissoes
          ? _buildLoadingComLogs()
          : (!_podeVerRelatorio && !_podeExportarRelatorio)
          ? _buildSemAcessoRelatorio()
          : _isLoading
          ? _buildLoadingComLogs()
          : RefreshIndicator(
              onRefresh: _carregarDados,
              color: _ensureVisible(context.uai.success, context.uai.card),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final r = UaiResponsive.fromConstraints(context, constraints);

                  return SingleChildScrollView(
                    padding: _relatorioPadding(r),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _relatorioMaxWidth(r),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroRelatorioTela(),
                            SizedBox(height: 16),
                            // ===== CARDS DE RESUMO =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildResumoCard(
                                          'Receitas',
                                          _totalReceitas,
                                          Icons.trending_up,
                                          context.uai.success,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: _buildResumoCard(
                                          'Gastos',
                                          _totalGastos,
                                          Icons.trending_down,
                                          context.uai.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _saldoLiquido >= 0
                                              ? context.uai.success.withOpacity(
                                                  0.16,
                                                )
                                              : context.uai.error.withOpacity(
                                                  0.16,
                                                ),
                                          _saldoLiquido >= 0
                                              ? context.uai.success.withOpacity(
                                                  0.08,
                                                )
                                              : context.uai.error.withOpacity(
                                                  0.08,
                                                ),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: material.Border.all(
                                        color: _saldoLiquido >= 0
                                            ? context.uai.success.withOpacity(
                                                0.25,
                                              )
                                            : context.uai.error.withOpacity(
                                                0.28,
                                              ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _saldoLiquido >= 0
                                                  ? Icons.check_circle
                                                  : Icons.warning,
                                              color: _saldoLiquido >= 0
                                                  ? context.uai.success
                                                  : context.uai.error,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'SALDO LÍQUIDO:',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          _formatarMoeda(_saldoLiquido),
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: _saldoLiquido >= 0
                                                ? _ensureVisible(
                                                    context.uai.success,
                                                    context.uai.card,
                                                  )
                                                : _ensureVisible(
                                                    context.uai.error,
                                                    context.uai.card,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== RECEITAS POR TIPO =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '💰 RECEITAS POR TIPO',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.success,
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  _buildReceitaTipoRow(
                                    'Inscrições',
                                    _totalInscricoes,
                                    Icons.receipt,
                                    context.uai.info,
                                  ),
                                  SizedBox(height: 8),
                                  _buildReceitaTipoRow(
                                    'Camisas',
                                    _totalCamisas,
                                    Icons.shopping_bag,
                                    context.uai.warning,
                                  ),
                                  SizedBox(height: 8),
                                  _buildReceitaTipoRow(
                                    'Patrocínios',
                                    _totalPatrocinios,
                                    Icons.volunteer_activism,
                                    context.uai.associacao,
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== GRÁFICO DE PIZZA =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🥧 RECEITAS VS GASTOS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.success,
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  SizedBox(
                                    height: context.uaiResponsive.isPhone
                                        ? 220
                                        : 260,
                                    child: PieChart(
                                      PieChartData(
                                        sections: [
                                          PieChartSectionData(
                                            value: _totalReceitas,
                                            title:
                                                'Receitas\n${_formatarMoeda(_totalReceitas)}',
                                            color: context.uai.success,
                                            radius:
                                                context.uaiResponsive.isPhone
                                                ? 80
                                                : 92,
                                            titleStyle: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _onSuccess(),
                                            ),
                                          ),
                                          PieChartSectionData(
                                            value: _totalGastos,
                                            title:
                                                'Gastos\n${_formatarMoeda(_totalGastos)}',
                                            color: context.uai.error,
                                            radius:
                                                context.uaiResponsive.isPhone
                                                ? 80
                                                : 92,
                                            titleStyle: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _onError(),
                                            ),
                                          ),
                                        ],
                                        sectionsSpace: 2,
                                        centerSpaceRadius:
                                            context.uaiResponsive.isPhone
                                            ? 40
                                            : 46,
                                        startDegreeOffset: 180,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildLegendaItem(
                                        'Receitas',
                                        context.uai.success,
                                      ),
                                      SizedBox(width: 24),
                                      _buildLegendaItem(
                                        'Gastos',
                                        context.uai.error,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== PARTICIPAÇÕES =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '👥 PARTICIPAÇÕES',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: context.uai.info,
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context.uai.info.withOpacity(
                                            0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          'Total: $_totalParticipantes',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _ensureVisible(
                                              context.uai.info,
                                              context.uai.card,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatusCard(
                                          'Quitados',
                                          _quitados,
                                          Icons.check_circle,
                                          context.uai.success,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: _buildStatusCard(
                                          'Patrocínio',
                                          _cobertosPorPatrocinio,
                                          Icons.volunteer_activism,
                                          context.uai.associacao,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: _buildStatusCard(
                                          'Inadimplentes',
                                          _inadimplentes,
                                          Icons.warning,
                                          context.uai.warning,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),

                                  if (_totalParticipantes > 0)
                                    Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: _quitados > 0
                                                  ? _quitados
                                                  : 1,
                                              child: Container(
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: context.uai.success,
                                                  borderRadius:
                                                      BorderRadius.horizontal(
                                                        left: Radius.circular(
                                                          4,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ),
                                            if (_cobertosPorPatrocinio > 0)
                                              Expanded(
                                                flex: _cobertosPorPatrocinio,
                                                child: Container(
                                                  height: 8,
                                                  color: context.uai.associacao,
                                                ),
                                              ),
                                            Expanded(
                                              flex: _inadimplentes > 0
                                                  ? _inadimplentes
                                                  : 1,
                                              child: Container(
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: context.uai.warning,
                                                  borderRadius:
                                                      BorderRadius.horizontal(
                                                        right: Radius.circular(
                                                          4,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${_quitados} quitados',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _ensureVisible(
                                                  context.uai.success,
                                                  context.uai.card,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${_cobertosPorPatrocinio} patrocínio',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _ensureVisible(
                                                  context.uai.associacao,
                                                  context.uai.card,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${_inadimplentes} inadimplentes',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _ensureVisible(
                                                  context.uai.warning,
                                                  context.uai.card,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== RECEITAS POR FORMA DE PAGAMENTO =====
                            if (_receitasPorForma.isNotEmpty)
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.uai.card,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: context.uai.border,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '💳 RECEITAS POR FORMA',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: context.uai.success,
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    ..._receitasPorForma.entries.map((entry) {
                                      final percentual = (_totalReceitas > 0)
                                          ? (entry.value / _totalReceitas * 100)
                                          : 0;
                                      return Padding(
                                        padding: EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _getCorFormaPagamento(
                                                  entry.key,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                entry.key,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                _formatarMoeda(entry.value),
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                '${percentual.toStringAsFixed(1)}%',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  color:
                                                      context.uai.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),

                            SizedBox(height: 16),

                            // ===== DETALHES DAS CAMISAS =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '👕 CAMISAS DOS ALUNOS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.info,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildDetalheItem(
                                        'Total',
                                        '${_camisasParticipacoes['total']}',
                                        Icons.shopping_bag,
                                        context.uai.info,
                                      ),
                                      _buildDetalheItem(
                                        'Pagas',
                                        '${_camisasParticipacoes['pagas']}',
                                        Icons.paid,
                                        context.uai.success,
                                      ),
                                      _buildDetalheItem(
                                        'Valor',
                                        _formatarMoeda(
                                          _camisasParticipacoes['valor'],
                                        ),
                                        Icons.attach_money,
                                        context.uai.warning,
                                      ),
                                    ],
                                  ),
                                  if (Map<String, int>.from(
                                    _camisasParticipacoes['por_detalhe'] ?? {},
                                  ).isNotEmpty) ...[
                                    SizedBox(height: 12),
                                    Text(
                                      'Distribuição:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          Map<String, int>.from(
                                            _camisasParticipacoes['por_detalhe'] ??
                                                {},
                                          ).entries.map((entry) {
                                            return Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: context.uai.info
                                                    .withOpacity(0.08),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _labelGradeCamisa(
                                                      entry.key,
                                                    ),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _ensureVisible(
                                                        context.uai.info,
                                                        context.uai.card,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    '${entry.value}',
                                                    style: TextStyle(
                                                      color: _ensureVisible(
                                                        context.uai.info,
                                                        context.uai.card,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '👕 CAMISAS AVULSAS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.warning,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildDetalheItem(
                                        'Total',
                                        '${_camisasAvulsas['total']}',
                                        Icons.shopping_bag,
                                        context.uai.warning,
                                      ),
                                      _buildDetalheItem(
                                        'Pagas',
                                        '${_camisasAvulsas['pagas']}',
                                        Icons.paid,
                                        context.uai.success,
                                      ),
                                      _buildDetalheItem(
                                        'Valor',
                                        _formatarMoeda(
                                          _camisasAvulsas['valor'],
                                        ),
                                        Icons.attach_money,
                                        context.uai.warning,
                                      ),
                                    ],
                                  ),
                                  if (Map<String, int>.from(
                                    _camisasAvulsas['por_detalhe'] ?? {},
                                  ).isNotEmpty) ...[
                                    SizedBox(height: 12),
                                    Text(
                                      'Distribuição:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          Map<String, int>.from(
                                            _camisasAvulsas['por_detalhe'] ??
                                                {},
                                          ).entries.map((entry) {
                                            return Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: context.uai.warning
                                                    .withOpacity(0.08),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _labelGradeCamisa(
                                                      entry.key,
                                                    ),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _ensureVisible(
                                                        context.uai.warning,
                                                        context.uai.card,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    '${entry.value}',
                                                    style: TextStyle(
                                                      color: _ensureVisible(
                                                        context.uai.warning,
                                                        context.uai.card,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== RESUMO TOTAL DE CAMISAS =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '👕 RESUMO TOTAL DE CAMISAS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.associacao,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildDetalheItem(
                                        'Total',
                                        '${_detalhesCamisas['total_camisas']}',
                                        Icons.shopping_bag,
                                        context.uai.associacao,
                                      ),
                                      _buildDetalheItem(
                                        'Pagas',
                                        '${_detalhesCamisas['camisas_pagas']}',
                                        Icons.paid,
                                        context.uai.success,
                                      ),
                                      _buildDetalheItem(
                                        'Valor',
                                        _formatarMoeda(
                                          _detalhesCamisas['valor_total_camisas'],
                                        ),
                                        Icons.attach_money,
                                        context.uai.warning,
                                      ),
                                    ],
                                  ),
                                  if (Map<String, int>.from(
                                    _detalhesCamisas['por_detalhe'] ?? {},
                                  ).isNotEmpty) ...[
                                    SizedBox(height: 12),
                                    Text(
                                      'Distribuição total:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          Map<String, int>.from(
                                            _detalhesCamisas['por_detalhe'] ??
                                                {},
                                          ).entries.map((entry) {
                                            return Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: context.uai.associacao
                                                    .withOpacity(0.08),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _labelGradeCamisa(
                                                      entry.key,
                                                    ),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _ensureVisible(
                                                        context.uai.associacao,
                                                        context.uai.card,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    '${entry.value}',
                                                    style: TextStyle(
                                                      color: _ensureVisible(
                                                        context.uai.associacao,
                                                        context.uai.card,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== DETALHES DOS PATROCÍNIOS =====
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.uai.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.uai.border,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🤝 PATROCÍNIOS',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.associacao,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildDetalheItem(
                                        'Total',
                                        '${_detalhesPatrocinios['total_patrocinadores']}',
                                        Icons.people,
                                        context.uai.associacao,
                                      ),
                                      _buildDetalheItem(
                                        'Pagos',
                                        '${_detalhesPatrocinios['patrocinios_pagos']}',
                                        Icons.check_circle,
                                        context.uai.success,
                                      ),
                                      _buildDetalheItem(
                                        'Pendentes',
                                        '${_detalhesPatrocinios['patrocinios_pendentes']}',
                                        Icons.pending,
                                        context.uai.warning,
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.uai.associacao.withOpacity(
                                        0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Total recebido:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          _formatarMoeda(
                                            _detalhesPatrocinios['valor_total_patrocinios'],
                                          ),
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: _ensureVisible(
                                              context.uai.associacao,
                                              context.uai.card,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (_usosPatrocinio.isNotEmpty) ...[
                                    SizedBox(height: 16),
                                    Divider(),
                                    SizedBox(height: 8),
                                    Text(
                                      '📋 Alunos beneficiados:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    ..._usosPatrocinio.map(
                                      (uso) => Container(
                                        margin: EdgeInsets.only(bottom: 8),
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: context.uai.background,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: material.Border.all(
                                            color: context.uai.associacao
                                                .withOpacity(0.25),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: context.uai.associacao
                                                    .withOpacity(0.16),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.volunteer_activism,
                                                color: context.uai.associacao,
                                                size: 20,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    uso['aluno_nome'],
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    'Patrocinador: ${uso['patrocinador']}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: context
                                                          .uai
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                  if (uso['observacao']
                                                      .isNotEmpty)
                                                    Text(
                                                      uso['observacao'],
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: context
                                                            .uai
                                                            .textMuted,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  _formatarMoeda(uso['valor']),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: _ensureVisible(
                                                      context.uai.associacao,
                                                      context.uai.card,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  _formatter.format(
                                                    uso['data'],
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: context
                                                        .uai
                                                        .textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // ===== GASTOS POR CATEGORIA =====
                            if (_gastosPorCategoria.isNotEmpty)
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.uai.card,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: context.uai.border,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '💸 GASTOS POR CATEGORIA',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: context.uai.error,
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    ..._gastosPorCategoria.entries.map((entry) {
                                      final percentual = (_totalGastos > 0)
                                          ? (entry.value / _totalGastos * 100)
                                          : 0;
                                      return Padding(
                                        padding: EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: context.uai.error,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                entry.key,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                _formatarMoeda(entry.value),
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                '${percentual.toStringAsFixed(1)}%',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  color:
                                                      context.uai.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),

                            SizedBox(height: 16),

                            // ===== CONSISTÊNCIA DOS DADOS =====
                            if (_participacoesDuplicadasIgnoradas > 0 ||
                                _participacoesRemovidasIgnoradas > 0 ||
                                _usosPatrocinioOrfaosIgnorados > 0 ||
                                _usosPatrocinioDuplicadosIgnorados > 0) ...[
                              _buildConsistenciaDadosCard(),
                              SizedBox(height: 16),
                            ],

                            // ===== AVISO DE ATUALIZAÇÃO =====
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.uai.info.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: material.Border.all(
                                  color: context.uai.info.withOpacity(0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info,
                                    color: _ensureVisible(
                                      context.uai.info,
                                      context.uai.card,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Os dados são atualizados em tempo real. Puxe para baixo para recarregar.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _ensureVisible(
                                          context.uai.info,
                                          context.uai.card,
                                        ),
                                      ),
                                    ),
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
            ),
    );
  }

  Widget _buildConsistenciaDadosCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: material.Border.all(color: context.uai.info.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: context.uai.info.withOpacity(0.16).withOpacity(0.35),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_rounded,
                color: _ensureVisible(context.uai.info, context.uai.card),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Conferência automática aplicada',
                  style: TextStyle(
                    color: _ensureVisible(context.uai.info, context.uai.card),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Ao atualizar, o relatório considera apenas participantes válidos e ignora duplicidades ou usos de patrocínio que ficaram órfãos.',
            style: TextStyle(
              color: _ensureVisible(context.uai.info, context.uai.card),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildConsistenciaChip(
                'Participações duplicadas',
                _participacoesDuplicadasIgnoradas,
                context.uai.warning,
              ),
              _buildConsistenciaChip(
                'Participações removidas',
                _participacoesRemovidasIgnoradas,
                context.uai.error,
              ),
              _buildConsistenciaChip(
                'Patrocínios órfãos',
                _usosPatrocinioOrfaosIgnorados,
                context.uai.associacao,
              ),
              _buildConsistenciaChip(
                'Patrocínios duplicados',
                _usosPatrocinioDuplicadosIgnorados,
                context.uai.info,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConsistenciaChip(String label, int valor, Color cor) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: material.Border.all(color: cor.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            valor > 0 ? Icons.cleaning_services_rounded : Icons.check_rounded,
            color: cor,
            size: 14,
          ),
          SizedBox(width: 5),
          Text(
            '$label: $valor',
            style: TextStyle(
              color: cor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== WIDGETS AUXILIARES ====================

  Widget _buildReceitaTipoRow(
    String titulo,
    double valor,
    IconData icon,
    Color cor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: cor, size: 16),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            _formatarMoeda(valor),
            style: TextStyle(
              fontSize: context.uaiResponsive.isPhone ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCard(
    String titulo,
    double valor,
    IconData icon,
    Color cor,
  ) {
    final r = context.uaiResponsive;

    return Container(
      padding: EdgeInsets.all(r.isPhone ? 12 : 16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: material.Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor),
          SizedBox(height: 4),
          Text(
            _formatarMoeda(valor),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          Text(
            titulo,
            style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheItem(
    String label,
    String valor,
    IconData icon,
    Color cor,
  ) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: cor, size: 20),
        ),
        SizedBox(height: 4),
        Text(
          valor,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.uai.textSecondary),
        ),
      ],
    );
  }

  Widget _buildStatusCard(String label, int valor, IconData icon, Color cor) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: material.Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 16),
          SizedBox(height: 2),
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: context.uai.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendaItem(String texto, Color cor) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        SizedBox(width: 4),
        Text(texto, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  String _formatarMoeda(double valor) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
  }

  Color _getCorFormaPagamento(String forma) {
    switch (forma.toUpperCase()) {
      case 'PIX':
        return context.uai.success;
      case 'DINHEIRO':
        return context.uai.info;
      case 'CARTÃO':
      case 'CRÉDITO':
      case 'DÉBITO':
        return context.uai.associacao;
      case 'PATROCÍNIO':
        return context.uai.warning;
      case 'CAMISA AVULSA':
        return context.uai.warning;
      default:
        return context.uai.textMuted;
    }
  }
}
