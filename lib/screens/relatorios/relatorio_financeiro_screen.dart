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

class RelatorioFinanceiroScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const RelatorioFinanceiroScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<RelatorioFinanceiroScreen> createState() => _RelatorioFinanceiroScreenState();
}

class _RelatorioFinanceiroScreenState extends State<RelatorioFinanceiroScreen> {
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  bool _isLoading = false;

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
    'por_tamanho': <String, int>{},
  };

  // CAMISAS DOS ALUNOS (participações)
  Map<String, dynamic> _camisasParticipacoes = {
    'total': 0,
    'pagas': 0,
    'valor': 0,
    'por_tamanho': <String, int>{},
  };

  // CAMISAS AVULSAS
  Map<String, dynamic> _camisasAvulsas = {
    'total': 0,
    'pagas': 0,
    'valor': 0,
    'por_tamanho': <String, int>{},
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

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    try {
      _resetarVariaveis();

      // 🔥 CARREGAR EM SEQUÊNCIA, NÃO EM PARALELO!
      await _carregarPatrocinios();
      await _carregarParticipacoes();     // 1º Carrega participações
      await _carregarCamisasAvulsas();    // 2º Depois carrega avulsas (já tem _camisasParticipacoes)
      await _carregarGastos();

      setState(() {
        _saldoLiquido = _totalReceitas - _totalGastos;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  // 🔥 NOVO MÉTODO PARA RESETAR VARIÁVEIS
  void _resetarVariaveis() {
    _totalReceitas = 0;
    _totalGastos = 0;
    _totalParticipantes = 0;
    _quitados = 0;
    _inadimplentes = 0;
    _cobertosPorPatrocinio = 0;
    _totalInscricoes = 0;
    _totalCamisas = 0;
    _totalPatrocinios = 0;
    _receitasPorForma = {};
    _gastosPorCategoria = {};
    _usosPatrocinio = [];
  }

  // ==================== PATROCÍNIOS ====================
  Future<void> _carregarPatrocinios() async {
    try {
      final patrocinadoresSnapshot = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      debugPrint('🤝 ===== CARREGANDO PATROCÍNIOS =====');
      debugPrint('🤝 Total de patrocinadores: ${patrocinadoresSnapshot.docs.length}');

      double totalPatrocinios = 0;
      int pagos = 0;
      int pendentes = 0;
      List<Map<String, dynamic>> usos = [];

      for (var patrocinador in patrocinadoresSnapshot.docs) {
        final data = patrocinador.data();
        final status = data['status']?.toString() ?? 'PENDENTE';
        final nomePatrocinador = data['nome'] ?? 'Patrocinador';

        debugPrint('\n📌 Patrocinador: $nomePatrocinador (${patrocinador.id})');
        debugPrint('   - Status: $status');

        double valorPago = (data['valor_pago'] as num?)?.toDouble() ?? 0;

        if (valorPago == 0) {
          final saldoInicial = (data['saldo_inicial'] as num?)?.toDouble() ?? 0;
          final saldoDisponivel = (data['saldo_disponivel'] as num?)?.toDouble() ?? 0;
          valorPago = saldoInicial - saldoDisponivel;
          debugPrint('   - Valor pago calculado: R\$ ${valorPago.toStringAsFixed(2)}');
        }

        debugPrint('   🔍 Buscando usos na subcoleção...');

        final usosSnapshot = await patrocinador.reference
            .collection('usos')
            .orderBy('data', descending: true)
            .get();

        debugPrint('   📊 Usos encontrados: ${usosSnapshot.docs.length}');

        double totalUsos = 0;

        for (var uso in usosSnapshot.docs) {
          final usoData = uso.data();
          final valorUso = (usoData['valor'] as num?)?.toDouble() ?? 0;
          totalUsos += valorUso;

          debugPrint('   - Uso: ${usoData['aluno_nome']} - R\$ $valorUso');

          usos.add({
            'patrocinador': nomePatrocinador,
            'aluno_nome': usoData['aluno_nome'] ?? 'Aluno',
            'valor': valorUso,
            'data': usoData['data'] is Timestamp
                ? (usoData['data'] as Timestamp).toDate()
                : DateTime.now(),
            'observacao': usoData['observacao'] ?? '',
          });
        }

        if (totalUsos > 0) {
          if (valorPago == 0) {
            valorPago = totalUsos;
            debugPrint('   🔥 Usando valor dos usos: R\$ $valorPago');
          }
          totalPatrocinios += valorPago;
          pagos++;
        } else if (valorPago > 0) {
          totalPatrocinios += valorPago;
          pagos++;
        } else if (status == 'PENDENTE' || status == 'ATRASADO') {
          pendentes++;
        }
      }

      setState(() {
        _totalPatrocinios = totalPatrocinios;
        _detalhesPatrocinios = {
          'total_patrocinadores': patrocinadoresSnapshot.docs.length,
          'patrocinios_pagos': pagos,
          'valor_total_patrocinios': totalPatrocinios,
          'patrocinios_pendentes': pendentes,
        };
        _usosPatrocinio = usos;
      });

      debugPrint('\n✅ RESUMO PATROCÍNIOS:');
      debugPrint('   - Total recebido: R\$ ${totalPatrocinios.toStringAsFixed(2)}');
      debugPrint('   - Patrocinadores pagos: $pagos');
      debugPrint('   - Usos encontrados: ${usos.length}');

    } catch (e) {
      debugPrint('❌ Erro ao carregar patrocínios: $e');
    }
  }


// ==================== PARTICIPAÇÕES ====================
  Future<void> _carregarParticipacoes() async {
    try {
      final participacoesSnapshot = await FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      debugPrint('\n📊 ===== CARREGANDO PARTICIPAÇÕES =====');
      debugPrint('📊 Total de participações: ${participacoesSnapshot.docs.length}');

      double totalInscricoes = 0;
      double totalCamisasParticipacoes = 0;
      Map<String, double> porForma = {};
      Map<String, int> camisasPorTamanho = {};
      int totalCamisasParticipacoesCount = 0;
      int camisasPagasParticipacoesCount = 0;

      int quitados = 0;
      int inadimplentes = 0;
      int cobertosPatrocinio = 0;

      // 🔥 Lista de nomes de participantes com patrocínio
      Set<String> participantesComPatrocinio = _usosPatrocinio
          .map((uso) => uso['aluno_nome'] as String)
          .toSet();

      for (var participacao in participacoesSnapshot.docs) {
        final data = participacao.data();
        final totalPago = (data['total_pago'] as num?)?.toDouble() ?? 0;
        final valorInscricao = (data['valor_inscricao'] as num?)?.toDouble() ?? 0;
        final valorCamisa = (data['valor_camisa'] as num?)?.toDouble() ?? 0;
        final totalDevido = valorInscricao + valorCamisa;
        final tamanhoCamisa = data['tamanho_camisa'] as String?;
        final alunoNome = data['aluno_nome'] as String? ?? '';

        bool temPatrocinio = participantesComPatrocinio.contains(alunoNome);

        debugPrint('\n📌 Aluno: $alunoNome');
        debugPrint('   - Total devido: R\$ $totalDevido');
        debugPrint('   - Total pago (agregado): R\$ $totalPago');
        debugPrint('   - Tem patrocínio: $temPatrocinio');

        // 🔥 CLASSIFICAÇÃO DO STATUS (usando o totalPago agregado)
        if (temPatrocinio) {
          cobertosPatrocinio++;
          debugPrint('   ✅ Classificado: COBERTO POR PATROCÍNIO');
        } else if (totalPago >= totalDevido - 1) {
          quitados++;
          debugPrint('   ✅ Classificado: QUITADO');
        } else {
          inadimplentes++;
          debugPrint('   ⚠️ Classificado: INADIMPLENTE');
        }

        // 🔥 CONTABILIZA RECEITAS (usando pagamentos INDIVIDUAIS)
        if (totalPago > 0) {
          final todosPagamentos = await FirebaseFirestore.instance
              .collection('eventos')
              .doc(widget.eventoId)
              .collection('participacoes')
              .doc(participacao.id)
              .collection('pagamentos')
              .where('status', isEqualTo: 'confirmado')
              .get();

          debugPrint('   💳 Pagamentos individuais encontrados: ${todosPagamentos.docs.length}');

          for (var pag in todosPagamentos.docs) {
            final pagData = pag.data();
            final valor = (pagData['valor'] as num?)?.toDouble() ?? 0;
            final forma = pagData['forma_pagamento'] as String? ?? 'OUTROS';

            debugPrint('      - Forma: $forma, Valor: R\$ $valor');

            // 🔥 PULA PATROCÍNIO (JÁ FOI CONTABILIZADO)
            if (forma == 'PATROCÍNIO') {
              debugPrint('        ⏭️ Pulando PATROCÍNIO (já contabilizado)');
              continue;
            }

            // 🔥 SEPARA CAMISA DE INSCRIÇÃO
            else if (valorCamisa > 0 && pagData['observacoes']?.contains('camisa') == true) {
              totalCamisasParticipacoes += valor;
              debugPrint('        ✅ Adicionado às CAMISAS: R\$ $valor');
            } else {
              totalInscricoes += valor;
              debugPrint('        ✅ Adicionado às INSCRIÇÕES: R\$ $valor');
            }

            porForma[forma] = (porForma[forma] ?? 0) + valor;
          }
        }

        // 🔥 CONTABILIZA CAMISAS
        if (tamanhoCamisa != null && tamanhoCamisa.isNotEmpty) {
          totalCamisasParticipacoesCount++;
          camisasPorTamanho[tamanhoCamisa] = (camisasPorTamanho[tamanhoCamisa] ?? 0) + 1;

          // Verifica se a camisa foi paga (considerando que o valor da camisa pode vir de múltiplas fontes)
          if (totalPago >= valorCamisa - 1) {
            camisasPagasParticipacoesCount++;
          }
        }
      }

      // 🔥 CALCULA O TOTAL DE RECEITAS (INSCRIÇÕES + CAMISAS + PATROCÍNIOS)
      double totalReceitasParticipacoes = totalInscricoes + totalCamisasParticipacoes;

      setState(() {
        _totalParticipantes = participacoesSnapshot.docs.length;
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
          'por_tamanho': camisasPorTamanho,
        };

        porForma.forEach((key, value) {
          _receitasPorForma[key] = (_receitasPorForma[key] ?? 0) + value;
        });
      });

      debugPrint('\n✅ RESUMO PARTICIPAÇÕES:');
      debugPrint('   - Quitados: $quitados');
      debugPrint('   - Patrocínio: $cobertosPatrocinio');
      debugPrint('   - Inadimplentes: $inadimplentes');
      debugPrint('   - Inscrições (dinheiro real): R\$ ${totalInscricoes.toStringAsFixed(2)}');
      debugPrint('   - Camisas: R\$ ${totalCamisasParticipacoes.toStringAsFixed(2)}');
      debugPrint('   - TOTAL RECEITAS (sem patrocínio): R\$ ${totalReceitasParticipacoes.toStringAsFixed(2)}');
      debugPrint('   - Patrocínios (já contabilizados): R\$ ${_totalPatrocinios.toStringAsFixed(2)}');
      debugPrint('   - TOTAL GERAL: R\$ ${(totalReceitasParticipacoes + _totalPatrocinios).toStringAsFixed(2)}');

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
      Map<String, int> porTamanho = {};

      for (var camisa in camisasSnapshot.docs) {
        final data = camisa.data();
        final valor = (data['valor'] as num?)?.toDouble() ?? 0;
        final pago = data['pago'] as bool? ?? false;
        final tamanho = data['tamanho']?.toString() ?? 'OUTRO';

        porTamanho[tamanho] = (porTamanho[tamanho] ?? 0) + 1;

        if (pago && valor > 0) {
          totalValor += valor;
          pagas++;
        }
      }

      setState(() {
        // 🔥 CORREÇÃO: USAR SOMA ACUMULADA, NÃO ATRIBUIÇÃO!
        _totalReceitas += totalValor;  // ✅ Soma ao que já existe (R$ 450 + R$ 0 = R$ 450)
        _totalCamisas += totalValor;   // ✅ Soma ao que já existe

        _camisasAvulsas = {
          'total': camisasSnapshot.docs.length,
          'pagas': pagas,
          'valor': totalValor,
          'por_tamanho': porTamanho,
        };

        _detalhesCamisas = {
          'total_camisas': _camisasParticipacoes['total'] + _camisasAvulsas['total'],
          'camisas_pagas': _camisasParticipacoes['pagas'] + _camisasAvulsas['pagas'],
          'valor_total_camisas': _camisasParticipacoes['valor'] + _camisasAvulsas['valor'],
          'por_tamanho': _combinarMapas(
            _camisasParticipacoes['por_tamanho'],
            _camisasAvulsas['por_tamanho'],
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
  Map<String, int> _combinarMapas(Map<String, int> a, Map<String, int> b) {
    final result = Map<String, int>.from(a);
    b.forEach((key, value) {
      result[key] = (result[key] ?? 0) + value;
    });
    return result;
  }

  // ==================== EXPORTAR EXCEL ====================
  Future<void> _exportarExcel() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Relatório Financeiro'];

      sheet.appendRow(['RELATÓRIO FINANCEIRO - ${widget.eventoNome}']);
      sheet.appendRow(['Gerado em: ${_formatter.format(DateTime.now())}']);
      sheet.appendRow([]);

      sheet.appendRow(['📊 RESUMO GERAL']);
      sheet.appendRow(['Receitas Totais:', 'R\$ ${_totalReceitas.toStringAsFixed(2)}']);
      sheet.appendRow(['Gastos Totais:', 'R\$ ${_totalGastos.toStringAsFixed(2)}']);
      sheet.appendRow(['Saldo Líquido:', 'R\$ ${_saldoLiquido.toStringAsFixed(2)}']);
      sheet.appendRow([]);

      sheet.appendRow(['💰 RECEITAS POR TIPO']);
      sheet.appendRow(['Inscrições:', 'R\$ ${_totalInscricoes.toStringAsFixed(2)}']);
      sheet.appendRow(['Camisas:', 'R\$ ${_totalCamisas.toStringAsFixed(2)}']);
      sheet.appendRow(['Patrocínios:', 'R\$ ${_totalPatrocinios.toStringAsFixed(2)}']);
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
      sheet.appendRow(['Valor:', 'R\$ ${_camisasParticipacoes['valor'].toStringAsFixed(2)}']);

      if ((_camisasParticipacoes['por_tamanho'] as Map).isNotEmpty) {
        sheet.appendRow(['Distribuição:']);
        (_camisasParticipacoes['por_tamanho'] as Map<String, int>).forEach((tamanho, qtd) {
          sheet.appendRow(['  $tamanho:', '$qtd']);
        });
      }
      sheet.appendRow([]);

      sheet.appendRow(['👕 CAMISAS AVULSAS']);
      sheet.appendRow(['Total:', '${_camisasAvulsas['total']}']);
      sheet.appendRow(['Pagas:', '${_camisasAvulsas['pagas']}']);
      sheet.appendRow(['Valor:', 'R\$ ${_camisasAvulsas['valor'].toStringAsFixed(2)}']);

      if ((_camisasAvulsas['por_tamanho'] as Map).isNotEmpty) {
        sheet.appendRow(['Distribuição:']);
        (_camisasAvulsas['por_tamanho'] as Map<String, int>).forEach((tamanho, qtd) {
          sheet.appendRow(['  $tamanho:', '$qtd']);
        });
      }
      sheet.appendRow([]);

      sheet.appendRow(['👕 RESUMO TOTAL DE CAMISAS']);
      sheet.appendRow(['Total:', '${_detalhesCamisas['total_camisas']}']);
      sheet.appendRow(['Pagas:', '${_detalhesCamisas['camisas_pagas']}']);
      sheet.appendRow(['Valor total:', 'R\$ ${_detalhesCamisas['valor_total_camisas'].toStringAsFixed(2)}']);

      if ((_detalhesCamisas['por_tamanho'] as Map).isNotEmpty) {
        sheet.appendRow(['Distribuição total:']);
        (_detalhesCamisas['por_tamanho'] as Map<String, int>).forEach((tamanho, qtd) {
          sheet.appendRow(['  $tamanho:', '$qtd']);
        });
      }
      sheet.appendRow([]);

      sheet.appendRow(['🤝 DETALHES DOS PATROCÍNIOS']);
      sheet.appendRow(['Total de patrocinadores:', '${_detalhesPatrocinios['total_patrocinadores']}']);
      sheet.appendRow(['Patrocínios pagos:', '${_detalhesPatrocinios['patrocinios_pagos']}']);
      sheet.appendRow(['Patrocínios pendentes:', '${_detalhesPatrocinios['patrocinios_pendentes']}']);
      sheet.appendRow(['Valor total patrocínios:', 'R\$ ${_detalhesPatrocinios['valor_total_patrocinios'].toStringAsFixed(2)}']);
      sheet.appendRow([]);

      if (_usosPatrocinio.isNotEmpty) {
        sheet.appendRow(['📋 ALUNOS BENEFICIADOS POR PATROCÍNIO']);
        sheet.appendRow(['Patrocinador', 'Aluno', 'Valor', 'Data', 'Observação']);
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
          double percentual = _totalReceitas > 0 ? (valor / _totalReceitas * 100) : 0;
          sheet.appendRow([forma, 'R\$ ${valor.toStringAsFixed(2)}', '${percentual.toStringAsFixed(1)}%']);
        });
        sheet.appendRow([]);
      }

      if (_gastosPorCategoria.isNotEmpty) {
        sheet.appendRow(['💸 GASTOS POR CATEGORIA']);
        _gastosPorCategoria.forEach((categoria, valor) {
          double percentual = _totalGastos > 0 ? (valor / _totalGastos * 100) : 0;
          sheet.appendRow([categoria, 'R\$ ${valor.toStringAsFixed(2)}', '${percentual.toStringAsFixed(1)}%']);
        });
        sheet.appendRow([]);
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/relatorio_financeiro_${widget.eventoId}.xlsx');
      await file.writeAsBytes(excel.encode()!);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Relatório Financeiro - ${widget.eventoNome}',
      );

    } catch (e) {
      debugPrint('❌ Erro ao exportar Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '📊 Relatório Financeiro',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportarExcel,
            tooltip: 'Exportar Excel',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _carregarDados,
        color: Colors.green.shade900,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== CARDS DE RESUMO =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
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
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildResumoCard(
                            'Gastos',
                            _totalGastos,
                            Icons.trending_down,
                            Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _saldoLiquido >= 0
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                            _saldoLiquido >= 0
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: material.Border.all(
                          color: _saldoLiquido >= 0
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _saldoLiquido >= 0
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color: _saldoLiquido >= 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              const Text(
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
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ===== RECEITAS POR TIPO =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '💰 RECEITAS POR TIPO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildReceitaTipoRow(
                      'Inscrições',
                      _totalInscricoes,
                      Icons.receipt,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildReceitaTipoRow(
                      'Camisas',
                      _totalCamisas,
                      Icons.shopping_bag,
                      Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    _buildReceitaTipoRow(
                      'Patrocínios',
                      _totalPatrocinios,
                      Icons.volunteer_activism,
                      Colors.purple,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ===== GRÁFICO DE PIZZA =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🥧 RECEITAS VS GASTOS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 220,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              value: _totalReceitas,
                              title: 'Receitas\n${_formatarMoeda(_totalReceitas)}',
                              color: Colors.green,
                              radius: 80,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: _totalGastos,
                              title: 'Gastos\n${_formatarMoeda(_totalGastos)}',
                              color: Colors.red,
                              radius: 80,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          startDegreeOffset: 180,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendaItem('Receitas', Colors.green),
                        const SizedBox(width: 24),
                        _buildLegendaItem('Gastos', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ===== PARTICIPAÇÕES =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
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
                          '👥 PARTICIPAÇÕES',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Total: $_totalParticipantes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatusCard(
                            'Quitados',
                            _quitados,
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusCard(
                            'Patrocínio',
                            _cobertosPorPatrocinio,
                            Icons.volunteer_activism,
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusCard(
                            'Inadimplentes',
                            _inadimplentes,
                            Icons.warning,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_totalParticipantes > 0)
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: _quitados > 0 ? _quitados : 1,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                              if (_cobertosPorPatrocinio > 0)
                                Expanded(
                                  flex: _cobertosPorPatrocinio,
                                  child: Container(
                                    height: 8,
                                    color: Colors.purple,
                                  ),
                                ),
                              Expanded(
                                flex: _inadimplentes > 0 ? _inadimplentes : 1,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_quitados} quitados',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              Text(
                                '${_cobertosPorPatrocinio} patrocínio',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                              Text(
                                '${_inadimplentes} inadimplentes',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ===== RECEITAS POR FORMA DE PAGAMENTO =====
              if (_receitasPorForma.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💳 RECEITAS POR FORMA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._receitasPorForma.entries.map((entry) {
                        final percentual = (_totalReceitas > 0)
                            ? (entry.value / _totalReceitas * 100)
                            : 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getCorFormaPagamento(entry.key),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  _formatarMoeda(entry.value),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${percentual.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
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

              const SizedBox(height: 16),

              // ===== DETALHES DAS CAMISAS =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '👕 CAMISAS DOS ALUNOS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDetalheItem(
                          'Total',
                          '${_camisasParticipacoes['total']}',
                          Icons.shopping_bag,
                          Colors.blue,
                        ),
                        _buildDetalheItem(
                          'Pagas',
                          '${_camisasParticipacoes['pagas']}',
                          Icons.paid,
                          Colors.green,
                        ),
                        _buildDetalheItem(
                          'Valor',
                          _formatarMoeda(_camisasParticipacoes['valor']),
                          Icons.attach_money,
                          Colors.orange,
                        ),
                      ],
                    ),
                    if ((_camisasParticipacoes['por_tamanho'] as Map).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Distribuição:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_camisasParticipacoes['por_tamanho'] as Map<String, int>).entries.map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
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

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '👕 CAMISAS AVULSAS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDetalheItem(
                          'Total',
                          '${_camisasAvulsas['total']}',
                          Icons.shopping_bag,
                          Colors.orange,
                        ),
                        _buildDetalheItem(
                          'Pagas',
                          '${_camisasAvulsas['pagas']}',
                          Icons.paid,
                          Colors.green,
                        ),
                        _buildDetalheItem(
                          'Valor',
                          _formatarMoeda(_camisasAvulsas['valor']),
                          Icons.attach_money,
                          Colors.orange,
                        ),
                      ],
                    ),
                    if ((_camisasAvulsas['por_tamanho'] as Map).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Distribuição:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_camisasAvulsas['por_tamanho'] as Map<String, int>).entries.map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
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

              const SizedBox(height: 16),

              // ===== RESUMO TOTAL DE CAMISAS =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '👕 RESUMO TOTAL DE CAMISAS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDetalheItem(
                          'Total',
                          '${_detalhesCamisas['total_camisas']}',
                          Icons.shopping_bag,
                          Colors.purple,
                        ),
                        _buildDetalheItem(
                          'Pagas',
                          '${_detalhesCamisas['camisas_pagas']}',
                          Icons.paid,
                          Colors.green,
                        ),
                        _buildDetalheItem(
                          'Valor',
                          _formatarMoeda(_detalhesCamisas['valor_total_camisas']),
                          Icons.attach_money,
                          Colors.orange,
                        ),
                      ],
                    ),
                    if ((_detalhesCamisas['por_tamanho'] as Map).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Distribuição total:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_detalhesCamisas['por_tamanho'] as Map<String, int>).entries.map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    color: Colors.purple.shade700,
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

              const SizedBox(height: 16),

              // ===== DETALHES DOS PATROCÍNIOS =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🤝 PATROCÍNIOS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDetalheItem(
                          'Total',
                          '${_detalhesPatrocinios['total_patrocinadores']}',
                          Icons.people,
                          Colors.purple,
                        ),
                        _buildDetalheItem(
                          'Pagos',
                          '${_detalhesPatrocinios['patrocinios_pagos']}',
                          Icons.check_circle,
                          Colors.green,
                        ),
                        _buildDetalheItem(
                          'Pendentes',
                          '${_detalhesPatrocinios['patrocinios_pendentes']}',
                          Icons.pending,
                          Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total recebido:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _formatarMoeda(_detalhesPatrocinios['valor_total_patrocinios']),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_usosPatrocinio.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        '📋 Alunos beneficiados:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._usosPatrocinio.map((uso) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: material.Border.all(color: Colors.purple.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.volunteer_activism,
                                color: Colors.purple,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    uso['aluno_nome'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Patrocinador: ${uso['patrocinador']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (uso['observacao'].isNotEmpty)
                                    Text(
                                      uso['observacao'],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatarMoeda(uso['valor']),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade900,
                                  ),
                                ),
                                Text(
                                  _formatter.format(uso['data']),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ===== GASTOS POR CATEGORIA =====
              if (_gastosPorCategoria.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💸 GASTOS POR CATEGORIA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._gastosPorCategoria.entries.map((entry) {
                        final percentual = (_totalGastos > 0)
                            ? (entry.value / _totalGastos * 100)
                            : 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.shade400,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  _formatarMoeda(entry.value),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${percentual.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
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

              const SizedBox(height: 16),

              // ===== AVISO DE ATUALIZAÇÃO =====
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: material.Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Os dados são atualizados em tempo real. Puxe para baixo para recarregar.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
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
  }

  // ==================== WIDGETS AUXILIARES ====================

  Widget _buildReceitaTipoRow(String titulo, double valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: cor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            _formatarMoeda(valor),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCard(String titulo, double valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: material.Border.all(
          color: cor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor),
          const SizedBox(height: 4),
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
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheItem(String label, String valor, IconData icon, Color cor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: cor, size: 20),
        ),
        const SizedBox(height: 4),
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
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(String label, int valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: material.Border.all(
          color: cor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 16),
          const SizedBox(height: 2),
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
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
            ),
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
          decoration: BoxDecoration(
            color: cor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  String _formatarMoeda(double valor) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
  }

  Color _getCorFormaPagamento(String forma) {
    switch (forma.toUpperCase()) {
      case 'PIX':
        return Colors.green;
      case 'DINHEIRO':
        return Colors.blue;
      case 'CARTÃO':
      case 'CRÉDITO':
      case 'DÉBITO':
        return Colors.purple;
      case 'PATROCÍNIO':
        return Colors.amber;
      case 'CAMISA AVULSA':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}