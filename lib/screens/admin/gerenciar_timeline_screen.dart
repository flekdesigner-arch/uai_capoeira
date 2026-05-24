
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class GerenciarTimelineScreen extends StatefulWidget {
  const GerenciarTimelineScreen({super.key});

  @override
  State<GerenciarTimelineScreen> createState() => _GerenciarTimelineScreenState();
}

class _GerenciarTimelineScreenState extends State<GerenciarTimelineScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _tituloController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  final List<String> _tipos = ['evento', 'treino', 'roda', 'formatura', 'noticia'];

  List<XFile> _imagensSelecionadas = [];
  List<String> _imagensUrls = [];

  bool _uploading = false;
  bool _modoCriacao = false;
  bool _exibirPortfolioNoSite = true;

  String? _editandoId;
  String _tipoSelecionado = 'evento';
  String _searchQuery = '';
  String _filtroTipo = 'todos';

  @override
  void initState() {
    super.initState();
    _carregarConfiguracaoPortfolio();
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descricaoController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfiguracaoPortfolio() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('portfolio_site').get();

      if (doc.exists) {
        setState(() => _exibirPortfolioNoSite = doc['exibir'] ?? true);
      } else {
        await _firestore.collection('configuracoes').doc('portfolio_site').set({'exibir': true});
      }
    } catch (e) {
      debugPrint('Erro ao carregar configuração do portfólio: $e');
    }
  }

  Future<void> _salvarConfiguracaoPortfolio(bool valor) async {
    try {
      await _firestore.collection('configuracoes').doc('portfolio_site').set({
        'exibir': valor,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _mostrarSnackBar(valor ? '✅ Portfólio visível no site' : '❌ Portfólio oculto no site');
    } catch (e) {
      _mostrarSnackBar('Erro ao salvar configuração: $e', isErro: true);
    }
  }

  String _getStoragePath() {
    final now = DateTime.now();
    return 'timeline/${now.year}/${now.month}';
  }

  Future<void> _selecionarImagens() async {
    try {
      final imagens = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (imagens.isNotEmpty) {
        setState(() => _imagensSelecionadas.addAll(imagens));
      }
    } catch (e) {
      _mostrarSnackBar('Erro ao selecionar imagens: $e', isErro: true);
    }
  }

  void _removerImagemSelecionada(int index) {
    setState(() => _imagensSelecionadas.removeAt(index));
  }

  void _removerImagemUrl(String url) {
    setState(() => _imagensUrls.remove(url));
  }

  Future<List<String>> _uploadImagens() async {
    final urls = <String>[];
    final pasta = _getStoragePath();

    for (final imagem in _imagensSelecionadas) {
      try {
        final file = File(imagem.path);
        final fileName = '$pasta/${DateTime.now().millisecondsSinceEpoch}_${imagem.name}';
        final ref = _storage.ref().child(fileName);

        final uploadTask = ref.putFile(file);
        final snapshot = await uploadTask;
        final url = await snapshot.ref.getDownloadURL();

        urls.add(url);
      } catch (e) {
        debugPrint('Erro no upload: $e');
      }
    }

    return urls;
  }

  Future<void> _deletarImagemStorage(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      debugPrint('Erro ao deletar imagem do storage: $e');
    }
  }

  Future<void> _salvarPublicacao() async {
    if (_tituloController.text.trim().isEmpty) {
      _mostrarSnackBar('Título é obrigatório!', isErro: true);
      return;
    }

    setState(() => _uploading = true);

    try {
      final novasUrls = await _uploadImagens();
      final todasUrls = [..._imagensUrls, ...novasUrls];

      final dados = {
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
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _carregarParaEdicao(Map<String, dynamic> dados, String id) {
    setState(() {
      _editandoId = id;
      _modoCriacao = true;
      _tituloController.text = dados['titulo']?.toString() ?? '';
      _descricaoController.text = dados['descricao']?.toString() ?? '';
      _tipoSelecionado = dados['tipo']?.toString() ?? 'evento';
      _linkController.text = dados['link']?.toString() ?? '';
      _imagensUrls = List<String>.from(dados['imagens'] ?? []);
      _imagensSelecionadas = [];
    });
  }

  Future<void> _deletarPublicacao(String id, List<String> imagensUrls) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.red.shade800),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Excluir publicação?',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Text(
            imagensUrls.isEmpty
                ? 'Essa ação não poderá ser desfeita.'
                : 'Essa ação não poderá ser desfeita.\n\n${imagensUrls.length} imagem(ns) também serão removidas do Storage.',
            style: const TextStyle(height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('EXCLUIR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: CircularProgressIndicator(color: Colors.purple.shade900),
        ),
      );

      for (final url in imagensUrls) {
        await _deletarImagemStorage(url);
      }

      await _firestore.collection('timeline_publicacoes').doc(id).delete();

      if (mounted) Navigator.pop(context);
      _mostrarSnackBar('✅ Publicação excluída com sucesso!');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarSnackBar('Erro ao excluir: $e', isErro: true);
    }
  }

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

  String _formatarData(dynamic timestamp) {
    if (timestamp == null) return 'Data não disponível';

    try {
      if (timestamp is Timestamp) {
        return DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
      }

      if (timestamp is DateTime) {
        return DateFormat('dd/MM/yyyy HH:mm').format(timestamp);
      }
    } catch (_) {}

    return timestamp.toString();
  }

  String _formatarDataRelativa(dynamic timestamp) {
    if (timestamp == null) return '';

    try {
      final date = timestamp is Timestamp
          ? timestamp.toDate()
          : timestamp is DateTime
          ? timestamp
          : null;

      if (date == null) return '';

      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 0) return '${diff.inDays}d atrás';
      if (diff.inHours > 0) return '${diff.inHours}h atrás';
      if (diff.inMinutes > 0) return '${diff.inMinutes}min atrás';
      return 'Agora mesmo';
    } catch (_) {
      return '';
    }
  }

  void _mostrarSnackBar(String mensagem, {bool isErro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: isErro ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  bool _filtrarPublicacao(Map<String, dynamic> data) {
    final passouTipo = _filtroTipo == 'todos' || data['tipo'] == _filtroTipo;

    if (_searchQuery.isEmpty) return passouTipo;

    final query = _searchQuery.toLowerCase();
    final titulo = data['titulo']?.toString().toLowerCase() ?? '';
    final descricao = data['descricao']?.toString().toLowerCase() ?? '';

    return (titulo.contains(query) || descricao.contains(query)) && passouTipo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _modoCriacao ? 'Publicação' : 'Timeline',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_modoCriacao) ...[
            IconButton(
              icon: Badge(
                isLabelVisible: _searchQuery.isNotEmpty,
                smallSize: 8,
                child: const Icon(Icons.search_rounded),
              ),
              onPressed: _mostrarDialogoBusca,
              tooltip: 'Buscar',
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: _filtroTipo != 'todos',
                smallSize: 8,
                child: const Icon(Icons.filter_list_rounded),
              ),
              onPressed: _mostrarDialogoFiltro,
              tooltip: 'Filtrar',
            ),
          ],
          if (_modoCriacao)
            IconButton(
              onPressed: _uploading
                  ? null
                  : () {
                _limparFormulario();
                setState(() => _modoCriacao = false);
              },
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Fechar',
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
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'NOVA',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
      )
          : null,
    );
  }

  Widget _buildFormulario() {
    final isEditando = _editandoId != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFormHero(isEditando),
                      const SizedBox(height: 14),
                      _buildTipoSelector(),
                      const SizedBox(height: 14),
                      _buildDadosCard(),
                      const SizedBox(height: 14),
                      _buildImagensCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildSalvarBottomBar(),
      ],
    );
  }

  Widget _buildFormHero(bool isEditando) {
    final cor = _getCorPorTipo(_tipoSelecionado);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withOpacity(0.95), cor.withOpacity(0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: Icon(
              _getIconPorTipo(_tipoSelecionado),
              color: Colors.white,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                isEditando ? 'Editar publicação' : 'Nova publicação',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Preencha o conteúdo, escolha o tipo e adicione imagens para aparecer na timeline.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTipoSelector() {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.category_rounded,
            title: 'Tipo de publicação',
            subtitle: 'Escolha como esse conteúdo será identificado.',
            color: _getCorPorTipo(_tipoSelecionado),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tipos.map((tipo) {
              final selected = _tipoSelecionado == tipo;
              final cor = _getCorPorTipo(tipo);

              return ChoiceChip(
                selected: selected,
                label: Text(tipo.toUpperCase()),
                avatar: Icon(
                  _getIconPorTipo(tipo),
                  size: 16,
                  color: selected ? Colors.white : cor,
                ),
                selectedColor: cor,
                backgroundColor: cor.withOpacity(0.07),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : cor,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
                side: BorderSide(color: cor.withOpacity(0.16)),
                onSelected: (_) => setState(() => _tipoSelecionado = tipo),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDadosCard() {
    return _cardShell(
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.edit_note_rounded,
            title: 'Dados da publicação',
            subtitle: 'Título, descrição e link opcional.',
            color: Colors.purple,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _tituloController,
            label: 'Título *',
            hint: 'Ex: Roda de Capoeira de Sábado',
            icon: Icons.title_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _descricaoController,
            label: 'Descrição',
            hint: 'Descreva o evento ou publicação...',
            icon: Icons.description_rounded,
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _linkController,
            label: 'Link opcional',
            hint: 'https://exemplo.com',
            icon: Icons.link_rounded,
            keyboardType: TextInputType.url,
          ),
        ],
      ),
    );
  }

  Widget _buildImagensCard() {
    final total = _imagensUrls.length + _imagensSelecionadas.length;

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: Icons.photo_library_rounded,
            title: 'Imagens',
            subtitle: total == 0
                ? 'Adicione imagens para deixar a publicação mais bonita.'
                : '$total imagem(ns) selecionada(s).',
            color: Colors.blue,
          ),
          const SizedBox(height: 14),
          if (_imagensUrls.isNotEmpty) ...[
            _buildImagesBlock(
              title: 'Imagens atuais',
              urls: _imagensUrls,
              isLocal: false,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
          ],
          if (_imagensSelecionadas.isNotEmpty) ...[
            _buildImagesBlock(
              title: 'Novas imagens',
              files: _imagensSelecionadas,
              isLocal: true,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _selecionarImagens,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('ADICIONAR IMAGENS'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purple.shade900,
              side: BorderSide(color: Colors.purple.shade200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagesBlock({
    required String title,
    List<String>? urls,
    List<XFile>? files,
    required bool isLocal,
    required Color color,
  }) {
    final count = isLocal ? files?.length ?? 0 : urls?.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title ($count)',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = isLocal
                    ? FileImage(File(files![index].path)) as ImageProvider
                    : NetworkImage(urls![index]) as ImageProvider;

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image(
                        image: image,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 104,
                          height: 104,
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      right: 5,
                      child: InkWell(
                        onTap: () {
                          if (isLocal) {
                            _removerImagemSelecionada(index);
                          } else {
                            _removerImagemUrl(urls![index]);
                          }
                        },
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
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
    );
  }

  Widget _buildSalvarBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading
                    ? null
                    : () {
                  _limparFormulario();
                  setState(() => _modoCriacao = false);
                },
                icon: const Icon(Icons.close_rounded),
                label: const Text('CANCELAR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade800,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _salvarPublicacao,
                icon: _uploading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.publish_rounded),
                label: Text(
                  _uploading
                      ? 'SALVANDO...'
                      : _editandoId != null
                      ? 'ATUALIZAR'
                      : 'PUBLICAR',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaPublicacoes() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('timeline_publicacoes')
          .orderBy('data_publicacao', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildErrorState(snapshot.error);

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: Colors.purple.shade900),
          );
        }

        final publicacoes = snapshot.data?.docs ?? [];
        final filtradas = publicacoes.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _filtrarPublicacao(data);
        }).toList();

        if (filtradas.isEmpty) return _buildEmptyState();

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 1120 ? 1120.0 : constraints.maxWidth;
            final isWide = constraints.maxWidth >= 940;

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 94),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      children: [
                        _buildDashboardHeader(
                          total: publicacoes.length,
                          filtradas: filtradas.length,
                        ),
                        const SizedBox(height: 14),
                        if (isWide)
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: filtradas.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return SizedBox(
                                width: (maxWidth - 12) / 2,
                                child: _buildCardPublicacaoLista(data, doc.id),
                              );
                            }).toList(),
                          )
                        else
                          Column(
                            children: filtradas.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildCardPublicacaoLista(data, doc.id),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardHeader({
    required int total,
    required int filtradas,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade900, Colors.purple.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.shade900.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.timeline_rounded,
              color: Colors.white,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Gerenciar Timeline',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Crie publicações, adicione imagens e controle o portfólio no site.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(
                    icon: Icons.article_rounded,
                    label: '$filtradas exibidas',
                  ),
                  _whiteChip(
                    icon: Icons.collections_rounded,
                    label: '$total total',
                  ),
                  _whiteSwitchChip(),
                ],
              ),
              if (_searchQuery.isNotEmpty || _filtroTipo != 'todos') ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                      _filtroTipo = 'todos';
                    });
                  },
                  icon: const Icon(Icons.cleaning_services_rounded),
                  label: const Text('Limpar filtros'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _whiteSwitchChip() {
    return InkWell(
      onTap: () {
        final novo = !_exibirPortfolioNoSite;
        setState(() => _exibirPortfolioNoSite = novo);
        _salvarConfiguracaoPortfolio(novo);
      },
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _exibirPortfolioNoSite
              ? Colors.green.withOpacity(0.22)
              : Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _exibirPortfolioNoSite
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: Colors.white,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              _exibirPortfolioNoSite ? 'Site visível' : 'Site oculto',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _whiteChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPublicacaoLista(Map<String, dynamic> data, String id) {
    final imagens = List<String>.from(data['imagens'] ?? []);
    final tipo = data['tipo']?.toString() ?? 'evento';
    final corTipo = _getCorPorTipo(tipo);
    final titulo = data['titulo']?.toString() ?? 'Sem título';
    final descricao = data['descricao']?.toString() ?? '';
    final link = data['link']?.toString() ?? '';

    return InkWell(
      onTap: () => _carregarParaEdicao(data, id),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: _cardDecoration(borderColor: corTipo.withOpacity(0.12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (imagens.isNotEmpty)
                AspectRatio(
                  aspectRatio: 1.95,
                  child: Image.network(
                    imagens.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildImagemFallback(tipo, corTipo),
                  ),
                )
              else
                SizedBox(
                  height: 138,
                  child: _buildImagemFallback(tipo, corTipo),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _typeChip(tipo),
                        if (_formatarDataRelativa(data['data_publicacao']).isNotEmpty)
                          _infoChip(
                            icon: Icons.schedule_rounded,
                            label: _formatarDataRelativa(data['data_publicacao']),
                            color: Colors.grey,
                          ),
                        if (imagens.isNotEmpty)
                          _infoChip(
                            icon: Icons.image_rounded,
                            label: '${imagens.length} img',
                            color: Colors.blue,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade900,
                        fontSize: 16,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        descricao,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                          height: 1.32,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (link.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _linkPreview(link),
                    ],
                    if (imagens.length > 1) ...[
                      const SizedBox(height: 10),
                      _miniaturas(imagens.skip(1).toList()),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _carregarParaEdicao(data, id),
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('EDITAR'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue.shade700,
                              side: BorderSide(color: Colors.blue.shade100),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(fontWeight: FontWeight.w900),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _deletarPublicacao(id, imagens),
                            icon: const Icon(Icons.delete_rounded, size: 18),
                            label: const Text('EXCLUIR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(fontWeight: FontWeight.w900),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
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
      ),
    );
  }

  Widget _buildImagemFallback(String tipo, Color corTipo) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [corTipo.withOpacity(0.16), corTipo.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _getIconPorTipo(tipo),
          size: 56,
          color: corTipo.withOpacity(0.62),
        ),
      ),
    );
  }

  Widget _miniaturas(List<String> imagens) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imagens.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imagens[index],
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: Colors.grey.shade200,
                child: Icon(Icons.broken_image_rounded, color: Colors.grey.shade400),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _linkPreview(String link) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: Colors.blue.shade700, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              link,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String tipo) {
    final cor = _getCorPorTipo(tipo);

    return _infoChip(
      icon: _getIconPorTipo(tipo),
      label: tipo.toUpperCase(),
      color: cor,
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoBusca() {
    final controller = TextEditingController(text: _searchQuery);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogHandle(),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Buscar publicações',
                    hintText: 'Digite título ou descrição...',
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.purple.shade900),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onSubmitted: (value) {
                    setState(() => _searchQuery = value.trim());
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _searchQuery = controller.text.trim());
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('BUSCAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade900,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _mostrarDialogoFiltro() {
    String tipoTemp = _filtroTipo;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogHandle(),
                    const SizedBox(height: 16),
                    _sectionHeader(
                      icon: Icons.filter_list_rounded,
                      title: 'Filtrar por tipo',
                      subtitle: 'Escolha quais publicações deseja ver.',
                      color: Colors.purple,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          selected: tipoTemp == 'todos',
                          label: const Text('TODOS'),
                          selectedColor: Colors.purple.shade900,
                          labelStyle: TextStyle(
                            color: tipoTemp == 'todos'
                                ? Colors.white
                                : Colors.purple.shade900,
                            fontWeight: FontWeight.w900,
                          ),
                          onSelected: (_) => setStateDialog(() => tipoTemp = 'todos'),
                        ),
                        ..._tipos.map((tipo) {
                          final selected = tipoTemp == tipo;
                          final cor = _getCorPorTipo(tipo);

                          return ChoiceChip(
                            selected: selected,
                            label: Text(tipo.toUpperCase()),
                            avatar: Icon(
                              _getIconPorTipo(tipo),
                              size: 16,
                              color: selected ? Colors.white : cor,
                            ),
                            selectedColor: cor,
                            backgroundColor: cor.withOpacity(0.07),
                            side: BorderSide(color: cor.withOpacity(0.16)),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : cor,
                              fontWeight: FontWeight.w900,
                            ),
                            onSelected: (_) => setStateDialog(() => tipoTemp = tipo),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _filtroTipo = 'todos');
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.cleaning_services_rounded),
                            label: const Text('LIMPAR'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() => _filtroTipo = tipoTemp);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('APLICAR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade900,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dialogHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 72 : 0),
          child: Icon(icon, color: Colors.purple.shade900),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.purple.shade900, width: 1.4),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.5,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: child,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline_rounded, size: 74, color: Colors.grey.shade300),
              const SizedBox(height: 14),
              const Text(
                'Nenhuma publicação encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                _searchQuery.isNotEmpty || _filtroTipo != 'todos'
                    ? 'Tente ajustar os filtros de busca.'
                    : 'Toque em Nova para criar a primeira publicação.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 70, color: Colors.red.shade700),
              const SizedBox(height: 12),
              const Text(
                'Erro ao carregar publicações',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Tente novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: borderColor ?? Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  IconData _getIconPorTipo(String tipo) {
    switch (tipo) {
      case 'evento':
        return Icons.event_rounded;
      case 'treino':
        return Icons.fitness_center_rounded;
      case 'roda':
        return Icons.groups_rounded;
      case 'formatura':
        return Icons.school_rounded;
      case 'noticia':
        return Icons.newspaper_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Color _getCorPorTipo(String tipo) {
    switch (tipo) {
      case 'evento':
        return Colors.blue;
      case 'treino':
        return Colors.green;
      case 'roda':
        return Colors.orange;
      case 'formatura':
        return Colors.purple;
      case 'noticia':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}
