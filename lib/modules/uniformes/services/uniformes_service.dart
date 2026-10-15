import 'dart:async';
import '../../../core/session_log/session_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/modules/associacao/services/associacao_financeiro_service.dart';

class UniformesService {
  UniformesService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  late final AssociacaoFinanceiroService _financeiroAssociacao =
      AssociacaoFinanceiroService(firestore: _firestore, auth: _auth);

  User? get currentUser => _auth.currentUser;

  // Telemetria não pode impedir uma operação de uniformes nem duplicar escritas.
  void _audit(String module, String type, String id, String action, String result) {
    unawaited(SessionLogService.instance.recordEntityOperation(
      module: module, entityType: type, entityId: id,
      operation: action, result: result,
    ).catchError((Object _) {}));
  }


  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static const origemEstoque = 'estoque';
  static const origemForaEstoque = 'fora_do_estoque';
  static const origemEncomenda = 'encomenda';

  Map<String, String> _contaRecebimentoPorForma(String? formaPagamento) {
    final forma = (formaPagamento ?? '').trim().toLowerCase();

    if (forma.contains('dinheiro') ||
        forma.contains('espécie') ||
        forma.contains('especie')) {
      return const {
        'id': 'caixa_geral',
        'nome': 'Caixa geral',
      };
    }

    // PIX, transferência e cartão representam valor bancarizado.
    return const {
      'id': 'pix_associacao',
      'nome': 'PIX / Conta da associação',
    };
  }

  Future<bool> _usuarioEhAdmin() async {
    final uid = currentUser?.uid;
    if (uid == null) return false;

    final snap = await _firestore.collection('usuarios').doc(uid).get();
    if (!snap.exists) return false;
    final data = snap.data() ?? const <String, dynamic>{};
    final peso = (data['peso_permissao'] as num?)?.toInt() ?? 0;
    final tipo = (data['tipo'] ?? '').toString().toLowerCase();
    return peso >= 90 ||
        tipo == 'admin' ||
        tipo == 'administrador' ||
        data['admin'] == true ||
        data['administrador'] == true ||
        data['isAdmin'] == true ||
        data['super_admin'] == true ||
        data['superadmin'] == true;
  }

  Future<String> adicionarItemEstoque(
    Map<String, dynamic> dados, {
    String? itemId,
  }) async {
    if (itemId == null) {
      dados.addAll({
        'criado_em': FieldValue.serverTimestamp(),
        'criado_por': currentUser?.uid,
      });
      return (await _firestore.collection('uniformes_estoque').add(dados)).id;
    }

    dados.addAll({
      'ultima_atualizacao': FieldValue.serverTimestamp(),
      'atualizado_por': currentUser?.uid,
    });

    await _firestore
        .collection('uniformes_estoque')
        .doc(itemId)
        .update(dados);

    return itemId;
  }

  Future<void> registrarMovimentacao({
    required String itemId,
    required String itemNome,
    required String tipo,
    required int quantidade,
    required int quantidadeAnterior,
  }) async {
    await _firestore.collection('movimentacoes_estoque').add({
      'item_id': itemId,
      'item_nome': itemNome,
      'tipo': tipo,
      'quantidade': quantidade,
      'quantidade_anterior': quantidadeAnterior,
      'quantidade_nova': tipo == 'entrada'
          ? quantidadeAnterior + quantidade
          : quantidadeAnterior - quantidade,
      'usuario_id': currentUser?.uid,
      'data': FieldValue.serverTimestamp(),
    });
  }

  String _origemItem(Map<String, dynamic> item) {
    final raw = item['origem']?.toString().trim().toLowerCase();

    if (raw == origemEstoque ||
        raw == origemForaEstoque ||
        raw == origemEncomenda) {
      return raw!;
    }

    return item['controla_estoque'] == true
        ? origemEstoque
        : origemForaEstoque;
  }

  Map<String, dynamic> _snapshotItem(Map<String, dynamic> item) {
    final qtd = (item['quantidade'] as num?)?.toInt() ?? 0;
    final unit = (item['preco_unitario'] as num?)?.toDouble() ?? 0;
    final desconto = (item['desconto'] as num?)?.toDouble() ?? 0;
    final origem = _origemItem(item);

    return {
      ...item,
      'produto_id': item['produto_id'] ?? item['item_id'],
      'produto_nome': item['produto_nome'] ?? item['nome'] ?? 'Item',
      'nome': item['nome'] ?? item['produto_nome'] ?? 'Item',
      'categoria': item['categoria'] ?? '',
      'tamanho': item['tamanho'] ?? '',
      'quantidade': qtd,
      'preco_unitario': unit,
      'valor_unitario': unit,
      'desconto': desconto,
      'valor_total': (qtd * unit) - desconto,
      'origem': origem,
      'controla_estoque': origem == origemEstoque,
      'status_entrega': item['status_entrega'] ?? 'aguardando',
    };
  }

  String _statusPagamento(double total, double pago) {
    const eps = 0.005;
    if (pago <= eps) return 'pendente';
    if (pago + eps < total) return 'parcial';
    return 'pago';
  }

  String _statusEntrega(List<Map<String, dynamic>> itens) {
    if (itens.isEmpty) return 'aguardando';

    final statuses = itens
        .map((e) => (e['status_entrega'] ?? 'aguardando').toString())
        .toList();

    if (statuses.every((s) => s == 'entregue')) return 'entregue';
    if (statuses.every((s) => s == 'cancelado')) return 'cancelado';
    if (statuses.any((s) => s == 'entregue')) return 'parcial';
    return 'aguardando';
  }

  Future<String> registrarVenda(
    Map<String, dynamic> dadosVenda, {
    String? formaPagamentoInicial,
  }) async {
    // Um único ponto de registro para os dois motores de venda.
    final id = _isWindowsDesktop
        ? await _registrarVendaWindows(dadosVenda,
            formaPagamentoInicial: formaPagamentoInicial)
        : await _registrarVendaPadrao(dadosVenda,
            formaPagamentoInicial: formaPagamentoInicial);
    _audit('uniformes', 'venda', id, 'criou', 'sucesso');
    return id;
  }

  Future<String> _registrarVendaPadrao(
    Map<String, dynamic> dadosVenda, {
    String? formaPagamentoInicial,
  }) async {
    final vendaRef = _firestore.collection('vendas_uniformes').doc();

    final itensRaw =
        List<Map<String, dynamic>>.from(dadosVenda['itens'] ?? const []);
    final itens = itensRaw.map(_snapshotItem).toList();

    final total = (dadosVenda['valor_total'] as num?)?.toDouble() ??
        itens.fold<double>(
          0,
          (a, b) => a + ((b['valor_total'] as num?)?.toDouble() ?? 0),
        );

    final pagoSolicitado =
        (dadosVenda['valor_pago'] as num?)?.toDouble() ?? 0;
    final pagoInicial = pagoSolicitado.clamp(0, total).toDouble();

    final alunoId = dadosVenda['aluno_id']?.toString().trim() ?? '';
    final alunoNome = dadosVenda['aluno_nome']?.toString().trim() ?? '';
    final pagamentoId =
        pagoInicial > 0 ? 'pg_inicial_${vendaRef.id}' : null;

    await _firestore.runTransaction((tx) async {
      final estoqueSnaps =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};

      for (final item in itens.where((e) => e['origem'] == origemEstoque)) {
        final id = (item['item_id'] ?? item['produto_id'])?.toString() ?? '';
        if (id.isEmpty) {
          throw Exception('Item de estoque inválido.');
        }

        final snap = await tx.get(
          _firestore.collection('uniformes_estoque').doc(id),
        );

        if (!snap.exists) {
          throw Exception('Item de estoque não encontrado.');
        }

        estoqueSnaps[id] = snap;
      }

      for (final item in itens.where((e) => e['origem'] == origemEstoque)) {
        final id = (item['item_id'] ?? item['produto_id']).toString();
        final qtd = (item['quantidade'] as num).toInt();
        final anterior =
            (estoqueSnaps[id]!.data()?['quantidade'] as num?)?.toInt() ?? 0;

        if (qtd <= 0 || anterior < qtd) {
          throw Exception('Estoque insuficiente para ${item['nome']}.');
        }

        tx.update(
          _firestore.collection('uniformes_estoque').doc(id),
          {
            'quantidade': anterior - qtd,
            'ultima_atualizacao': FieldValue.serverTimestamp(),
          },
        );

        tx.set(
          _firestore
              .collection('movimentacoes_estoque')
              .doc('venda_${vendaRef.id}_$id'),
          {
            'item_id': id,
            'item_nome': item['nome'],
            'tipo': 'saida',
            'quantidade': qtd,
            'quantidade_anterior': anterior,
            'quantidade_nova': anterior - qtd,
            'usuario_id': currentUser?.uid,
            'data': FieldValue.serverTimestamp(),
            'origem_tipo': 'venda_uniforme',
            'origem_id': vendaRef.id,
          },
        );
      }

      final pagamentos = <Map<String, dynamic>>[];

      if (pagamentoId != null) {
        pagamentos.add({
          'id': pagamentoId,
          'valor': pagoInicial,
          'forma': formaPagamentoInicial ?? 'Outro',
          'data': DateTime.now().toIso8601String(),
          'usuario_id': currentUser?.uid,
          'status': 'confirmado',
        });

        final contaRecebimento =
            _contaRecebimentoPorForma(formaPagamentoInicial);

        await _financeiroAssociacao.registrarMovimentacaoAutomaticaNaTransacao(
          tx: tx,
          tipo: 'entrada',
          valor: pagoInicial,
          descricao:
              'Venda de uniforme${alunoNome.isEmpty ? '' : ' — $alunoNome'}',
          categoria: 'Uniformes',
          subcategoria: 'Venda',
          origemModulo: 'uniformes_vendas',
          origemId: '${vendaRef.id}::$pagamentoId',
          origemDescricao: 'Venda ${vendaRef.id}',
          formaPagamento: formaPagamentoInicial ?? 'Outro',
          contaId: contaRecebimento['id']!,
          contaNome: contaRecebimento['nome']!,
          alunoId: alunoId.isEmpty ? null : alunoId,
          extras: {
            'venda_id': vendaRef.id,
            'pagamento_id': pagamentoId,
            'origem_tipo': 'venda_uniforme',
          },
        );
      }

      tx.set(vendaRef, {
        ...dadosVenda,
        'id': vendaRef.id,
        'venda_id': vendaRef.id,
        'itens': itens,
        'valor_total': total,
        'subtotal': total,
        'valor_pago': pagoInicial,
        'total_pago': pagoInicial,
        'saldo_aberto': (total - pagoInicial).clamp(0, double.infinity),
        'status_pagamento': _statusPagamento(total, pagoInicial),
        'status_entrega': _statusEntrega(itens),
        'status': 'ativa',
        'destino_financeiro': 'associacao',
        'pagamentos': pagamentos,
        'data_venda': FieldValue.serverTimestamp(),
        'criado_em': FieldValue.serverTimestamp(),
        'criado_por': currentUser?.uid,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': currentUser?.uid,
      });

      if (alunoId.isNotEmpty) {
        tx.set(
          _firestore
              .collection('alunos')
              .doc(alunoId)
              .collection('historico_edicoes')
              .doc('uniforme_venda_${vendaRef.id}'),
          {
            'tipo_edicao': 'uniformes',
            'subtipo_edicao': 'uniforme_venda',
            'origem': 'venda_uniforme',
            'origem_id': vendaRef.id,
            'resumo': 'Compra registrada',
            'descricao_evento': _descricaoItens(
              itens,
              total,
              _statusPagamento(total, pagoInicial),
              _statusEntrega(itens),
            ),
            'pode_reverter': false,
            'revertido': false,
            'criado_em': FieldValue.serverTimestamp(),
            'criado_por_uid': currentUser?.uid,
            'criado_por_nome': currentUser?.displayName ??
                currentUser?.email ??
                'Administração',
          },
        );
        if (_statusEntrega(itens) == 'entregue') {
          tx.set(
            _firestore.collection('alunos').doc(alunoId).collection('historico_edicoes').doc('uniforme_entrega_${vendaRef.id}_geral'),
            {
              'tipo_edicao': 'uniformes',
              'subtipo_edicao': 'uniforme_entrega',
              'origem': 'venda_uniforme',
              'origem_id': vendaRef.id,
              'resumo': 'Uniforme entregue',
              'descricao_evento': 'Uniforme entregue no momento da venda.',
              'pode_reverter': false,
              'revertido': false,
              'criado_em': FieldValue.serverTimestamp(),
              'criado_por_uid': currentUser?.uid,
              'criado_por_nome': currentUser?.displayName ?? currentUser?.email ?? 'Administração',
            },
            SetOptions(merge: true),
          );
        }
      }
    });

    return vendaRef.id;
  }

  /// Caminho conservador para o desktop Windows.
  ///
  /// O log real mostrou que o commit de venda/estoque/histórico concluía e o
  /// processo morria imediatamente antes do financeiro da Associação. Por isso
  /// o fluxo abaixo:
  /// 1) usa leitura pontual + WriteBatch;
  /// 2) grava a venda, estoque e histórico;
  /// 3) dá tempo para o plugin nativo drenar callbacks;
  /// 4) registra o financeiro depois, com idempotência por origemId;
  /// 5) marca no documento se o financeiro sincronizou ou ficou pendente.
  Future<String> _registrarVendaWindows(
    Map<String, dynamic> dadosVenda, {
    String? formaPagamentoInicial,
  }) async {
    final vendaRef = _firestore.collection('vendas_uniformes').doc();

    final itensRaw =
        List<Map<String, dynamic>>.from(dadosVenda['itens'] ?? const []);
    final itens = itensRaw.map(_snapshotItem).toList();

    final total = (dadosVenda['valor_total'] as num?)?.toDouble() ??
        itens.fold<double>(
          0,
          (a, b) => a + ((b['valor_total'] as num?)?.toDouble() ?? 0),
        );

    final pagoSolicitado =
        (dadosVenda['valor_pago'] as num?)?.toDouble() ?? 0;
    final pagoInicial = pagoSolicitado.clamp(0, total).toDouble();

    final alunoId = dadosVenda['aluno_id']?.toString().trim() ?? '';
    final alunoNome = dadosVenda['aluno_nome']?.toString().trim() ?? '';
    final pagamentoId =
        pagoInicial > 0 ? 'pg_inicial_${vendaRef.id}' : null;

    debugPrint('[UNIFORMES_WINDOWS] 01 preparando venda ${vendaRef.id}');

    final estoqueAtual = <String, int>{};

    for (final item in itens.where((e) => e['origem'] == origemEstoque)) {
      final id = (item['item_id'] ?? item['produto_id'])?.toString() ?? '';

      if (id.isEmpty) {
        throw Exception('Item de estoque inválido.');
      }

      final snap =
          await _firestore.collection('uniformes_estoque').doc(id).get();

      if (!snap.exists) {
        throw Exception('Item de estoque não encontrado.');
      }

      estoqueAtual[id] =
          (snap.data()?['quantidade'] as num?)?.toInt() ?? 0;
    }

    debugPrint('[UNIFORMES_WINDOWS] 02 estoque validado');

    final batch = _firestore.batch();

    for (final item in itens.where((e) => e['origem'] == origemEstoque)) {
      final id = (item['item_id'] ?? item['produto_id']).toString();
      final qtd = (item['quantidade'] as num).toInt();
      final anterior = estoqueAtual[id] ?? 0;

      if (qtd <= 0 || anterior < qtd) {
        throw Exception('Estoque insuficiente para ${item['nome']}.');
      }

      batch.update(
        _firestore.collection('uniformes_estoque').doc(id),
        {
          'quantidade': anterior - qtd,
          'ultima_atualizacao': FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        _firestore
            .collection('movimentacoes_estoque')
            .doc('venda_${vendaRef.id}_$id'),
        {
          'item_id': id,
          'item_nome': item['nome'],
          'tipo': 'saida',
          'quantidade': qtd,
          'quantidade_anterior': anterior,
          'quantidade_nova': anterior - qtd,
          'usuario_id': currentUser?.uid,
          'data': FieldValue.serverTimestamp(),
          'origem_tipo': 'venda_uniforme',
          'origem_id': vendaRef.id,
        },
      );
    }

    final pagamentos = <Map<String, dynamic>>[];

    if (pagamentoId != null) {
      pagamentos.add({
        'id': pagamentoId,
        'valor': pagoInicial,
        'forma': formaPagamentoInicial ?? 'Outro',
        'data': DateTime.now().toIso8601String(),
        'usuario_id': currentUser?.uid,
        'status': 'confirmado',
      });
    }

    batch.set(vendaRef, {
      ...dadosVenda,
      'id': vendaRef.id,
      'venda_id': vendaRef.id,
      'itens': itens,
      'valor_total': total,
      'subtotal': total,
      'valor_pago': pagoInicial,
      'total_pago': pagoInicial,
      'saldo_aberto': (total - pagoInicial).clamp(0, double.infinity),
      'status_pagamento': _statusPagamento(total, pagoInicial),
      'status_entrega': _statusEntrega(itens),
      'status': 'ativa',
      'destino_financeiro': 'associacao',
      'pagamentos': pagamentos,
      'data_venda': FieldValue.serverTimestamp(),
      'criado_em': FieldValue.serverTimestamp(),
      'criado_por': currentUser?.uid,
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por': currentUser?.uid,
      'windows_safe_write': true,
      'financeiro_sync_status':
          pagamentoId == null ? 'nao_aplicavel' : 'pendente',
      'financeiro_sync_tentativas': 0,
    });

    if (alunoId.isNotEmpty) {
      batch.set(
        _firestore
            .collection('alunos')
            .doc(alunoId)
            .collection('historico_edicoes')
            .doc('uniforme_venda_${vendaRef.id}'),
        {
          'tipo_edicao': 'uniformes',
          'subtipo_edicao': 'uniforme_venda',
          'origem': 'venda_uniforme',
          'origem_id': vendaRef.id,
          'resumo': 'Compra registrada',
          'descricao_evento': _descricaoItens(
            itens,
            total,
            _statusPagamento(total, pagoInicial),
            _statusEntrega(itens),
          ),
          'pode_reverter': false,
          'revertido': false,
          'criado_em': FieldValue.serverTimestamp(),
          'criado_por_uid': currentUser?.uid,
          'criado_por_nome':
              currentUser?.displayName ??
              currentUser?.email ??
              'Administração',
        },
      );
      if (_statusEntrega(itens) == 'entregue') {
        batch.set(
          _firestore.collection('alunos').doc(alunoId).collection('historico_edicoes').doc('uniforme_entrega_${vendaRef.id}_geral'),
          {
            'tipo_edicao': 'uniformes',
            'subtipo_edicao': 'uniforme_entrega',
            'origem': 'venda_uniforme',
            'origem_id': vendaRef.id,
            'resumo': 'Uniforme entregue',
            'descricao_evento': 'Uniforme entregue no momento da venda.',
            'pode_reverter': false,
            'revertido': false,
            'criado_em': FieldValue.serverTimestamp(),
            'criado_por_uid': currentUser?.uid,
            'criado_por_nome': currentUser?.displayName ?? currentUser?.email ?? 'Administração',
          },
          SetOptions(merge: true),
        );
      }
    }

    debugPrint('[UNIFORMES_WINDOWS] 03 commit do batch');
    await batch.commit();
    debugPrint('[UNIFORMES_WINDOWS] 04 venda/estoque/historico gravados');

    if (pagamentoId != null) {
      // Evita emendar uma nova sequência Firestore exatamente no retorno do
      // commit. No Windows isso era o ponto real imediatamente anterior ao
      // Lost connection to device.
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      try {
        debugPrint('[UNIFORMES_WINDOWS] 05 iniciando financeiro associacao');

        final contaRecebimento =
            _contaRecebimentoPorForma(formaPagamentoInicial);

        await _financeiroAssociacao.registrarMovimentacaoAutomatica(
          tipo: 'entrada',
          valor: pagoInicial,
          descricao:
              'Venda de uniforme${alunoNome.isEmpty ? '' : ' — $alunoNome'}',
          categoria: 'Uniformes',
          subcategoria: 'Venda',
          origemModulo: 'uniformes_vendas',
          origemId: '${vendaRef.id}::$pagamentoId',
          origemDescricao: 'Venda ${vendaRef.id}',
          formaPagamento: formaPagamentoInicial ?? 'Outro',
          contaId: contaRecebimento['id']!,
          contaNome: contaRecebimento['nome']!,
        );

        debugPrint('[UNIFORMES_WINDOWS] 06 financeiro associacao gravado');

        // Atualização leve e isolada; se falhar, não invalida a venda.
        try {
          await vendaRef.update({
            'financeiro_sync_status': 'sincronizado',
            'financeiro_sync_em': FieldValue.serverTimestamp(),
            'financeiro_sync_tentativas': FieldValue.increment(1),
          });
        } catch (e) {
          debugPrint(
            '[UNIFORMES_WINDOWS] aviso: nao foi possivel marcar sync financeiro: $e',
          );
        }
      } catch (e, st) {
        debugPrint('[UNIFORMES_WINDOWS] financeiro ficou pendente: $e');
        debugPrintStack(stackTrace: st);

        try {
          await vendaRef.update({
            'financeiro_sync_status': 'pendente',
            'financeiro_sync_erro': e.toString(),
            'financeiro_sync_tentativas': FieldValue.increment(1),
          });
        } catch (_) {
          // A venda principal já foi concluída; não transformar falha de
          // auditoria em falha da venda.
        }
      }
    }

    debugPrint('[UNIFORMES_WINDOWS] 07 venda concluida ${vendaRef.id}');
    return vendaRef.id;
  }

  static String _descricaoItens(
    List<Map<String, dynamic>> itens,
    double total,
    String pg,
    String entrega,
  ) {
    final linhas = itens
        .map(
          (e) =>
              '${e['nome']}${(e['tamanho']?.toString().isNotEmpty ?? false) ? ' • Tam. ${e['tamanho']}' : ''} • ${e['quantidade']}x',
        )
        .join('\n');

    return '$linhas\n'
        'Valor: R\$ ${total.toStringAsFixed(2)}\n'
        'Pagamento: ${pg.toUpperCase()}\n'
        'Entrega: ${entrega.toUpperCase()}';
  }

  Future<void> registrarPagamentoVenda({
    required String vendaId,
    required double valorPagamento,
    required String formaPagamento,
    Map<String, dynamic>? vendaData,
    String? pagamentoId,
  }) async {
    if (valorPagamento <= 0) {
      throw Exception('Informe um valor maior que zero.');
    }

    final idPagamento =
        pagamentoId ?? 'pg_${DateTime.now().microsecondsSinceEpoch}';
    final vendaRef = _firestore.collection('vendas_uniformes').doc(vendaId);

    if (_isWindowsDesktop) {
      final snap = await vendaRef.get();
      if (!snap.exists) throw Exception('Venda não encontrada.');

      final data = snap.data()!;
      if ((data['status'] ?? 'ativa') == 'cancelada') {
        throw Exception('Venda cancelada não recebe pagamento.');
      }

      final pagamentos =
          List<Map<String, dynamic>>.from(data['pagamentos'] ?? const []);
      if (pagamentos.any((p) => p['id']?.toString() == idPagamento)) return;

      final total = (data['valor_total'] as num?)?.toDouble() ?? 0;
      final pagoAtual = (data['valor_pago'] as num?)?.toDouble() ?? 0;
      if (pagoAtual + valorPagamento > total + 0.005) {
        throw Exception('O pagamento é maior que o saldo em aberto.');
      }

      final novoPago = pagoAtual + valorPagamento;
      pagamentos.add({
        'id': idPagamento,
        'valor': valorPagamento,
        'forma': formaPagamento,
        'data': DateTime.now().toIso8601String(),
        'usuario_id': currentUser?.uid,
        'status': 'confirmado',
      });

      final alunoId = data['aluno_id']?.toString().trim() ?? '';
      final alunoNome = (data['aluno_nome'] ?? 'Venda de uniforme').toString();
      final batch = _firestore.batch();
      batch.update(vendaRef, {
        'valor_pago': novoPago,
        'total_pago': novoPago,
        'saldo_aberto': (total - novoPago).clamp(0, double.infinity),
        'status_pagamento': _statusPagamento(total, novoPago),
        'pagamentos': pagamentos,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': currentUser?.uid,
      });

      if (alunoId.isNotEmpty) {
        batch.set(
          _firestore
              .collection('alunos')
              .doc(alunoId)
              .collection('historico_edicoes')
              .doc('uniforme_pagamento_${vendaId}_$idPagamento'),
          {
            'tipo_edicao': 'uniformes',
            'subtipo_edicao': novoPago + 0.005 < total
                ? 'uniforme_pagamento_parcial'
                : 'uniforme_pagamento',
            'origem': 'venda_uniforme',
            'origem_id': vendaId,
            'resumo': novoPago + 0.005 < total
                ? 'Pagamento parcial confirmado'
                : 'Pagamento confirmado',
            'descricao_evento':
                'R\$ ${valorPagamento.toStringAsFixed(2)} via $formaPagamento\nVenda #$vendaId',
            'pode_reverter': false,
            'revertido': false,
            'criado_em': FieldValue.serverTimestamp(),
            'criado_por_uid': currentUser?.uid,
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final contaRecebimento =
            _contaRecebimentoPorForma(formaPagamento);

        await _financeiroAssociacao.registrarMovimentacaoAutomatica(
          tipo: 'entrada',
          valor: valorPagamento,
          descricao: 'Venda de uniforme — $alunoNome',
          categoria: 'Uniformes',
          subcategoria: 'Venda',
          origemModulo: 'uniformes_vendas',
          origemId: '$vendaId::$idPagamento',
          origemDescricao: 'Venda $vendaId',
          formaPagamento: formaPagamento,
          contaId: contaRecebimento['id']!,
          contaNome: contaRecebimento['nome']!,
          alunoId: alunoId.isEmpty ? null : alunoId,
        );
        await vendaRef.update({
          'financeiro_sync_status': 'sincronizado',
          'financeiro_sync_em': FieldValue.serverTimestamp(),
        });
      } catch (e, st) {
        debugPrint('[UNIFORMES_WINDOWS] financeiro do pagamento pendente: $e');
        debugPrintStack(stackTrace: st);
        try {
          await vendaRef.update({
            'financeiro_sync_status': 'pendente',
            'financeiro_sync_erro': e.toString(),
          });
        } catch (_) {}
      }
      return;
    }

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(vendaRef);

      if (!snap.exists) {
        throw Exception('Venda não encontrada.');
      }

      final data = snap.data()!;

      if ((data['status'] ?? 'ativa') == 'cancelada') {
        throw Exception('Venda cancelada não recebe pagamento.');
      }

      final pagamentos =
          List<Map<String, dynamic>>.from(data['pagamentos'] ?? const []);

      if (pagamentos.any((p) => p['id']?.toString() == idPagamento)) {
        return;
      }

      final total = (data['valor_total'] as num?)?.toDouble() ?? 0;
      final pagoAtual = (data['valor_pago'] as num?)?.toDouble() ?? 0;

      if (pagoAtual + valorPagamento > total + 0.005) {
        throw Exception('O pagamento é maior que o saldo em aberto.');
      }

      final novoPago = pagoAtual + valorPagamento;

      pagamentos.add({
        'id': idPagamento,
        'valor': valorPagamento,
        'forma': formaPagamento,
        'data': DateTime.now().toIso8601String(),
        'usuario_id': currentUser?.uid,
        'status': 'confirmado',
      });

      tx.update(vendaRef, {
        'valor_pago': novoPago,
        'total_pago': novoPago,
        'saldo_aberto': (total - novoPago).clamp(0, double.infinity),
        'status_pagamento': _statusPagamento(total, novoPago),
        'pagamentos': pagamentos,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': currentUser?.uid,
      });

      final alunoId = data['aluno_id']?.toString().trim() ?? '';
      final alunoNome = (data['aluno_nome'] ?? 'Venda de uniforme').toString();

      final contaRecebimento =
          _contaRecebimentoPorForma(formaPagamento);

      await _financeiroAssociacao.registrarMovimentacaoAutomaticaNaTransacao(
        tx: tx,
        tipo: 'entrada',
        valor: valorPagamento,
        descricao: 'Venda de uniforme — $alunoNome',
        categoria: 'Uniformes',
        subcategoria: 'Venda',
        origemModulo: 'uniformes_vendas',
        origemId: '$vendaId::$idPagamento',
        origemDescricao: 'Venda $vendaId',
        formaPagamento: formaPagamento,
        contaId: contaRecebimento['id']!,
        contaNome: contaRecebimento['nome']!,
        alunoId: alunoId.isEmpty ? null : alunoId,
        extras: {
          'venda_id': vendaId,
          'pagamento_id': idPagamento,
          'origem_tipo': 'venda_uniforme',
        },
      );

      if (alunoId.isNotEmpty) {
        tx.set(
          _firestore
              .collection('alunos')
              .doc(alunoId)
              .collection('historico_edicoes')
              .doc('uniforme_pagamento_${vendaId}_$idPagamento'),
          {
            'tipo_edicao': 'uniformes',
            'subtipo_edicao': novoPago + 0.005 < total
                ? 'uniforme_pagamento_parcial'
                : 'uniforme_pagamento',
            'origem': 'venda_uniforme',
            'origem_id': vendaId,
            'resumo': novoPago + 0.005 < total
                ? 'Pagamento parcial confirmado'
                : 'Pagamento confirmado',
            'descricao_evento':
                'R\$ ${valorPagamento.toStringAsFixed(2)} via $formaPagamento\nVenda #$vendaId',
            'pode_reverter': false,
            'revertido': false,
            'criado_em': FieldValue.serverTimestamp(),
            'criado_por_uid': currentUser?.uid,
          },
        );
      }
    });
  }

  Future<void> atualizarVenda({
    required String vendaId,
    required List<Map<String, dynamic>> itens,
    required String observacoes,
  }) async {
    final ref = _firestore.collection('vendas_uniformes').doc(vendaId);
    final snapshots = itens.map(_snapshotItem).toList();
    final novoTotal = snapshots.fold<double>(
      0,
      (a, b) => a + ((b['valor_total'] as num?)?.toDouble() ?? 0),
    );

    if (_isWindowsDesktop) {
      final snap = await ref.get();
      if (!snap.exists) throw Exception('Venda não encontrada.');
      final pago = (snap.data()?['valor_pago'] as num?)?.toDouble() ?? 0;
      if (novoTotal + 0.005 < pago) {
        throw Exception('O total da venda não pode ficar abaixo do valor já pago. Faça um estorno antes.');
      }
      final batch = _firestore.batch();
      batch.update(ref, {
        'itens': snapshots,
        'observacoes': observacoes,
        'valor_total': novoTotal,
        'subtotal': novoTotal,
        'saldo_aberto': (novoTotal - pago).clamp(0, double.infinity),
        'status_pagamento': _statusPagamento(novoTotal, pago),
        'status_entrega': _statusEntrega(snapshots),
        'ultima_edicao': FieldValue.serverTimestamp(),
        'editado_por': currentUser?.uid,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': currentUser?.uid,
      });
      await batch.commit();
      return;
    }

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Venda não encontrada.');
      final pago = (snap.data()?['valor_pago'] as num?)?.toDouble() ?? 0;
      if (novoTotal + 0.005 < pago) {
        throw Exception('O total da venda não pode ficar abaixo do valor já pago. Faça um estorno antes.');
      }
      tx.update(ref, {
        'itens': snapshots,
        'observacoes': observacoes,
        'valor_total': novoTotal,
        'subtotal': novoTotal,
        'saldo_aberto': (novoTotal - pago).clamp(0, double.infinity),
        'status_pagamento': _statusPagamento(novoTotal, pago),
        'status_entrega': _statusEntrega(snapshots),
        'ultima_edicao': FieldValue.serverTimestamp(),
        'editado_por': currentUser?.uid,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': currentUser?.uid,
      });
    });
  }

  Future<void> registrarEntregaItem({
    required String vendaId,
    required int itemIndex,
    required bool entregue,
  }) async {
    final ref = _firestore.collection('vendas_uniformes').doc(vendaId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Venda não encontrada.');

    final data = snap.data()!;
    if ((data['status'] ?? 'ativa') == 'cancelada') {
      throw Exception('Venda cancelada não pode ter a entrega alterada.');
    }

    final itens = List<Map<String, dynamic>>.from(data['itens'] ?? const []);
    if (itemIndex < 0 || itemIndex >= itens.length) throw Exception('Item inválido.');

    itens[itemIndex] = {
      ...itens[itemIndex],
      'status_entrega': entregue ? 'entregue' : 'aguardando',
      'entregue_em': entregue ? DateTime.now().toIso8601String() : null,
      'entregue_por': entregue ? currentUser?.uid : null,
    };

    final geral = _statusEntrega(itens);
    final batch = _firestore.batch();
    batch.update(ref, {
      'itens': itens,
      'status_entrega': geral,
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por': currentUser?.uid,
      if (geral == 'entregue') 'entregue_em': FieldValue.serverTimestamp(),
      if (geral == 'entregue') 'entregue_por': currentUser?.uid,
    });

    final alunoId = data['aluno_id']?.toString().trim() ?? '';
    if (alunoId.isNotEmpty && entregue) {
      batch.set(
        _firestore.collection('alunos').doc(alunoId).collection('historico_edicoes').doc('uniforme_entrega_${vendaId}_$itemIndex'),
        {
          'tipo_edicao': 'uniformes',
          'subtipo_edicao': 'uniforme_entrega',
          'origem': 'venda_uniforme',
          'origem_id': vendaId,
          'resumo': 'Uniforme entregue',
          'descricao_evento': '${itens[itemIndex]['nome']}${(itens[itemIndex]['tamanho']?.toString().isNotEmpty ?? false) ? ' • Tam. ${itens[itemIndex]['tamanho']}' : ''}',
          'pode_reverter': false,
          'revertido': false,
          'criado_em': FieldValue.serverTimestamp(),
          'criado_por_uid': currentUser?.uid,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> atualizarStatusEntregaVenda({
    required String vendaId,
    required String statusEntrega,
  }) async {
    if (statusEntrega != 'aguardando' && statusEntrega != 'entregue') {
      throw Exception('Status de entrega inválido.');
    }

    final ref = _firestore.collection('vendas_uniformes').doc(vendaId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Venda não encontrada.');

    final data = snap.data()!;
    if ((data['status'] ?? 'ativa') == 'cancelada') {
      throw Exception('Venda cancelada não pode ter a entrega alterada.');
    }

    final itens = List<Map<String, dynamic>>.from(data['itens'] ?? const [])
        .map((item) => <String, dynamic>{
              ...item,
              'status_entrega': statusEntrega,
              if (statusEntrega == 'entregue')
                'entregue_em': DateTime.now().toIso8601String(),
              if (statusEntrega == 'entregue') 'entregue_por': currentUser?.uid,
              if (statusEntrega == 'aguardando') 'entregue_em': null,
              if (statusEntrega == 'aguardando') 'entregue_por': null,
            })
        .toList();

    final updates = <String, dynamic>{
      'itens': itens,
      'status_entrega': statusEntrega,
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por': currentUser?.uid,
      if (statusEntrega == 'entregue') 'entregue_em': FieldValue.serverTimestamp(),
      if (statusEntrega == 'entregue') 'entregue_por': currentUser?.uid,
      if (statusEntrega == 'aguardando') 'entregue_em': FieldValue.delete(),
      if (statusEntrega == 'aguardando') 'entregue_por': FieldValue.delete(),
    };

    final alunoId = data['aluno_id']?.toString().trim() ?? '';
    final historicoRef = alunoId.isEmpty
        ? null
        : _firestore
            .collection('alunos')
            .doc(alunoId)
            .collection('historico_edicoes')
            .doc('uniforme_entrega_${vendaId}_geral');

    // Usa WriteBatch também no Windows para preservar a proteção do plugin
    // cloud_firestore já aplicada aos fluxos críticos de Uniformes.
    final batch = _firestore.batch();
    batch.update(ref, updates);
    if (historicoRef != null && statusEntrega == 'entregue') {
      batch.set(
        historicoRef,
        {
          'tipo_edicao': 'uniformes',
          'subtipo_edicao': 'uniforme_entrega',
          'origem': 'venda_uniforme',
          'origem_id': vendaId,
          'resumo': 'Uniforme entregue',
          'descricao_evento': 'Entrega da venda #$vendaId confirmada pela administração.',
          'pode_reverter': false,
          'revertido': false,
          'criado_em': FieldValue.serverTimestamp(),
          'criado_por_uid': currentUser?.uid,
          'criado_por_nome': currentUser?.displayName ?? currentUser?.email ?? 'Administração',
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  String? _motivoBloqueioExclusao(Map<String, dynamic> data) {
    if ((data['status'] ?? 'ativa') != 'cancelada') {
      return 'Cancele a venda antes de excluí-la definitivamente.';
    }

    final pagamentos = List<Map<String, dynamic>>.from(data['pagamentos'] ?? const []);
    final valorPago = (data['valor_pago'] as num?)?.toDouble() ?? 0;
    if (pagamentos.isNotEmpty || valorPago > 0.005) {
      return 'Esta venda possui histórico financeiro e deve permanecer para auditoria.';
    }

    final itens = List<Map<String, dynamic>>.from(data['itens'] ?? const []);
    if (itens.any((item) => (item['status_entrega'] ?? '').toString() == 'entregue')) {
      return 'Esta venda possui item entregue e deve permanecer para preservar o histórico do aluno.';
    }

    return null;
  }

  Future<String?> verificarExclusaoDefinitiva(String vendaId) async {
    final snap = await _firestore.collection('vendas_uniformes').doc(vendaId).get();
    if (!snap.exists) return 'Venda não encontrada.';

    // Administrador pode apagar lançamentos de teste/duplicados mesmo quando
    // a venda gerou financeiro ou já estava ativa. O service ainda faz a
    // limpeza completa dos vínculos antes de remover a venda.
    if (await _usuarioEhAdmin()) return null;
    return _motivoBloqueioExclusao(snap.data()!);
  }

  Future<void> excluirVendaDefinitivamente({required String vendaId}) async {
    final vendaRef = _firestore.collection('vendas_uniformes').doc(vendaId);
    final snap = await vendaRef.get();
    if (!snap.exists) throw Exception('Venda não encontrada.');

    final data = snap.data()!;
    final admin = await _usuarioEhAdmin();
    final bloqueio = admin ? null : _motivoBloqueioExclusao(data);
    if (bloqueio != null) throw Exception(bloqueio);

    final itens = List<Map<String, dynamic>>.from(data['itens'] ?? const []);
    final estoqueAtual = <String, int>{};

    for (final item in itens.where((e) => (e['origem'] ?? '') == origemEstoque)) {
      final id = (item['item_id'] ?? item['produto_id'])?.toString() ?? '';
      if (id.isEmpty || estoqueAtual.containsKey(id)) continue;
      final estoqueSnap = await _firestore.collection('uniformes_estoque').doc(id).get();
      if (!estoqueSnap.exists) {
        throw Exception('Não foi possível restaurar o estoque desta venda com segurança.');
      }
      estoqueAtual[id] = (estoqueSnap.data()?['quantidade'] as num?)?.toInt() ?? 0;
    }

    final batch = _firestore.batch();
    final restauradoPorItem = <String, int>{};
    for (final item in itens.where((e) => (e['origem'] ?? '') == origemEstoque)) {
      final id = (item['item_id'] ?? item['produto_id'])?.toString() ?? '';
      if (id.isEmpty) continue;
      final qtd = (item['quantidade'] as num?)?.toInt() ?? 0;
      restauradoPorItem[id] = (restauradoPorItem[id] ?? 0) + qtd;
    }

    for (final entry in restauradoPorItem.entries) {
      batch.update(
        _firestore.collection('uniformes_estoque').doc(entry.key),
        {
          'quantidade': (estoqueAtual[entry.key] ?? 0) + entry.value,
          'ultima_atualizacao': FieldValue.serverTimestamp(),
        },
      );
      batch.delete(
        _firestore.collection('movimentacoes_estoque').doc('venda_${vendaId}_${entry.key}'),
      );
    }

    final alunoId = data['aluno_id']?.toString().trim() ?? '';
    if (alunoId.isNotEmpty) {
      final hist = _firestore.collection('alunos').doc(alunoId).collection('historico_edicoes');
      // Remove todos os eventos derivados desta venda (compra, pagamentos,
      // entrega e cancelamento), inclusive IDs legados que não eram cobertos
      // pela exclusão antiga.
      final historicoSnap = await hist.where('origem_id', isEqualTo: vendaId).get();
      for (final doc in historicoSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(hist.doc('uniforme_venda_$vendaId'));
      batch.delete(hist.doc('uniforme_cancelamento_$vendaId'));
      batch.delete(hist.doc('uniforme_entrega_${vendaId}_geral'));
      for (var i = 0; i < itens.length; i++) {
        batch.delete(hist.doc('uniforme_entrega_${vendaId}_$i'));
      }
    }

    if (admin) {
      final pagamentos = List<Map<String, dynamic>>.from(data['pagamentos'] ?? const []);
      final pagamentoIds = pagamentos
          .map((p) => p['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final refsFinanceiro = await _financeiroAssociacao
          .referenciasMovimentacoesVendaUniformeParaExclusaoAdmin(
        vendaId: vendaId,
        pagamentoIds: pagamentoIds,
      );
      for (final refFinanceiro in refsFinanceiro) {
        batch.delete(refFinanceiro);
      }
    }

    batch.delete(vendaRef);
    await batch.commit();
    _audit('uniformes', 'venda', vendaId, 'excluiu', 'sucesso');
  }

  Future<void> cancelarVenda({
    required String vendaId,
    required String motivo,
  }) async {
    if (motivo.trim().length < 3) {
      throw Exception('Informe o motivo do cancelamento.');
    }

    final ref = _firestore.collection('vendas_uniformes').doc(vendaId);
    final snap = await ref.get();

    if (!snap.exists) {
      throw Exception('Venda não encontrada.');
    }

    final data = snap.data()!;

    if ((data['status'] ?? 'ativa') == 'cancelada') {
      return;
    }

    final pagamentos =
        List<Map<String, dynamic>>.from(data['pagamentos'] ?? const []);

    for (final pg
        in pagamentos.where((p) => (p['status'] ?? 'confirmado') == 'confirmado')) {
      final pgId = pg['id']?.toString() ?? '';

      if (pgId.isNotEmpty) {
        await _financeiroAssociacao.estornarPorOrigem(
          origemModulo: 'uniformes_vendas',
          origemId: '$vendaId::$pgId',
          motivo: 'Cancelamento da venda $vendaId: ${motivo.trim()}',
        );
      }
    }

    final cancelamentoData = <String, dynamic>{
      'status': 'cancelada',
      'status_entrega': 'cancelado',
      'cancelado_em': FieldValue.serverTimestamp(),
      'cancelado_por': currentUser?.uid,
      'motivo_cancelamento': motivo.trim(),
      'atualizado_em': FieldValue.serverTimestamp(),
    };

    final alunoId = data['aluno_id']?.toString().trim() ?? '';

    if (_isWindowsDesktop) {
      // No Windows, evita runTransaction/tx.get neste fluxo crítico.
      // O plugin cloud_firestore já apresentou callbacks nativos fora da
      // platform thread; batch com IDs determinísticos reduz esse caminho.
      debugPrint('[UNIFORMES_WINDOWS] 20 iniciando cancelamento $vendaId');

      final batch = _firestore.batch();
      batch.update(ref, cancelamentoData);

      if (alunoId.isNotEmpty) {
        batch.set(
          _firestore
              .collection('alunos')
              .doc(alunoId)
              .collection('historico_edicoes')
              .doc('uniforme_cancelamento_$vendaId'),
          {
            'tipo_edicao': 'uniformes',
            'subtipo_edicao': 'uniforme_cancelamento',
            'origem': 'venda_uniforme',
            'origem_id': vendaId,
            'resumo': 'Venda cancelada',
            'descricao_evento':
                'Venda #$vendaId\nMotivo: ${motivo.trim()}',
            'pode_reverter': false,
            'revertido': false,
            'criado_em': FieldValue.serverTimestamp(),
            'criado_por_uid': currentUser?.uid,
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      debugPrint('[UNIFORMES_WINDOWS] 21 cancelamento gravado $vendaId');
      return;
    }

    await _firestore.runTransaction((tx) async {
      final atual = await tx.get(ref);

      if (!atual.exists) {
        return;
      }

      final d = atual.data()!;

      tx.update(ref, cancelamentoData);

      final alunoIdAtual = d['aluno_id']?.toString().trim() ?? '';

      if (alunoIdAtual.isNotEmpty) {
        tx.set(
          _firestore
              .collection('alunos')
              .doc(alunoIdAtual)
              .collection('historico_edicoes')
              .doc('uniforme_cancelamento_$vendaId'),
          {
            'tipo_edicao': 'uniformes',
            'subtipo_edicao': 'uniforme_cancelamento',
            'origem': 'venda_uniforme',
            'origem_id': vendaId,
            'resumo': 'Venda cancelada',
            'descricao_evento':
                'Venda #$vendaId\nMotivo: ${motivo.trim()}',
            'pode_reverter': false,
            'revertido': false,
            'criado_em': FieldValue.serverTimestamp(),
            'criado_por_uid': currentUser?.uid,
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<String> criarPedido(Map<String, dynamic> dadosPedido) async {
    final id = (await _firestore.collection('pedidos_uniformes').add(dadosPedido)).id;
    _audit('uniformes', 'pedido', id, 'criou', 'sucesso');
    return id;
  }

  Future<void> atualizarStatusPedido(
    String pedidoId,
    String status,
  ) async {
    final updates = <String, dynamic>{'status': status};

    if (status == 'em_confeccao') {
      updates['data_inicio_confeccao'] = FieldValue.serverTimestamp();
    } else if (status == 'finalizado') {
      updates['data_finalizacao'] = FieldValue.serverTimestamp();
    }

    await _firestore
        .collection('pedidos_uniformes')
        .doc(pedidoId)
        .update(updates);
    _audit('uniformes', 'pedido', pedidoId, 'atualizou', 'sucesso');
  }

  Future<void> registrarPagamentoPedido({
    required String pedidoId,
    required double valorPagamento,
    required String formaPagamento,
    required Map<String, dynamic> pedidoData,
  }) async {
    final novoPago =
        ((pedidoData['valor_pago'] ?? 0) as num).toDouble() + valorPagamento;
    final total = ((pedidoData['valor_total'] ?? 0) as num).toDouble();
    final pagamentoId =
        'pg_${DateTime.now().microsecondsSinceEpoch}';

    await _firestore.collection('pedidos_uniformes').doc(pedidoId).update({
      'valor_pago': novoPago,
      'status_pagamento': novoPago >= total ? 'pago' : 'parcial',
      'pagamentos': FieldValue.arrayUnion([
        {
          'id': pagamentoId,
          'valor': valorPagamento,
          'forma': formaPagamento,
          'data': DateTime.now().toIso8601String(),
          'usuario_id': currentUser?.uid,
        },
      ]),
    });

    // PEDIDO aqui representa a encomenda/compra do ALUNO.
    // Quando o aluno paga, o dinheiro entra no caixa da Associação.
    // O pagamento ao fornecedor é uma despesa separada e deve ser lançado
    // depois no Financeiro com o valor real negociado/efetivamente pago.
    final alunoNome =
        (pedidoData['aluno_nome'] ?? 'Aluno').toString().trim();
    final alunoId = (pedidoData['aluno_id'] ?? '').toString().trim();

    final contaRecebimento =
        _contaRecebimentoPorForma(formaPagamento);

    await _financeiroAssociacao.registrarMovimentacaoAutomatica(
      tipo: 'entrada',
      valor: valorPagamento,
      descricao:
          'Recebimento de pedido de uniforme — $alunoNome',
      categoria: 'Uniformes',
      subcategoria: 'Recebimento de pedido',
      origemModulo: 'uniformes_pedidos',
      origemId: '$pedidoId::$pagamentoId',
      origemDescricao: 'Pedido $pedidoId',
      formaPagamento: formaPagamento,
      contaId: contaRecebimento['id']!,
      contaNome: contaRecebimento['nome']!,
      alunoId: alunoId.isEmpty ? null : alunoId,
      observacoes:
          'Pagamento recebido do aluno. O custo do fornecedor deve ser lançado separadamente como saída.',
    );
  }

  String gerarIdPedido() {
    final now = DateTime.now();

    return 'PED-${DateFormat('yyyyMMdd').format(now)}-'
        '${DateFormat('HHmmss').format(now)}-'
        '${1000 + now.millisecond % 9000}';
  }
}
