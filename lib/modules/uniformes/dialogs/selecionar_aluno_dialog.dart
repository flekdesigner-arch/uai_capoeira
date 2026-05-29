import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class SelecionarAlunoDialog extends StatefulWidget {
  final Color corTema;

  const SelecionarAlunoDialog({
    super.key,
    this.corTema = Colors.green, // Valor padrão será ignorado internamente em favor do tema
  });

  @override
  State<SelecionarAlunoDialog> createState() => _SelecionarAlunoDialogState();
}

class _SelecionarAlunoDialogState extends State<SelecionarAlunoDialog> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _selectedTurmaId;
  List<Map<String, dynamic>> _turmasDisponiveis = [];

  // Helpers de contraste
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _mostrarFotoAmpliada(String? fotoUrl, String nome) async {
    if (fotoUrl == null || fotoUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$nome não possui foto'),
          duration: const Duration(seconds: 1),
          backgroundColor: context.uai.info,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Container(
          color: Colors.black87, // overlay escuro fixo para contraste com a foto
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: CachedNetworkImage(
              imageUrl: fotoUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white, size: 80),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Usa a cor do tema do módulo, mas o parâmetro corTema pode ser usado se realmente desejado.
    // Para manter a compatibilidade, usaremos widget.corTema como fallback se não houver token equivalente.
    // Porém, como o projeto pede tokens, assumimos que quem chama vai passar a cor do tema.
    // Vamos usar widget.corTema como cor de destaque, mas com contraste seguro.
    final Color corDestaque = widget.corTema; // pode vir de context.uai.success, etc.
    final Color corDestaqueFg = _readableOn(corDestaque);
    final Color textPrimary = context.uai.textPrimary;
    final Color textSecondary = context.uai.textSecondary;
    final Color textMuted = context.uai.textMuted;
    final Color cardAlt = context.uai.cardAlt;
    final Color border = context.uai.border;
    final Color surface = context.uai.surface;
    final Color primary = context.uai.primary;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Cabeçalho temático
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: corDestaque,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(context.uai.cardRadius),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: corDestaqueFg),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      'SELECIONAR ALUNO',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: corDestaqueFg,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: corDestaqueFg),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            // Chips de turmas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('alunos')
                    .where('status_atividade', isEqualTo: 'ATIVO(A)')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final turmas = <String, String>{};
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final turmaId = data['turma_id'] as String?;
                    final turmaNome = data['turma'] as String?;
                    if (turmaId != null && turmaNome != null) {
                      turmas[turmaId] = turmaNome;
                    }
                  }
                  _turmasDisponiveis = turmas.entries
                      .map((e) => {'id': e.key, 'nome': e.value})
                      .toList()
                    ..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTurmaChip(null, 'Todas', corDestaque, corDestaqueFg),
                        ..._turmasDisponiveis.map((turma) {
                          return _buildTurmaChip(
                              turma['id'] as String, turma['nome'] as String,
                              corDestaque, corDestaqueFg);
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Campo de busca
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Pesquisar aluno...',
                  hintStyle: TextStyle(color: textMuted),
                  prefixIcon: Icon(Icons.search, color: textMuted),
                  filled: true,
                  fillColor: cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.uai.inputRadius),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.uai.inputRadius),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.uai.inputRadius),
                    borderSide: BorderSide(color: primary, width: 1.4),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: Icon(Icons.clear, color: textMuted),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            // Lista de alunos
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('alunos')
                    .where('status_atividade', isEqualTo: 'ATIVO(A)')
                    .orderBy('nome')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 50, color: context.uai.error),
                          const SizedBox(height: 16),
                          Text('Erro: ${snapshot.error}', style: TextStyle(color: textPrimary)),
                          ElevatedButton(
                            onPressed: () => Navigator.maybePop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: _readableOn(primary),
                            ),
                            child: const Text('Voltar'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: primary));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 50, color: textMuted),
                          const SizedBox(height: 16),
                          Text('Nenhum aluno ativo encontrado', style: TextStyle(color: textSecondary)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.maybePop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: _readableOn(primary),
                            ),
                            child: const Text('Voltar'),
                          ),
                        ],
                      ),
                    );
                  }

                  var alunos = snapshot.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    if (_selectedTurmaId != null && data['turma_id'] != _selectedTurmaId) {
                      return false;
                    }
                    if (_searchQuery.isNotEmpty) {
                      final nome = data['nome']?.toString().toLowerCase() ?? '';
                      return nome.contains(_searchQuery.toLowerCase());
                    }
                    return true;
                  }).toList();

                  if (alunos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 50, color: textMuted),
                          const SizedBox(height: 16),
                          Text('Nenhum aluno encontrado', style: TextStyle(color: textSecondary)),
                          const SizedBox(height: 8),
                          if (_selectedTurmaId != null)
                            TextButton(
                              onPressed: () => setState(() => _selectedTurmaId = null),
                              child: Text('Mostrar todas as turmas', style: TextStyle(color: primary)),
                            )
                          else
                            ElevatedButton(
                              onPressed: () => Navigator.maybePop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: _readableOn(primary),
                              ),
                              child: const Text('Voltar'),
                            ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: alunos.length,
                    itemBuilder: (context, index) {
                      var doc = alunos[index];
                      var data = doc.data() as Map<String, dynamic>;
                      final nome = data['nome']?.toString() ?? 'Sem nome';
                      final turma = data['turma']?.toString() ?? 'Sem turma';
                      final fotoUrl = data['foto_perfil_aluno'] as String?;
                      final apelido = data['apelido'] as String?;

                      Widget avatar = fotoUrl != null && fotoUrl.isNotEmpty
                          ? GestureDetector(
                        onLongPress: () => _mostrarFotoAmpliada(fotoUrl, nome),
                        child: CachedNetworkImage(
                          imageUrl: fotoUrl,
                          imageBuilder: (context, imageProvider) => CircleAvatar(
                            backgroundImage: imageProvider,
                            radius: 24,
                          ),
                          placeholder: (_, __) => CircleAvatar(
                            backgroundColor: corDestaque.withOpacity(0.2),
                            radius: 24,
                            child: Text(
                              nome[0].toUpperCase(),
                              style: TextStyle(color: corDestaque),
                            ),
                          ),
                          errorWidget: (_, __, ___) => CircleAvatar(
                            backgroundColor: corDestaque.withOpacity(0.2),
                            radius: 24,
                            child: Text(
                              nome[0].toUpperCase(),
                              style: TextStyle(color: corDestaque),
                            ),
                          ),
                        ),
                      )
                          : CircleAvatar(
                        backgroundColor: corDestaque.withOpacity(0.2),
                        radius: 24,
                        child: Text(
                          nome[0].toUpperCase(),
                          style: TextStyle(color: corDestaque),
                        ),
                      );

                      return ListTile(
                        leading: avatar,
                        title: Text(nome, style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary)),
                        subtitle: Text(
                          apelido != null && apelido.isNotEmpty ? '$turma • $apelido' : turma,
                          style: TextStyle(color: textSecondary),
                        ),
                        onTap: () {
                          Navigator.pop(context, <String, String>{
                            'id': doc.id,
                            'nome': nome,
                            'foto_url': fotoUrl ?? '',
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurmaChip(String? turmaId, String label, Color cor, Color corFg) {
    final bool isSelected = _selectedTurmaId == turmaId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? corFg : context.uai.textPrimary,
          ),
        ),
        selected: isSelected,
        selectedColor: cor,
        backgroundColor: context.uai.cardAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? cor : context.uai.border),
        ),
        onSelected: (selected) {
          setState(() {
            _selectedTurmaId = selected ? turmaId : null;
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
    );
  }
}