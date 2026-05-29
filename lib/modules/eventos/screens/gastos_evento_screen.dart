import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';

class GastosEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const GastosEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<GastosEventoScreen> createState() => _GastosEventoScreenState();
}

class _GastosEventoScreenState extends State<GastosEventoScreen> {
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


  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _categoriaController = TextEditingController();

  final PermissaoService _permissaoService = PermissaoService();

  bool _podeGerenciarGastos = false;
  bool _carregandoPermissoes = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _verificarPermissoes();
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final pode = await _permissaoService.temQualquerPermissao([
        'pode_gerenciar_gastos_evento',
        'pode_gerenciar_financeiro',
        'pode_gerenciar_taxas',
      ]);

      if (!mounted) return;
      setState(() {
        _podeGerenciarGastos = pode;
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões de gastos: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  double _parseValor(String value) {
    final normalizado = value
        .trim()
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  void _mostrarSemPermissao([String mensagem = 'Você não tem permissão para gerenciar gastos.']) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _adicionarGasto() async {
    if (!_podeGerenciarGastos) {
      _mostrarSemPermissao();
      return;
    }

    final descricao = _descricaoController.text.trim();
    final categoria = _categoriaController.text.trim();
    final valor = _parseValor(_valorController.text);

    if (descricao.isEmpty || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Informe a descrição e um valor válido.'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _salvando = true);

    try {
      await FirebaseFirestore.instance.collection('gastos_eventos').add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'descricao': descricao,
        'valor': valor,
        'categoria': categoria.isEmpty ? 'Sem categoria' : categoria,
        'data': FieldValue.serverTimestamp(),
        'criado_em': FieldValue.serverTimestamp(),
      });

      _descricaoController.clear();
      _valorController.clear();
      _categoriaController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Gasto adicionado!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao adicionar gasto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar gasto: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluirGasto(String gastoId, String descricao) async {
    if (!_podeGerenciarGastos) {
      _mostrarSemPermissao('Você não tem permissão para excluir gastos.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir gasto'),
        content: Text(
          descricao.trim().isEmpty
              ? 'Deseja remover este gasto?'
              : 'Deseja remover o gasto "$descricao"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.delete_outline_rounded),
            label: Text('EXCLUIR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _appBarFg(),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('gastos_eventos')
          .doc(gastoId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ Gasto excluído!'),
            backgroundColor: context.uai.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao excluir gasto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir gasto: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _gastosStream() {
    return FirebaseFirestore.instance
        .collection('gastos_eventos')
        .where('evento_id', isEqualTo: widget.eventoId)
        .orderBy('data', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          'Gastos - ${widget.eventoNome}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        actions: [
          IconButton(
            onPressed: _verificarPermissoes,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recarregar permissões',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFormularioGasto(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _gastosStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErroState('Erro: ${snapshot.error}');
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: context.uai.primary),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                double total = 0;

                for (final doc in docs) {
                  final data = doc.data();
                  total += (data['valor'] as num?)?.toDouble() ?? 0;
                }

                return Column(
                  children: [
                    _buildTotalCard(total, docs.length),
                    Expanded(
                      child: docs.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final gasto = doc.data();
                          final valor = (gasto['valor'] as num?)?.toDouble() ?? 0;
                          final descricao = gasto['descricao']?.toString() ?? '';
                          final categoria = gasto['categoria']?.toString() ?? 'Sem categoria';

                          return _buildGastoCard(
                            gastoId: doc.id,
                            descricao: descricao,
                            categoria: categoria,
                            valor: valor,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissaoBanner() {
    if (_carregandoPermissoes) {
      return Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(14, 14, 14, 0),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.uai.cardAlt),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.uai.primary,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Conferindo permissão de gastos...',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final color = _podeGerenciarGastos ? context.uai.success : context.uai.warning;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(
            _podeGerenciarGastos
                ? Icons.check_circle_rounded
                : Icons.lock_outline_rounded,
            color: _ensureVisible(color, context.uai.card),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              _podeGerenciarGastos
                  ? 'Permissão liberada para adicionar e excluir gastos.'
                  : 'Você pode visualizar os gastos, mas não pode adicionar ou excluir.',
              style: TextStyle(
                color: _ensureVisible(color, context.uai.card),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioGasto() {
    if (!_podeGerenciarGastos && !_carregandoPermissoes) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.uai.cardAlt),
        boxShadow: [
          BoxShadow(
            color: context.uai.textPrimary.withOpacity(0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: context.uai.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Novo gasto',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          TextField(
            controller: _descricaoController,
            enabled: _podeGerenciarGastos && !_salvando,
            decoration: InputDecoration(
              labelText: 'Descrição do gasto',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: Icon(Icons.description_rounded),
              filled: true,
              fillColor: context.uai.cardAlt,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;

              final valorField = TextField(
                controller: _valorController,
                enabled: _podeGerenciarGastos && !_salvando,
                decoration: InputDecoration(
                  labelText: 'Valor (R\$)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  prefixIcon: Icon(Icons.attach_money_rounded),
                  filled: true,
                  fillColor: context.uai.cardAlt,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              );

              final categoriaField = TextField(
                controller: _categoriaController,
                enabled: _podeGerenciarGastos && !_salvando,
                decoration: InputDecoration(
                  labelText: 'Categoria',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  prefixIcon: Icon(Icons.category_rounded),
                  filled: true,
                  fillColor: context.uai.cardAlt,
                ),
              );

              if (narrow) {
                return Column(
                  children: [
                    valorField,
                    const SizedBox(height: 10),
                    categoriaField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: valorField),
                  const SizedBox(width: 10),
                  Expanded(child: categoriaField),
                ],
              );
            },
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed:
              _podeGerenciarGastos && !_salvando ? _adicionarGasto : null,
              icon: _salvando
                  ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.uai.card,
                ),
              )
                  : Icon(Icons.add_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'ADICIONAR GASTO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.uai.success,
                foregroundColor: _appBarFg(),
                disabledBackgroundColor: context.uai.success.withOpacity(0.24),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(double total, int quantidade) {
    return Container(
      margin: EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.uai.success, context.uai.success],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.success.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(Icons.payments_rounded, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Total de gastos\n$quantidade lançamento(s)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.88),
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _formatarMoeda(total),
            style: TextStyle(
              color: context.uai.card,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGastoCard({
    required String gastoId,
    required String descricao,
    required String categoria,
    required double valor,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: 9),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.uai.cardAlt),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.uai.success.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.receipt_rounded, color: context.uai.success),
        ),
        title: Text(
          descricao.isEmpty ? 'Sem descrição' : descricao,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 3),
          child: Text(
            categoria.isEmpty ? 'Sem categoria' : categoria,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              _formatarMoeda(valor),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: context.uai.success,
              ),
            ),
            if (_podeGerenciarGastos)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: context.uai.error),
                tooltip: 'Excluir gasto',
                onPressed: () => _excluirGasto(gastoId, descricao),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErroState(String mensagem) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Text(
          mensagem,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.uai.error),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: context.uai.border),
            SizedBox(height: 14),
            Text(
              'Nenhum gasto registrado',
              style: TextStyle(
                fontSize: 16,
                color: context.uai.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              _podeGerenciarGastos
                  ? 'Adicione o primeiro gasto usando o formulário acima.'
                  : 'Quando houver gastos, eles aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    _categoriaController.dispose();
    super.dispose();
  }
}

