// lib/screens/eventos/camisas_evento_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class CamisasEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const CamisasEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<CamisasEventoScreen> createState() => _CamisasEventoScreenState();
}

class _CamisasEventoScreenState extends State<CamisasEventoScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _tamanhoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();

  final PermissaoService _permissaoService = PermissaoService();

  final List<String> _tamanhosPadrao = [
    'PP',
    'P',
    'M',
    'G',
    'GG',
    'XG',
    'XXG',
    '4A',
    '6A',
    '8A',
    '10A',
    '12A',
    '14A',
  ];

  List<String> _tamanhosDisponiveis = [];
  bool _isLoadingTamanhos = true;

  bool _carregandoPermissoes = true;
  bool _podeGerenciarCamisas = false;
  bool _salvando = false;

  String _filtroStatus = 'TODOS';

  final NumberFormat _realFormat =
  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _carregarTamanhosDoEvento();
    _verificarPermissoes();
  }

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

  Color _onPrimary() => _readableOn(context.uai.primary);
  Color _onSuccess() => _readableOn(context.uai.success);
  Color _onWarning() => _readableOn(context.uai.warning);
  Color _onError() => _readableOn(context.uai.error);
  Color _onInfo() => _readableOn(context.uai.info);
  Color _onAssociacao() => _readableOn(context.uai.associacao);

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  InputDecoration _uaiInputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: accent),
      filled: true,
      fillColor: t.cardAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    );
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final pode = await _permissaoService.temQualquerPermissao([
        'pode_gerenciar_camisas_evento',
        'pode_gerenciar_camisas',
      ]);

      if (!mounted) return;
      setState(() {
        _podeGerenciarCamisas = pode;
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões de camisas: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  Future<void> _carregarTamanhosDoEvento() async {
    try {
      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      if (eventoDoc.exists) {
        final data = eventoDoc.data();
        final tamanhosEvento = data?['tamanhosDisponiveis'] as List?;

        if (tamanhosEvento != null && tamanhosEvento.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _tamanhosDisponiveis = List<String>.from(tamanhosEvento);
            _isLoadingTamanhos = false;
          });
          debugPrint('✅ Tamanhos carregados do evento: $_tamanhosDisponiveis');
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _tamanhosDisponiveis = _tamanhosPadrao;
        _isLoadingTamanhos = false;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar tamanhos: $e');
      if (!mounted) return;
      setState(() {
        _tamanhosDisponiveis = _tamanhosPadrao;
        _isLoadingTamanhos = false;
      });
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

  void _mostrarSemPermissao([
    String mensagem = 'Você não tem permissão para gerenciar camisas.',
  ]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _abrirDialogAdicionar() async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para adicionar camisas.');
      return;
    }

    _nomeController.clear();
    _tamanhoController.clear();
    _valorController.clear();

    await showDialog<void>(
      context: context,
      barrierDismissible: !_salvando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: context.uai.surface,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.uai.cardRadius),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(context.uai.cardRadius),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDialogHeader(dialogContext),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _nomeController,
                                enabled: !_salvando,
                                decoration: _uaiInputDecoration(
                                  label: 'Nome do participante *',
                                  icon: Icons.person_rounded,
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 520;

                                  final tamanhoField = _buildTamanhoSelector(
                                    enabled: !_salvando,
                                    onSelected: () => setDialogState(() {}),
                                  );

                                  final valorField = TextField(
                                    controller: _valorController,
                                    enabled: !_salvando,
                                    decoration: _uaiInputDecoration(
                                      label: 'Valor',
                                      hint: 'R\$ 0,00',
                                      icon: Icons.attach_money_rounded,
                                    ),
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  );

                                  if (narrow) {
                                    return Column(
                                      children: [
                                        tamanhoField,
                                        const SizedBox(height: 12),
                                        valorField,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: tamanhoField),
                                      const SizedBox(width: 12),
                                      Expanded(child: valorField),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildDialogActions(dialogContext, setDialogState),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogHeader(BuildContext dialogContext) {
    final t = context.uai;
    final bg = t.associacao;
    final fg = _readableOn(bg);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(gradient: t.primaryGradient),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: fg.withOpacity(0.16)),
            ),
            child: Icon(Icons.shopping_bag_rounded, color: fg, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adicionar camisa',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.eventoNome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withOpacity(0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _salvando ? null : () => Navigator.pop(dialogContext),
            icon: Icon(Icons.close_rounded, color: fg),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildDialogActions(
      BuildContext dialogContext,
      void Function(void Function()) setDialogState,
      ) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _salvando ? null : () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _salvando
                  ? null
                  : () async {
                final ok = await _adicionarCamisa(fecharAoSalvar: true);
                setDialogState(() {});
                if (ok && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              icon: _salvando
                  ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _onPrimary(),
                ),
              )
                  : const Icon(Icons.add_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'ADICIONAR'),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _adicionarCamisa({bool fecharAoSalvar = false}) async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para adicionar camisas.');
      return false;
    }

    final nome = _nomeController.text.trim();
    final tamanho = _tamanhoController.text.trim();
    final valor = _parseValor(_valorController.text);

    if (nome.isEmpty || tamanho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Preencha nome e tamanho da camisa!'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    setState(() => _salvando = true);

    try {
      await FirebaseFirestore.instance.collection('camisas_eventos').add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'nome_participante': nome,
        'tamanho': tamanho,
        'valor': valor,
        'pago': false,
        'entregue': false,
        'data_registro': FieldValue.serverTimestamp(),
        'data_pagamento': null,
        'data_entrega': null,
      });

      _nomeController.clear();
      _tamanhoController.clear();
      _valorController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Camisa registrada com sucesso!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao adicionar camisa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _marcarPago(String camisaId, bool pago) async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para alterar pagamento.');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
        'pago': pago,
        'data_pagamento': pago ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      debugPrint('Erro ao marcar pagamento: $e');
    }
  }

  Future<void> _marcarEntregue(String camisaId, bool entregue) async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para alterar entrega.');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .doc(camisaId)
          .update({
        'entregue': entregue,
        'data_entrega': entregue ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      debugPrint('Erro ao marcar entrega: $e');
    }
  }

  Future<void> _editarValor(String camisaId, double valorAtual) async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para editar valores.');
      return;
    }

    final TextEditingController valorEditController = TextEditingController(
      text: valorAtual.toStringAsFixed(2).replaceAll('.', ','),
    );

    final novoValor = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Editar valor',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: valorEditController,
          decoration: _uaiInputDecoration(
            label: 'Valor (R\$)',
            icon: Icons.attach_money_rounded,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = _parseValor(valorEditController.text);
              Navigator.pop(dialogContext, valor);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );

    valorEditController.dispose();

    if (novoValor != null && novoValor != valorAtual) {
      try {
        await FirebaseFirestore.instance
            .collection('camisas_eventos')
            .doc(camisaId)
            .update({'valor': novoValor});
      } catch (e) {
        debugPrint('Erro ao editar valor: $e');
      }
    }
  }

  Future<void> _excluirCamisa(String camisaId, String nome) async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para excluir camisas.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Excluir registro',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          nome.trim().isEmpty
              ? 'Remover esta camisa da lista?'
              : 'Remover a camisa de "$nome"?',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('EXCLUIR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _onError(),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('camisas_eventos')
            .doc(camisaId)
            .delete();
      } catch (e) {
        debugPrint('Erro ao excluir camisa: $e');
      }
    }
  }

  Future<void> _selecionarTamanho({VoidCallback? onSelected}) async {
    if (!_podeGerenciarCamisas) {
      _mostrarSemPermissao('Você não tem permissão para escolher tamanho.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.uai.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (context) {
        final t = context.uai;
        final accent = _ensureVisible(t.associacao, t.surface);

        return Container(
          padding: const EdgeInsets.all(16),
          height: 420,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Selecione o tamanho',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoadingTamanhos
                    ? Center(child: CircularProgressIndicator(color: t.primary))
                    : GridView.builder(
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: _tamanhosDisponiveis.length,
                  itemBuilder: (context, index) {
                    final tamanho = _tamanhosDisponiveis[index];
                    final selected = _tamanhoController.text == tamanho;
                    final bg = selected
                        ? Color.alphaBlend(
                      accent.withOpacity(0.18),
                      t.cardAlt,
                    )
                        : t.cardAlt;

                    return InkWell(
                      onTap: () {
                        setState(() => _tamanhoController.text = tamanho);
                        onSelected?.call();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? accent : t.border,
                            width: selected ? 1.3 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            tamanho,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: selected ? accent : t.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTamanhoSelector({
    required bool enabled,
    VoidCallback? onSelected,
  }) {
    final t = context.uai;
    final hasValue = _tamanhoController.text.trim().isNotEmpty;
    final accent = _ensureVisible(t.associacao, t.cardAlt);

    return InkWell(
      onTap: enabled ? () => _selecionarTamanho(onSelected: onSelected) : null,
      borderRadius: BorderRadius.circular(t.inputRadius),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.cardAlt,
          borderRadius: BorderRadius.circular(t.inputRadius),
          border: Border.all(color: hasValue ? accent : t.border),
        ),
        child: Row(
          children: [
            Icon(Icons.shopping_bag_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasValue ? _tamanhoController.text : 'Tamanho *',
                style: TextStyle(
                  color: hasValue ? t.textPrimary : t.textMuted,
                  fontWeight: hasValue ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: accent),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    final t = context.uai;
    final List<Map<String, dynamic>> opcoes = [
      {'label': 'TODOS', 'icon': Icons.list, 'color': t.textMuted},
      {'label': 'PAGO', 'icon': Icons.paid, 'color': t.success},
      {'label': 'PENDENTE', 'icon': Icons.pending, 'color': t.warning},
      {'label': 'ENTREGUE', 'icon': Icons.check_circle, 'color': t.info},
      {'label': 'NÃO ENTREGUE', 'icon': Icons.access_time, 'color': t.error},
    ];

    return Container(
      color: t.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: opcoes.map((opcao) {
            final isSelected = _filtroStatus == opcao['label'];
            final rawColor = opcao['color'] as Color;
            final color = _ensureVisible(rawColor, t.card);
            final bg = isSelected ? color : t.card;
            final fg = isSelected ? _readableOn(color) : t.textSecondary;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                showCheckmark: true,
                checkmarkColor: fg,
                selectedColor: bg,
                backgroundColor: bg,
                side: BorderSide(color: isSelected ? color : t.border),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(opcao['icon'] as IconData, size: 16, color: fg),
                    const SizedBox(width: 4),
                    Text(opcao['label'].toString()),
                  ],
                ),
                onSelected: (_) {
                  setState(() => _filtroStatus = opcao['label'].toString());
                },
                labelStyle: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('camisas_eventos')
        .where('evento_id', isEqualTo: widget.eventoId);

    switch (_filtroStatus) {
      case 'PAGO':
        query = query.where('pago', isEqualTo: true);
        break;
      case 'PENDENTE':
        query = query.where('pago', isEqualTo: false);
        break;
      case 'ENTREGUE':
        query = query.where('entregue', isEqualTo: true);
        break;
      case 'NÃO ENTREGUE':
        query = query.where('entregue', isEqualTo: false);
        break;
    }

    return query.orderBy('data_registro', descending: true);
  }

  Widget _buildPermissaoBanner() {
    final t = context.uai;

    if (_carregandoPermissoes) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conferindo permissão de camisas...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final color = _podeGerenciarCamisas ? t.success : t.warning;
    final visible = _ensureVisible(color, t.card);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(visible.withOpacity(0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: visible.withOpacity(0.18)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(
            _podeGerenciarCamisas
                ? Icons.check_circle_rounded
                : Icons.lock_outline_rounded,
            color: visible,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _podeGerenciarCamisas
                  ? 'Permissão liberada para adicionar, editar, marcar pagamento/entrega e excluir camisas.'
                  : 'Você pode visualizar camisas, mas não pode alterar este módulo.',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCard(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final t = context.uai;
    final contagem = <String, int>{};
    int entregues = 0;
    int pagos = 0;
    double totalValor = 0;

    for (var doc in docs) {
      final data = doc.data();
      final tamanho = data['tamanho'] as String? ?? 'OUTRO';
      final entregue = data['entregue'] as bool? ?? false;
      final pago = data['pago'] as bool? ?? false;
      final valor = (data['valor'] as num?)?.toDouble() ?? 0;

      contagem[tamanho] = (contagem[tamanho] ?? 0) + 1;
      if (entregue) entregues++;
      if (pago) {
        pagos++;
        totalValor += valor;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.associacao.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: t.associacao.withOpacity(0.18)),
                ),
                child: Icon(
                  Icons.analytics_rounded,
                  color: _ensureVisible(t.associacao, t.card),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo das camisas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      'Filtros abaixo do resumo para liberar espaço da lista.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: t.associacao.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: t.associacao.withOpacity(0.16)),
                ),
                child: Text(
                  'Total: ${docs.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _ensureVisible(t.associacao, t.card),
                  ),
                ),
              ),
            ],
          ),
          if (contagem.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: contagem.entries.map((entry) {
                  final accent = _ensureVisible(t.associacao, t.cardAlt);
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accent.withOpacity(0.14)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${entry.value}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: t.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 440;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendLine('Pagos: $pagos', t.success),
                  _legendLine('Pendentes: ${docs.length - pagos}', t.warning),
                ],
              );
              final right = Column(
                crossAxisAlignment:
                narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  _legendLine('Entregues: $entregues', t.info),
                  _legendLine('Não entregues: ${docs.length - entregues}', t.error),
                ],
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [left, const SizedBox(height: 4), right],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [left, right],
              );
            },
          ),
          Divider(height: 18, color: t.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '💰 TOTAL ARRECADADO:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                _realFormat.format(totalValor),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _ensureVisible(t.success, t.card),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendLine(String label, Color color) {
    final visible = _ensureVisible(color, context.uai.card);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: visible),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: visible,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildCamisaCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final t = context.uai;
    final camisa = doc.data();
    final pago = camisa['pago'] as bool? ?? false;
    final entregue = camisa['entregue'] as bool? ?? false;
    final valor = (camisa['valor'] as num?)?.toDouble() ?? 0;
    final nome = camisa['nome_participante']?.toString() ?? '';
    final tamanho = camisa['tamanho']?.toString() ?? '?';

    Color corCard;
    if (pago && entregue) {
      corCard = t.success;
    } else if (pago && !entregue) {
      corCard = t.info;
    } else if (!pago && entregue) {
      corCard = t.warning;
    } else {
      corCard = t.error;
    }

    final visibleCardColor = _ensureVisible(corCard, t.card);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: t.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        side: BorderSide(color: visibleCardColor.withOpacity(0.36), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        visibleCardColor.withOpacity(0.72),
                        visibleCardColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: visibleCardColor.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      tamanho,
                      style: TextStyle(
                        color: _readableOn(visibleCardColor),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome.isEmpty ? 'Sem nome' : nome,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: t.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _badge(
                            icon: pago ? Icons.paid : Icons.pending,
                            label: pago ? 'Pago' : 'Pendente',
                            color: pago ? t.success : t.warning,
                          ),
                          _badge(
                            icon: entregue ? Icons.check_circle : Icons.access_time,
                            label: entregue ? 'Entregue' : 'Não entregue',
                            color: entregue ? t.info : t.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _realFormat.format(valor),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: visibleCardColor,
                  ),
                ),
              ],
            ),
            if (_podeGerenciarCamisas) ...[
              const SizedBox(height: 9),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 430;
                  final buttons = [
                    _actionButton(
                      icon: Icons.paid,
                      label: pago ? 'PAGO' : 'PAGAR',
                      color: pago ? t.success : t.textMuted,
                      onTap: () => _marcarPago(doc.id, !pago),
                    ),
                    _actionButton(
                      icon: entregue ? Icons.check_circle : Icons.local_shipping,
                      label: entregue ? 'ENTREGUE' : 'ENTREGAR',
                      color: entregue ? t.info : t.textMuted,
                      onTap: () => _marcarEntregue(doc.id, !entregue),
                    ),
                    _actionButton(
                      icon: Icons.edit,
                      label: 'EDITAR',
                      color: t.associacao,
                      onTap: () => _editarValor(doc.id, valor),
                    ),
                    _actionButton(
                      icon: Icons.delete,
                      label: 'EXCLUIR',
                      color: t.error,
                      onTap: () => _excluirCamisa(doc.id, nome),
                    ),
                  ];

                  if (narrow) {
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: buttons
                          .map(
                            (b) => SizedBox(
                          width: (constraints.maxWidth - 6) / 2,
                          child: b,
                        ),
                      )
                          .toList(),
                    );
                  }

                  return Row(
                    children: buttons
                        .map(
                          (b) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: b,
                        ),
                      ),
                    )
                        .toList(),
                  );
                },
              ),
            ],
            if (camisa['data_pagamento'] != null || camisa['data_entrega'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (camisa['data_pagamento'] != null)
                      Text(
                        'Pago: ${_formatarData(camisa['data_pagamento'])}',
                        style: TextStyle(
                          fontSize: 10,
                          color: _ensureVisible(t.success, t.card),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (camisa['data_entrega'] != null)
                      Text(
                        'Entregue: ${_formatarData(camisa['data_entrega'])}',
                        style: TextStyle(
                          fontSize: 10,
                          color: _ensureVisible(t.info, t.card),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(visible.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: visible.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: visible),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: visible,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: visible.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: visible.withOpacity(0.16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: visible),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: visible,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: t.associacao.withOpacity(0.10),
                shape: BoxShape.circle,
                border: Border.all(color: t.associacao.withOpacity(0.14)),
              ),
              child: Icon(
                Icons.shopping_bag,
                size: 60,
                color: _ensureVisible(t.associacao, t.background).withOpacity(0.72),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _filtroStatus == 'TODOS'
                  ? 'Nenhuma camisa registrada'
                  : 'Nenhuma camisa com filtro $_filtroStatus',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _podeGerenciarCamisas
                  ? 'Toque no botão + para adicionar a primeira camisa.'
                  : 'Quando houver camisas, elas aparecerão aqui.',
              style: TextStyle(fontSize: 14, color: t.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatarData(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      if (timestamp is Timestamp) {
        return DateFormat('dd/MM/yyyy').format(timestamp.toDate());
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _resumoStream() {
    return FirebaseFirestore.instance
        .collection('camisas_eventos')
        .where('evento_id', isEqualTo: widget.eventoId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final loading = _isLoadingTamanhos;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Camisas do Evento',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _appBarFg(),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.eventoNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: _appBarFg().withOpacity(0.82),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _verificarPermissoes,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recarregar permissões',
          ),
        ],
      ),
      floatingActionButton: _podeGerenciarCamisas
          ? FloatingActionButton(
        onPressed: _abrirDialogAdicionar,
        backgroundColor: t.primary,
        foregroundColor: _onPrimary(),
        tooltip: 'Adicionar camisa',
        child: const Icon(Icons.add_rounded),
      )
          : null,
      body: loading
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : Column(
        children: [
          if (_carregandoPermissoes || !_podeGerenciarCamisas)
            _buildPermissaoBanner(),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _resumoStream(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              return _buildResumoCard(docs);
            },
          ),
          _buildFiltros(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        'Erro: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.error),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: t.primary),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 92),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    return _buildCamisaCard(docs[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _tamanhoController.dispose();
    _valorController.dispose();
    super.dispose();
  }
}
