import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/graduacoes/services/graduacao_service.dart';

class AdicionarParticipanteModal extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final EventoModel evento;
  final bool isBatizado;

  const AdicionarParticipanteModal({
    Key? key,
    required this.aluno,
    required this.evento,
    required this.isBatizado,
  }) : super(key: key);

  @override
  State<AdicionarParticipanteModal> createState() => _AdicionarParticipanteModalState();
}

class _AdicionarParticipanteModalState extends State<AdicionarParticipanteModal> {
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
  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

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

    valorInscricao = widget.evento.valorInscricao;
    valorCamisa = widget.evento.temCamisa ? (widget.evento.valorCamisa ?? 0) : 0;
    valorTotal = valorInscricao + valorCamisa;

    debugPrint('🎯 Modal aberto para: ${widget.aluno['nome']}');
    debugPrint('🎯 É batizado: ${widget.isBatizado}');
    debugPrint('🎯 Nível atual: ${widget.aluno['nivel_graduacao']}');
    debugPrint('🎯 Graduação atual: ${widget.aluno['graduacao']}');
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
    debugPrint('   - data_nascimento: ${widget.aluno['data_nascimento']} (${widget.aluno['data_nascimento'].runtimeType})');
    debugPrint('   - tipo_publico: ${widget.aluno['tipo_publico']}');
    debugPrint('   - graduacao: ${widget.aluno['graduacao']}');

    // 🔥 PRIORIDADE 1: Calcular pela data de nascimento (MAIS IMPORTANTE!)
    if (widget.aluno['data_nascimento'] != null) {
      debugPrint('📅 data_nascimento encontrado: ${widget.aluno['data_nascimento']}');
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
      debugPrint('⚠️ USANDO FALLBACK - tipo_publico: ${widget.aluno['tipo_publico']}');
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

    debugPrint('❌ Ainda não pode ir para ADULTO (nível $nivelAtual, idade $idade)');
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
      if (widget.aluno['data_nascimento'] != null) {
        final dataNascimento = _converterData(widget.aluno['data_nascimento']);
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
      if (widget.aluno['data_nascimento'] != null) {
        final dataNascimento = _converterData(widget.aluno['data_nascimento']);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.uai.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: 16),

          Text(
            'Adicionar ${widget.aluno['nome']}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.uai.error,
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAlunoInfo(),
                  const SizedBox(height: 16),

                  if (widget.evento.temCamisa) ...[
                    _buildCamisaSection(),
                    const SizedBox(height: 16),
                  ],

                  _buildValoresSection(),
                  const SizedBox(height: 16),

                  if (widget.isBatizado) ...[
                    _buildGraduacaoSection(),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          _buildBotoes(),
        ],
      ),
    );
  }

  Widget _buildAlunoInfo() {
    String graduacaoText = widget.aluno['graduacao'] ?? 'Não possui';
    if (graduacaoText == 'SEM GRADUÇÃO') graduacaoText = 'Não possui';

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.uai.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.uai.error.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: context.uai.error.withOpacity(0.14),
            backgroundImage: widget.aluno['foto'] != null
                ? NetworkImage(widget.aluno['foto'])
                : null,
            child: widget.aluno['foto'] == null
                ? Text(
              widget.aluno['nome'][0].toUpperCase(),
              style: TextStyle(color: context.uai.error),
            )
                : null,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.aluno['nome'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Graduação: $graduacaoText',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.uai.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamisaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '👕 Camisa',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.uai.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonFormField<String>(
            value: _tamanhoCamisaSelecionado,
            decoration: const InputDecoration(
              labelText: 'Selecione o tamanho',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: (widget.evento.tamanhosDisponiveis ?? []).map((tamanho) {
              return DropdownMenuItem(
                value: tamanho,
                child: Text(tamanho),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _tamanhoCamisaSelecionado = value;
              });
            },
            validator: widget.evento.camisaObrigatoria
                ? (value) => value == null ? 'Selecione o tamanho' : null
                : null,
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
          '💰 Valores',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
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
              color: context.uai.info.withOpacity(0.08),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (widget.evento.permiteParcelamento)
                  Text(
                    'Parcelas: até ${widget.evento.maxParcelas}x',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.uai.success,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGraduacaoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎓 Graduação',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

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

            if (snapshot.hasError) {
              return Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Erro ao carregar graduações',
                  style: TextStyle(color: context.uai.primary),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _calcularMensagemSemGraduacao(),
                  style: TextStyle(color: context.uai.warning),
                ),
              );
            }

            final graduacoes = snapshot.data!;
            return _buildDropdownGraduacao(graduacoes);
          },
        ),
      ],
    );
  }

  Widget _buildDropdownGraduacao(List<Map<String, dynamic>> graduacoes) {
    // Agrupa por tipo
    final infantil = graduacoes.where((g) => g['tipo_publico'] == 'INFANTIL').toList();
    final adulto = graduacoes.where((g) => g['tipo_publico'] == 'ADULTO').toList();

    List<DropdownMenuItem<String>> items = [];

    if (infantil.isNotEmpty) {
      items.add(DropdownMenuItem(
        value: null,
        enabled: false,
        child: Padding(
          padding: EdgeInsets.only(top: 4, bottom: 2),
          child: Text('👶 GRADUAÇÕES INFANTIS',
              style: TextStyle(fontWeight: FontWeight.bold, color: context.uai.info, fontSize: 13)),
        ),
      ));
      items.addAll(infantil.map((grad) => _buildMenuItem(grad)));
    }

    if (adulto.isNotEmpty) {
      if (infantil.isNotEmpty) {
        items.add(const DropdownMenuItem(
          enabled: false,
          child: Divider(height: 16),
        ));
      }

      items.add(DropdownMenuItem(
        value: null,
        enabled: false,
        child: Padding(
          padding: EdgeInsets.only(top: 4, bottom: 2),
          child: Text('👨 GRADUAÇÕES ADULTAS',
              style: TextStyle(fontWeight: FontWeight.bold, color: context.uai.associacao, fontSize: 13)),
        ),
      ));
      items.addAll(adulto.map((grad) => _buildMenuItem(grad)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔥 ALTURA FIXA PARA O DROPDOWN
        Container(
          height: 56, // Altura fixa para o campo de seleção
          child: DropdownButtonFormField<String>(
            value: _graduacaoSelecionadaId,
            decoration: const InputDecoration(
              labelText: 'Selecione a nova graduação',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: items,
            onChanged: (String? selectedId) {
              if (selectedId != null) {
                setState(() {
                  _graduacaoSelecionadaId = selectedId;
                  _graduacaoSelecionada = graduacoes.firstWhere(
                        (g) => g['id'] == selectedId,
                    orElse: () => <String, dynamic>{},
                  );
                });
              }
            },
          ),
        ),
        if (_graduacaoSelecionadaId != null)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Nível: ${_graduacaoSelecionada?['nivel_graduacao'] ?? ''}',
              style: TextStyle(
                fontSize: 12,
                color: context.uai.success,
              ),
            ),
          ),
      ],
    );
  }
  DropdownMenuItem<String> _buildMenuItem(Map<String, dynamic> grad) {
    return DropdownMenuItem<String>(
      value: grad['id'],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Row(
          children: [
            // Círculo colorido da graduação
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(int.parse(grad['hex_cor1'].replaceFirst('#', '0xff'))),
                    Color(int.parse(grad['hex_cor2']?.replaceFirst('#', '0xff') ??
                        grad['hex_cor1'].replaceFirst('#', '0xff'))),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8),

            // 🔥 TEXTO EM UMA ÚNICA LINHA (SEM COLUMN)
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    color: context.uai.textPrimary.withOpacity(0.87),
                  ),
                  children: [
                    TextSpan(
                      text: grad['nome_graduacao'],
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    TextSpan(
                      text: ' • Nv ${grad['nivel_graduacao']} • Id ${grad['idade_minima']}+',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.uai.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildBotoes() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: context.uai.error,
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text('CANCELAR'),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _confirmar,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _appBarFg(),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('CONFIRMAR'),
          ),
        ),
      ],
    );
  }

  void _confirmar() {
    if (widget.evento.camisaObrigatoria && _tamanhoCamisaSelecionado == null) {
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
      'tamanhoCamisa': _tamanhoCamisaSelecionado,
      'graduacaoId': _graduacaoSelecionadaId,
      'graduacao': _graduacaoSelecionada,
    });
  }
}
