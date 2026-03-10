import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🔥 FALTAVA ESSE!
import '../../services/logo_service.dart';

class GerenciarLogoScreen extends StatefulWidget {
  const GerenciarLogoScreen({super.key});

  @override
  State<GerenciarLogoScreen> createState() => _GerenciarLogoScreenState();
}

class _GerenciarLogoScreenState extends State<GerenciarLogoScreen> {
  final LogoService _logoService = LogoService();
  final TextEditingController _urlController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarUrl();
  }

  Future<void> _carregarUrl() async {
    final url = await _logoService.getLogoUrl();
    setState(() {
      _urlController.text = url ?? '';
      _carregando = false;
    });
  }

  Future<void> _salvar() async {
    final novaUrl = _urlController.text.trim();
    if (novaUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, insira uma URL'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvando = true);

    try {
      await FirebaseFirestore.instance.collection('configuracoes').doc('logo').set({
        'url': novaUrl,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      // Limpa o cache do serviço para forçar recarregar
      _logoService.limparCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo salva com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  Future<void> _testarUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pré-visualização'),
        content: SizedBox(
          height: 200,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    'URL inválida',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Logo do Site'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _carregando = true;
                _carregarUrl();
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // CARD DE PRÉ-VISUALIZAÇÃO
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'PRÉ-VISUALIZAÇÃO',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _logoService.buildLogo(height: 150),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // CARD DE URL
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'URL DA LOGO',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Insira a URL de uma imagem (PNG, JPG, etc)',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _urlController,
                              decoration: InputDecoration(
                                hintText: 'https://exemplo.com/logo.png',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.link),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _testarUrl,
                                    icon: const Icon(Icons.preview),
                                    label: const Text('PRÉ-VISUALIZAR'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      side: const BorderSide(color: Colors.blue),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // CARD DE INFORMAÇÕES
                    Card(
                      elevation: 2,
                      color: Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue.shade900),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Dicas:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '• Use imagens com fundo transparente (PNG)\n'
                                        '• Tamanho recomendado: 500x500px\n'
                                        '• A logo será usada na página inicial do site',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // BOTÃO SALVAR
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _salvando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'SALVAR LOGO',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}