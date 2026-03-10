import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/inscricao_campeonato_model.dart';
import 'visualizar_termo_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DetalheInscricaoScreen extends StatefulWidget {
  final String inscricaoId;
  final bool podeGerenciar;

  const DetalheInscricaoScreen({
    super.key,
    required this.inscricaoId,
    required this.podeGerenciar,
  });

  @override
  State<DetalheInscricaoScreen> createState() => _DetalheInscricaoScreenState();
}

class _DetalheInscricaoScreenState extends State<DetalheInscricaoScreen> {
  late CampeonatoService _campeonatoService;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  InscricaoCampeonatoModel? _inscricao;
  bool _isLoading = true;
  String _observacao = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _campeonatoService = CampeonatoService();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final inscricao = await _campeonatoService.getInscricao(widget.inscricaoId);

      if (mounted) {
        setState(() {
          _inscricao = inscricao;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar inscrição: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _atualizarStatus(String novoStatus) async {
    if (!widget.podeGerenciar) return;

    setState(() => _isSaving = true);

    try {
      await _campeonatoService.atualizarStatusInscricao(widget.inscricaoId, novoStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Status atualizado para $novoStatus'),
            backgroundColor: Colors.green,
          ),
        );
        _carregarDados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmarPagamento() async {
    if (!widget.podeGerenciar) return;

    setState(() => _isSaving = true);

    try {
      await _campeonatoService.confirmarPagamento(widget.inscricaoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💰 Pagamento confirmado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _carregarDados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao confirmar pagamento'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 🗑️ EXCLUIR INSCRIÇÃO
  Future<void> _excluirInscricao() async {
    if (_inscricao == null) return;

    String nomeConfirmacao = '';
    bool podeExcluir = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade700,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '🗑️ EXCLUIR INSCRIÇÃO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Você está prestes a excluir permanentemente a inscrição de:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _inscricao!.nome,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Esta ação irá:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.close, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Remover todos os dados da inscrição',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.close, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Excluir foto do competidor (se houver)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.close, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Excluir comprovante de pagamento (se houver)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.close, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Excluir assinatura digital (se houver)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Digite o nome do competidor para confirmar:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (value) {
                    setDialogState(() {
                      nomeConfirmacao = value;
                      podeExcluir = value.trim().toUpperCase() == _inscricao!.nome.toUpperCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Digite o nome completo',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    errorText: podeExcluir ? null : 'O nome digitado não corresponde',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                onPressed: podeExcluir
                    ? () {
                  Navigator.pop(context);
                  _confirmarExclusao();
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('EXCLUIR'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 🗑️ CONFIRMAR EXCLUSÃO
  Future<void> _confirmarExclusao() async {
    if (_inscricao == null) return;

    setState(() => _isSaving = true);

    try {
      // Excluir foto
      if (_inscricao!.fotoUrl != null) {
        try {
          final ref = _storage.refFromURL(_inscricao!.fotoUrl!);
          await ref.delete();
          debugPrint('✅ Foto excluída com sucesso');
        } catch (e) {
          debugPrint('⚠️ Erro ao excluir foto: $e');
        }
      }

      // Excluir comprovante
      if (_inscricao!.comprovanteUrl != null) {
        try {
          final ref = _storage.refFromURL(_inscricao!.comprovanteUrl!);
          await ref.delete();
          debugPrint('✅ Comprovante excluído com sucesso');
        } catch (e) {
          debugPrint('⚠️ Erro ao excluir comprovante: $e');
        }
      }

      // Excluir assinatura
      if (_inscricao!.assinaturaUrl != null) {
        try {
          final ref = _storage.refFromURL(_inscricao!.assinaturaUrl!);
          await ref.delete();
          debugPrint('✅ Assinatura excluída com sucesso');
        } catch (e) {
          debugPrint('⚠️ Erro ao excluir assinatura: $e');
        }
      }

      // Excluir documento do Firestore
      await _campeonatoService.excluirInscricao(widget.inscricaoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Inscrição excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Erro ao excluir: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir inscrição'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _adicionarObservacao() async {
    if (_observacao.trim().isEmpty || !widget.podeGerenciar) return;

    setState(() => _isSaving = true);

    try {
      await _campeonatoService.adicionarObservacao(widget.inscricaoId, _observacao.trim());

      if (mounted) {
        setState(() => _observacao = '');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📝 Observação adicionada'),
            backgroundColor: Colors.green,
          ),
        );
        _carregarDados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar observação'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 📱 WHATSAPP
  Future<void> _abrirWhatsApp(String numero, {String? mensagem}) async {
    if (numero.isEmpty) {
      _mostrarMensagem('Número de telefone não disponível');
      return;
    }

    try {
      String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanedPhone.startsWith('0')) {
        cleanedPhone = cleanedPhone.substring(1);
      }
      if (!cleanedPhone.startsWith('55')) {
        cleanedPhone = '55$cleanedPhone';
      }

      String url = 'https://wa.me/$cleanedPhone';
      if (mensagem != null && mensagem.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(mensagem);
        url += '?text=$encodedMessage';
      }

      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final webUrl = Uri.parse('https://web.whatsapp.com/send?phone=$cleanedPhone' +
            (mensagem != null && mensagem.isNotEmpty ? '&text=${Uri.encodeComponent(mensagem)}' : ''));
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro WhatsApp: $e');
      _mostrarMensagem('Erro ao abrir WhatsApp');
    }
  }

  // 🔥 MÉTODO PRINCIPAL PARA ABRIR ARQUIVOS
  Future<void> _abrirLink(String? url) async {
    if (url == null || url.isEmpty) {
      _mostrarMensagem('Link inválido');
      return;
    }

    // Verificar se é PDF
    final isPdf = url.toLowerCase().contains('.pdf') ||
        url.toLowerCase().contains('pdf') ||
        url.toLowerCase().contains('application%2Fpdf');

    // Verificar se é imagem
    final isImage = url.toLowerCase().contains('.jpg') ||
        url.toLowerCase().contains('.jpeg') ||
        url.toLowerCase().contains('.png') ||
        url.toLowerCase().contains('.gif') ||
        (url.contains('firebasestorage') && !isPdf);

    if (isImage) {
      _abrirImagem(url);
      return;
    }

    if (isPdf) {
      await _abrirPdfNoApp(url);
      return;
    }

    // Para outros tipos de link
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _mostrarMensagem('Não foi possível abrir o link');
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
      _mostrarMensagem('Erro ao abrir link');
    }
  }

  // 🖼️ ABRIR IMAGEM
  void _abrirImagem(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white, size: 50),
                        SizedBox(height: 8),
                        Text(
                          'Erro ao carregar imagem',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📄 ABRIR PDF DENTRO DO APP USANDO WEBVIEW
  Future<void> _abrirPdfNoApp(String url) async {
    try {
      _mostrarMensagem('📄 Abrindo PDF...');

      if (!mounted) return;

      // Usar Google Docs Viewer para visualizar dentro do app
      final viewerUrl = 'https://docs.google.com/viewer?url=${Uri.encodeComponent(url)}&embedded=true';

      // Fechar snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Criar controller para o WebView
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              debugPrint('WebView progress: $progress%');
            },
            onPageStarted: (String url) {
              debugPrint('Page started: $url');
            },
            onPageFinished: (String url) {
              debugPrint('Page finished: $url');
            },
            onWebResourceError: (error) {
              debugPrint('WebView error: $error');
            },
          ),
        )
        ..loadRequest(Uri.parse(viewerUrl));

      // Abrir tela com WebView
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text(
                '📄 Comprovante',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.amber.shade900,
              foregroundColor: Colors.white,
              actions: [
                // Botão para abrir no navegador externo (fallback)
                IconButton(
                  icon: const Icon(Icons.open_in_browser),
                  onPressed: () async {
                    try {
                      final uri = Uri.parse(url);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      _mostrarMensagem('Erro ao abrir externamente');
                    }
                  },
                  tooltip: 'Abrir no navegador',
                ),
              ],
            ),
            body: WebViewWidget(controller: controller),
          ),
        ),
      );

    } catch (e) {
      debugPrint('❌ Erro ao abrir PDF: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Se falhar, pergunta se quer abrir no navegador
      final fallback = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('⚠️ Erro ao abrir PDF'),
          content: const Text('Não foi possível abrir o PDF no visualizador interno. Deseja abrir no navegador?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('ABRIR NO NAVEGADOR'),
            ),
          ],
        ),
      );

      if (fallback == true) {
        try {
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          _mostrarMensagem('Erro ao abrir PDF');
        }
      }
    }
  }

  void _mostrarTermo() {
    if (_inscricao == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisualizarTermoScreen(
          inscricao: _inscricao!,
        ),
      ),
    );
  }

  void _mostrarMensagem(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'confirmado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'confirmado':
        return 'CONFIRMADO';
      case 'cancelado':
        return 'CANCELADO';
      default:
        return 'PENDENTE';
    }
  }

  // 📱 BOTÃO DE CONTATO WHATSAPP
  Widget _buildContactButton({
    required String label,
    required String? numero,
    required String? nome,
    required Color cor,
    String? mensagemPadrao,
  }) {
    final bool temContato = numero != null && numero.isNotEmpty;

    return InkWell(
      onTap: temContato
          ? () => _abrirWhatsApp(
        numero,
        mensagem: mensagemPadrao ?? 'Olá $nome! Sua inscrição no campeonato está sendo analisada.',
      )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: temContato ? cor.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: temContato ? cor.withValues(alpha: 0.3) : Colors.grey.shade300,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/whatsapp.svg',
              height: 24,
              width: 24,
              colorFilter: ColorFilter.mode(
                temContato ? cor : Colors.grey.shade400,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: temContato ? Colors.black87 : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Detalhes da Inscrição',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (widget.podeGerenciar && _inscricao != null && !_isSaving) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _excluirInscricao,
              tooltip: 'Excluir inscrição',
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'confirmar') {
                  _atualizarStatus('confirmado');
                } else if (value == 'cancelar') {
                  _atualizarStatus('cancelado');
                } else if (value == 'pendente') {
                  _atualizarStatus('pendente');
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'confirmar',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Confirmar inscrição'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cancelar',
                  child: Row(
                    children: [
                      Icon(Icons.cancel, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Cancelar inscrição'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'pendente',
                  child: Row(
                    children: [
                      Icon(Icons.pending, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Marcar como pendente'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _inscricao == null
              ? _buildErrorState()
              : _buildContent(),
          if (_isSaving)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Inscrição não encontrada',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('VOLTAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final inscricao = _inscricao!;
    final statusColor = _getStatusColor(inscricao.status);
    final statusText = _getStatusText(inscricao.status);

    final dataNascimentoFormatada = inscricao.dataNascimento.isNotEmpty
        ? _formatarDataNascimento(inscricao.dataNascimento)
        : 'Não informada';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status e Pagamento
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Pagamento',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: inscricao.taxaPaga
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          inscricao.taxaPaga ? 'PAGO' : 'NÃO PAGO',
                          style: TextStyle(
                            color: inscricao.taxaPaga ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Foto e Nome
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.amber.shade400, width: 2),
                    ),
                    child: inscricao.fotoUrl != null && inscricao.fotoUrl!.isNotEmpty
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: CachedNetworkImage(
                        imageUrl: inscricao.fotoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Text(
                            inscricao.nome.isNotEmpty ? inscricao.nome[0] : '?',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ),
                    )
                        : Center(
                      child: Text(
                        inscricao.nome.isNotEmpty ? inscricao.nome[0] : '?',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inscricao.nome,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (inscricao.apelido.isNotEmpty)
                          Text(
                            'Apelido: ${inscricao.apelido}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.cake, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              '$dataNascimentoFormatada (${inscricao.idade} anos)',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Informações Pessoais
          _buildSection(
            title: '👤 DADOS PESSOAIS',
            icon: Icons.person,
            color: Colors.blue,
            children: [
              _buildInfoRow('CPF', _formatarCPF(inscricao.cpf)),
              _buildInfoRow('Sexo', inscricao.sexo),
              _buildInfoRow('Contato', inscricao.contatoAluno),
              _buildInfoRow('Endereço', inscricao.endereco),
              _buildInfoRow('Cidade', inscricao.cidade),
            ],
          ),

          const SizedBox(height: 16),

          // Informações do Grupo
          _buildSection(
            title: '🥋 GRUPO E GRADUAÇÃO',
            icon: Icons.group,
            color: Colors.green,
            children: [
              _buildInfoRow('Grupo', inscricao.grupo),
              _buildInfoRow('Professor', inscricao.professorNome),
              _buildInfoRow('Contato Prof.', inscricao.professorContato),
              const Divider(height: 16),
              _buildInfoRow('Graduação', inscricao.graduacaoNome ?? 'Não informada'),
              _buildInfoRow('Grupo UAI', inscricao.isGrupoUai ? 'Sim' : 'Não'),
            ],
          ),

          const SizedBox(height: 16),

          // Categoria
          _buildSection(
            title: '🏆 CATEGORIA',
            icon: Icons.emoji_events,
            color: Colors.purple,
            children: [
              _buildInfoRow('Categoria', inscricao.categoriaNome ?? 'Não informada'),
              if (inscricao.categoriaId != null)
                _buildInfoRow('ID', inscricao.categoriaId!),
            ],
          ),

          const SizedBox(height: 16),

          // Documentos
          _buildSection(
            title: '📎 DOCUMENTOS',
            icon: Icons.attach_file,
            color: Colors.teal,
            children: [
              GestureDetector(
                onTap: _mostrarTermo,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: inscricao.assinaturaUrl != null
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: inscricao.assinaturaUrl != null
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        inscricao.assinaturaUrl != null
                            ? Icons.draw
                            : Icons.description,
                        color: inscricao.assinaturaUrl != null
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inscricao.assinaturaUrl != null
                                  ? '✅ Termo assinado digitalmente'
                                  : '📝 Termo aceito (sem assinatura)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: inscricao.assinaturaUrl != null
                                    ? Colors.green.shade800
                                    : Colors.orange.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Toque para visualizar',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),

              if (inscricao.comprovanteUrl != null) ...[
                _buildDocumentTile(
                  url: inscricao.comprovanteUrl!,
                  titulo: 'Comprovante de pagamento',
                  icone: Icons.receipt,
                  cor: Colors.green,
                ),
              ],

              if (inscricao.fotoUrl != null)
                _buildDocumentTile(
                  url: inscricao.fotoUrl!,
                  titulo: 'Foto do competidor',
                  icone: Icons.photo_camera,
                  cor: Colors.purple,
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Data da inscrição
          if (inscricao.dataInscricao != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Inscrição: ${_dateTimeFormat.format(inscricao.dataInscricao!)}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // BOTÕES DE CONTATO WHATSAPP
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📱 CONTATOS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildContactButton(
                        label: 'ALUNO',
                        numero: inscricao.contatoAluno,
                        nome: inscricao.nome,
                        cor: Colors.green,
                        mensagemPadrao: 'Olá ${inscricao.nome}! Sua inscrição no campeonato está sendo analisada.',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildContactButton(
                        label: 'PROFESSOR',
                        numero: inscricao.professorContato,
                        nome: inscricao.professorNome,
                        cor: Colors.blue,
                        mensagemPadrao: 'Olá ${inscricao.professorNome}! O aluno ${inscricao.nome} se inscreveu no campeonato.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Ações (se tiver permissão)
          if (widget.podeGerenciar) ...[
            const Text(
              '⚙️ AÇÕES',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (!inscricao.taxaPaga)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _confirmarPagamento,
                  icon: const Icon(Icons.payment),
                  label: const Text('CONFIRMAR PAGAMENTO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Campo de observação
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📝 OBSERVAÇÕES',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Adicionar observação...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      maxLines: 3,
                      onChanged: (value) => _observacao = value,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _adicionarObservacao,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('ADICIONAR'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDocumentTile({
    required String url,
    required String titulo,
    required IconData icone,
    required Color cor,
  }) {
    final isPdf = url.toLowerCase().contains('.pdf') ||
        url.toLowerCase().contains('pdf') ||
        url.toLowerCase().contains('application%2Fpdf');

    return ListTile(
      leading: Icon(
        isPdf ? Icons.picture_as_pdf : icone,
        color: isPdf ? Colors.red : cor,
      ),
      title: Text(isPdf ? '$titulo (PDF)' : titulo),
      subtitle: Text(isPdf ? 'Clique para visualizar PDF' : 'Clique para visualizar'),
      trailing: Icon(
        isPdf ? Icons.picture_as_pdf : Icons.visibility,
        color: isPdf ? Colors.red : cor,
      ),
      onTap: () => _abrirLink(url),
    );
  }

  String _formatarDataNascimento(String dataStr) {
    try {
      final partes = dataStr.split('/');
      if (partes.length == 3) {
        return dataStr;
      }

      if (dataStr.contains('-')) {
        final partes = dataStr.split('-');
        if (partes.length == 3) {
          return '${partes[2]}/${partes[1]}/${partes[0]}';
        }
      }

      return dataStr;
    } catch (e) {
      return dataStr;
    }
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Não informado' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatarCPF(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }
}