import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/graduacoes/services/graduacao_service.dart';
import 'package:uai_capoeira/shared/services/svg_service.dart';

class AdicionarParticipanteModal extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final EventoModel evento;
  final bool isBatizado;
  final bool historicoSomenteGraduacao;

  const AdicionarParticipanteModal({
    super.key,
    required this.aluno,
    required this.evento,
    required this.isBatizado,
    this.historicoSomenteGraduacao = false,
  });

  @override
  State<AdicionarParticipanteModal> createState() =>
      _AdicionarParticipanteModalState();
}

class _AdicionarParticipanteModalState
    extends State<AdicionarParticipanteModal> {
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


  InputDecoration _uaiInputDecoration({
    required String label,
    IconData? icon,
    String? hint,
    String? prefixText,
  }) {
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: TextStyle(color: context.uai.textSecondary),
      hintStyle: TextStyle(color: context.uai.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: accent),
      filled: true,
      fillColor: context.uai.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: context.uai.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: context.uai.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  final GraduacaoService _graduacaoService = GraduacaoService();

  String? _tamanhoCamisaSelecionado;
  String _modelagemCamisaSelecionada = 'NORMAL';
  String _tipoCamisaSelecionado = 'MANGA';
  String? _graduacaoSelecionadaId;
  Map<String, dynamic>? _graduacaoSelecionada;

  late double valorInscricao;
  late double valorCamisa;
  late double valorTotal;

  // 🔥 ÚLTIMO NÍVEL INFANTIL
  final int _ultimoNivelInfantil = 8;

  @override
  void initState() {
    super.initState();

    valorInscricao = widget.historicoSomenteGraduacao ? 0 : widget.evento.valorInscricao;
    valorCamisa = widget.historicoSomenteGraduacao
        ? 0
        : (widget.evento.temCamisa ? (widget.evento.valorCamisa ?? 0) : 0);
    valorTotal = valorInscricao + valorCamisa;

    debugPrint('🎯 Modal aberto para: ${widget.aluno['nome']}');
    debugPrint('🎯 É batizado: ${widget.isBatizado}');
    debugPrint('🎯 Nível atual: ${widget.aluno['nivel_graduacao']}');
    debugPrint('🎯 Graduação atual: ${widget.aluno['graduacao']}');

    final modelagens = _modelagensEvento();
    final tipos = _tiposEvento();

    if (modelagens.isNotEmpty) {
      _modelagemCamisaSelecionada = modelagens.first;
    }

    if (tipos.isNotEmpty) {
      _tipoCamisaSelecionado = tipos.first;
    }

    if (!widget.historicoSomenteGraduacao) {
      valorCamisa = _valorCamisaPorTipo(_tipoCamisaSelecionado);
      valorTotal = valorInscricao + valorCamisa;
    }
  }

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

    if (clean == 'REGATA') {
      return 'REGATA';
    }

    return 'MANGA';
  }

  String _modelagemCamisaLabel(String value) {
    switch (_normalizarModelagemCamisa(value)) {
      case 'BABY_LOOK':
        return 'Baby Look';
      case 'NORMAL':
      default:
        return 'Normal';
    }
  }

  String _tipoCamisaLabel(String value) {
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

  List<String> _tamanhosEvento() {
    final lista = widget.evento.tamanhosDisponiveis;

    if (lista.isNotEmpty) {
      return lista
          .map((e) => e.toString().trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return const [
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
    ];
  }

  List<String> _modelagensEvento() {
    final lista = widget.evento.modelagensCamisaDisponiveis;

    if (lista.isNotEmpty) {
      final normalized = lista.map(_normalizarModelagemCamisa).toSet().toList();
      normalized.sort((a, b) {
        const ordem = {'NORMAL': 0, 'BABY_LOOK': 1};
        return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
      });
      return normalized;
    }

    return const ['NORMAL', 'BABY_LOOK'];
  }

  List<String> _tiposEvento() {
    final lista = widget.evento.tiposCamisaDisponiveis;

    if (lista.isNotEmpty) {
      final normalized = lista.map(_normalizarTipoCamisa).toSet().toList();
      normalized.sort((a, b) {
        const ordem = {'MANGA': 0, 'MANGA_LONGA': 1, 'REGATA': 2};
        return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
      });
      return normalized;
    }

    return const ['MANGA', 'MANGA_LONGA', 'REGATA'];
  }

  double _valorCamisaPorTipo(String tipo) {
    if (!widget.evento.temCamisa) return 0;

    final tipoNormalizado = _normalizarTipoCamisa(tipo);

    final valor = widget.evento.valorCamisaPorTipo(tipoNormalizado);

    // Compatibilidade extra: se por algum motivo o mapa vier zerado,
    // usa o valorCamisa antigo.
    if (valor > 0) return valor;

    return widget.evento.valorCamisa ?? 0;
  }

  void _atualizarValorCamisaPorTipo() {
    final novoValorCamisa = _valorCamisaPorTipo(_tipoCamisaSelecionado);

    setState(() {
      valorCamisa = novoValorCamisa;
      valorTotal = valorInscricao + valorCamisa;
    });
  }

  // 🔥 CONVERSÃO DE DATA
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

  // 🔥 PARSER DE DATA BRASILEIRA
  DateTime _parseDataBrasileira(String dataStr) {
    final meses = {
      'janeiro': 1,
      'fevereiro': 2,
      'março': 3,
      'abril': 4,
      'maio': 5,
      'junho': 6,
      'julho': 7,
      'agosto': 8,
      'setembro': 9,
      'outubro': 10,
      'novembro': 11,
      'dezembro': 12,
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

  // 🔥 CALCULAR IDADE
  int _calcularIdade(DateTime dataNascimento) {
    final hoje = DateTime.now();
    int idade = hoje.year - dataNascimento.year;
    if (hoje.month < dataNascimento.month ||
        (hoje.month == dataNascimento.month && hoje.day < dataNascimento.day)) {
      idade--;
    }
    return idade;
  }

  // 🔥 DETERMINAR CATEGORIA POR IDADE - PRIORIDADE MÁXIMA PARA DATA REAL
  String _determinarCategoriaPorIdade() {
    debugPrint('🔍 ===== DETERMINANDO CATEGORIA =====');
    debugPrint('📦 Dados do aluno:');
    debugPrint(
      '   - data_nascimento: ${widget.aluno['data_nascimento']} (${widget.aluno['data_nascimento'].runtimeType})',
    );
    debugPrint('   - tipo_publico: ${widget.aluno['tipo_publico']}');
    debugPrint('   - graduacao: ${widget.aluno['graduacao']}');

    // 🔥 PRIORIDADE 1: Calcular pela data de nascimento (MAIS IMPORTANTE!)
    if (widget.aluno['data_nascimento'] != null) {
      debugPrint(
        '📅 data_nascimento encontrado: ${widget.aluno['data_nascimento']}',
      );
      final dataNascimento = _converterData(widget.aluno['data_nascimento']);

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
    if (widget.aluno['tipo_publico'] != null) {
      debugPrint(
        '⚠️ USANDO FALLBACK - tipo_publico: ${widget.aluno['tipo_publico']}',
      );
      return widget.aluno['tipo_publico'];
    }

    debugPrint('⚠️ Nenhum dado encontrado, usando ADULTO como último recurso');
    return 'ADULTO';
  }

  // 🔥 VERIFICAR SE PODE MUDAR PARA ADULTO
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

    debugPrint(
      '❌ Ainda não pode ir para ADULTO (nível $nivelAtual, idade $idade)',
    );
    return false;
  }

  // 🔥 MENSAGEM PARA ALUNO SEM GRADUAÇÃO
  String _calcularMensagemSemGraduacao() {
    if (widget.aluno['data_nascimento'] == null) {
      return 'Aluno sem data de nascimento cadastrada';
    }

    final dataNascimento = _converterData(widget.aluno['data_nascimento']);
    if (dataNascimento == null) {
      return 'Erro ao processar data de nascimento';
    }

    final idade = _calcularIdade(dataNascimento);
    final categoria = idade < 13 ? 'INFANTIL' : 'ADULTO';

    return 'Aluno sem graduação (idade: $idade anos - Categoria: $categoria)';
  }

  // 🔥 REGRA PRINCIPAL - CARREGAR GRADUAÇÕES
  Future<List<Map<String, dynamic>>> _carregarGraduacoesParaAluno() async {
    final int? nivelAtual = widget.aluno['nivel_graduacao'];
    final String? graduacaoAtual = widget.aluno['graduacao'];
    final String? graduacaoAtualId = widget.aluno['graduacao_id'];

    debugPrint('🎓 ===== REGRAS DE GRADUAÇÃO =====');
    debugPrint('📊 Nível atual: $nivelAtual');
    debugPrint('📊 Graduação atual: $graduacaoAtual');
    debugPrint('📊 Graduação ID: $graduacaoAtualId');

    // 🔥 CASO 1: Aluno SEM graduação
    if (nivelAtual == null ||
        nivelAtual == 0 ||
        graduacaoAtual == null ||
        graduacaoAtual == 'SEM GRADUÇÃO') {
      debugPrint('📌 CASO 1: Aluno SEM graduação');

      final String categoria = _determinarCategoriaPorIdade();
      debugPrint('📌 Categoria determinada: $categoria');

      // Busca TODAS as graduações da categoria
      final todasGraduacoes = await _graduacaoService.buscarGraduacoesPorTipo(
        categoria,
      );
      debugPrint(
        '📚 Total de graduações $categoria: ${todasGraduacoes.length}',
      );

      if (todasGraduacoes.isEmpty) {
        debugPrint('❌ NENHUMA graduação encontrada para $categoria!');
        return [];
      }

      // Filtra por idade mínima (se tiver data)
      if (widget.aluno['data_nascimento'] != null) {
        final dataNascimento = _converterData(widget.aluno['data_nascimento']);
        final idade = dataNascimento != null
            ? _calcularIdade(dataNascimento)
            : 0;

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

    final String tipoAtual =
        graduacaoAtualObj?['tipo_publico'] ??
        (graduacaoAtual.contains('INFANTIL') == true ? 'INFANTIL' : 'ADULTO');

    debugPrint('📌 Tipo da graduação atual: $tipoAtual');

    // Busca todas as graduações
    final todasGraduacoes = await _graduacaoService.buscarTodasGraduacoes();

    // Separa por categoria
    final graduacoesInfantis = todasGraduacoes
        .where((g) => g['tipo_publico'] == 'INFANTIL')
        .toList();
    final graduacoesAdultas = todasGraduacoes
        .where((g) => g['tipo_publico'] == 'ADULTO')
        .toList();

    graduacoesInfantis.sort(
      (a, b) =>
          (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0),
    );
    graduacoesAdultas.sort(
      (a, b) =>
          (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0),
    );

    List<Map<String, dynamic>> resultados = [];

    // 🔥 SE É INFANTIL ATUALMENTE
    if (tipoAtual == 'INFANTIL') {
      debugPrint('📌 Aluno INFANTIL');

      // 1. Próximas graduações INFANTIS
      final proximasInfantis = graduacoesInfantis
          .where((g) => (g['nivel_graduacao'] ?? 0) > nivelAtual)
          .toList();
      resultados.addAll(proximasInfantis);
      debugPrint('   • Próximas INFANTIS: ${proximasInfantis.length}');

      // 🔥 CALCULA IDADE REAL PARA DECIDIR SOBRE ADULTO
      int idade = 0;
      if (widget.aluno['data_nascimento'] != null) {
        final dataNascimento = _converterData(widget.aluno['data_nascimento']);
        if (dataNascimento != null) {
          idade = _calcularIdade(dataNascimento);
          debugPrint('📊 Idade REAL calculada: $idade anos');
        }
      }

      // Verifica se pode mudar para adulto
      bool podeMostrarAdultas = _podeMudarParaAdulto(nivelAtual, idade);

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
      final proximasAdultas = graduacoesAdultas
          .where((g) => (g['nivel_graduacao'] ?? 0) > nivelAtual)
          .toList();
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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: keyboard),
        child: FractionallySizedBox(
          heightFactor: .94,
          child: Material(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: t.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(Icons.how_to_reg_rounded, color: t.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.historicoSomenteGraduacao
                                  ? (widget.isBatizado
                                      ? 'Inserir graduação no evento'
                                      : 'Inserir participação no evento')
                                  : 'Configurar participação',
                              style: TextStyle(color: t.textPrimary, fontSize: 19, fontWeight: FontWeight.w900),
                            ),
                            Text(
                              widget.evento.nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: t.border),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAlunoInfo(),
                        if (!widget.historicoSomenteGraduacao && widget.evento.temCamisa) ...[
                          const SizedBox(height: 18),
                          _buildCamisaSection(),
                        ],
                        if (!widget.historicoSomenteGraduacao) ...[
                          const SizedBox(height: 18),
                          _buildValoresSection(),
                        ],
                        if (widget.isBatizado) ...[
                          const SizedBox(height: 20),
                          _buildGraduacaoSection(),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border(top: BorderSide(color: t.border)),
                  ),
                  child: SafeArea(top: false, child: _buildBotoes()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlunoInfo() {
    final t = context.uai;
    String graduacaoText = (widget.aluno['graduacao'] ?? 'SEM GRADUAÇÃO').toString();
    if (graduacaoText.trim().isEmpty) graduacaoText = 'SEM GRADUAÇÃO';
    final nome = (widget.aluno['nome'] ?? 'Aluno').toString();
    final foto = (widget.aluno['foto'] ?? widget.aluno['foto_perfil_aluno'] ?? widget.aluno['foto_url'])?.toString();

    return SizedBox(
      height: 86,
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 86,
                child: foto != null && foto.isNotEmpty
                    ? Image.network(
                        foto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildAlunoInfoFallback(nome),
                      )
                    : _buildAlunoInfoFallback(nome),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary, fontSize: 14, height: 1.06, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        graduacaoText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.verified_user_rounded, color: t.primary, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlunoInfoFallback(String nome) {
    final t = context.uai;
    final initial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();
    return Container(
      color: t.cardAlt,
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildCamisaSection() {
    final tamanhos = _tamanhosEvento();
    final modelagens = _modelagensEvento();
    final tipos = _tiposEvento();

    if (!modelagens.contains(_modelagemCamisaSelecionada)) {
      _modelagemCamisaSelecionada = modelagens.isNotEmpty
          ? modelagens.first
          : 'NORMAL';
    }

    if (!tipos.contains(_tipoCamisaSelecionado)) {
      _tipoCamisaSelecionado = tipos.isNotEmpty ? tipos.first : 'MANGA';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Camisa do evento',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.uai.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.uai.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.uai.border),
          ),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _modelagemCamisaSelecionada,
                decoration: _uaiInputDecoration(
                  label: 'Modelagem',
                  icon: Icons.style_rounded,
                ),
                dropdownColor: context.uai.surface,
                items: modelagens.map((modelagem) {
                  return DropdownMenuItem(
                    value: modelagem,
                    child: Text(_modelagemCamisaLabel(modelagem)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _modelagemCamisaSelecionada = _normalizarModelagemCamisa(
                      value,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipoCamisaSelecionado,
                decoration: _uaiInputDecoration(
                  label: 'Tipo de camisa',
                  icon: Icons.design_services_rounded,
                ),
                dropdownColor: context.uai.surface,
                items: tipos.map((tipo) {
                  return DropdownMenuItem(
                    value: tipo,
                    child: Text(_tipoCamisaLabel(tipo)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _tipoCamisaSelecionado = _normalizarTipoCamisa(value);
                  _atualizarValorCamisaPorTipo();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tamanhoCamisaSelecionado,
                decoration: _uaiInputDecoration(
                  label: 'Tamanho',
                  icon: Icons.straighten_rounded,
                ),
                dropdownColor: context.uai.surface,
                items: tamanhos.map((tamanho) {
                  return DropdownMenuItem(value: tamanho, child: Text(tamanho));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _tamanhoCamisaSelecionado = value;
                  });
                },
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.uai.info.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.uai.info.withAlpha(46)),
                ),
                child: Text(
                  'Selecionado: '
                  '${_modelagemCamisaLabel(_modelagemCamisaSelecionada)} • '
                  '${_tipoCamisaLabel(_tipoCamisaSelecionado)} • '
                  '${_tamanhoCamisaSelecionado ?? 'sem tamanho'}'
                  ' • R\$ ${valorCamisa.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: TextStyle(
                    color: _ensureVisible(
                      context.uai.info,
                      context.uai.surface,
                    ),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildValoresSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valores da participação',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.uai.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.uai.info.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  'Inscrição: R\$ ${valorInscricao.toStringAsFixed(2)}',
                  style: TextStyle(color: context.uai.info),
                ),
                if (widget.evento.temCamisa)
                  Text(
                    'Camisa: R\$ ${valorCamisa.toStringAsFixed(2)}',
                    style: TextStyle(color: context.uai.info),
                  ),
                Divider(height: 16),
                Text(
                  'Total a pagar: R\$ ${valorTotal.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (widget.evento.permiteParcelamento)
                  Text(
                    'Parcelas: até ${widget.evento.maxParcelas}x',
                    style: TextStyle(fontSize: 12, color: context.uai.success),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGraduacaoSection() {
    final t = context.uai;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.primary.withAlpha(26),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.military_tech_rounded, color: t.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nova graduação',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Escolha visualmente a corda que o aluno receberá.',
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _carregarGraduacoesParaAluno(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.cardAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.border),
                ),
                child: Text(
                  snapshot.hasError ? 'Erro ao carregar graduações.' : _calcularMensagemSemGraduacao(),
                  style: TextStyle(color: t.textSecondary),
                ),
              );
            }
            return _buildGraduacaoCards(snapshot.data!);
          },
        ),
      ],
    );
  }

  Widget _buildGraduacaoCards(List<Map<String, dynamic>> graduacoes) {
    final t = context.uai;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180 ? 3 : constraints.maxWidth >= 760 ? 2 : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: graduacoes.map((grad) {
            final id = grad['id']?.toString() ?? '';
            final selected = _graduacaoSelecionadaId == id;
            final nome = grad['nome_graduacao']?.toString() ?? 'Graduação';
            final tipo = grad['tipo_publico']?.toString() ?? '';
            final nivel = grad['nivel_graduacao']?.toString() ?? '';
            final cor = selected ? t.primary : t.border;
            return SizedBox(
              width: width,
              child: Material(
                color: selected ? t.primary.withAlpha(20) : t.card,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _graduacaoSelecionadaId = id;
                      _graduacaoSelecionada = grad;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cor, width: selected ? 1.8 : 1),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 72, height: 54, child: _buildGraduacaoCordaPreview(grad)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nome,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [if (tipo.isNotEmpty) tipo, if (nivel.isNotEmpty) 'Nível $nivel'].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: t.textSecondary, fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle_rounded, color: t.primary, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _hexColor(dynamic value, Color fallback) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    var hex = raw.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Widget _buildGraduacaoCordaPreview(Map<String, dynamic> grad) {
    final cor1 = _hexColor(grad['hex_cor1'], context.uai.warning);
    final cor2 = _hexColor(grad['hex_cor2'], cor1);
    final ponta1 = _hexColor(grad['hex_ponta1'], cor1);
    final ponta2 = _hexColor(grad['hex_ponta2'], cor2);
    return FutureBuilder<String?>(
      future: SvgService.getSvgContent(context),
      builder: (_, snap) {
        final svg = SvgService.getModifiedSvg(
          svgContent: snap.data,
          cor1: cor1,
          cor2: cor2,
          ponta1: ponta1,
          ponta2: ponta2,
        );
        if (svg == null) {
          return Icon(Icons.military_tech_rounded, color: cor1);
        }
        final sanitized = svg.replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?</style\s*>', caseSensitive: false),
          '',
        );
        return SvgPicture.string(sanitized, fit: BoxFit.contain);
      },
    );
  }

  Widget _buildBotoes() {
    final t = context.uai;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('CANCELAR'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.textPrimary,
              side: BorderSide(color: t.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _confirmar,
            icon: const Icon(Icons.check_rounded, size: 19),
            label: const Text('CONFIRMAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmar() {
    if (!widget.historicoSomenteGraduacao &&
        widget.evento.camisaObrigatoria &&
        _tamanhoCamisaSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selecione o tamanho da camisa'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    if (widget.isBatizado && _graduacaoSelecionadaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selecione a nova graduação'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'tamanhoCamisa': widget.historicoSomenteGraduacao ? null : _tamanhoCamisaSelecionado,
      'modelagemCamisa': _normalizarModelagemCamisa(
        _modelagemCamisaSelecionada,
      ),
      'tipoCamisa': _normalizarTipoCamisa(_tipoCamisaSelecionado),
      'modelagem_camisa': _normalizarModelagemCamisa(
        _modelagemCamisaSelecionada,
      ),
      'tipo_camisa': _normalizarTipoCamisa(_tipoCamisaSelecionado),
      'valorCamisa': widget.historicoSomenteGraduacao ? 0.0 : valorCamisa,
      'valor_camisa': widget.historicoSomenteGraduacao ? 0.0 : valorCamisa,
      'graduacaoId': widget.isBatizado ? _graduacaoSelecionadaId : null,
      'graduacao': widget.isBatizado ? _graduacaoSelecionada : null,
    });
  }
}
