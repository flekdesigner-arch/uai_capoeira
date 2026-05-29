import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';
import 'fornecedor_form_screen.dart';

class FornecedoresListScreen extends StatefulWidget {
  const FornecedoresListScreen({super.key});

  @override
  State<FornecedoresListScreen> createState() => _FornecedoresListScreenState();
}

class _FornecedoresListScreenState extends State<FornecedoresListScreen> {
  final FornecedorService _fornecedorService = FornecedorService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers de contraste
  // ---------------------------------------------------------------------------
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  // ---------------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------------
  Future<void> _excluirFornecedor(String fornecedorId, String nome) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.uai.surface,
          title: Text(
            'Excluir fornecedor',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Tem certeza que deseja excluir "$nome"?',
            style: TextStyle(color: context.uai.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancelar',
                style: TextStyle(color: context.uai.textPrimary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.uai.error,
                foregroundColor: _readableOn(context.uai.error),
              ),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) return;

    try {
      await _fornecedorService.excluirFornecedor(fornecedorId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Fornecedor excluído!'),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _abrirFormulario({
    String? fornecedorId,
    Map<String, dynamic>? fornecedorData,
  }) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FornecedorFormScreen(
          fornecedorId: fornecedorId,
          fornecedorData: fornecedorData,
        ),
      ),
    );
    if (result == true) {
      // StreamBuilder já atualiza automaticamente,
      // mas mantemos setState para compatibilidade com callbacks existentes.
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FORNECEDORES',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Novo fornecedor',
            onPressed: () => _abrirFormulario(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Campo de busca
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: context.uai.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar fornecedor...',
                hintStyle: TextStyle(color: context.uai.textMuted),
                prefixIcon:
                Icon(Icons.search, color: context.uai.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear,
                      color: context.uai.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
                filled: true,
                fillColor: context.uai.cardAlt,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(context.uai.inputRadius),
                  borderSide: BorderSide(color: context.uai.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(context.uai.inputRadius),
                  borderSide: BorderSide(color: context.uai.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(context.uai.inputRadius),
                  borderSide:
                  BorderSide(color: context.uai.primary, width: 1.4),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // Lista de fornecedores
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fornecedorService.getFornecedoresAtivos(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Erro: ${snapshot.error}',
                      style: TextStyle(color: context.uai.error),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var fornecedores = snapshot.data!.docs;
                if (_searchQuery.isNotEmpty) {
                  fornecedores = fornecedores.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final nome =
                        data['nome']?.toString().toLowerCase() ?? '';
                    return nome.contains(_searchQuery.toLowerCase());
                  }).toList();
                }

                if (fornecedores.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum fornecedor encontrado',
                      style: TextStyle(color: context.uai.textSecondary),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: fornecedores.length,
                  itemBuilder: (_, index) {
                    final doc = fornecedores[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final nome = data['nome'] ?? 'Sem nome';
                    final contato = data['contato'] ?? '';
                    final telefone = data['telefone'] ?? '';

                    // Card com ListTile usando sombra do tema
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              context.uai.cardRadius),
                          boxShadow: context.uai.cardShadow,
                        ),
                        child: Material(
                          color: context.uai.card,
                          borderRadius: BorderRadius.circular(
                              context.uai.cardRadius),
                          clipBehavior: Clip.antiAlias,
                          elevation: 0, // sombra já aplicada no Container externo
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  context.uai.cardRadius),
                              border: Border.all(color: context.uai.border),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: context.uai.primary,
                                child: Icon(
                                  Icons.business,
                                  color: _readableOn(context.uai.primary),
                                ),
                              ),
                              title: Text(
                                nome,
                                style: TextStyle(
                                    color: context.uai.textPrimary),
                              ),
                              subtitle: Text(
                                '$contato${telefone.isNotEmpty ? ' • $telefone' : ''}',
                                style: TextStyle(
                                    color: context.uai.textSecondary),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'editar') {
                                    _abrirFormulario(
                                        fornecedorId: doc.id,
                                        fornecedorData: data);
                                  } else if (value == 'excluir') {
                                    _excluirFornecedor(doc.id, nome);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'editar',
                                      child: Text('Editar')),
                                  PopupMenuItem(
                                      value: 'excluir',
                                      child: Text('Excluir')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}