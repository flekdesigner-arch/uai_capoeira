import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  State<DetalheParticipacaoScreen> createState() => _DetalheParticipacaoScreenState();
}


class _PermissaoDetalheChip {
  final String label;
  final bool liberado;
  final IconData icon;

  const _PermissaoDetalheChip(this.label, this.liberado, this.icon);
}

class _DetalheParticipacaoScreenState extends State<DetalheParticipacaoScreen> {
  late ParticipacaoModel _participacao;
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PagamentoService _pagamentoService = PagamentoService();
  final PermissaoService _permissaoService = PermissaoService();
  final GraduacaoService _graduacaoService = GraduacaoService();

  bool _isLoading = false;
  bool _carregandoPermissoes = true;
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

  // Dados do aluno para cálculo de graduação
  Map<String, dynamic>? _dadosAluno;

  // 🔥 Cache para dados do aluno (evita múltiplas chamadas)
  final Map<String, Map<String, dynamic>> _cacheAluno = {};

  // 🔥 ÚLTIMO NÍVEL INFANTIL
  final int _ultimoNivelInfantil = 8;

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

  String? _stringLimpa(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;
    return text;
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
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
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
    _carregarDados();
    _verificarPermissoes();
    _verificarPatrocinio();
    _carregarDadosAluno();
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
      final participacaoAtualizada = await _participacaoService.buscarPorId(widget.participacaoId);

      if (participacaoAtualizada != null) {
        setState(() {
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
        _permissaoService.temQualquerPermissao([
          'pode_concluir_participacao_evento',
          'pode_finalizar_participacao',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_editar_participacao_evento',
          'pode_editar_participante_evento',
          'pode_editar_participante',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_editar_graduacao_evento',
          'pode_editar_participacao_evento',
          'pode_editar_participante_evento',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_registrar_pagamento_evento',
          'pode_registrar_pagamento',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_editar_pagamento_evento',
          'pode_editar_pagamento',
        ]),
        _permissaoService.temQualquerPermissao([
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
  DateTime? _converterData(dynamic data) {
    if (data == null) return null;

    try {
      if (data is Timestamp) {
        return data.toDate();
      }
      if (data is String) {
        try {
          return DateTime.parse(data);
        } catch (e) {
          return _parseDataBrasileira(data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao converter data: $e');
      return null;
    }
  }

  // 🔥 PARSER DE DATA BRASILEIRA (copiado do modal)
  DateTime _parseDataBrasileira(String dataStr) {
    final meses = {
      'janeiro': 1, 'fevereiro': 2, 'março': 3, 'abril': 4,
      'maio': 5, 'junho': 6, 'julho': 7, 'agosto': 8,
      'setembro': 9, 'outubro': 10, 'novembro': 11, 'dezembro': 12
    };

    final parts = dataStr.toLowerCase().split(' ');
    if (parts.length >= 5) {
      final dia = int.tryParse(parts[0]) ?? 1;
      final mes = meses[parts[2]] ?? 1;
      final ano = int.tryParse(parts[4]) ?? 2000;
      return DateTime(ano, mes, dia);
    }
    return DateTime.now();
  }

  // 🔥 CALCULAR IDADE (copiado do modal)
  int _calcularIdade(DateTime dataNascimento) {
    final hoje = DateTime.now();
    int idade = hoje.year - dataNascimento.year;
    if (hoje.month < dataNascimento.month ||
        (hoje.month == dataNascimento.month && hoje.day < dataNascimento.day)) {
      idade--;
    }
    return idade;
  }

  // 🔥 DETERMINAR CATEGORIA POR IDADE (copiado do modal)
  String _determinarCategoriaPorIdade() {
    debugPrint('🔍 ===== DETERMINANDO CATEGORIA =====');
    debugPrint('📦 Dados do aluno:');
    debugPrint('   - data_nascimento: ${_dadosAluno?['data_nascimento']}');
    debugPrint('   - tipo_publico: ${_dadosAluno?['tipo_publico']}');
    debugPrint('   - graduacao: ${_dadosAluno?['graduacao']}');

    // 🔥 PRIORIDADE 1: Calcular pela data de nascimento (MAIS IMPORTANTE!)
    if (_dadosAluno?['data_nascimento'] != null) {
      debugPrint('📅 data_nascimento encontrado: ${_dadosAluno?['data_nascimento']}');
      final dataNascimento = _converterData(_dadosAluno?['data_nascimento']);

      if (dataNascimento != null) {
        final idade = _calcularIdade(dataNascimento);
        debugPrint('✅ Idade REAL calculada: $idade anos');

        // 🔥 REGRA: < 13 anos = INFANTIL, >= 13 = ADULTO
        final categoria = idade < 13 ? 'INFANTIL' : 'ADULTO';
        debugPrint('🏷️ Categoria pela IDADE REAL: $categoria');
        return categoria;
      } else {
        debugPrint('❌ Falha na conversão da data');
      }
    } else {
      debugPrint('❌ data_nascimento é null');
    }

    // 🔥 PRIORIDADE 2: Se não tem data, usa o tipo_publico do aluno (FALLBACK)
    if (_dadosAluno?['tipo_publico'] != null) {
      debugPrint('⚠️ USANDO FALLBACK - tipo_publico: ${_dadosAluno?['tipo_publico']}');
      return _dadosAluno!['tipo_publico'];
    }

    debugPrint('⚠️ Nenhum dado encontrado, usando ADULTO como último recurso');
    return 'ADULTO';
  }

  // 🔥 VERIFICAR SE PODE MUDAR PARA ADULTO (copiado do modal)
  bool _podeMudarParaAdulto(int nivelAtual, int idade) {
    debugPrint('🔍 VERIFICANDO SE PODE MUDAR PARA ADULTO:');
    debugPrint('   - Nível atual: $nivelAtual');
    debugPrint('   - Idade real: $idade');
    debugPrint('   - Último nível infantil: $_ultimoNivelInfantil');

    // Se já atingiu o último nível infantil
    if (nivelAtual >= _ultimoNivelInfantil) {
      debugPrint('✅ Último nível infantil atingido, pode ir para ADULTO');
      return true;
    }

    // Se a idade já permite ADULTO (13+)
    if (idade >= 13) {
      debugPrint('✅ Idade $idade permite ADULTO');
      return true;
    }

    debugPrint('❌ Ainda não pode ir para ADULTO (nível $nivelAtual, idade $idade)');
    return false;
  }

  // 🔥 REGRA PRINCIPAL - CARREGAR GRADUAÇÕES (copiado do modal)
  Future<List<Map<String, dynamic>>> _carregarGraduacoesParaAluno() async {
    final int? nivelAtual = _dadosAluno?['nivel_graduacao'];
    final String? graduacaoAtual = _dadosAluno?['graduacao'];
    final String? graduacaoAtualId = _dadosAluno?['graduacao_id'];

    debugPrint('🎓 ===== REGRAS DE GRADUAÇÃO =====');
    debugPrint('📊 Nível atual: $nivelAtual');
    debugPrint('📊 Graduação atual: $graduacaoAtual');
    debugPrint('📊 Graduação ID: $graduacaoAtualId');

    // 🔥 CASO 1: Aluno SEM graduação
    if (nivelAtual == null || nivelAtual == 0 ||
        graduacaoAtual == null || graduacaoAtual == 'SEM GRADUÇÃO') {

      debugPrint('📌 CASO 1: Aluno SEM graduação');

      final String categoria = _determinarCategoriaPorIdade();
      debugPrint('📌 Categoria determinada: $categoria');

      // Busca TODAS as graduações da categoria
      final todasGraduacoes = await _graduacaoService.buscarGraduacoesPorTipo(categoria);
      debugPrint('📚 Total de graduações $categoria: ${todasGraduacoes.length}');

      if (todasGraduacoes.isEmpty) {
        debugPrint('❌ NENHUMA graduação encontrada para $categoria!');
        return [];
      }

      // Filtra por idade mínima (se tiver data)
      if (_dadosAluno?['data_nascimento'] != null) {
        final dataNascimento = _converterData(_dadosAluno?['data_nascimento']);
        final idade = dataNascimento != null ? _calcularIdade(dataNascimento) : 0;

        final viaveis = todasGraduacoes.where((grad) {
          final idadeMinima = grad['idade_minima'] ?? 0;
          return idade >= idadeMinima;
        }).toList();

        debugPrint('📚 Após filtro de idade: ${viaveis.length}');

        if (viaveis.isEmpty) {
          debugPrint('⚠️ Filtro de idade zerou, mostrando todas');
          return todasGraduacoes;
        }

        return viaveis;
      }

      return todasGraduacoes;
    }

    // 🔥 CASO 2: Aluno COM graduação
    debugPrint('📌 CASO 2: Aluno COM graduação');

    // Busca a graduação atual para saber o tipo
    Map<String, dynamic>? graduacaoAtualObj;
    if (graduacaoAtualId != null && graduacaoAtualId.isNotEmpty) {
      graduacaoAtualObj = await _graduacaoService.buscarPorId(graduacaoAtualId);
    }

    final String tipoAtual = graduacaoAtualObj?['tipo_publico'] ??
        (graduacaoAtual?.contains('INFANTIL') == true ? 'INFANTIL' : 'ADULTO');

    debugPrint('📌 Tipo da graduação atual: $tipoAtual');

    // Busca todas as graduações
    final todasGraduacoes = await _graduacaoService.buscarTodasGraduacoes();

    // Separa por categoria
    final graduacoesInfantis = todasGraduacoes.where((g) => g['tipo_publico'] == 'INFANTIL').toList();
    final graduacoesAdultas = todasGraduacoes.where((g) => g['tipo_publico'] == 'ADULTO').toList();

    graduacoesInfantis.sort((a, b) => (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0));
    graduacoesAdultas.sort((a, b) => (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0));

    List<Map<String, dynamic>> resultados = [];

    // 🔥 SE É INFANTIL ATUALMENTE
    if (tipoAtual == 'INFANTIL') {
      debugPrint('📌 Aluno INFANTIL');

      // 1. Próximas graduações INFANTIS
      final proximasInfantis = graduacoesInfantis.where((g) =>
      (g['nivel_graduacao'] ?? 0) > (nivelAtual ?? 0)).toList();
      resultados.addAll(proximasInfantis);
      debugPrint('   • Próximas INFANTIS: ${proximasInfantis.length}');

      // 🔥 CALCULA IDADE REAL PARA DECIDIR SOBRE ADULTO
      int idade = 0;
      if (_dadosAluno?['data_nascimento'] != null) {
        final dataNascimento = _converterData(_dadosAluno?['data_nascimento']);
        if (dataNascimento != null) {
          idade = _calcularIdade(dataNascimento);
          debugPrint('📊 Idade REAL calculada: $idade anos');
        }
      }

      // Verifica se pode mudar para adulto
      bool podeMostrarAdultas = _podeMudarParaAdulto(nivelAtual ?? 0, idade);

      if (podeMostrarAdultas) {
        debugPrint('   ✅ Pode mostrar ADULTAS');
        resultados.addAll(graduacoesAdultas);
        debugPrint('   • Todas ADULTAS: ${graduacoesAdultas.length}');
      } else {
        debugPrint('   ❌ Não pode mostrar ADULTAS ainda');
      }
    }
    // 🔥 SE É ADULTO ATUALMENTE
    else {
      debugPrint('📌 Aluno ADULTO - só pode ir para níveis maiores');
      final proximasAdultas = graduacoesAdultas.where((g) =>
      (g['nivel_graduacao'] ?? 0) > (nivelAtual ?? 0)).toList();
      resultados.addAll(proximasAdultas);
      debugPrint('   • Próximas ADULTAS: ${proximasAdultas.length}');
    }

    // Remove duplicatas e ordena
    final uniqueResults = resultados.toSet().toList();
    uniqueResults.sort((a, b) {
      // Primeiro por tipo (INFANTIL antes de ADULTO)
      if (a['tipo_publico'] != b['tipo_publico']) {
        return a['tipo_publico'] == 'INFANTIL' ? -1 : 1;
      }
      // Depois por nível
      return (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0);
    });

    debugPrint('📚 TOTAL DE OPÇÕES: ${uniqueResults.length}');
    return uniqueResults;
  }

  Future<void> _registrarPagamento() async {
    if (!_podeRegistrarPagamento) {
      _mostrarSemPermissao('Você não tem permissão para registrar pagamentos.');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RegistrarPagamentoModal(
        saldoAtual: _saldo,
        valorTotal: _participacao.valorTotal,
        sugestoes: _gerarSugestoesPagamento(),
        temPatrocinio: _temPatrocinio,
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      try {
        if (result['formaPagamento'] == 'PATROCÍNIO') {
          await _registrarPagamentoComPatrocinio(result);
        } else {
          await _registrarPagamentoNormal(result);
        }

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

  Future<void> _registrarPagamentoNormal(Map<String, dynamic> result) async {
    final pagamento = PagamentoModel(
      id: '',
      valor: result['valor'],
      formaPagamento: result['formaPagamento'],
      dataPagamento: DateTime.now(),
      observacoes: result['observacoes'],
      registroPor: FirebaseAuth.instance.currentUser?.uid ?? '',
      registroPorNome: FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário',
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
      _participacao = _participacao.copyWith(
        totalPago: novoTotalPago,
      );
      _totalPago = novoTotalPago;
      _saldo = _participacao.valorTotal - novoTotalPago;
    });

    debugPrint('💰 NOVO SALDO CALCULADO:');
    debugPrint('   - Total evento: ${_participacao.valorTotal}');
    debugPrint('   - Total pago: ${_participacao.totalPago}');
    debugPrint('   - Saldo devedor: $_saldo');

    if (_saldo <= 0.01) {
      await _participacaoService.atualizarStatus(
        widget.participacaoId,
        'quitado',
      );

      setState(() {
        _participacao = _participacao.copyWith(status: 'quitado');
      });
    }
  }

  Future<void> _registrarPagamentoComPatrocinio(Map<String, dynamic> result) async {
    final pagamento = PagamentoModel(
      id: '',
      valor: result['valor'],
      formaPagamento: 'PATROCÍNIO',
      dataPagamento: DateTime.now(),
      observacoes: 'Coberto por patrocínio: ${result['observacoes']}',
      registroPor: FirebaseAuth.instance.currentUser?.uid ?? '',
      registroPorNome: FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário',
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
      _participacao = _participacao.copyWith(
        totalPago: novoTotalPago,
      );
      _totalPago = novoTotalPago;
      _saldo = _participacao.valorTotal - novoTotalPago;
    });

    // 🔥 FIX: VERIFICA SE ZEROU O SALDO E ATUALIZA O STATUS
    if (_saldo <= 0.01) {
      await _participacaoService.atualizarStatus(
        widget.participacaoId,
        'quitado',
      );
      setState(() {
        _participacao = _participacao.copyWith(status: 'quitado');
      });
    }

    // Atualiza o saldo do patrocinador
    final patrocinadoresSnapshot = await FirebaseFirestore.instance
        .collection('patrocinadores_eventos')
        .where('evento_id', isEqualTo: widget.eventoId)
        .where('saldo_disponivel', isGreaterThan: 0)
        .limit(1)
        .get();

    if (patrocinadoresSnapshot.docs.isNotEmpty) {
      final patrocinadorDoc = patrocinadoresSnapshot.docs.first;
      final saldoAtual = (patrocinadorDoc['saldo_disponivel'] ?? 0).toDouble();
      final novoSaldo = saldoAtual - result['valor'];

      await patrocinadorDoc.reference.update({
        'saldo_disponivel': novoSaldo,
        'atualizado_em': FieldValue.serverTimestamp(),
      });

      await patrocinadorDoc.reference
          .collection('usos')
          .add({
        'participacao_id': widget.participacaoId,
        'aluno_nome': _participacao.alunoNome,
        'valor': result['valor'],
        'data': DateTime.now(),
        'observacao': result['observacoes'],
      });
    }
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

    await FirebaseFirestore.instance
        .collection('participacoes_eventos_em_andamento')
        .doc(widget.participacaoId)
        .update({
      'total_pago': totalConfirmado,
      'status': novoStatus,
      'atualizado_em': FieldValue.serverTimestamp(),
    });

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

  Future<void> _ajustarUsoPatrocinioAoEditar({
    required PagamentoModel pagamento,
    required double novoValor,
    required String observacoes,
  }) async {
    final forma = pagamento.formaPagamento.toUpperCase();

    if (forma != 'PATROCÍNIO' && forma != 'PATROCINIO') return;

    final diferenca = novoValor - pagamento.valor;

    final patrocinadoresSnapshot = await FirebaseFirestore.instance
        .collection('patrocinadores_eventos')
        .where('evento_id', isEqualTo: widget.eventoId)
        .get();

    for (final patrocinador in patrocinadoresSnapshot.docs) {
      final usosSnapshot = await patrocinador.reference
          .collection('usos')
          .where('participacao_id', isEqualTo: widget.participacaoId)
          .get();

      for (final uso in usosSnapshot.docs) {
        final usoValor = (uso.data()['valor'] as num?)?.toDouble() ?? 0;

        if ((usoValor - pagamento.valor).abs() <= 0.01) {
          await uso.reference.update({
            'valor': novoValor,
            'observacao': observacoes,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

          final saldoAtual =
              (patrocinador.data()['saldo_disponivel'] as num?)?.toDouble() ?? 0;

          await patrocinador.reference.update({
            'saldo_disponivel': saldoAtual - diferenca,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

          return;
        }
      }
    }
  }

  Future<void> _removerUsoPatrocinioDoPagamento(PagamentoModel pagamento) async {
    final forma = pagamento.formaPagamento.toUpperCase();

    if (forma != 'PATROCÍNIO' && forma != 'PATROCINIO') return;

    final patrocinadoresSnapshot = await FirebaseFirestore.instance
        .collection('patrocinadores_eventos')
        .where('evento_id', isEqualTo: widget.eventoId)
        .get();

    for (final patrocinador in patrocinadoresSnapshot.docs) {
      final usosSnapshot = await patrocinador.reference
          .collection('usos')
          .where('participacao_id', isEqualTo: widget.participacaoId)
          .get();

      for (final uso in usosSnapshot.docs) {
        final usoValor = (uso.data()['valor'] as num?)?.toDouble() ?? 0;

        if ((usoValor - pagamento.valor).abs() <= 0.01) {
          await uso.reference.delete();

          final saldoAtual =
              (patrocinador.data()['saldo_disponivel'] as num?)?.toDouble() ?? 0;

          await patrocinador.reference.update({
            'saldo_disponivel': saldoAtual + pagamento.valor,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

          return;
        }
      }
    }
  }

  Future<void> _editarPagamento(PagamentoModel pagamento) async {
    if (!_podeEditarPagamento) {
      _mostrarSemPermissao('Você não tem permissão para editar pagamentos.');
      return;
    }

    if (_participacao.estaFinalizado) {
      _mostrarSemPermissao('Participação finalizada não permite editar pagamentos.');
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

        final statuses = <String>[
          'confirmado',
          'pendente',
          'cancelado',
        ];

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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: formaSelecionada,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pagamento',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payment_rounded),
                      ),
                      items: formas
                          .map((forma) => DropdownMenuItem(
                        value: forma,
                        child: Text(forma),
                      ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => formaSelecionada = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: statusSelecionado,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.verified_rounded),
                      ),
                      items: statuses
                          .map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.toUpperCase()),
                      ))
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
                    final valor = double.tryParse(
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
      final pagamentoRef = FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .collection('participacoes')
          .doc(widget.participacaoId)
          .collection('pagamentos')
          .doc(pagamento.id);

      final novoValor = (result['valor'] as num).toDouble();
      final novasObservacoes = result['observacoes']?.toString() ?? '';

      await _ajustarUsoPatrocinioAoEditar(
        pagamento: pagamento,
        novoValor: novoValor,
        observacoes: novasObservacoes,
      );

      await pagamentoRef.update({
        'valor': novoValor,
        'forma_pagamento': result['formaPagamento'],
        'status': result['status'],
        'observacoes': novasObservacoes,
        'atualizado_em': FieldValue.serverTimestamp(),
        'editado_por': FirebaseAuth.instance.currentUser?.uid ?? '',
      });

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
    if (!_podeExcluirPagamento) {
      _mostrarSemPermissao('Você não tem permissão para excluir pagamentos.');
      return;
    }

    if (_participacao.estaFinalizado) {
      _mostrarSemPermissao('Participação finalizada não permite excluir pagamentos.');
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
      await _removerUsoPatrocinioDoPagamento(pagamento);

      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .collection('participacoes')
          .doc(widget.participacaoId)
          .collection('pagamentos')
          .doc(pagamento.id)
          .delete();

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

      if (_participacao.valorCamisa > 0 && _participacao.valorCamisa <= _saldo) {
        sugestoes.add(_participacao.valorCamisa);
      }

      if (_participacao.valorInscricao > 0 && _participacao.valorInscricao <= _saldo) {
        sugestoes.add(_participacao.valorInscricao);
      }
    }

    return sugestoes.toSet().toList()..sort();
  }

  Future<void> _editarCamisa() async {
    if (!_podeEditarCamisa) {
      _mostrarSemPermissao('Você não tem permissão para editar camisa.');
      return;
    }

    // 🔥 CORREÇÃO: Converter List<dynamic> para List<String>
    List<String> tamanhosDisponiveis = [];

    try {
      if (_dadosEvento != null && _dadosEvento!.containsKey('tamanhosDisponiveis')) {
        final rawValue = _dadosEvento!['tamanhosDisponiveis'];

        if (rawValue != null) {
          if (rawValue is List) {
            // Converte cada item para String de forma segura
            tamanhosDisponiveis = rawValue
                .where((item) => item != null) // Remove nulos
                .map((item) => item.toString()) // Converte para String
                .toList();
          } else if (rawValue is String) {
            // Se for uma string, pode ser um formato específico (ex: "P,M,G,GG")
            tamanhosDisponiveis = rawValue
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao processar tamanhos disponíveis: $e');
      // Em caso de erro, usa uma lista padrão de tamanhos
      tamanhosDisponiveis = ['PP', 'P', 'M', 'G', 'GG', 'XG'];
    }

    // Se ainda estiver vazia, usa uma lista padrão
    if (tamanhosDisponiveis.isEmpty) {
      tamanhosDisponiveis = ['PP', 'P', 'M', 'G', 'GG', 'XG'];
    }

    debugPrint('📏 Tamanhos disponíveis processados: $tamanhosDisponiveis');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditarCamisaModal(
        tamanhoAtual: _participacao.tamanhoCamisa,
        entregue: _participacao.camisaEntregue,
        tamanhosDisponiveis: tamanhosDisponiveis, // 👈 Agora é List<String>
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      try {
        await _participacaoService.atualizarCamisa(
          participacaoId: widget.participacaoId,
          tamanho: result['tamanho'],
          entregue: result['entregue'],
        );

        setState(() {
          _participacao = _participacao.copyWith(
            tamanhoCamisa: result['tamanho'],
            camisaEntregue: result['entregue'],
          );
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
    if (!_podeEditarGraduacao) {
      _mostrarSemPermissao('Você não tem permissão para editar graduação.');
      return;
    }

    // 🔥 Garantir que temos os dados do aluno
    if (_dadosAluno == null) {
      await _carregarDadosAluno();
    }

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
                content: Text('✅ Graduação atualizada para: ${graduacao['nome_graduacao']}'),
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
    if (!_podeFinalizarAgora()) return;

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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
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

  String _formatarData(DateTime? data) {
    if (data == null) return '—';
    return DateFormat('dd/MM/yyyy').format(data);
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
      color: enabled ? color : Colors.grey.shade400,
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
        final webUrl = Uri.parse('https://web.whatsapp.com/send?phone=$cleanedPhone' +
            (mensagem != null && mensagem.isNotEmpty ? '&text=${Uri.encodeComponent(mensagem)}' : ''));

        await launchUrl(
          webUrl,
          mode: LaunchMode.externalApplication,
        );
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

  Widget _buildWhatsAppButtons(Map<String, dynamic> dadosAluno) {
    final contatoAluno = dadosAluno['contato_aluno'] as String? ?? '';
    final contatoResponsavel = dadosAluno['contato_responsavel'] as String?;

    return Row(
      children: [
        Expanded(
          child: _buildWhatsAppButton(
            label: 'WhatsApp\nAluno',  // 🔥 COM QUEBRA DE LINHA
            onPressed: contatoAluno.isNotEmpty
                ? () => _abrirWhatsApp(contatoAluno)
                : null,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildWhatsAppButton(
            label: 'WhatsApp\nResponsável',  // 🔥 COM QUEBRA DE LINHA
            onPressed: contatoResponsavel != null && contatoResponsavel.isNotEmpty
                ? () => _abrirWhatsApp(contatoResponsavel)
                : null,
            color: Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildWhatsAppButton({
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(  // 🔥 MUDEI DE ROW PARA COLUMN
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWhatsAppIcon(
                  enabled: onPressed != null,
                  color: color,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: onPressed != null ? Colors.black87 : Colors.grey.shade400,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,  // 🔥 PERMITE 2 LINHAS
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 30),
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
                        _buildResumoFinanceiroTema(),
                        const SizedBox(height: 14),
                        _buildPagamentosSectionTema(),
                        if (_podeRegistrarPagamento &&
                            !_participacao.estaFinalizado &&
                            _saldo > 0) ...[
                          const SizedBox(height: 12),
                          _buildNovoPagamentoButtonTema(),
                        ],
                        const SizedBox(height: 14),
                        _buildCamisaSectionTema(),
                        if (_participacao.isBatizado) ...[
                          const SizedBox(height: 14),
                          _buildGraduacaoSectionTema(),
                        ],
                        const SizedBox(height: 14),
                        _buildCertificadoHibridoCardTema(certificado),
                        const SizedBox(height: 14),
                        if (_podeFinalizarAgora()) _buildFinalizarButtonTema(),
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
              'Carregando participação...',
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
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.18)),
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
        final contatoResponsavel =
        dadosAluno['contato_responsavel'] as String?;

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
                  onPressed: contatoResponsavel != null &&
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
      color: Color.alphaBlend(
        accent.withOpacity(enabled ? 0.08 : 0.03),
        t.card,
      ),
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
              color: enabled ? accent.withOpacity(0.18) : t.border,
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
      subtitle: 'Total, pago e saldo',
      color: t.info,
      slim: true,
      child: Row(
        children: [
          Expanded(
            child: _miniInfoCardTema(
              'Total',
              _formatarMoeda(_participacao.valorTotal),
              Icons.receipt_rounded,
              t.info,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniInfoCardTema(
              'Pago',
              _formatarMoeda(_totalPago),
              Icons.check_circle_rounded,
              t.success,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniInfoCardTema(
              'Saldo',
              _formatarMoeda(_saldo),
              Icons.pending_rounded,
              _saldo > 0 ? t.warning : t.success,
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
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
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
      trailing: _podeRegistrarPagamento &&
          !_participacao.estaFinalizado &&
          _saldo > 0
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
      subtitle: 'Tamanho e status de entrega',
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
          final narrow = constraints.maxWidth < 480;
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
                tamanho,
                const SizedBox(height: 10),
                status,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: tamanho),
              const SizedBox(width: 12),
              Expanded(child: status),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGraduacaoSectionTema() {
    final t = context.uai;
    final atualColor =
    _ensureVisible(_getCorGraduacao(_participacao.graduacao), t.card);
    final novaColor =
    _ensureVisible(_getCorGraduacao(_participacao.graduacaoNova), t.card);

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
            color: Color.alphaBlend(accent.withOpacity(0.07), t.card),
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: accent.withOpacity(0.20)),
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
                          : 'Gere pelo gerador de certificados ou vincule um link antes de finalizar.',
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
        color: cor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: cor.withOpacity(0.15)),
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
            color: t.warning.withOpacity(0.07),
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.warning.withOpacity(0.16)),
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
        border: Border.all(color: accent.withOpacity(0.16)),
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
              if (trailing != null) trailing,
            ],
          ),
          SizedBox(height: slim ? 10 : 14),
          child,
        ],
      ),
    );
  }

  Widget _infoTileTema(
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
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
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: accent.withOpacity(0.20)),
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
        color: accent.withOpacity(0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.14)),
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
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
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
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.18)),
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

  Widget _buildInfoCard(String label, String value, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
      String label,
      String value, {
        IconData? icon,
        Color? iconColor,
        Color? textColor,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor ?? Colors.grey.shade400),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildParcelasPendentes() {
    final parcelas = <Widget>[];

    if (_saldo <= 0) return parcelas;

    final sugestoes = _gerarSugestoesPagamento();

    if (sugestoes.isEmpty) {
      parcelas.add(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withOpacity(0.16)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ainda existe saldo pendente.',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
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
            color: Colors.red.withOpacity(0.045),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.payments_rounded, color: Colors.red.shade900, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  valor >= _saldo - 0.01 ? 'Quitar saldo restante' : 'Pagamento sugerido',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _formatarMoeda(valor),
                style: TextStyle(
                  color: Colors.red.shade900,
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

  Widget _buildPagamentoCard(PagamentoModel pagamento) {
    final cor = pagamento.status == 'confirmado' ? Colors.green : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withOpacity(0.13)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              pagamento.status == 'confirmado'
                  ? Icons.check_circle_rounded
                  : Icons.schedule_rounded,
              color: cor,
              size: 24,
            ),
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
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5),
                ),
                if ((pagamento.observacoes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    pagamento.observacoes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  pagamento.status.toUpperCase(),
                  style: TextStyle(
                    color: cor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if ((_podeEditarPagamento || _podeExcluirPagamento) &&
                  !_participacao.estaFinalizado) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_podeEditarPagamento)
                      InkWell(
                        onTap: () => _editarPagamento(pagamento),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    if (_podeExcluirPagamento)
                      InkWell(
                        onTap: () => _excluirPagamento(pagamento),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Colors.red.shade700,
                          ),
                        ),
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

      if (!openedDefault) {
        _showSnackTema(
          'Não foi possível abrir o certificado.',
          background: context.uai.error,
          icon: Icons.error_outline_rounded,
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
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
