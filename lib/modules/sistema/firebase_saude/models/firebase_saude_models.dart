class FirebaseSaudeResumo {
  final DateTime? timestamp;
  final String statusGeral;
  final String projeto;
  final Map<String, int> contadores;
  final Map<String, dynamic> atualizacoes;
  final Map<String, dynamic> configuracoes;
  final List<FirebaseSaudeDiagnostico> diagnosticos;
  final Map<String, dynamic> usoCustos;

  const FirebaseSaudeResumo({
    required this.timestamp,
    required this.statusGeral,
    required this.projeto,
    required this.contadores,
    required this.atualizacoes,
    required this.configuracoes,
    required this.diagnosticos,
    required this.usoCustos,
  });

  factory FirebaseSaudeResumo.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeResumo(
      timestamp: _parseDate(map['timestamp']),
      statusGeral: (map['statusGeral'] ?? 'informativo').toString(),
      projeto: (map['projeto'] ?? '').toString(),
      contadores: _intMap(map['contadores']),
      atualizacoes: _dynamicMap(map['atualizacoes']),
      configuracoes: _dynamicMap(map['configuracoes']),
      diagnosticos: _listMap(
        map['diagnosticos'],
      ).map(FirebaseSaudeDiagnostico.fromMap).toList(),
      usoCustos: _dynamicMap(map['usoCustos']),
    );
  }
}

class FirebaseSaudeColecao {
  final String nome;
  final String descricao;
  final int quantidade;
  final DateTime? ultimaAtualizacao;
  final String risco;
  final bool podeVisualizarDetalhes;

  const FirebaseSaudeColecao({
    required this.nome,
    required this.descricao,
    required this.quantidade,
    required this.ultimaAtualizacao,
    required this.risco,
    required this.podeVisualizarDetalhes,
  });

  factory FirebaseSaudeColecao.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeColecao(
      nome: (map['nome'] ?? '').toString(),
      descricao: (map['descricao'] ?? '').toString(),
      quantidade: _toInt(map['quantidade']),
      ultimaAtualizacao: _parseDate(map['ultimaAtualizacao']),
      risco: (map['risco'] ?? 'medio').toString(),
      podeVisualizarDetalhes: map['podeVisualizarDetalhes'] == true,
    );
  }
}

class FirebaseSaudeDocumento {
  final String id;
  final Map<String, dynamic> dados;

  const FirebaseSaudeDocumento({required this.id, required this.dados});

  factory FirebaseSaudeDocumento.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeDocumento(
      id: (map['id'] ?? '').toString(),
      dados: _dynamicMap(map['dados']),
    );
  }
}

class FirebaseSaudeDocumentosPage {
  final List<FirebaseSaudeDocumento> documentos;
  final String? nextPageToken;
  final bool hasMore;

  const FirebaseSaudeDocumentosPage({
    required this.documentos,
    required this.nextPageToken,
    required this.hasMore,
  });

  factory FirebaseSaudeDocumentosPage.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeDocumentosPage(
      documentos: _listMap(
        map['documentos'],
      ).map(FirebaseSaudeDocumento.fromMap).toList(),
      nextPageToken: map['nextPageToken']?.toString(),
      hasMore: map['hasMore'] == true,
    );
  }
}

class FirebaseSaudeStorageItem {
  final String nome;
  final String path;
  final int tamanho;
  final String contentType;
  final DateTime? updated;
  final String prefixo;
  final bool pasta;

  const FirebaseSaudeStorageItem({
    required this.nome,
    required this.path,
    required this.tamanho,
    required this.contentType,
    required this.updated,
    required this.prefixo,
    required this.pasta,
  });

  factory FirebaseSaudeStorageItem.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeStorageItem(
      nome: (map['nome'] ?? '').toString(),
      path: (map['path'] ?? '').toString(),
      tamanho: _toInt(map['tamanho']),
      contentType: (map['contentType'] ?? '').toString(),
      updated: _parseDate(map['updated']),
      prefixo: (map['prefixo'] ?? '').toString(),
      pasta: map['pasta'] == true,
    );
  }
}

class FirebaseSaudeFunctionInfo {
  final String nome;
  final String descricao;
  final String status;

  const FirebaseSaudeFunctionInfo({
    required this.nome,
    required this.descricao,
    required this.status,
  });

  factory FirebaseSaudeFunctionInfo.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeFunctionInfo(
      nome: (map['nome'] ?? '').toString(),
      descricao: (map['descricao'] ?? '').toString(),
      status: (map['status'] ?? 'manual').toString(),
    );
  }
}

class FirebaseSaudeDiagnostico {
  final String titulo;
  final String descricao;
  final int quantidade;
  final String nivel;
  final List<Map<String, dynamic>> exemplos;

  const FirebaseSaudeDiagnostico({
    required this.titulo,
    required this.descricao,
    required this.quantidade,
    required this.nivel,
    required this.exemplos,
  });

  factory FirebaseSaudeDiagnostico.fromMap(Map<String, dynamic> map) {
    return FirebaseSaudeDiagnostico(
      titulo: (map['titulo'] ?? '').toString(),
      descricao: (map['descricao'] ?? '').toString(),
      quantidade: _toInt(map['quantidade']),
      nivel: (map['nivel'] ?? 'info').toString(),
      exemplos: _listMap(map['exemplos']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  if (value is Map && value['_seconds'] is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value['_seconds'] as num).toInt() * 1000,
    ).toLocal();
  }
  return null;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

Map<String, int> _intMap(dynamic value) {
  final map = _dynamicMap(value);
  return map.map((key, value) => MapEntry(key, _toInt(value)));
}

Map<String, dynamic> _dynamicMap(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _listMap(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }
  return <Map<String, dynamic>>[];
}
