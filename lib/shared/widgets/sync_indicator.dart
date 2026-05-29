import 'package:flutter/material.dart';

class SyncIndicator extends StatelessWidget {
  final bool isPending;
  final bool isCompact;

  const SyncIndicator({
    super.key,
    required this.isPending,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPending) return const SizedBox.shrink();

    // Versão compacta (para cards da lista)
    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync,
              size: 14,
              color: Colors.orange.shade800,
            ),
            const SizedBox(width: 4),
            Text(
              'Aguardando',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Versão completa (para cabeçalho ou detalhes)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sync,
            size: 16,
            color: Colors.orange.shade800,
          ),
          const SizedBox(width: 8),
          const Text(
            'Aguardando sincronização',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class GlobalSyncCounter extends StatelessWidget {
  final int pendingCount;

  const GlobalSyncCounter({
    super.key,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sync,
              size: 18,
              color: Colors.amber.shade800,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pendingCount == 1
                      ? '1 aluno aguardando sincronização'
                      : '$pendingCount alunos aguardando sincronização',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Os dados serão salvos automaticamente quando a conexão for restaurada.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade700,
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