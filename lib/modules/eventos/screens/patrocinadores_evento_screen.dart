// lib/screens/eventos/patrocinadores_evento_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';

class PatrocinadoresEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const PatrocinadoresEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<PatrocinadoresEventoScreen> createState() =>
      _PatrocinadoresEventoScreenState();
}

class _PatrocinadoresEventoScreenState
    extends State<PatrocinadoresEventoScreen> {
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

  Color _onWarning() => _readableOn(context.uai.warning);
  Color _onSuccess() => _readableOn(context.uai.success);
  Color _onError() => _readableOn(context.uai.error);

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


  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _contatoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  final PermissaoService _permissaoService = PermissaoService();

  File? _imagemSelecionada;
  String? _logoUrl;
  bool _uploading = false;
  bool _salvando = false;

  bool _carregandoPermissoes = true;
  bool _podeGerenciarPatrocinadores = false;

  DateTime? _dataPrevista;
  DateTime? _dataRealizada;

  String _filtroStatus = 'TODOS';

  final NumberFormat _realFormat =
  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _dataPrevista = DateTime.now().add(const Duration(days: 30));
    _verificarPermissoes();
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final pode = await _permissaoService.temQualquerPermissao([
        'pode_gerenciar_patrocinadores_evento',
        'pode_gerenciar_patrocinadores',
      ]);

      if (!mounted) return;
      setState(() {
        _podeGerenciarPatrocinadores = pode;
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões de patrocinadores: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  void _mostrarSemPermissao([
    String mensagem = 'Você não tem permissão para gerenciar patrocinadores.',
  ]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double _parseValor(String value) {
    final normalizado = value
        .trim()
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  Future<void> _selecionarImagem() async {
    if (!_podeGerenciarPatrocinadores) {
      _mostrarSemPermissao('Você não tem permissão para selecionar logo.');
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _imagemSelecionada = File(image.path);
          _logoUrl = null;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImagem() async {
    if (_imagemSelecionada == null) return null;

    setState(() => _uploading = true);

    try {
      final String fileName =
          'patrocinadores/${widget.eventoId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      final UploadTask uploadTask = storageRef.putFile(_imagemSelecionada!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _logoUrl = downloadUrl;
        _uploading = false;
      });

      return downloadUrl;
    } catch (e) {
      debugPrint('Erro no upload: $e');
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no upload: ${e.toString()}'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
  }

  void _removerImagem() {
    setState(() {
      _imagemSelecionada = null;
      _logoUrl = null;
    });
  }

  Future<void> _selecionarDataPrevista(
      BuildContext dialogContext,
      void Function(void Function()) setDialogState,
      ) async {
    final DateTime? picked = await showDatePicker(
      context: dialogContext,
      initialDate: _dataPrevista ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: context.uai.warning),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dataPrevista = picked);
      setDialogState(() {});
    }
  }

  Future<void> _selecionarDataRealizada(
      BuildContext dialogContext,
      void Function(void Function()) setDialogState,
      ) async {
    final DateTime? picked = await showDatePicker(
      context: dialogContext,
      initialDate: _dataRealizada ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: context.uai.success),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dataRealizada = picked);
      setDialogState(() {});
    }
  }

  Future<void> _abrirDialogAdicionar() async {
    if (!_podeGerenciarPatrocinadores) {
      _mostrarSemPermissao(
        'Você não tem permissão para adicionar patrocinadores.',
      );
      return;
    }

    _nomeController.clear();
    _contatoController.clear();
    _valorController.clear();
    _observacoesController.clear();

    setState(() {
      _dataPrevista = DateTime.now().add(const Duration(days: 30));
      _dataRealizada = null;
      _imagemSelecionada = null;
      _logoUrl = null;
      _uploading = false;
      _salvando = false;
    });

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: context.uai.card,
            surfaceTintColor: Colors.transparent,
            insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.86,
                maxWidth: 680,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogHeader(dialogContext),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _nomeController,
                            decoration: _uaiInputDecoration(
                              label: 'Nome do patrocinador *',
                              icon: Icons.business_rounded,
                            ),
                          ),
                          SizedBox(height: 10),
                          TextField(
                            controller: _contatoController,
                            decoration: _uaiInputDecoration(
                              label: 'Contato (WhatsApp)',
                              icon: Icons.phone_rounded,
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 520;

                              final valorField = TextField(
                                controller: _valorController,
                                decoration: _uaiInputDecoration(
                                  label: 'Valor (R\$)',
                                  icon: Icons.attach_money_rounded,
                                  hint: '0,00',
                                ),
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              );

                              final logoField = _buildLogoPicker(setDialogState);

                              if (narrow) {
                                return Column(
                                  children: [
                                    valorField,
                                    const SizedBox(height: 10),
                                    logoField,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: valorField),
                                  const SizedBox(width: 10),
                                  Expanded(child: logoField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 520;

                              final prevista = _buildDateBox(
                                icon: Icons.calendar_today_rounded,
                                label: _dataPrevista != null
                                    ? 'Prev: ${_dateFormat.format(_dataPrevista!)}'
                                    : 'Data prevista',
                                color: context.uai.warning,
                                selected: _dataPrevista != null,
                                onTap: () => _selecionarDataPrevista(
                                  context,
                                  setDialogState,
                                ),
                              );

                              final realizada = _buildDateBox(
                                icon: Icons.check_circle_rounded,
                                label: _dataRealizada != null
                                    ? 'Pago: ${_dateFormat.format(_dataRealizada!)}'
                                    : 'Data pagamento',
                                color: context.uai.success,
                                selected: _dataRealizada != null,
                                onTap: () => _selecionarDataRealizada(
                                  context,
                                  setDialogState,
                                ),
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    prevista,
                                    const SizedBox(height: 10),
                                    realizada,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: prevista),
                                  const SizedBox(width: 10),
                                  Expanded(child: realizada),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: 10),
                          TextField(
                            controller: _observacoesController,
                            decoration: _uaiInputDecoration(
                              label: 'Observações',
                              icon: Icons.note_rounded,
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildDialogActions(dialogContext),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext dialogContext) {
    final onWarning = _onWarning();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.warning,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: onWarning.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: onWarning.withOpacity(0.18)),
            ),
            child: Icon(Icons.handshake_rounded, color: onWarning, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Adicionar patrocinador',
              style: TextStyle(
                color: onWarning,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: onWarning),
            onPressed: _salvando ? null : () => Navigator.pop(dialogContext),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildLogoPicker(void Function(void Function()) setDialogState) {
    if (_uploading) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: context.uai.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.uai.cardAlt),
        ),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.uai.warning,
          ),
        ),
      );
    }

    return InkWell(
      onTap: () async {
        await _selecionarImagem();
        setDialogState(() {});
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _imagemSelecionada != null
              ? context.uai.success.withOpacity(0.08)
              : context.uai.surface,
          border: Border.all(
            color: _imagemSelecionada != null
                ? context.uai.success.withOpacity(0.45)
                : context.uai.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              _imagemSelecionada != null
                  ? Icons.check_circle_rounded
                  : Icons.image_rounded,
              color: _imagemSelecionada != null
                  ? context.uai.success
                  : context.uai.warning,
              size: 20,
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                _imagemSelecionada != null ? 'Logo selecionada' : 'Upload logo',
                style: TextStyle(
                  fontSize: 12,
                  color: _imagemSelecionada != null
                      ? context.uai.success
                      : context.uai.warning,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_imagemSelecionada != null)
              IconButton(
                icon: Icon(Icons.close_rounded, size: 17, color: context.uai.error),
                onPressed: () {
                  _removerImagem();
                  setDialogState(() {});
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBox({
    required IconData icon,
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : context.uai.surface,
          border: Border.all(
            color: selected ? color.withOpacity(0.35) : context.uai.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? color : context.uai.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogActions(BuildContext dialogContext) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _salvando ? null : () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _salvando
                  ? null
                  : () async {
                Navigator.pop(dialogContext);
                await _adicionarPatrocinador();
              },
              icon: _salvando
                  ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _onWarning(),
                ),
              )
                  : Icon(Icons.add_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'ADICIONAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.uai.warning,
                foregroundColor: _onWarning(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _adicionarPatrocinador() async {
    if (!_podeGerenciarPatrocinadores) {
      _mostrarSemPermissao(
        'Você não tem permissão para adicionar patrocinadores.',
      );
      return;
    }

    if (_nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nome do patrocinador é obrigatório!'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _salvando = true);

    String? imagemUrl;
    if (_imagemSelecionada != null) {
      imagemUrl = await _uploadImagem();
      if (imagemUrl == null) {
        if (mounted) setState(() => _salvando = false);
        return;
      }
    }

    final valor = _parseValor(_valorController.text);

    String status = 'PENDENTE';
    if (_dataRealizada != null) {
      status = 'PAGO';
    } else if (_dataPrevista != null && _dataPrevista!.isBefore(DateTime.now())) {
      status = 'ATRASADO';
    }

    try {
      final docRef =
      await FirebaseFirestore.instance.collection('patrocinadores_eventos').add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'nome': _nomeController.text.trim(),
        'contato': _contatoController.text.trim(),
        'valor': valor,
        'valor_pago': _dataRealizada != null ? valor : 0,
        'logo_url': imagemUrl,
        'observacoes': _observacoesController.text.trim(),
        'status': status,
        'data_prevista':
        _dataPrevista != null ? Timestamp.fromDate(_dataPrevista!) : null,
        'data_realizada':
        _dataRealizada != null ? Timestamp.fromDate(_dataRealizada!) : null,
        'data_registro': FieldValue.serverTimestamp(),
        'saldo_inicial': _dataRealizada != null ? valor : 0,
        'saldo_disponivel': _dataRealizada != null ? valor : 0,
      });

      if (_dataRealizada != null && valor > 0) {
        await docRef.collection('pagamentos').add({
          'valor': valor,
          'data': Timestamp.fromDate(_dataRealizada!),
          'observacao': 'Contribuição inicial',
        });
      }

      _nomeController.clear();
      _contatoController.clear();
      _valorController.clear();
      _observacoesController.clear();

      if (!mounted) return;

      setState(() {
        _dataPrevista = DateTime.now().add(const Duration(days: 30));
        _dataRealizada = null;
        _imagemSelecionada = null;
        _logoUrl = null;
        _salvando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'PAGO'
                ? '✅ Patrocinador adicionado com contribuição!'
                : '✅ Patrocinador registrado!',
          ),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Erro ao adicionar patrocinador: $e');
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: ${e.toString()}'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _registrarPagamento(
      String patrocinadorId,
      double valor,
      String nome,
      ) async {
    if (!_podeGerenciarPatrocinadores) {
      _mostrarSemPermissao(
        'Você não tem permissão para registrar contribuição.',
      );
      return;
    }

    final TextEditingController valorController = TextEditingController(
      text: valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    DateTime dataPagamento = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: context.uai.card,
            surfaceTintColor: Colors.transparent,
            title: const Text('Registrar contribuição'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Patrocinador: $nome'),
                const SizedBox(height: 16),
                TextField(
                  controller: valorController,
                  decoration: _uaiInputDecoration(
                    label: 'Valor (R\$)',
                    icon: Icons.attach_money,
                  ),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: dataPagamento,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => dataPagamento = picked);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.uai.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: context.uai.success),
                        SizedBox(width: 8),
                        Text(
                          'Data: ${_dateFormat.format(dataPagamento)}',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('CANCELAR'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.success,
                  foregroundColor: _onSuccess(),
                ),
                child: const Text('REGISTRAR'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    final valorPago = _parseValor(valorController.text);
    if (valorPago <= 0) {
      _mostrarSemPermissao('Informe um valor válido para registrar.');
      return;
    }

    try {
      final patrocinadorRef = FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .doc(patrocinadorId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(patrocinadorRef);
        if (!snapshot.exists) return;

        final data = snapshot.data()!;
        final saldoAtual = (data['saldo_disponivel'] as num?)?.toDouble() ?? 0;
        final saldoInicial = (data['saldo_inicial'] as num?)?.toDouble() ?? 0;
        final valorAtualPago = (data['valor_pago'] as num?)?.toDouble() ?? 0;
        final novoSaldo = saldoAtual + valorPago;

        transaction.update(patrocinadorRef, {
          'valor_pago': valorAtualPago + valorPago,
          'saldo_inicial': saldoInicial + valorPago,
          'saldo_disponivel': novoSaldo,
          'status': 'PAGO',
          'data_realizada': Timestamp.fromDate(dataPagamento),
        });

        transaction.set(
          patrocinadorRef.collection('pagamentos').doc(),
          {
            'valor': valorPago,
            'data': Timestamp.fromDate(dataPagamento),
            'observacao': 'Registro manual',
          },
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Contribuição de ${_realFormat.format(valorPago)} registrada!',
            ),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao registrar pagamento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar contribuição: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _excluirPatrocinador(
      String patrocinadorId,
      String? logoUrl,
      String nome,
      ) async {
    if (!_podeGerenciarPatrocinadores) {
      _mostrarSemPermissao('Você não tem permissão para excluir patrocinadores.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir patrocinador'),
        content: Text(
          nome.trim().isEmpty
              ? 'Remover este patrocinador?'
              : 'Remover "$nome" do evento?',
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
              foregroundColor: _onError(),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (logoUrl != null && logoUrl.isNotEmpty) {
        try {
          final storageRef = FirebaseStorage.instance.refFromURL(logoUrl);
          await storageRef.delete();
        } catch (e) {
          debugPrint('Erro ao deletar imagem: $e');
        }
      }

      await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .doc(patrocinadorId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ Patrocinador removido!'),
            backgroundColor: context.uai.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao excluir patrocinador: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: ${e.toString()}'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _abrirContato(String? contato) async {
    if (contato == null || contato.isEmpty) return;

    try {
      final String numeroLimpo = contato.replaceAll(RegExp(r'[^0-9]'), '');
      final Uri uri = Uri.parse('https://wa.me/55$numeroLimpo');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o contato'),
            backgroundColor: context.uai.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir contato: $e');
    }
  }

  Widget _buildFiltros() {
    final List<Map<String, dynamic>> opcoes = [
      {'label': 'TODOS', 'icon': Icons.list, 'color': context.uai.textMuted},
      {'label': 'PAGO', 'icon': Icons.paid, 'color': context.uai.success},
      {'label': 'PENDENTE', 'icon': Icons.pending, 'color': context.uai.warning},
      {'label': 'ATRASADO', 'icon': Icons.warning, 'color': context.uai.error},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: opcoes.map((opcao) {
          final isSelected = _filtroStatus == opcao['label'];
          final color = opcao['color'] as Color;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    opcao['icon'] as IconData,
                    size: 16,
                    color: isSelected ? _readableOn(color) : _ensureVisible(color, context.uai.background),
                  ),
                  const SizedBox(width: 4),
                  Text(opcao['label'].toString()),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _filtroStatus = opcao['label'].toString());
              },
              selectedColor: color,
              checkmarkColor: _readableOn(color),
              labelStyle: TextStyle(
                color: isSelected ? _readableOn(color) : context.uai.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('patrocinadores_eventos')
        .where('evento_id', isEqualTo: widget.eventoId);

    if (_filtroStatus != 'TODOS') {
      query = query.where('status', isEqualTo: _filtroStatus);
    }

    return query.orderBy('data_registro', descending: true);
  }

  String _formatarData(dynamic timestamp) {
    if (timestamp == null) return '—';
    try {
      if (timestamp is Timestamp) {
        return _dateFormat.format(timestamp.toDate());
      }
      return '—';
    } catch (e) {
      return '—';
    }
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'PAGO':
        return context.uai.success;
      case 'PENDENTE':
        return context.uai.warning;
      case 'ATRASADO':
        return context.uai.error;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _getIconStatus(String status) {
    switch (status) {
      case 'PAGO':
        return Icons.check_circle;
      case 'PENDENTE':
        return Icons.schedule;
      case 'ATRASADO':
        return Icons.warning;
      default:
        return Icons.help;
    }
  }

  List<Widget> _buildBotoesAcao({
    required String? contato,
    required String status,
    required String docId,
    required double valor,
    required String nome,
    required String? logoUrl,
  }) {
    final botoes = <Widget>[];

    if (contato != null && contato.isNotEmpty) {
      botoes.add(
        _actionButton(
          icon: Icons.phone,
          label: 'CONTATO',
          color: context.uai.success,
          onTap: () => _abrirContato(contato),
        ),
      );
    }

    if (_podeGerenciarPatrocinadores && status != 'PAGO') {
      botoes.add(
        _actionButton(
          icon: Icons.paid,
          label: 'REG. PAGTO',
          color: context.uai.success,
          onTap: () => _registrarPagamento(docId, valor, nome),
        ),
      );
    }

    if (_podeGerenciarPatrocinadores) {
      botoes.add(
        _actionButton(
          icon: Icons.delete_outline_rounded,
          label: 'EXCLUIR',
          color: context.uai.error,
          onTap: () => _excluirPatrocinador(docId, logoUrl, nome),
        ),
      );
    }

    return botoes;
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissaoBanner() {
    if (_carregandoPermissoes) {
      return Container(
        margin: EdgeInsets.fromLTRB(16, 14, 16, 0),
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
                color: context.uai.warning,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Conferindo permissão de patrocinadores...',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final color = _podeGerenciarPatrocinadores ? context.uai.success : context.uai.warning;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(
            _podeGerenciarPatrocinadores
                ? Icons.check_circle_rounded
                : Icons.lock_outline_rounded,
            color: _ensureVisible(color, context.uai.card),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              _podeGerenciarPatrocinadores
                  ? 'Permissão liberada para adicionar, registrar pagamento e excluir patrocinadores.'
                  : 'Você pode visualizar patrocinadores, mas não pode alterar este módulo.',
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

  Widget _buildResumoCard({
    required int total,
    required int pagos,
    required int pendentes,
    required int atrasados,
    required double totalPrevisto,
    required double totalPago,
  }) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.warning.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: context.uai.warning.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: context.uai.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resumo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: context.uai.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: context.uai.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Total: $total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.uai.warning,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusIndicator('Pagos', pagos, context.uai.success),
              _buildStatusIndicator('Pendentes', pendentes, context.uai.warning),
              _buildStatusIndicator('Atrasados', atrasados, context.uai.error),
            ],
          ),
          Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildValorResumo('Previsto', totalPrevisto, context.uai.textPrimary),
              _buildValorResumo('Recebido', totalPago, context.uai.success),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValorResumo(String label, double value, Color color) {
    return Column(
      crossAxisAlignment:
      label == 'Recebido' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.uai.textMuted)),
        Text(
          _realFormat.format(value),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: context.uai.warning.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.handshake_rounded,
                  size: 62, color: context.uai.warning.withOpacity(0.24)),
            ),
            SizedBox(height: 16),
            Text(
              _filtroStatus == 'TODOS'
                  ? 'Nenhum patrocinador cadastrado'
                  : 'Nenhum patrocinador com status $_filtroStatus',
              style: TextStyle(
                fontSize: 16,
                color: context.uai.textMuted,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              _podeGerenciarPatrocinadores
                  ? 'Clique no botão + para adicionar.'
                  : 'Quando houver patrocinadores, eles aparecerão aqui.',
              style: TextStyle(
                fontSize: 14,
                color: context.uai.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErroState(Object? error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 50, color: context.uai.error.withOpacity(0.45)),
            SizedBox(height: 12),
            Text(
              'Erro: $error',
              style: TextStyle(color: context.uai.error),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatrocinadorCard(DocumentSnapshot<Map<String, dynamic>> doc) {
    final patrocinador = doc.data() ?? {};

    final nome = patrocinador['nome']?.toString() ?? '';
    final contato = patrocinador['contato']?.toString();
    final logoUrl = patrocinador['logo_url']?.toString();
    final valor = (patrocinador['valor'] as num?)?.toDouble() ?? 0;
    final valorPago = (patrocinador['valor_pago'] as num?)?.toDouble() ?? 0;
    final status = patrocinador['status']?.toString() ?? 'PENDENTE';
    final observacoes = patrocinador['observacoes']?.toString() ?? '';
    final dataPrevista = patrocinador['data_prevista'];
    final dataRealizada = patrocinador['data_realizada'];

    final corStatus = _getCorStatus(status);
    final iconStatus = _getIconStatus(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: corStatus.withOpacity(0.24),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogoBox(logoUrl, corStatus),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nome.isEmpty ? 'Sem nome' : nome,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: corStatus.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(iconStatus, size: 12, color: corStatus),
                                const SizedBox(width: 4),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: corStatus,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 5),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (dataPrevista != null)
                            _miniDateChip(
                              icon: Icons.calendar_today,
                              label: 'Prev: ${_formatarData(dataPrevista)}',
                              color: context.uai.warning,
                            ),
                          if (dataRealizada != null)
                            _miniDateChip(
                              icon: Icons.check_circle,
                              label: 'Pago: ${_formatarData(dataRealizada)}',
                              color: context.uai.success,
                            ),
                        ],
                      ),
                      if (observacoes.isNotEmpty) ...[
                        SizedBox(height: 5),
                        Text(
                          observacoes,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.uai.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 9),
            Container(
              padding: EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: context.uai.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _valueColumn('Previsto', _realFormat.format(valor), null),
                  if (valorPago > 0)
                    _valueColumn(
                      'Recebido',
                      _realFormat.format(valorPago),
                      context.uai.success,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _buildBotoesAcao(
                contato: contato,
                status: status,
                docId: doc.id,
                valor: valor,
                nome: nome,
                logoUrl: logoUrl,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoBox(String? logoUrl, Color corStatus) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: corStatus.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: corStatus.withOpacity(0.3)),
      ),
      child: logoUrl != null && logoUrl.isNotEmpty
          ? ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          logoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(Icons.business, color: corStatus),
            );
          },
        ),
      )
          : Center(child: Icon(Icons.business, color: corStatus)),
    );
  }

  Widget _miniDateChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  Widget _valueColumn(String label, String value, Color? color) {
    return Column(
      crossAxisAlignment:
      label == 'Recebido' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: context.uai.textMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color ?? context.uai.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          '🤝 Patrocinadores - ${widget.eventoNome}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _verificarPermissoes,
            tooltip: 'Recarregar permissões',
          ),
          if (_podeGerenciarPatrocinadores)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: _abrirDialogAdicionar,
              tooltip: 'Adicionar patrocinador',
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErroState(snapshot.error);
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: context.uai.warning),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          double totalPrevisto = 0;
          double totalPago = 0;
          int pagos = 0;
          int pendentes = 0;
          int atrasados = 0;

          for (final doc in docs) {
            final data = doc.data();
            final valor = (data['valor'] as num?)?.toDouble() ?? 0;
            final status = data['status']?.toString() ?? 'PENDENTE';
            final valorPago = (data['valor_pago'] as num?)?.toDouble() ?? 0;

            totalPrevisto += valor;
            totalPago += valorPago;

            switch (status) {
              case 'PAGO':
                pagos++;
                break;
              case 'ATRASADO':
                atrasados++;
                break;
              default:
                pendentes++;
            }
          }

          return Column(
            children: [
              _buildFiltros(),
              _buildResumoCard(
                total: docs.length,
                pagos: pagos,
                pendentes: pendentes,
                atrasados: atrasados,
                totalPrevisto: totalPrevisto,
                totalPago: totalPago,
              ),
              Expanded(
                child: docs.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    return _buildPatrocinadorCard(docs[index]);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _podeGerenciarPatrocinadores
          ? FloatingActionButton(
        onPressed: _abrirDialogAdicionar,
        backgroundColor: context.uai.warning,
        foregroundColor: _onWarning(),
        child: const Icon(Icons.add_rounded),
      )
          : null,
    );
  }

  Widget _buildStatusIndicator(String label, int valor, Color cor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            valor.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.uai.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _contatoController.dispose();
    _valorController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }
}

