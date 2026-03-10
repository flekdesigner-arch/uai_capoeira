import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cached_network_image/cached_network_image.dart';
import 'aluno_detalhe_screen.dart';
import 'editar_aluno_screen.dart';

class AlunosScreen extends StatefulWidget {
  const AlunosScreen({super.key});

  @override
  State<AlunosScreen> createState() => _AlunosScreenState();
}

class _AlunosScreenState extends State<AlunosScreen> {
  String? _svgContent;
  String _searchQuery = '';
  String _statusFilter = 'ATIVO(A)';
  int _viewMode = 0; // 0 = Lista, 1 = Grade, 2 = Compacta
  final List<IconData> _viewModeIcons = [Icons.view_list, Icons.grid_view, Icons.format_list_bulleted];
  final List<String> _viewModeTooltips = ['Visualizar em Lista', 'Visualizar em Grade', 'Visualização Compacta'];

  // ✅ MAPA EM MEMÓRIA PARA CACHE DE CORES DAS GRADUAÇÕES - AGORA INDEXADO POR NOME
  final Map<String, Map<String, dynamic>> _graduacoesCache = {}; // Key: nome_graduacao
  final Map<String, String> _svgCache = {}; // Key: nome_graduacao
  final Map<String, bool> _graduacaoValidaCache = {}; // Key: nome_graduacao

  @override
  void initState() {
    super.initState();
    _loadSvg();
    _preloadGraduacoes();
  }

  Future<void> _loadSvg() async {
    final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
    if (mounted) {
      setState(() {
        _svgContent = content;
      });
    }
  }

  Future<void> _preloadGraduacoes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .get();

      for (var doc in snapshot.docs) {
        final nomeGraduacao = doc['nome_graduacao']?.toString();
        if (nomeGraduacao != null && nomeGraduacao.isNotEmpty) {
          _graduacoesCache[nomeGraduacao] = {
            'id': doc.id,
            'hex_cor1': doc['hex_cor1'],
            'hex_cor2': doc['hex_cor2'],
            'hex_ponta1': doc['hex_ponta1'],
            'hex_ponta2': doc['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
          };
        }
      }
      debugPrint('✅ ${_graduacoesCache.length} graduações carregadas em cache (indexadas por nome)');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações: $e');
    }
  }

  int _calculateAge(Timestamp? birthDate) {
    if (birthDate == null) return 0;
    final today = DateTime.now();
    final birth = birthDate.toDate();
    int age = today.year - birth.year;
    if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) {
      age--;
    }
    return age;
  }

  // 🔍 NOVO MÉTODO: OBTER NOME DA GRADUAÇÃO DO ALUNO
  String _obterNomeGraduacaoAluno(Map<String, dynamic> data) {
    // Prioridade 1: Nome da graduação vindo do cache/graduacoes
    final graduacaoId = data['graduacao_id']?.toString();
    if (graduacaoId != null && graduacaoId.isNotEmpty) {
      // Se temos o ID, tenta encontrar no cache por ID (mas vamos converter para nome)
      for (var entry in _graduacoesCache.entries) {
        if (entry.value['id'] == graduacaoId) {
          return entry.key; // Retorna o nome (que é a chave do cache)
        }
      }
    }

    // Prioridade 2: Campo graduacao_nome direto
    final graduacaoNome = data['graduacao_nome']?.toString();
    if (graduacaoNome != null && graduacaoNome.isNotEmpty) {
      return graduacaoNome;
    }

    // Prioridade 3: Campo graduacao_atual
    final graduacaoAtual = data['graduacao_atual']?.toString();
    if (graduacaoAtual != null && graduacaoAtual.isNotEmpty) {
      return graduacaoAtual;
    }

    // Prioridade 4: Graduação padrão
    return 'SEM GRADUAÇÃO';
  }

  // ✅ MODIFICAÇÃO: Buscar cores pelo nome da graduação
  Future<String?> _getModifiedSvg(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);

    if (nomeGraduacao.isEmpty || nomeGraduacao == 'SEM GRADUAÇÃO' || _svgContent == null) {
      return null;
    }

    final cacheKey = 'svg_$nomeGraduacao';
    if (_svgCache.containsKey(cacheKey)) {
      return _svgCache[cacheKey];
    }

    // Busca as cores da graduação pelo nome
    Map<String, dynamic>? coresGraduacao;

    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      coresGraduacao = _graduacoesCache[nomeGraduacao];
    } else {
      // Se não está no cache, busca no Firestore pelo nome
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('graduacoes')
            .where('nome_graduacao', isEqualTo: nomeGraduacao)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          final doc = querySnapshot.docs.first;
          coresGraduacao = {
            'id': doc.id,
            'hex_cor1': doc['hex_cor1'],
            'hex_cor2': doc['hex_cor2'],
            'hex_ponta1': doc['hex_ponta1'],
            'hex_ponta2': doc['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
          };
          _graduacoesCache[nomeGraduacao] = coresGraduacao;
        } else {
          // Graduação não existe na coleção
          return null;
        }
      } catch (e) {
        debugPrint('❌ Erro ao buscar graduação por nome "$nomeGraduacao": $e');
        return null;
      }
    }

    if (coresGraduacao == null) return null;

    final document = xml.XmlDocument.parse(_svgContent!);

    Color colorFromHex(String? hexColor) {
      if (hexColor == null || hexColor.length < 7) return Colors.grey;
      try {
        return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
      } catch (e) {
        return Colors.grey;
      }
    }

    void changeColor(String id, Color color) {
      final element = document.rootElement.descendants.whereType<xml.XmlElement>().firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName(''))
      );
      if (element.name.local.isNotEmpty) {
        final style = element.getAttribute('style') ?? '';
        final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
        final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
        element.setAttribute('style', 'fill:$hex;$newStyle');
      }
    }

    changeColor('cor1', colorFromHex(coresGraduacao['hex_cor1']));
    changeColor('cor2', colorFromHex(coresGraduacao['hex_cor2']));
    changeColor('corponta1', colorFromHex(coresGraduacao['hex_ponta1']));
    changeColor('corponta2', colorFromHex(coresGraduacao['hex_ponta2']));

    final svgString = document.toXmlString();
    _svgCache[cacheKey] = svgString;

    return svgString;
  }

  // ✅ Verificar se aluno tem graduação VÁLIDA - AGORA POR NOME
  Future<bool> _hasValidGraduation(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);

    if (nomeGraduacao.isEmpty || nomeGraduacao == 'SEM GRADUAÇÃO') {
      return false;
    }

    if (_graduacaoValidaCache.containsKey(nomeGraduacao)) {
      return _graduacaoValidaCache[nomeGraduacao]!;
    }

    // Verificar no cache primeiro
    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      _graduacaoValidaCache[nomeGraduacao] = true;
      return true;
    }

    // Se não está no cache, verificar no Firestore pelo nome
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .where('nome_graduacao', isEqualTo: nomeGraduacao)
          .limit(1)
          .get();

      final isValid = querySnapshot.docs.isNotEmpty;
      _graduacaoValidaCache[nomeGraduacao] = isValid;

      if (isValid) {
        final doc = querySnapshot.docs.first;
        _graduacoesCache[nomeGraduacao] = {
          'id': doc.id,
          'hex_cor1': doc['hex_cor1'],
          'hex_cor2': doc['hex_cor2'],
          'hex_ponta1': doc['hex_ponta1'],
          'hex_ponta2': doc['hex_ponta2'],
          'nome_graduacao': nomeGraduacao,
        };
      }

      return isValid;
    } catch (e) {
      debugPrint('Erro ao verificar graduação por nome "$nomeGraduacao": $e');
      _graduacaoValidaCache[nomeGraduacao] = false;
      return false;
    }
  }

  // ✅ Função para obter o nome da graduação corretamente (simplificada)
  String _getGraduacaoNome(Map<String, dynamic> data) {
    return _obterNomeGraduacaoAluno(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alunos'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_viewModeIcons[_viewMode]),
            tooltip: _viewModeTooltips[_viewMode],
            onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 3),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Cadastrar Novo Aluno',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EditarAlunoScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  tooltip: 'Filtrar por Status',
                  onSelected: (value) => setState(() => _statusFilter = value),
                  itemBuilder: (BuildContext context) {
                    return ['ATIVO(A)', 'INATIVO(A)', 'TODOS'].map((String choice) {
                      return PopupMenuItem<String>(value: choice, child: Text(choice));
                    }).toList();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('alunos').orderBy('nome').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Nenhum aluno encontrado."));
          }

          var filteredDocs = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final nome = (data['nome'] as String? ?? '').toLowerCase();
            final status = data['status_atividade'] as String? ?? '';
            return nome.contains(_searchQuery.toLowerCase()) && (_statusFilter == 'TODOS' || status == _statusFilter);
          }).toList();

          if (filteredDocs.isEmpty) {
            return const Center(child: Text("Nenhum resultado encontrado para os filtros aplicados."));
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _getCurrentView(filteredDocs),
          );
        },
      ),
    );
  }

  Widget _getCurrentView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    switch (_viewMode) {
      case 0:
        return _buildListView(docs);
      case 1:
        return _buildGridView(docs);
      case 2:
        return _buildCompactView(docs);
      default:
        return _buildListView(docs);
    }
  }

  Widget _buildListView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return ListView.builder(
      key: const ValueKey('listView'),
      padding: const EdgeInsets.all(12.0),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final aluno = docs[index];
        final data = aluno.data();
        final nomeAluno = data['nome'] ?? 'Nome não informado';
        final fotoUrl = data['foto_perfil_aluno'] as String?;
        final idade = _calculateAge(data['data_nascimento']);
        final graduacaoNome = _getGraduacaoNome(data);

        return FutureBuilder<bool>(
          future: _hasValidGraduation(data),
          builder: (context, graduationSnapshot) {
            final hasValidGraduation = graduationSnapshot.data ?? false;

            return FutureBuilder<String?>(
              future: hasValidGraduation ? _getModifiedSvg(data) : Future.value(null),
              builder: (context, svgSnapshot) {
                final modifiedSvg = svgSnapshot.data;
                final isLoadingSvg = svgSnapshot.connectionState == ConnectionState.waiting;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 3,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlunoDetalheScreen(alunoId: aluno.id))),
                    child: Row(
                      children: [
                        // FOTO COM TAG DE IDADE
                        Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              color: Colors.grey[200],
                              child: fotoUrl != null && fotoUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                imageUrl: fotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: (c, u, e) => _placeholderIcon(),
                              )
                                  : _placeholderIcon(),
                            ),
                            // TAG DE IDADE
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 24,
                                color: Colors.red.shade900.withOpacity(0.9),
                                child: Center(
                                  child: Text(
                                    '$idade ANOS',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  nomeAluno,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (graduacaoNome.isNotEmpty && graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    graduacaoNome,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // SVG DA CORDA (apenas se tiver graduação válida)
                        if (hasValidGraduation)
                          Container(
                            width: 60,
                            padding: const EdgeInsets.only(right: 12),
                            child: isLoadingSvg
                                ? const CircularProgressIndicator(strokeWidth: 2)
                                : (modifiedSvg != null
                                ? SvgPicture.string(modifiedSvg, height: 60)
                                : const SizedBox.shrink()
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGridView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return GridView.builder(
      key: const ValueKey('gridView'),
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final aluno = docs[index];
        final data = aluno.data();
        final nomeAluno = data['nome'] ?? 'Nome não informado';
        final fotoUrl = data['foto_perfil_aluno'] as String?;
        final idade = _calculateAge(data['data_nascimento']);
        final graduacaoNome = _getGraduacaoNome(data);

        return Card(
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlunoDetalheScreen(alunoId: aluno.id))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // FOTO QUE PREENCHE TODO O ESPAÇO
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        color: Colors.grey[200],
                        child: fotoUrl != null && fotoUrl.isNotEmpty
                            ? CachedNetworkImage(
                          imageUrl: fotoUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorWidget: (c, u, e) => _placeholderIcon(size: 80),
                        )
                            : _placeholderIcon(size: 80),
                      ),
                      // TAG DE IDADE
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 28,
                          color: Colors.red.shade900.withOpacity(0.9),
                          child: Center(
                            child: Text(
                              '$idade ANOS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // INFORMAÇÕES DO ALUNO
                Container(
                  padding: const EdgeInsets.all(12.0),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeAluno.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (graduacaoNome.isNotEmpty && graduacaoNome != 'SEM GRADUAÇÃO') ...[
                        const SizedBox(height: 4),
                        Text(
                          graduacaoNome,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
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
          ),
        );
      },
    );
  }

  Widget _buildCompactView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return ListView.builder(
      key: const ValueKey('compactView'),
      padding: const EdgeInsets.all(8.0),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final aluno = docs[index];
        final data = aluno.data();
        final nomeAluno = data['nome'] ?? 'Nome não informado';
        final fotoUrl = data['foto_perfil_aluno'] as String?;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          elevation: 1,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlunoDetalheScreen(alunoId: aluno.id))),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // FOTO PEQUENA
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                    ),
                    child: fotoUrl != null && fotoUrl.isNotEmpty
                        ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.cover,
                        errorWidget: (c, u, e) => Icon(Icons.person, size: 30, color: Colors.grey[400]),
                      ),
                    )
                        : Icon(Icons.person, size: 30, color: Colors.grey[400]),
                  ),

                  const SizedBox(width: 12),

                  // NOME DO ALUNO
                  Expanded(
                    child: Text(
                      nomeAluno,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // ÍCONE DE SETA
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderIcon({double size = 50}) {
    return Center(
      child: Icon(Icons.person, size: size, color: Colors.white),
    );
  }
}