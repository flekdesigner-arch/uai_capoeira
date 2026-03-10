import 'package:flutter/material.dart';
import '../../widgets/signature_painter.dart';
import '../../services/signature_service.dart';

class SignatureScreen extends StatefulWidget {
  final String inscricaoId;
  final String nomeResponsavel;
  final String nomeAluno;
  final Function(String imageUrl) onConfirm;

  const SignatureScreen({
    super.key,
    required this.inscricaoId,
    required this.nomeResponsavel,
    required this.nomeAluno,
    required this.onConfirm,
  });

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final SignatureService _signatureService = SignatureService();
  late SignatureController _signatureController;
  bool _isLoading = false;
  String? _erroMensagem;

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController();
    _signatureController.addListener(_onSignatureChanged);
  }

  @override
  void dispose() {
    _signatureController.removeListener(_onSignatureChanged);
    _signatureController.dispose();
    super.dispose();
  }

  void _onSignatureChanged() {
    setState(() {});
  }

  Future<void> _confirmarAssinatura() async {
    if (!_signatureController.hasSignature) {
      setState(() {
        _erroMensagem = 'Por favor, faça sua assinatura';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _erroMensagem = null;
    });

    try {
      debugPrint('🚀 Iniciando processo de assinatura...');

      // Pegar os pontos da assinatura do controller
      final points = _signatureController.points;
      debugPrint('📊 Pontos da assinatura: ${points.length} traços');

      if (points.isEmpty) {
        throw Exception('Nenhum traço encontrado');
      }

      // Converter para imagem - SEM width/height FIXOS!
      debugPrint('🎨 Convertendo para imagem (com recorte automático)...');
      final imageData = await _signatureService.signatureToImage(
        context,
        points,
        backgroundColor: Colors.white,
        penColor: Colors.black,
        padding: 20.0, // Padding ao redor da assinatura
      );

      if (imageData == null) {
        throw Exception('Erro ao processar imagem da assinatura');
      }

      debugPrint('📏 Tamanho da imagem: ${imageData.length} bytes');

      // Tentar método principal primeiro
      debugPrint('📤 Tentando upload principal...');
      String? imageUrl = await _signatureService.salvarAssinatura(
        imageData: imageData,
        inscricaoId: widget.inscricaoId,
        nomeResponsavel: widget.nomeResponsavel,
        nomeAluno: widget.nomeAluno,
      );

      // Se falhar, tentar método alternativo
      if (imageUrl == null) {
        debugPrint('⚠️ Upload principal falhou, tentando método alternativo...');
        imageUrl = await _signatureService.salvarAssinaturaAlternativo(
          imageData: imageData,
          inscricaoId: widget.inscricaoId,
          nomeResponsavel: widget.nomeResponsavel,
          nomeAluno: widget.nomeAluno,
        );
      }

      if (imageUrl == null) {
        throw Exception('Falha em todos os métodos de upload');
      }

      debugPrint('✅ Assinatura salva com sucesso: $imageUrl');

      // Retornar a URL
      widget.onConfirm(imageUrl);

      if (mounted) {
        Navigator.pop(context, true);
      }

    } catch (e) {
      debugPrint('❌ Erro detalhado: $e');
      setState(() {
        _erroMensagem = 'Erro: ${e.toString().replaceAll('Exception:', '').trim()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('✍️ Assinatura Digital'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _signatureController.clear();
              setState(() {
                _erroMensagem = null;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // INSTRUÇÕES
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade900),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Use o mouse/dedo para assinar no quadro abaixo',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          // ÁREA DA ASSINATURA
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: Colors.white,
                  child: SignaturePad(
                    controller: _signatureController,
                    penColor: Colors.black,
                    strokeWidth: 3.0,
                  ),
                ),
              ),
            ),
          ),

          // MENSAGEM DE ERRO
          if (_erroMensagem != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _erroMensagem!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),

          // INFORMAÇÕES DO SIGNATÁRIO
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Signatário:',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            widget.nomeResponsavel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.child_care, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Aluno:',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            widget.nomeAluno,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // BOTÕES
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('CANCELAR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _confirmarAssinatura,
                    icon: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.check),
                    label: Text(_isLoading ? 'SALVANDO...' : 'CONFIRMAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
}