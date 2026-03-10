import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 👈 ADICIONADO
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/campeonato_model.dart';

class RegistrarResultadoScreen extends StatefulWidget {
  final String categoriaId;
  final int chaveIndex;
  final String competidor1Id;
  final String competidor2Id;
  final String nome1;
  final String nome2;
  final String apelido1;
  final String apelido2;
  final String? fotoUrl1; // 👈 NOVO
  final String? fotoUrl2; // 👈 NOVO

  const RegistrarResultadoScreen({
    super.key,
    required this.categoriaId,
    required this.chaveIndex,
    required this.competidor1Id,
    required this.competidor2Id,
    required this.nome1,
    required this.nome2,
    required this.apelido1,
    required this.apelido2,
    this.fotoUrl1,
    this.fotoUrl2,
  });

  @override
  State<RegistrarResultadoScreen> createState() => _RegistrarResultadoScreenState();
}

class _RegistrarResultadoScreenState extends State<RegistrarResultadoScreen> {
  final CampeonatoService _campeonatoService = CampeonatoService();

  String? _vencedorId;
  bool _isRegistrando = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Resultado'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _mostrarInfo,
            tooltip: 'Informações',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // VS Grande com cores Amarelo/Azul
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  // Competidor 1 - AMARELO 🟡
                  Expanded(
                    child: _buildCompetidorButton(
                      id: widget.competidor1Id,
                      nome: widget.nome1,
                      apelido: widget.apelido1,
                      fotoUrl: widget.fotoUrl1,
                      isSelected: _vencedorId == widget.competidor1Id,
                      cor: Colors.amber.shade700,
                    ),
                  ),

                  // VS no meio
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ),

                  // Competidor 2 - AZUL 🔵
                  Expanded(
                    child: _buildCompetidorButton(
                      id: widget.competidor2Id,
                      nome: widget.nome2,
                      apelido: widget.apelido2,
                      fotoUrl: widget.fotoUrl2,
                      isSelected: _vencedorId == widget.competidor2Id,
                      cor: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Botão de confirmar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _vencedorId == null || _isRegistrando
                    ? null
                    : _registrarResultado,
                icon: const Icon(Icons.check_circle),
                label: Text(
                  _isRegistrando ? 'REGISTRANDO...' : 'CONFIRMAR RESULTADO',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
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

            const SizedBox(height: 16),

            // Botão de desistência (W.O.)
            TextButton.icon(
              onPressed: _registrarWOLosers,
              icon: const Icon(Icons.sports_score, color: Colors.orange),
              label: const Text(
                'Registrar W.O.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompetidorButton({
    required String id,
    required String nome,
    required String apelido,
    required String? fotoUrl,
    required bool isSelected,
    required Color cor,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _vencedorId = id;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? cor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cor : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Círculo com foto ou ícone
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : cor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: cor, width: 3),
              ),
              child: fotoUrl != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: CachedNetworkImage(
                  imageUrl: fotoUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) => Icon(
                    Icons.person,
                    size: 40,
                    color: isSelected ? cor : cor,
                  ),
                ),
              )
                  : Icon(
                Icons.person,
                size: 40,
                color: isSelected ? cor : cor,
              ),
            ),
            const SizedBox(height: 12),

            // Nome
            Text(
              nome,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Apelido (se tiver)
            if (apelido.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                apelido,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Badge de VENCEDOR
            if (isSelected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'VENCEDOR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _registrarResultado() async {
    if (_vencedorId == null) return;

    setState(() => _isRegistrando = true);

    try {
      await _campeonatoService.registrarResultado(
        widget.categoriaId,
        widget.chaveIndex,
        _vencedorId!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Resultado registrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Erro ao registrar resultado: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao registrar resultado'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegistrando = false);
    }
  }

  // Registrar W.O. (Walkover) - um competidor não compareceu
  Future<void> _registrarWOLosers() async {
    if (_vencedorId != null) return; // Já tem vencedor

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('⚠️ Registrar W.O.'),
        content: const Text(
            'Isso significa que um competidor não compareceu.\n'
                'Qual competidor está presente?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'competidor1'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.apelido1.isNotEmpty ? widget.apelido1 : 'COMP. 1'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'competidor2'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.apelido2.isNotEmpty ? widget.apelido2 : 'COMP. 2'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirm == null) return;

    setState(() {
      _vencedorId = confirm == 'competidor1'
          ? widget.competidor1Id
          : widget.competidor2Id;
    });

    await Future.delayed(const Duration(milliseconds: 300));
    _registrarResultado();
  }

  void _mostrarInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ℹ️ Instruções'),
        content: const Text(
            'Clique no competidor vencedor para selecioná-lo.\n\n'
                '🟡 Amarelo = Competidor 1\n'
                '🔵 Azul = Competidor 2\n\n'
                '• O botão verde confirma o resultado\n'
                '• Use W.O. se um competidor não compareceu\n'
                '• O vencedor avançará para a próxima rodada'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}