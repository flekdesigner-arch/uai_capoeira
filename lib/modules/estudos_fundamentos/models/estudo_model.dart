import 'package:cloud_firestore/cloud_firestore.dart';

import 'estudo_ciclo_model.dart';

class EstudoModel {
  final String id;
  final String cicloId;
  final String cicloTituloSnapshot;
  final int numero;
  final int ordem;
  final String titulo;
  final String subtitulo;
  final String perguntaPrincipal;
  final String resumo;
  final String textoAprofundado;
  final String mitoOuFato;
  final String voceSabia;
  final String palavrasImportantes;
  final String reflexaoFinal;
  final String fontes;
  final String videoYoutubeUrl;
  final String linkExterno;
  final String capaUrl;
  final String capaStoragePath;
  final double capaFocoX;
  final double capaFocoY;
  final List<String> imagensUrls;
  final List<String> imagensStoragePaths;
  final String status;
  final bool mostrarNaLinhaDoTempo;
  final bool mostrarComoEmBreve;
  final int duracaoEstimadaMin;
  final String estudoAnteriorId;
  final String proximoEstudoId;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final String criadoPor;
  final String atualizadoPor;

  const EstudoModel({
    required this.id,
    required this.cicloId,
    required this.cicloTituloSnapshot,
    required this.numero,
    required this.ordem,
    required this.titulo,
    required this.subtitulo,
    required this.perguntaPrincipal,
    required this.resumo,
    required this.textoAprofundado,
    required this.mitoOuFato,
    required this.voceSabia,
    required this.palavrasImportantes,
    required this.reflexaoFinal,
    required this.fontes,
    required this.videoYoutubeUrl,
    required this.linkExterno,
    required this.capaUrl,
    required this.capaStoragePath,
    required this.capaFocoX,
    required this.capaFocoY,
    required this.imagensUrls,
    required this.imagensStoragePaths,
    required this.status,
    required this.mostrarNaLinhaDoTempo,
    required this.mostrarComoEmBreve,
    required this.duracaoEstimadaMin,
    required this.estudoAnteriorId,
    required this.proximoEstudoId,
    this.criadoEm,
    this.atualizadoEm,
    required this.criadoPor,
    required this.atualizadoPor,
  });

  factory EstudoModel.empty() {
    return const EstudoModel(
      id: '',
      cicloId: '',
      cicloTituloSnapshot: '',
      numero: 1,
      ordem: 1,
      titulo: '',
      subtitulo: '',
      perguntaPrincipal: '',
      resumo: '',
      textoAprofundado: '',
      mitoOuFato: '',
      voceSabia: '',
      palavrasImportantes: '',
      reflexaoFinal: '',
      fontes: '',
      videoYoutubeUrl: '',
      linkExterno: '',
      capaUrl: '',
      capaStoragePath: '',
      capaFocoX: 0.5,
      capaFocoY: 0.5,
      imagensUrls: <String>[],
      imagensStoragePaths: <String>[],
      status: EstudoCicloStatus.rascunho,
      mostrarNaLinhaDoTempo: true,
      mostrarComoEmBreve: false,
      duracaoEstimadaMin: 0,
      estudoAnteriorId: '',
      proximoEstudoId: '',
      criadoPor: '',
      atualizadoPor: '',
    );
  }

  factory EstudoModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return EstudoModel.fromMap(doc.id, doc.data());
  }

  factory EstudoModel.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final status = _text(map['status'], fallback: EstudoCicloStatus.rascunho);
    return EstudoModel(
      id: id,
      cicloId: _text(map['cicloId']),
      cicloTituloSnapshot: _text(map['cicloTituloSnapshot']),
      numero: _intValue(map['numero'], fallback: 0),
      ordem: _intValue(map['ordem'], fallback: 0),
      titulo: _text(map['titulo']),
      subtitulo: _text(map['subtitulo']),
      perguntaPrincipal: _text(map['perguntaPrincipal']),
      resumo: _text(map['resumo']),
      textoAprofundado: _text(map['textoAprofundado']),
      mitoOuFato: _text(map['mitoOuFato']),
      voceSabia: _text(map['voceSabia']),
      palavrasImportantes: _text(map['palavrasImportantes']),
      reflexaoFinal: _text(map['reflexaoFinal']),
      fontes: _text(map['fontes']),
      videoYoutubeUrl: _text(map['videoYoutubeUrl']),
      linkExterno: _text(map['linkExterno']),
      capaUrl: normalizarImagemUrl(_text(map['capaUrl'])),
      capaStoragePath: _text(map['capaStoragePath']),
      capaFocoX: _doubleClamped(map['capaFocoX'], fallback: 0.5),
      capaFocoY: _doubleClamped(map['capaFocoY'], fallback: 0.5),
      imagensUrls: normalizarListaUrls(map['imagensUrls']),
      imagensStoragePaths: normalizarListaStoragePaths(
        map['imagensStoragePaths'],
      ),
      status: EstudoCicloStatus.isValid(status)
          ? status
          : EstudoCicloStatus.rascunho,
      mostrarNaLinhaDoTempo: _boolValue(
        map['mostrarNaLinhaDoTempo'],
        fallback: true,
      ),
      mostrarComoEmBreve: _boolValue(map['mostrarComoEmBreve']),
      duracaoEstimadaMin: _intValue(map['duracaoEstimadaMin'], fallback: 0),
      estudoAnteriorId: _text(map['estudoAnteriorId']),
      proximoEstudoId: _text(map['proximoEstudoId']),
      criadoEm: _dateValue(map['criadoEm']),
      atualizadoEm: _dateValue(map['atualizadoEm']),
      criadoPor: _text(map['criadoPor']),
      atualizadoPor: _text(map['atualizadoPor']),
    );
  }

  List<String> get palavrasImportantesLista =>
      _splitItems(palavrasImportantes, splitComma: true);

  List<String> get fontesLista => _splitItems(fontes);

  bool get possuiVideo => videoYoutubeUrl.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'cicloId': cicloId,
      'cicloTituloSnapshot': cicloTituloSnapshot,
      'numero': numero,
      'ordem': ordem,
      'titulo': titulo.trim(),
      'subtitulo': subtitulo.trim(),
      'perguntaPrincipal': perguntaPrincipal.trim(),
      'resumo': resumo.trim(),
      'textoAprofundado': textoAprofundado.trim(),
      'mitoOuFato': mitoOuFato.trim(),
      'voceSabia': voceSabia.trim(),
      'palavrasImportantes': palavrasImportantes.trim(),
      'reflexaoFinal': reflexaoFinal.trim(),
      'fontes': fontes.trim(),
      'videoYoutubeUrl': videoYoutubeUrl.trim(),
      'linkExterno': linkExterno.trim(),
      'capaUrl': normalizarImagemUrl(capaUrl),
      'capaStoragePath': capaStoragePath.trim(),
      'capaFocoX': capaFocoX.clamp(0.0, 1.0),
      'capaFocoY': capaFocoY.clamp(0.0, 1.0),
      'imagensUrls': normalizarListaUrls(imagensUrls),
      'imagensStoragePaths': normalizarListaStoragePaths(imagensStoragePaths),
      'status': status,
      'mostrarNaLinhaDoTempo': mostrarNaLinhaDoTempo,
      'mostrarComoEmBreve': mostrarComoEmBreve,
      'duracaoEstimadaMin': duracaoEstimadaMin,
      'estudoAnteriorId': estudoAnteriorId,
      'proximoEstudoId': proximoEstudoId,
      'criadoPor': criadoPor,
      'atualizadoPor': atualizadoPor,
      if (criadoEm != null) 'criadoEm': Timestamp.fromDate(criadoEm!),
      if (atualizadoEm != null)
        'atualizadoEm': Timestamp.fromDate(atualizadoEm!),
    };
  }

  EstudoModel copyWith({
    String? id,
    String? cicloId,
    String? cicloTituloSnapshot,
    int? numero,
    int? ordem,
    String? titulo,
    String? subtitulo,
    String? perguntaPrincipal,
    String? resumo,
    String? textoAprofundado,
    String? mitoOuFato,
    String? voceSabia,
    String? palavrasImportantes,
    String? reflexaoFinal,
    String? fontes,
    String? videoYoutubeUrl,
    String? linkExterno,
    String? capaUrl,
    String? capaStoragePath,
    double? capaFocoX,
    double? capaFocoY,
    List<String>? imagensUrls,
    List<String>? imagensStoragePaths,
    String? status,
    bool? mostrarNaLinhaDoTempo,
    bool? mostrarComoEmBreve,
    int? duracaoEstimadaMin,
    String? estudoAnteriorId,
    String? proximoEstudoId,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
    String? criadoPor,
    String? atualizadoPor,
  }) {
    return EstudoModel(
      id: id ?? this.id,
      cicloId: cicloId ?? this.cicloId,
      cicloTituloSnapshot: cicloTituloSnapshot ?? this.cicloTituloSnapshot,
      numero: numero ?? this.numero,
      ordem: ordem ?? this.ordem,
      titulo: titulo ?? this.titulo,
      subtitulo: subtitulo ?? this.subtitulo,
      perguntaPrincipal: perguntaPrincipal ?? this.perguntaPrincipal,
      resumo: resumo ?? this.resumo,
      textoAprofundado: textoAprofundado ?? this.textoAprofundado,
      mitoOuFato: mitoOuFato ?? this.mitoOuFato,
      voceSabia: voceSabia ?? this.voceSabia,
      palavrasImportantes: palavrasImportantes ?? this.palavrasImportantes,
      reflexaoFinal: reflexaoFinal ?? this.reflexaoFinal,
      fontes: fontes ?? this.fontes,
      videoYoutubeUrl: videoYoutubeUrl ?? this.videoYoutubeUrl,
      linkExterno: linkExterno ?? this.linkExterno,
      capaUrl: capaUrl ?? this.capaUrl,
      capaStoragePath: capaStoragePath ?? this.capaStoragePath,
      capaFocoX: (capaFocoX ?? this.capaFocoX).clamp(0.0, 1.0),
      capaFocoY: (capaFocoY ?? this.capaFocoY).clamp(0.0, 1.0),
      imagensUrls: imagensUrls ?? this.imagensUrls,
      imagensStoragePaths: imagensStoragePaths ?? this.imagensStoragePaths,
      status: status ?? this.status,
      mostrarNaLinhaDoTempo:
          mostrarNaLinhaDoTempo ?? this.mostrarNaLinhaDoTempo,
      mostrarComoEmBreve: mostrarComoEmBreve ?? this.mostrarComoEmBreve,
      duracaoEstimadaMin: duracaoEstimadaMin ?? this.duracaoEstimadaMin,
      estudoAnteriorId: estudoAnteriorId ?? this.estudoAnteriorId,
      proximoEstudoId: proximoEstudoId ?? this.proximoEstudoId,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      criadoPor: criadoPor ?? this.criadoPor,
      atualizadoPor: atualizadoPor ?? this.atualizadoPor,
    );
  }

  static List<String> normalizarListaUrls(dynamic value) {
    final rawItems = <String>[];
    if (value is Iterable) {
      rawItems.addAll(value.map((item) => item?.toString() ?? ''));
    } else if (value is String) {
      rawItems.addAll(value.split(RegExp(r'\r?\n')));
    }

    final seen = <String>{};
    final urls = <String>[];
    for (final item in rawItems) {
      final url = normalizarImagemUrl(item);
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      urls.add(url);
    }
    return List.unmodifiable(urls);
  }

  static List<String> normalizarListaStoragePaths(dynamic value) {
    final rawItems = <String>[];
    if (value is Iterable) {
      rawItems.addAll(value.map((item) => item?.toString() ?? ''));
    } else if (value is String) {
      rawItems.addAll(value.split(RegExp(r'\r?\n')));
    }

    final seen = <String>{};
    final paths = <String>[];
    for (final item in rawItems) {
      final path = item.trim();
      if (path.isEmpty || seen.contains(path)) continue;
      seen.add(path);
      paths.add(path);
    }
    return List.unmodifiable(paths);
  }

  static String normalizarImagemUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';

    final uri = Uri.tryParse(text);
    final host = uri?.host.toLowerCase() ?? '';
    final hostDriveValido =
        host == 'drive.google.com' ||
        host == 'www.drive.google.com' ||
        host.endsWith('.drive.google.com');
    if (uri != null && hostDriveValido) {
      final segments = uri.pathSegments;
      final fileIndex = segments.indexOf('d');
      if (fileIndex >= 0 && fileIndex + 1 < segments.length) {
        final fileId = segments[fileIndex + 1].trim();
        if (fileId.isNotEmpty) {
          return 'https://drive.google.com/thumbnail?id=$fileId&sz=w1600';
        }
      }
      final id = uri.queryParameters['id']?.trim() ?? '';
      if (id.isNotEmpty) {
        return 'https://drive.google.com/thumbnail?id=$id&sz=w1600';
      }
    }
    return text;
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') {
      return fallback;
    }
    return text;
  }

  static bool _boolValue(dynamic value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return ['true', 'sim', '1'].contains(value.trim().toLowerCase());
    }
    return fallback;
  }

  static int _intValue(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  static List<String> _splitItems(String value, {bool splitComma = false}) {
    final normalized = splitComma ? value.replaceAll(',', '\n') : value;
    return normalized
        .split(RegExp(r'\r?\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static double _doubleClamped(dynamic value, {required double fallback}) {
    double parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(value.trim()) ?? fallback;
    } else {
      parsed = fallback;
    }
    return parsed.clamp(0.0, 1.0);
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class EstudosResumo {
  final int total;
  final int publicados;
  final int rascunhos;
  final int emBreve;
  final int ocultos;
  final int arquivados;

  const EstudosResumo({
    required this.total,
    required this.publicados,
    required this.rascunhos,
    required this.emBreve,
    required this.ocultos,
    required this.arquivados,
  });

  factory EstudosResumo.fromEstudos(List<EstudoModel> estudos) {
    return EstudosResumo(
      total: estudos.length,
      publicados: estudos
          .where((e) => e.status == EstudoCicloStatus.publicado)
          .length,
      rascunhos: estudos
          .where((e) => e.status == EstudoCicloStatus.rascunho)
          .length,
      emBreve: estudos
          .where((e) => e.status == EstudoCicloStatus.emBreve)
          .length,
      ocultos: estudos
          .where((e) => e.status == EstudoCicloStatus.oculto)
          .length,
      arquivados: estudos
          .where((e) => e.status == EstudoCicloStatus.arquivado)
          .length,
    );
  }
}
