import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/participacao_model.dart';
import '../../models/pagamento_model.dart';
import '../../services/participacao_service.dart';
import '../../services/permissao_service.dart';
import '../../services/pagamento_service.dart';
import '../../services/graduacao_service.dart';
import '../../widgets/registrar_pagamento_modal.dart';
import '../../widgets/editar_camisa_modal.dart';
import '../../widgets/editar_graduacao_modal.dart';

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

class _DetalheParticipacaoScreenState extends State<DetalheParticipacaoScreen> {
  late ParticipacaoModel _participacao;
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PagamentoService _pagamentoService = PagamentoService();
  final PermissaoService _permissaoService = PermissaoService();
  final GraduacaoService _graduacaoService = GraduacaoService();

  bool _isLoading = false;
  bool _podeFinalizar = false;
  bool _podeEditarCamisa = false;
  bool _podeEditarGraduacao = false;
  bool _podeRegistrarPagamento = false;
  bool _temPatrocinio = false;

  List<PagamentoModel> _pagamentos = [];
  double _totalPago = 0;
  double _saldo = 0;

  // Dados do evento (taxas, camisas, etc)
  Map<String, dynamic>? _dadosEvento;

  // Dados do aluno para cálculo de graduação
  Map<String, dynamic>? _dadosAluno;

  // 🔥 ÚLTIMO NÍVEL INFANTIL
  final int _ultimoNivelInfantil = 8;

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
        debugPrint('🔍 DADOS NO FIRESTORE:');
        debugPrint('   - valorInscricao: ${data['valor_inscricao']}');
        debugPrint('   - valorCamisa: ${data['valor_camisa']}');
        debugPrint('   - total_pago: ${data['total_pago']}');
      }

      // 🔥 1º - Carrega a participação ATUALIZADA do Firestore
      final participacaoAtualizada = await _participacaoService.buscarPorId(widget.participacaoId);

      if (participacaoAtualizada != null) {
        setState(() {
          _participacao = ParticipacaoModel.fromMap(
            widget.participacaoId,
            participacaoAtualizada,
          );
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

  Future<void> _verificarPermissoes() async {
    _podeFinalizar = await _permissaoService.temPermissao('pode_finalizar_participacao') ?? false;
    _podeEditarCamisa = await _permissaoService.temPermissao('pode_editar_participante') ?? false;
    _podeEditarGraduacao = await _permissaoService.temPermissao('pode_editar_graduacao_evento') ?? false;
    _podeRegistrarPagamento = await _permissaoService.temPermissao('pode_registrar_pagamento') ?? false;

    if (mounted) setState(() {});
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

    return _podeFinalizar &&
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

    // 🔥 ATUALIZA O MODEL COM O NOVO TOTAL PAGO
    final novoTotalPago = _participacao.totalPago + pagamento.valor;

    setState(() {
      _participacao = _participacao.copyWith(
        totalPago: novoTotalPago,
      );
      _totalPago = novoTotalPago;
      _saldo = _participacao.valorTotal - novoTotalPago;
    });

    // 🔥 Atualiza o saldo do patrocinador
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
    if (!_podeEditarCamisa) return;

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
    if (!_podeEditarGraduacao) return;

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
        final linkCertificado = await _gerarCertificado();

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

  Future<String> _gerarCertificado() async {
    return 'https://exemplo.com/certificado_${_participacao.alunoId}.pdf';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _participacao.alunoNome,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_podeFinalizarAgora())
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.white),
                onPressed: _isLoading ? null : _finalizarParticipacao,
                tooltip: 'Finalizar participação',
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _carregarDados,
        color: Colors.red.shade900,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === CARD DO ALUNO ===
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade900,
                      Colors.red.shade700,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.shade900.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      backgroundImage: _participacao.alunoFoto != null &&
                          _participacao.alunoFoto!.isNotEmpty
                          ? NetworkImage(_participacao.alunoFoto!)
                          : null,
                      child: _participacao.alunoFoto == null ||
                          _participacao.alunoFoto!.isEmpty
                          ? Text(
                        _participacao.alunoNome[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 32,
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _participacao.alunoNome,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _participacao.corStatus,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _participacao.textoStatus,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // === RESUMO FINANCEIRO ===
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📊 RESUMO FINANCEIRO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            'Total',
                            _formatarMoeda(_participacao.valorTotal),
                            Icons.receipt,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            'Pago',
                            _formatarMoeda(_totalPago),
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            'Saldo',
                            _formatarMoeda(_saldo),
                            Icons.pending,
                            _saldo > 0 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // === PAGAMENTOS ===
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '💰 PAGAMENTOS',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        if (_podeRegistrarPagamento && !_participacao.estaFinalizado && _saldo > 0)
                          ElevatedButton.icon(
                            onPressed: _registrarPagamento,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Novo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(80, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_pagamentos.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.payment, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                'Nenhum pagamento registrado',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._pagamentos.map((p) => _buildPagamentoCard(p)),

                    if (_participacao.parcelas > 0 && _saldo > 0) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Parcelas pendentes:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._buildParcelasPendentes(),
                    ],
                  ],
                ),
              ),

              if (_podeRegistrarPagamento && !_participacao.estaFinalizado && _saldo > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _registrarPagamento,
                    icon: const Icon(Icons.pix),
                    label: Text(
                      'NOVO PAGAMENTO (${_formatarMoeda(_saldo)})',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // === CAMISA ===
              _buildInfoSection(
                icon: Icons.shopping_bag,
                title: 'CAMISA',
                color: Colors.blue,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildInfoRow(
                        'Tamanho',
                        _participacao.tamanhoCamisa ?? 'Não definido',
                        icon: Icons.straighten,
                      ),
                    ),
                    Expanded(
                      child: _buildInfoRow(
                        'Status',
                        _participacao.camisaEntregue ? 'Entregue' : 'Pendente',
                        icon: _participacao.camisaEntregue
                            ? Icons.check_circle
                            : Icons.access_time,
                        iconColor: _participacao.camisaEntregue ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (_podeEditarCamisa)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: _editarCamisa,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // === GRADUAÇÃO ===
              if (_participacao.isBatizado)
                _buildInfoSection(
                  icon: Icons.school,
                  title: 'GRADUAÇÃO',
                  color: Colors.purple,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoRow(
                              'Atual',
                              _participacao.graduacao ?? '—',
                              icon: Icons.circle,
                              iconColor: _getCorGraduacao(_participacao.graduacao),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildInfoRow(
                              'Nova',
                              _participacao.graduacaoNova ?? '—',
                              icon: Icons.circle,
                              iconColor: _getCorGraduacao(_participacao.graduacaoNova),
                              textColor: _participacao.graduacaoNova != null
                                  ? Colors.green
                                  : null,
                            ),
                          ),
                          if (_podeEditarGraduacao && !_participacao.estaFinalizado)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: _editarGraduacao,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // === CERTIFICADO ===
              if (_participacao.linkCertificado != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: InkWell(
                    onTap: () => _abrirLink(_participacao.linkCertificado),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Certificado',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Clique para visualizar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.open_in_new, color: Colors.green.shade700),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // === BOTÃO FINALIZAR ===
              if (_podeFinalizarAgora())
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _finalizarParticipacao,
                    icon: const Icon(Icons.check_circle),
                    label: Text(
                      _participacao.isBatizado
                          ? 'FINALIZAR PARTICIPAÇÃO (atualiza graduação)'
                          : 'FINALIZAR PARTICIPAÇÃO',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              // === AVISO ===
              if (!_participacao.estaFinalizado && !_podeFinalizarAgora())
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⏳ Aguardando data do evento',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            Text(
                              'A finalização estará disponível a partir de ${_formatarData(_participacao.dataEvento)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
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
  }

  Widget _buildInfoCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
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

  Widget _buildPagamentoCard(PagamentoModel pagamento) {
    final cor = pagamento.status == 'confirmado' ? Colors.green : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              pagamento.formaPagamento == 'PIX'
                  ? Icons.pix
                  : pagamento.formaPagamento == 'PATROCÍNIO'
                  ? Icons.volunteer_activism
                  : Icons.payment,
              color: cor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatarData(pagamento.dataPagamento),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            pagamento.status == 'confirmado'
                                ? Icons.check_circle
                                : Icons.access_time,
                            size: 10,
                            color: cor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            pagamento.status == 'confirmado' ? 'Confirmado' : 'Pendente',
                            style: TextStyle(
                              fontSize: 9,
                              color: cor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pagamento.formaPagamento,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Text(
                      _formatarMoeda(pagamento.valor),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                if (pagamento.observacoes != null && pagamento.observacoes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      pagamento.observacoes!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildParcelasPendentes() {
    final widgets = <Widget>[];

    final parcelasPagas = _pagamentos
        .where((p) => p.parcela != null)
        .map((p) => p.parcela!)
        .toSet();

    for (int i = 1; i <= _participacao.parcelas; i++) {
      if (!parcelasPagas.contains(i)) {
        final dataVencimento = _participacao.dataEvento
            .subtract(Duration(days: 30 * (_participacao.parcelas - i)));

        widgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pendente - ${i}ª parcela',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Vencimento: ${_formatarData(dataVencimento)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                // 🔥 SÓ MOSTRA BOTÃO DE PAGAR SE SALDO > 0
                if (_podeRegistrarPagamento && !_participacao.estaFinalizado && _saldo > 0)
                  TextButton(
                    onPressed: _registrarPagamento,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('PAGAR'),
                  ),
              ],
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Future<void> _abrirLink(String? url) async {
    if (url == null || url.isEmpty) return;

    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
    }
  }
}