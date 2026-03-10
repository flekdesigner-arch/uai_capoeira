// lib/screens/eventos/patrocinadores_evento_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class PatrocinadoresEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const PatrocinadoresEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<PatrocinadoresEventoScreen> createState() => _PatrocinadoresEventoScreenState();
}

class _PatrocinadoresEventoScreenState extends State<PatrocinadoresEventoScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _contatoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  File? _imagemSelecionada;
  String? _logoUrl;
  bool _uploading = false;

  DateTime? _dataPrevista;
  DateTime? _dataRealizada;

  String _filtroStatus = 'TODOS';

  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _dataPrevista = DateTime.now().add(const Duration(days: 30));
  }

  Future<void> _selecionarImagem() async {
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
          const SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImagem() async {
    if (_imagemSelecionada == null) return null;

    setState(() => _uploading = true);

    try {
      final String fileName = 'patrocinadores/${widget.eventoId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
      setState(() => _uploading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no upload: ${e.toString()}'),
            backgroundColor: Colors.red,
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

  Future<void> _selecionarDataPrevista(BuildContext dialogContext) async {
    final DateTime? picked = await showDatePicker(
      context: dialogContext,
      initialDate: _dataPrevista ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.amber,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dataPrevista = picked;
      });
    }
  }

  Future<void> _selecionarDataRealizada(BuildContext dialogContext) async {
    final DateTime? picked = await showDatePicker(
      context: dialogContext,
      initialDate: _dataRealizada ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.green,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dataRealizada = picked;
      });
    }
  }

  Future<void> _abrirDialogAdicionar() async {
    _nomeController.clear();
    _contatoController.clear();
    _valorController.clear();
    _observacoesController.clear();
    setState(() {
      _dataPrevista = DateTime.now().add(const Duration(days: 30));
      _dataRealizada = null;
      _imagemSelecionada = null;
      _logoUrl = null;
    });

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_add, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Adicionar Patrocinador - ${widget.eventoNome}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _nomeController,
                            decoration: const InputDecoration(
                              labelText: 'Nome do Patrocinador *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.business, color: Colors.amber),
                            ),
                          ),
                          const SizedBox(height: 8),

                          TextField(
                            controller: _contatoController,
                            decoration: const InputDecoration(
                              labelText: 'Contato (WhatsApp)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone, color: Colors.amber),
                            ),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _valorController,
                                  decoration: InputDecoration(
                                    labelText: 'Valor (R\$)',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.attach_money, color: Colors.amber),
                                    hintText: '0,00',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),

                              Expanded(
                                child: _uploading
                                    ? Container(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                                      ),
                                    ),
                                  ),
                                )
                                    : InkWell(
                                  onTap: () async {
                                    await _selecionarImagem();
                                    setDialogState(() {});
                                  },
                                  child: Container(
                                    height: 56,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: _imagemSelecionada != null
                                          ? Colors.green.shade50
                                          : Colors.white,
                                      border: Border.all(
                                        color: _imagemSelecionada != null
                                            ? Colors.green.shade400
                                            : Colors.grey.shade400,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _imagemSelecionada != null
                                              ? Icons.check_circle
                                              : Icons.image,
                                          color: _imagemSelecionada != null
                                              ? Colors.green
                                              : Colors.amber,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            _imagemSelecionada != null
                                                ? 'Logo selecionada'
                                                : 'Upload Logo',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _imagemSelecionada != null
                                                  ? Colors.green.shade900
                                                  : Colors.amber.shade900,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_imagemSelecionada != null)
                                          IconButton(
                                            icon: const Icon(Icons.close, size: 16, color: Colors.red),
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
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _selecionarDataPrevista(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today, size: 16, color: Colors.amber),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _dataPrevista != null
                                                ? 'Prev: ${_dateFormat.format(_dataPrevista!)}'
                                                : 'Data prevista',
                                            style: TextStyle(
                                              color: _dataPrevista != null
                                                  ? Colors.amber.shade900
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              Expanded(
                                child: InkWell(
                                  onTap: () => _selecionarDataRealizada(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: _dataRealizada != null
                                          ? Colors.green.shade50
                                          : Colors.white,
                                      border: Border.all(
                                        color: _dataRealizada != null
                                            ? Colors.green.shade400
                                            : Colors.grey.shade400,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 16,
                                          color: _dataRealizada != null ? Colors.green : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _dataRealizada != null
                                                ? 'Pago: ${_dateFormat.format(_dataRealizada!)}'
                                                : 'Data pagamento',
                                            style: TextStyle(
                                              color: _dataRealizada != null
                                                  ? Colors.green.shade900
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          TextField(
                            controller: _observacoesController,
                            decoration: const InputDecoration(
                              labelText: 'Observações',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.note, color: Colors.amber),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCELAR'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _adicionarPatrocinador();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('ADICIONAR'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _adicionarPatrocinador() async {
    if (_nomeController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nome do patrocinador é obrigatório!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    String? imagemUrl;
    if (_imagemSelecionada != null) {
      imagemUrl = await _uploadImagem();
      if (imagemUrl == null) return;
    }

    double valor = 0;
    if (_valorController.text.isNotEmpty) {
      valor = double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0;
    }

    String status = 'PENDENTE';
    if (_dataRealizada != null) {
      status = 'PAGO';
    } else if (_dataPrevista != null && _dataPrevista!.isBefore(DateTime.now())) {
      status = 'ATRASADO';
    }

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .add({
        'evento_id': widget.eventoId,
        'evento_nome': widget.eventoNome,
        'nome': _nomeController.text.trim(),
        'contato': _contatoController.text.trim(),
        'valor': valor,
        'valor_pago': _dataRealizada != null ? valor : 0,
        'logo_url': imagemUrl,
        'observacoes': _observacoesController.text.trim(),
        'status': status,
        'data_prevista': _dataPrevista != null
            ? Timestamp.fromDate(_dataPrevista!)
            : null,
        'data_realizada': _dataRealizada != null
            ? Timestamp.fromDate(_dataRealizada!)
            : null,
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

      setState(() {
        _dataPrevista = DateTime.now().add(const Duration(days: 30));
        _dataRealizada = null;
        _imagemSelecionada = null;
        _logoUrl = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _dataRealizada != null
                  ? '✅ Patrocinador adicionado com contribuição!'
                  : '✅ Patrocinador registrado!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao adicionar patrocinador: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _registrarPagamento(String patrocinadorId, double valor, String nome) async {
    final TextEditingController valorController = TextEditingController(
      text: valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    DateTime dataPagamento = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Registrar Contribuição'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Patrocinador: $nome'),
                const SizedBox(height: 16),
                TextField(
                  controller: valorController,
                  decoration: const InputDecoration(
                    labelText: 'Valor (R\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  keyboardType: TextInputType.number,
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
                      setDialogState(() {
                        dataPagamento = picked;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Data: ${_dateFormat.format(dataPagamento)}',
                          style: const TextStyle(fontSize: 16),
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
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('REGISTRAR'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final valorPago = double.tryParse(
          valorController.text.replaceAll(',', '.')
      ) ?? valor;

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
              content: Text('✅ Contribuição de ${_realFormat.format(valorPago)} registrada!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Erro ao registrar pagamento: $e');
      }
    }
  }

  Future<void> _excluirPatrocinador(String patrocinadorId, String? logoUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Patrocinador'),
        content: const Text('Remover este patrocinador?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
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
            const SnackBar(
              content: Text('Patrocinador removido!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Erro ao excluir patrocinador: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
      }
    } catch (e) {
      debugPrint('Erro ao abrir contato: $e');
    }
  }

  // VERSÃO SIMPLIFICADA DOS FILTROS
  Widget _buildFiltros() {
    final List<Map<String, dynamic>> opcoes = [
      {'label': 'TODOS', 'icon': Icons.list, 'color': Colors.grey},
      {'label': 'PAGO', 'icon': Icons.paid, 'color': Colors.green},
      {'label': 'PENDENTE', 'icon': Icons.pending, 'color': Colors.orange},
      {'label': 'ATRASADO', 'icon': Icons.warning, 'color': Colors.red},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 60, // Altura fixa para evitar problemas de layout
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: opcoes.map((opcao) {
          final isSelected = _filtroStatus == opcao['label'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    opcao['icon'],
                    size: 16,
                    color: isSelected ? Colors.white : opcao['color'],
                  ),
                  const SizedBox(width: 4),
                  Text(opcao['label']),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _filtroStatus = opcao['label'];
                });
              },
              selectedColor: opcao['color'],
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontSize: 12,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Query _buildQuery() {
    Query query = FirebaseFirestore.instance
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
        return Colors.green;
      case 'PENDENTE':
        return Colors.orange;
      case 'ATRASADO':
        return Colors.red;
      default:
        return Colors.grey;
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

  // VERSÃO SIMPLIFICADA DOS BOTÕES (SEM EXPANDED)
  List<Widget> _buildBotoesAcao({
    required String? contato,
    required String status,
    required String docId,
    required double valor,
    required String nome,
    required String? logoUrl,
  }) {
    List<Widget> botoes = [];

    if (contato != null && contato.isNotEmpty) {
      botoes.add(
        Container(
          margin: const EdgeInsets.only(right: 4),
          child: InkWell(
            onTap: () => _abrirContato(contato),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'CONTATO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (status != 'PAGO') {
      botoes.add(
        Container(
          margin: const EdgeInsets.only(right: 4),
          child: InkWell(
            onTap: () => _registrarPagamento(docId, valor, nome),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.paid, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'REG. PAGTO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    botoes.add(
      InkWell(
        onTap: () => _excluirPatrocinador(docId, logoUrl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete, size: 14, color: Colors.red),
              SizedBox(width: 4),
              Text(
                'EXCLUIR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return botoes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '🤝 Patrocinadores - ${widget.eventoNome}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _abrirDialogAdicionar,
            tooltip: 'Adicionar Patrocinador',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          print('=== DEBUG LISTA ===');
          print('Connection state: ${snapshot.connectionState}');
          print('Has data: ${snapshot.hasData}');
          print('Has error: ${snapshot.hasError}');

          if (snapshot.hasError) {
            print('ERRO: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Erro: ${snapshot.error}',
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star,
                      size: 60,
                      color: Colors.amber.shade200,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _filtroStatus == 'TODOS'
                          ? 'Nenhum patrocinador cadastrado'
                          : 'Nenhum patrocinador com status $_filtroStatus',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Clique no botão + para adicionar',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          print('Patrocinadores encontrados: ${docs.length}');

          // Calcular resumo
          double totalPrevisto = 0;
          double totalPago = 0;
          int pagos = 0;
          int pendentes = 0;
          int atrasados = 0;

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final valor = (data['valor'] as num?)?.toDouble() ?? 0;
            final status = data['status'] as String? ?? 'PENDENTE';
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
              // Filtros
              _buildFiltros(),

              // Card de Resumo
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📊 RESUMO',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Total: ${docs.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatusIndicator('Pagos', pagos, Colors.green),
                        _buildStatusIndicator('Pendentes', pendentes, Colors.orange),
                        _buildStatusIndicator('Atrasados', atrasados, Colors.red),
                      ],
                    ),

                    const Divider(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Previsto:',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              _realFormat.format(totalPrevisto),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Recebido:',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              _realFormat.format(totalPago),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Lista de Patrocinadores
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final patrocinador = doc.data() as Map<String, dynamic>;

                    final nome = patrocinador['nome'] ?? '';
                    final contato = patrocinador['contato'];
                    final logoUrl = patrocinador['logo_url'];
                    final valor = (patrocinador['valor'] as num?)?.toDouble() ?? 0;
                    final valorPago = (patrocinador['valor_pago'] as num?)?.toDouble() ?? 0;
                    final status = patrocinador['status'] as String? ?? 'PENDENTE';
                    final observacoes = patrocinador['observacoes'] ?? '';
                    final dataPrevista = patrocinador['data_prevista'];
                    final dataRealizada = patrocinador['data_realizada'];

                    final corStatus = _getCorStatus(status);
                    final iconStatus = _getIconStatus(status);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: corStatus.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Linha principal
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Logo
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: corStatus.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: corStatus.withOpacity(0.3)),
                                  ),
                                  child: logoUrl != null && logoUrl.isNotEmpty
                                      ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
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
                                      : Center(
                                    child: Icon(Icons.business, color: corStatus),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Informações
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Nome e Status
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              nome,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                                                Icon(
                                                  iconStatus,
                                                  size: 12,
                                                  color: corStatus,
                                                ),
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
                                      const SizedBox(height: 4),

                                      // Datas
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          if (dataPrevista != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.calendar_today,
                                                      size: 10, color: Colors.amber),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    'Prev: ${_formatarData(dataPrevista)}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.amber.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (dataRealizada != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.check_circle,
                                                      size: 10, color: Colors.green),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    'Pago: ${_formatarData(dataRealizada)}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.green.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),

                                      // Observações
                                      if (observacoes.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          observacoes,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Valores
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Previsto',
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                      Text(
                                        _realFormat.format(valor),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),

                                  if (valorPago > 0)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'Recebido',
                                          style: TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                        Text(
                                          _realFormat.format(valorPago),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Botões de ação (Wrap para quebrar linha se necessário)
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
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirDialogAdicionar,
        backgroundColor: Colors.amber,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, int valor, Color cor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
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
        const SizedBox(height: 4),
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
}