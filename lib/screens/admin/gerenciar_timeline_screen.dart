import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class GerenciarTimelineScreen extends StatefulWidget {
  const GerenciarTimelineScreen({super.key});

  @override
  State<GerenciarTimelineScreen> createState() => _GerenciarTimelineScreenState();
}

class _GerenciarTimelineScreenState extends State<GerenciarTimelineScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // Controladores para o formulário
  final TextEditingController _tituloController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  List<XFile> _imagensSelecionadas = [];
  List<String> _imagensUrls = [];
  bool _uploading = false;
  String? _editandoId;
  String _tipoSelecionado = 'evento';

  // Controle de visualização
  bool _modoCriacao = false;
  String _searchQuery = '';
  String _filtroTipo = 'todos';

  // 🔥 CONTROLE DO PORTFÓLIO NO SITE
  bool _exibirPortfolioNoSite = true; // Valor padrão

  // Tipos de publicação
  final List<String> _tipos = ['evento', 'treino', 'roda', 'formatura', 'noticia'];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracaoPortfolio();
  }

  // 🔥 CARREGAR CONFIGURAÇÃO DO PORTFÓLIO
  Future<void> _carregarConfiguracaoPortfolio() async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('configuracoes')
          .doc('portfolio_site')
          .get();

      if (doc.exists) {
        setState(() {
          _exibirPortfolioNoSite = doc['exibir'] ?? true;
        });
      } else {
        // Criar documento com valor padrão
        await _firestore
            .collection('configuracoes')
            .doc('portfolio_site')
            .set({'exibir': true});
      }
    } catch (e) {
      debugPrint('Erro ao carregar configuração do portfólio: $e');
    }
  }

  // 🔥 SALVAR CONFIGURAÇÃO DO PORTFÓLIO
  Future<void> _salvarConfiguracaoPortfolio(bool valor) async {
    try {
      await _firestore
          .collection('configuracoes')
          .doc('portfolio_site')
          .update({'exibir': valor});

      _mostrarSnackBar(
          valor ? '✅ Portfólio visível no site' : '❌ Portfólio oculto no site'
      );
    } catch (e) {
      _mostrarSnackBar('Erro ao salvar configuração: $e', isErro: true);
    }
  }

  // 🔥 PASTA NO STORAGE
  String _getStoragePath() {
    return 'timeline/${DateTime.now().year}/${DateTime.now().month}';
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descricaoController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  // 🔥 SELECIONAR IMAGENS
  Future<void> _selecionarImagens() async {
    try {
      final List<XFile>? imagens = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (imagens != null) {
        setState(() {
          _imagensSelecionadas.addAll(imagens);
        });
      }
    } catch (e) {
      _mostrarSnackBar('Erro ao selecionar imagens: $e', isErro: true);
    }
  }

  // 🔥 REMOVER IMAGEM SELECIONADA
  void _removerImagemSelecionada(int index) {
    setState(() {
      _imagensSelecionadas.removeAt(index);
    });
  }

  // 🔥 REMOVER IMAGEM JÁ UPLOADADA
  void _removerImagemUrl(String url) {
    setState(() {
      _imagensUrls.remove(url);
    });
  }

  // 🔥 UPLOAD DAS IMAGENS
  Future<List<String>> _uploadImagens() async {
    List<String> urls = [];
    String pasta = _getStoragePath();

    for (var imagem in _imagensSelecionadas) {
      try {
        File file = File(imagem.path);
        String fileName = '$pasta/${DateTime.now().millisecondsSinceEpoch}_${imagem.name}';
        Reference ref = _storage.ref().child(fileName);

        UploadTask uploadTask = ref.putFile(file);
        TaskSnapshot snapshot = await uploadTask;
        String url = await snapshot.ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        print('Erro no upload: $e');
      }
    }

    return urls;
  }

  // 🔥 DELETAR IMAGEM DO STORAGE
  Future<void> _deletarImagemStorage(String url) async {
    try {
      Reference ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      print('Erro ao deletar imagem do storage: $e');
    }
  }

  // 🔥 SALVAR PUBLICAÇÃO
  Future<void> _salvarPublicacao() async {
    if (_tituloController.text.trim().isEmpty) {
      _mostrarSnackBar('Título é obrigatório!', isErro: true);
      return;
    }

    setState(() => _uploading = true);

    try {
      List<String> novasUrls = await _uploadImagens();
      List<String> todasUrls = [..._imagensUrls, ...novasUrls];

      Map<String, dynamic> dados = {
        'titulo': _tituloController.text.trim(),
        'descricao': _descricaoController.text.trim(),
        'tipo': _tipoSelecionado,
        'link': _linkController.text.trim(),
        'imagens': todasUrls,
        'data_publicacao': FieldValue.serverTimestamp(),
        'data_atualizacao': FieldValue.serverTimestamp(),
        'data_evento': _tipoSelecionado == 'evento' ? FieldValue.serverTimestamp() : null,
        'ativo': true,
      };

      if (_editandoId != null) {
        await _firestore.collection('timeline_publicacoes').doc(_editandoId).update(dados);
        _mostrarSnackBar('Publicação atualizada com sucesso!');
      } else {
        await _firestore.collection('timeline_publicacoes').add(dados);
        _mostrarSnackBar('Publicação criada com sucesso!');
      }

      _limparFormulario();
      setState(() => _modoCriacao = false);
    } catch (e) {
      _mostrarSnackBar('Erro ao salvar: $e', isErro: true);
    } finally {
      setState(() => _uploading = false);
    }
  }

  // 🔥 CARREGAR PUBLICAÇÃO PARA EDIÇÃO
  void _carregarParaEdicao(Map<String, dynamic> dados, String id) {
    setState(() {
      _editandoId = id;
      _modoCriacao = true;
      _tituloController.text = dados['titulo'] ?? '';
      _descricaoController.text = dados['descricao'] ?? '';
      _tipoSelecionado = dados['tipo'] ?? 'evento';
      _linkController.text = dados['link'] ?? '';
      _imagensUrls = List<String>.from(dados['imagens'] ?? []);
      _imagensSelecionadas = [];
    });
  }

  // 🔥 DELETAR PUBLICAÇÃO
  Future<void> _deletarPublicacao(String id, List<String> imagensUrls) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Confirmar exclusão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tem certeza que deseja excluir esta publicação?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta ação não poderá ser desfeita!',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (imagensUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '🗑️ ${imagensUrls.length} imagem(ns) serão excluídas permanentemente',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
            ),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR PERMANENTEMENTE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        for (String url in imagensUrls) {
          await _deletarImagemStorage(url);
        }

        await _firestore.collection('timeline_publicacoes').doc(id).delete();

        Navigator.pop(context);
        _mostrarSnackBar('✅ Publicação excluída com sucesso!');
      } catch (e) {
        Navigator.pop(context);
        _mostrarSnackBar('Erro ao excluir: $e', isErro: true);
      }
    }
  }

  // 🔥 LIMPAR FORMULÁRIO
  void _limparFormulario() {
    setState(() {
      _editandoId = null;
      _tituloController.clear();
      _descricaoController.clear();
      _linkController.clear();
      _tipoSelecionado = 'evento';
      _imagensSelecionadas = [];
      _imagensUrls = [];
    });
  }

  // 🔥 FORMATAR DATA
  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return 'Data não disponível';
    return DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
  }

  String _formatarDataRelativa(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d atrás';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h atrás';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}min atrás';
    } else {
      return 'Agora mesmo';
    }
  }

  void _mostrarSnackBar(String mensagem, {bool isErro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: isErro ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // 🔥 FILTRAR PUBLICAÇÕES
  bool _filtrarPublicacao(Map<String, dynamic> data) {
    bool passouTipo = _filtroTipo == 'todos' || data['tipo'] == _filtroTipo;

    if (_searchQuery.isEmpty) return passouTipo;

    String titulo = data['titulo']?.toLowerCase() ?? '';
    String descricao = data['descricao']?.toLowerCase() ?? '';
    return (titulo.contains(_searchQuery.toLowerCase()) ||
        descricao.contains(_searchQuery.toLowerCase())) &&
        passouTipo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          _modoCriacao ? 'CRIAR / EDITAR PUBLICAÇÃO' : 'GERENCIAR TIMELINE',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // 🔥 CHAVE (SWITCH) PARA CONTROLAR PORTFÓLIO NO SITE
          if (!_modoCriacao)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _exibirPortfolioNoSite ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Portfólio no Site:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _exibirPortfolioNoSite,
                    onChanged: (valor) {
                      setState(() {
                        _exibirPortfolioNoSite = valor;
                      });
                      _salvarConfiguracaoPortfolio(valor);
                    },
                    activeColor: Colors.white,
                    activeTrackColor: Colors.green.shade400,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.grey.shade400,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),

          if (!_modoCriacao)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _mostrarDialogoBusca(),
            ),
          if (!_modoCriacao)
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _mostrarDialogoFiltro(),
            ),
          if (_modoCriacao)
            TextButton.icon(
              onPressed: () {
                _limparFormulario();
                setState(() => _modoCriacao = false);
              },
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text('VOLTAR', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _modoCriacao ? _buildFormulario() : _buildListaPublicacoes(),
      floatingActionButton: !_modoCriacao
          ? FloatingActionButton.extended(
        onPressed: () {
          _limparFormulario();
          setState(() => _modoCriacao = true);
        },
        icon: const Icon(Icons.add),
        label: const Text('NOVA PUBLICAÇÃO'),
        backgroundColor: Colors.purple.shade900,
      )
          : null,
    );
  }

  // 📝 FORMULÁRIO DE CRIAÇÃO/EDIÇÃO
  Widget _buildFormulario() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CABEÇALHO DO FORMULÁRIO
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getIconPorTipo(_tipoSelecionado),
                              color: Colors.purple.shade900,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _editandoId != null ? 'Editando Publicação' : 'Nova Publicação',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Preencha os dados abaixo para ${_editandoId != null ? 'atualizar' : 'criar'} a publicação',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // TIPO
                    const Text(
                      'TIPO DE PUBLICAÇÃO',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _tipos.map((tipo) {
                          bool isSelected = _tipoSelecionado == tipo;
                          return FilterChip(
                            selected: isSelected,
                            label: Text(tipo.toUpperCase()),
                            avatar: Icon(
                              _getIconPorTipo(tipo),
                              size: 16,
                              color: isSelected ? Colors.white : _getCorPorTipo(tipo),
                            ),
                            selectedColor: _getCorPorTipo(tipo),
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (selected) {
                              setState(() => _tipoSelecionado = tipo);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // TÍTULO
                    const Text(
                      'TÍTULO *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tituloController,
                      decoration: InputDecoration(
                        hintText: 'Ex: Roda de Capoeira de Sábado',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        prefixIcon: const Icon(Icons.title),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // DESCRIÇÃO
                    const Text(
                      'DESCRIÇÃO',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descricaoController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Descreva o evento ou publicação em detalhes...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Icon(Icons.description),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // LINK
                    const Text(
                      'LINK (opcional)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _linkController,
                      decoration: InputDecoration(
                        hintText: 'https://exemplo.com',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        prefixIcon: const Icon(Icons.link),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // IMAGENS
                    const Text(
                      'IMAGENS',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),

                    // IMAGENS ATUAIS
                    if (_imagensUrls.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.image, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Imagens Atuais (${_imagensUrls.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imagensUrls.length,
                                itemBuilder: (context, index) {
                                  return Stack(
                                    children: [
                                      Container(
                                        width: 100,
                                        height: 100,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue.shade200),
                                          image: DecorationImage(
                                            image: NetworkImage(_imagensUrls[index]),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 12,
                                        child: GestureDetector(
                                          onTap: () => _removerImagemUrl(_imagensUrls[index]),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // NOVAS IMAGENS
                    if (_imagensSelecionadas.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.cloud_upload, color: Colors.green.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Novas Imagens (${_imagensSelecionadas.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imagensSelecionadas.length,
                                itemBuilder: (context, index) {
                                  return Stack(
                                    children: [
                                      Container(
                                        width: 100,
                                        height: 100,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green.shade200),
                                          image: DecorationImage(
                                            image: FileImage(File(_imagensSelecionadas[index].path)),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 12,
                                        child: GestureDetector(
                                          onTap: () => _removerImagemSelecionada(index),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // BOTÃO ADICIONAR IMAGEM
                    OutlinedButton.icon(
                      onPressed: _selecionarImagens,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('ADICIONAR IMAGENS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple,
                        side: const BorderSide(color: Colors.purple),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // BOTÕES DE AÇÃO
          Container(
            padding: const EdgeInsets.all(24),
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
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _limparFormulario();
                        setState(() => _modoCriacao = false);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('CANCELAR'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _uploading ? null : _salvarPublicacao,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _uploading
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Text(_editandoId != null ? 'ATUALIZAR' : 'PUBLICAR'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 📋 LISTA DE PUBLICAÇÕES (EM VEZ DE GRID)
  Widget _buildListaPublicacoes() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('timeline_publicacoes')
          .orderBy('data_publicacao', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar publicações',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final publicacoes = snapshot.data?.docs ?? [];

        // Aplicar filtros
        final publicacoesFiltradas = publicacoes.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _filtrarPublicacao(data);
        }).toList();

        if (publicacoesFiltradas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.timeline,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Nenhuma publicação encontrada',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _searchQuery.isNotEmpty || _filtroTipo != 'todos'
                      ? 'Tente ajustar os filtros de busca'
                      : 'Clique no botão + para criar sua primeira publicação',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: publicacoesFiltradas.length,
          itemBuilder: (context, index) {
            final doc = publicacoesFiltradas[index];
            final data = doc.data() as Map<String, dynamic>;
            final id = doc.id;

            return _buildCardPublicacaoLista(data, id);
          },
        );
      },
    );
  }

  // 📇 CARD EM LISTA (COM BOTÕES GRANDES)
  Widget _buildCardPublicacaoLista(Map<String, dynamic> data, String id) {
    final List<String> imagens = List<String>.from(data['imagens'] ?? []);
    final String tipo = data['tipo'] ?? 'evento';
    final Color corTipo = _getCorPorTipo(tipo);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _carregarParaEdicao(data, id),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IMAGEM DE CAPA
            if (imagens.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Image.network(
                  imagens.first,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: corTipo.withOpacity(0.1),
                      child: Center(
                        child: Icon(
                          _getIconPorTipo(tipo),
                          size: 50,
                          color: corTipo.withOpacity(0.5),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // CONTEÚDO
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TIPO E DATA
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: corTipo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getIconPorTipo(tipo),
                              size: 14,
                              color: corTipo,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tipo.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: corTipo,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatarData(data['data_publicacao']),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // TÍTULO
                  Text(
                    data['titulo'] ?? 'Sem título',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // DESCRIÇÃO
                  if (data['descricao'] != null && data['descricao'].toString().isNotEmpty)
                    Text(
                      data['descricao'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 16),

                  // LINK (SE TIVER)
                  if (data['link'] != null && data['link'].toString().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              data['link'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // MINIATURAS DAS IMAGENS ADICIONAIS
                  if (imagens.length > 1)
                    Container(
                      height: 60,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: imagens.length - 1,
                        itemBuilder: (context, imgIndex) {
                          return Container(
                            width: 60,
                            height: 60,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(imagens[imgIndex + 1]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // BOTÕES DE AÇÃO (GRANDES)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _carregarParaEdicao(data, id),
                          icon: const Icon(Icons.edit),
                          label: const Text('EDITAR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _deletarPublicacao(id, imagens),
                          icon: const Icon(Icons.delete),
                          label: const Text('EXCLUIR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔍 DIÁLOGO DE BUSCA
  void _mostrarDialogoBusca() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buscar publicações'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Digite o título ou descrição...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() => _searchQuery = value);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // 🎯 DIÁLOGO DE FILTROS
  void _mostrarDialogoFiltro() {
    String tipoTemp = _filtroTipo;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Filtrar por tipo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tipo:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('TODOS'),
                    selected: tipoTemp == 'todos',
                    onSelected: (selected) {
                      setStateDialog(() => tipoTemp = 'todos');
                    },
                  ),
                  ..._tipos.map((tipo) {
                    return FilterChip(
                      label: Text(tipo.toUpperCase()),
                      avatar: Icon(
                        _getIconPorTipo(tipo),
                        size: 16,
                        color: tipoTemp == tipo ? Colors.white : _getCorPorTipo(tipo),
                      ),
                      selected: tipoTemp == tipo,
                      selectedColor: _getCorPorTipo(tipo),
                      checkmarkColor: Colors.white,
                      onSelected: (selected) {
                        setStateDialog(() => tipoTemp = tipo);
                      },
                    );
                  }).toList(),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _filtroTipo = 'todos';
                });
                Navigator.pop(context);
              },
              child: const Text('LIMPAR'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _filtroTipo = tipoTemp;
                });
                Navigator.pop(context);
              },
              child: const Text('APLICAR'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconPorTipo(String tipo) {
    switch (tipo) {
      case 'evento': return Icons.event;
      case 'treino': return Icons.fitness_center;
      case 'roda': return Icons.people;
      case 'formatura': return Icons.school;
      case 'noticia': return Icons.newspaper;
      default: return Icons.event;
    }
  }

  Color _getCorPorTipo(String tipo) {
    switch (tipo) {
      case 'evento': return Colors.blue;
      case 'treino': return Colors.green;
      case 'roda': return Colors.orange;
      case 'formatura': return Colors.purple;
      case 'noticia': return Colors.red;
      default: return Colors.blue;
    }
  }
}