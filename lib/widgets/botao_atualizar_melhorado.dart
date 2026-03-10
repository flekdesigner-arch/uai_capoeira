// widgets/botao_atualizar_melhorado.dart
import 'package:flutter/material.dart';
import 'package:uai_capoeira/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/services/versao_service.dart';

class BotaoAtualizarMelhorado extends StatefulWidget {
  const BotaoAtualizarMelhorado({super.key});

  @override
  State<BotaoAtualizarMelhorado> createState() => _BotaoAtualizarMelhoradoState();
}

class _BotaoAtualizarMelhoradoState extends State<BotaoAtualizarMelhorado>
    with SingleTickerProviderStateMixin {
  final VersaoService _versaoService = VersaoService();
  final AtualizacaoDiretaService _atualizacaoService = AtualizacaoDiretaService();

  bool _verificando = false;
  Map<String, dynamic>? _infoAtualizacao;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _verificarAtualizacao();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _verificarAtualizacao() async {
    if (_verificando) return;

    setState(() => _verificando = true);

    try {
      final versaoLocal = await _versaoService.getVersaoLocal();
      final info = await _atualizacaoService.verificarAtualizacao(versaoLocal);

      if (mounted) setState(() {
        _infoAtualizacao = info;
        _verificando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _mostrarDialogAtualizacao(BuildContext context) async {
    if (_infoAtualizacao == null) return;

    final podeAtualizar = _infoAtualizacao!['podeAtualizar'] as bool;
    final ultimaVersao = _infoAtualizacao!['ultimaVersao'] as String;
    final versaoAtual = _infoAtualizacao!['versaoAtual'] as String;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(podeAtualizar ? Icons.system_update : Icons.check_circle,
                color: podeAtualizar ? Colors.orange : Colors.green, size: 22),
            const SizedBox(width: 8),
            Text(podeAtualizar ? 'Atualização' : 'Atualizado',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoLinha('Atual', versaoAtual),
            const SizedBox(height: 8),
            if (podeAtualizar) _buildInfoLinha('Nova', ultimaVersao, destaque: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR', style: TextStyle(fontSize: 12)),
          ),
          if (podeAtualizar)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _atualizacaoService.baixarEInstalarComFeedback(context, ultimaVersao);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(80, 32),
              ),
              child: const Text('ATUALIZAR', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoLinha(String rotulo, String valor, {bool destaque = false}) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: destaque ? Colors.orange.shade100 : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            destaque ? Icons.new_releases : Icons.info_outline,
            size: 12,
            color: destaque ? Colors.orange.shade800 : Colors.grey.shade700,
          ),
        ),
        const SizedBox(width: 8),
        Text('$rotulo: ', style: const TextStyle(fontSize: 12)),
        Text(valor,
            style: TextStyle(fontSize: 12,
              fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
              color: destaque ? Colors.orange.shade800 : null,
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
            SizedBox(width: 6),
            Text('Verificando...', style: TextStyle(fontSize: 10)),
          ],
        ),
      );
    }

    final podeAtualizar = _infoAtualizacao?['podeAtualizar'] as bool? ?? false;
    final ultimaVersao = _infoAtualizacao?['ultimaVersao'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: podeAtualizar
              ? [Colors.orange.shade700, Colors.orange.shade500]
              : [Colors.green.shade700, Colors.green.shade500],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: podeAtualizar ? () => _mostrarDialogAtualizacao(context) : null,
          borderRadius: BorderRadius.circular(30),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: podeAtualizar ? _pulseAnimation.value : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        podeAtualizar ? Icons.system_update : Icons.check_circle,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          podeAtualizar ? 'v$ultimaVersao' : 'Atualizado',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (podeAtualizar) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'NOVO',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}