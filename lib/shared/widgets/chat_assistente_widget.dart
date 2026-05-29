import 'package:flutter/material.dart';
import 'package:uai_capoeira/shared/services/assistente_chat_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatAssistenteWidget extends StatefulWidget {
  const ChatAssistenteWidget({super.key});

  @override
  State<ChatAssistenteWidget> createState() => _ChatAssistenteWidgetState();
}

class _ChatAssistenteWidgetState extends State<ChatAssistenteWidget> {
  final AssistenteChatService _service = AssistenteChatService();
  bool _ativo = false;
  bool _aberto = false;
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _mensagens = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    _carregarConfig();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    _config = await _service.carregarConfiguracoesCompletas();
    setState(() {
      _ativo = _config['ativo'] ?? false;
    });

    if (_ativo) {
      _mensagens.add({
        'texto': _config['perfil']['mensagem_boas_vindas'],
        'isUsuario': false,
        'timestamp': DateTime.now(),
      });
    }
  }

  Future<void> _enviarMensagem(String texto) async {
    if (texto.trim().isEmpty) return;

    // Adiciona mensagem do usuário
    setState(() {
      _mensagens.add({
        'texto': texto,
        'isUsuario': true,
        'timestamp': DateTime.now(),
      });
      _carregando = true;
    });

    _inputController.clear();
    _rolarParaFim();

    // 🔥 ENVIA A CONFIG COMPLETA
    final resposta = await _service.enviarMensagem(texto, _config);

    // Extrai ação
    final acao = _service.extrairAcao(resposta);
    final respostaLimpa = _service.limparResposta(resposta);

    setState(() {
      _mensagens.add({
        'texto': respostaLimpa,
        'isUsuario': false,
        'timestamp': DateTime.now(),
        'acao': acao,
      });
      _carregando = false;
    });

    _rolarParaFim();
  }

  Future<void> _executarAcao(String acao) async {
    final acoes = _config['acoes'] ?? {};
    final configAcao = acoes[acao];

    if (configAcao == null) return;

    switch (acao) {
      case 'inscricao':
        Navigator.pushNamed(context, '/inscricao-publica');
        break;
      case 'campeonato':
        Navigator.pushNamed(context, '/inscricao-campeonato');
        break;
      case 'whatsapp':
        final url = configAcao['url_base'] ?? '';
        if (url.isNotEmpty) {
          final Uri uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        break;
      case 'maps':
        final endereco = _config['informacoes']['endereco'] ?? '';
        final url = 'https://maps.google.com/?q=${Uri.encodeComponent(endereco)}';
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
    }
  }

  void _rolarParaFim() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _enviarPerguntaRapida(String pergunta) {
    _enviarMensagem(pergunta);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ativo) return const SizedBox.shrink();

    final corPrimaria = _parseColor(_config['aparencia']['cor_primaria'] ?? '#FF0000');

    return Stack(
      children: [
        if (_aberto)
          Positioned(
            bottom: 20,
            right: 20,
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: MediaQuery.of(context).size.width < 600 ? 350 : 400,
                height: 550,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: corPrimaria,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          if (_config['aparencia']['mostrar_avatar'] == true)
                            Text(_config['perfil']['avatar'], style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _config['perfil']['nome'],
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  _config['perfil']['status'],
                                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() => _aberto = false),
                          ),
                        ],
                      ),
                    ),

                    // Perguntas Rápidas (se houver)
                    if (_config['respostas_rapidas']?['perguntas_sugeridas'] != null &&
                        (_config['respostas_rapidas']['perguntas_sugeridas'] as List).isNotEmpty)
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: (_config['respostas_rapidas']['perguntas_sugeridas'] as List)
                              .map<Widget>((pergunta) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(pergunta, style: const TextStyle(fontSize: 12)),
                              onPressed: () => _enviarPerguntaRapida(pergunta),
                              backgroundColor: corPrimaria.withOpacity(0.1),
                              side: BorderSide(color: corPrimaria.withOpacity(0.3)),
                            ),
                          ))
                              .toList(),
                        ),
                      ),

                    // Messages
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _mensagens.length + (_carregando ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _mensagens.length && _carregando) {
                            return _buildMensagemCarregando(corPrimaria);
                          }
                          final msg = _mensagens[index];
                          return _buildMensagem(msg, corPrimaria);
                        },
                      ),
                    ),

                    // Input
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              decoration: InputDecoration(
                                hintText: 'Digite sua pergunta...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(25),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              onSubmitted: _enviarMensagem,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: corPrimaria,
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white, size: 20),
                              onPressed: () => _enviarMensagem(_inputController.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Botão flutuante
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            onPressed: () => setState(() => _aberto = !_aberto),
            backgroundColor: corPrimaria,
            child: Icon(_aberto ? Icons.close : Icons.chat, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildMensagem(Map<String, dynamic> msg, Color corPrimaria) {
    final isUsuario = msg['isUsuario'];

    return Align(
      alignment: isUsuario ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isUsuario ? corPrimaria : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUsuario ? const Radius.circular(4) : const Radius.circular(16),
            bottomLeft: isUsuario ? const Radius.circular(16) : const Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg['texto'],
              style: TextStyle(
                color: isUsuario ? Colors.white : Colors.black87,
                fontSize: (_config['aparencia']['tamanho_fonte'] ?? 14).toDouble(),
              ),
            ),
            if (msg['acao'] != null && msg['acao'].isNotEmpty) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _executarAcao(msg['acao']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: corPrimaria,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(_config['acoes'][msg['acao']]?['texto_botao'] ?? 'AÇÃO'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMensagemCarregando(Color corPrimaria) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: corPrimaria,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Digitando...'),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.red;
    }
  }
}
