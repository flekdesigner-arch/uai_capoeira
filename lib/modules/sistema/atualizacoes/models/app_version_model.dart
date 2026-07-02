// lib/modules/sistema/atualizacoes/models/app_version_model.dart
//
// =====================================================
// 🧪 LABORATÓRIO DE ATUALIZAÇÕES - MODEL DE VERSÃO
// =====================================================
//
// Este model representa uma versão publicada ou preparada do APK.
//
// Coleção sugerida no Firestore:
//
// versoes_app/{versionId}
//
// Exemplo de ID:
// 2_0_61
//
// Exemplo de documento:
// {
//   "versionId": "2_0_61",
//   "versao": "2.0.61",
//   "build": 1,
//   "nomeArquivo": "uai_capoeira_2.0.61.apk",
//   "storagePath": "apks/uai_capoeira_2.0.61.apk",
//   "downloadUrl": "...",
//   "tamanhoBytes": 66174165,
//   "obrigatoria": false,
//   "publicada": true,
//   "canal": "producao",
//   "titulo": "Versão 2.0.61 disponível",
//   "resumo": "Controle de atualizações e notificações",
//   "melhorias": ["Melhoria 1", "Melhoria 2"],
//   "correcoes": ["Correção 1"],
//   "implementacoes": ["Implementação 1"],
//   "removidos": [],
//   "observacoes": "",
//   "criadoEm": Timestamp,
//   "publicadoEm": Timestamp,
//   "criadoPor": "...",
//   "criadoPorNome": "...",
//   "atualizadoEm": Timestamp
// }
//
// =====================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class AppVersionModel {
  final String versionId;
  final String versao;
  final int build;

  final String nomeArquivo;
  final String storagePath;
  final String downloadUrl;
  final int tamanhoBytes;

  final bool obrigatoria;
  final bool publicada;

  /// Canal da versão.
  /// Por enquanto vamos usar "producao", mas já deixamos pronto para futuro:
  /// "teste", "beta", "producao".
  final String canal;

  final String titulo;
  final String resumo;

  final List<String> melhorias;
  final List<String> correcoes;
  final List<String> implementacoes;
  final List<String> removidos;

  final String observacoes;

  final DateTime? criadoEm;
  final DateTime? publicadoEm;
  final DateTime? atualizadoEm;

  final String criadoPor;
  final String criadoPorNome;

  const AppVersionModel({
    required this.versionId,
    required this.versao,
    required this.build,
    required this.nomeArquivo,
    required this.storagePath,
    required this.downloadUrl,
    required this.tamanhoBytes,
    required this.obrigatoria,
    required this.publicada,
    required this.canal,
    required this.titulo,
    required this.resumo,
    required this.melhorias,
    required this.correcoes,
    required this.implementacoes,
    required this.removidos,
    required this.observacoes,
    required this.criadoEm,
    required this.publicadoEm,
    required this.atualizadoEm,
    required this.criadoPor,
    required this.criadoPorNome,
  });

  factory AppVersionModel.empty({String versao = '', int build = 1}) {
    final id = gerarVersionId(versao);

    return AppVersionModel(
      versionId: id,
      versao: versao,
      build: build,
      nomeArquivo: versao.trim().isEmpty ? '' : 'uai_capoeira_$versao.apk',
      storagePath: versao.trim().isEmpty ? '' : 'apks/uai_capoeira_$versao.apk',
      downloadUrl: '',
      tamanhoBytes: 0,
      obrigatoria: false,
      publicada: false,
      canal: 'producao',
      titulo: versao.trim().isEmpty
          ? 'Nova versão disponível'
          : 'Versão $versao disponível',
      resumo: '',
      melhorias: const [],
      correcoes: const [],
      implementacoes: const [],
      removidos: const [],
      observacoes: '',
      criadoEm: null,
      publicadoEm: null,
      atualizadoEm: null,
      criadoPor: '',
      criadoPorNome: '',
    );
  }

  factory AppVersionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return AppVersionModel.fromMap(data, fallbackId: doc.id);
  }

  factory AppVersionModel.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final versao = _asString(map['versao']);

    return AppVersionModel(
      versionId: _asString(map['versionId']).isNotEmpty
          ? _asString(map['versionId'])
          : (fallbackId ?? gerarVersionId(versao)),
      versao: versao,
      build: _asInt(map['build'], fallback: 1),
      nomeArquivo: _asString(map['nomeArquivo']),
      storagePath: _asString(map['storagePath']),
      downloadUrl: _asString(map['downloadUrl']),
      tamanhoBytes: _asInt(map['tamanhoBytes']),
      obrigatoria: _asBool(map['obrigatoria']),
      publicada: _asBool(map['publicada']),
      canal: _asString(map['canal'], fallback: 'producao'),
      titulo: _asString(
        map['titulo'],
        fallback: versao.isEmpty
            ? 'Nova versão disponível'
            : 'Versão $versao disponível',
      ),
      resumo: _asString(map['resumo']),
      melhorias: _asStringList(map['melhorias']),
      correcoes: _asStringList(map['correcoes']),
      implementacoes: _asStringList(map['implementacoes']),
      removidos: _asStringList(map['removidos']),
      observacoes: _asString(map['observacoes']),
      criadoEm: _asDateTime(map['criadoEm']),
      publicadoEm: _asDateTime(map['publicadoEm']),
      atualizadoEm: _asDateTime(map['atualizadoEm']),
      criadoPor: _asString(map['criadoPor']),
      criadoPorNome: _asString(map['criadoPorNome']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'versionId': versionId,
      'versao': versao,
      'build': build,
      'nomeArquivo': nomeArquivo,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'tamanhoBytes': tamanhoBytes,
      'obrigatoria': obrigatoria,
      'publicada': publicada,
      'canal': canal,
      'titulo': titulo,
      'resumo': resumo,
      'melhorias': melhorias,
      'correcoes': correcoes,
      'implementacoes': implementacoes,
      'removidos': removidos,
      'observacoes': observacoes,
      'criadoEm': criadoEm == null ? null : Timestamp.fromDate(criadoEm!),
      'publicadoEm': publicadoEm == null
          ? null
          : Timestamp.fromDate(publicadoEm!),
      'atualizadoEm': atualizadoEm == null
          ? null
          : Timestamp.fromDate(atualizadoEm!),
      'criadoPor': criadoPor,
      'criadoPorNome': criadoPorNome,
    };
  }

  /// Mapa usado para criar uma versão no Firestore.
  /// Usa FieldValue.serverTimestamp() para datas criadas no servidor.
  Map<String, dynamic> toCreateMap({
    required String usuarioId,
    required String usuarioNome,
  }) {
    return {
      ...toMap(),
      'criadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
      'criadoPor': usuarioId,
      'criadoPorNome': usuarioNome,
    };
  }

  /// Mapa usado para publicar uma versão.
  /// Este mapa atualiza o documento da versão em versoes_app/{id}.
  Map<String, dynamic> toPublishMap({
    required String downloadUrl,
    required String storagePath,
    required String nomeArquivo,
    required int tamanhoBytes,
    required bool obrigatoria,
  }) {
    return {
      'downloadUrl': downloadUrl,
      'storagePath': storagePath,
      'nomeArquivo': nomeArquivo,
      'tamanhoBytes': tamanhoBytes,
      'obrigatoria': obrigatoria,
      'publicada': true,
      'publicadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    };
  }

  /// Mapa usado para atualizar configuracoes/app.
  /// Mantém compatibilidade com seu sistema atual que já lê versao_atual.
  Map<String, dynamic> toConfigAppMap({
    required String usuarioId,
    required String usuarioNome,
  }) {
    return {
      'versao_atual': versao,
      'versao_minima_obrigatoria': obrigatoria ? versao : FieldValue.delete(),
      'ultima_versao_id': versionId,
      'atualizacao_obrigatoria': obrigatoria,
      'titulo_atualizacao': titulo,
      'mensagem_atualizacao': resumo,
      'apk_url': downloadUrl,
      'apk_path': storagePath,
      'apk_nome_arquivo': nomeArquivo,
      'apk_tamanho_bytes': tamanhoBytes,
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por': usuarioId,
      'atualizado_por_nome': usuarioNome,
    };
  }

  AppVersionModel copyWith({
    String? versionId,
    String? versao,
    int? build,
    String? nomeArquivo,
    String? storagePath,
    String? downloadUrl,
    int? tamanhoBytes,
    bool? obrigatoria,
    bool? publicada,
    String? canal,
    String? titulo,
    String? resumo,
    List<String>? melhorias,
    List<String>? correcoes,
    List<String>? implementacoes,
    List<String>? removidos,
    String? observacoes,
    DateTime? criadoEm,
    DateTime? publicadoEm,
    DateTime? atualizadoEm,
    String? criadoPor,
    String? criadoPorNome,
  }) {
    final novaVersao = versao ?? this.versao;
    final novoId = versionId ?? this.versionId;

    return AppVersionModel(
      versionId: novoId.isNotEmpty ? novoId : gerarVersionId(novaVersao),
      versao: novaVersao,
      build: build ?? this.build,
      nomeArquivo: nomeArquivo ?? this.nomeArquivo,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      tamanhoBytes: tamanhoBytes ?? this.tamanhoBytes,
      obrigatoria: obrigatoria ?? this.obrigatoria,
      publicada: publicada ?? this.publicada,
      canal: canal ?? this.canal,
      titulo: titulo ?? this.titulo,
      resumo: resumo ?? this.resumo,
      melhorias: melhorias ?? this.melhorias,
      correcoes: correcoes ?? this.correcoes,
      implementacoes: implementacoes ?? this.implementacoes,
      removidos: removidos ?? this.removidos,
      observacoes: observacoes ?? this.observacoes,
      criadoEm: criadoEm ?? this.criadoEm,
      publicadoEm: publicadoEm ?? this.publicadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      criadoPor: criadoPor ?? this.criadoPor,
      criadoPorNome: criadoPorNome ?? this.criadoPorNome,
    );
  }

  bool get temApk =>
      storagePath.trim().isNotEmpty && downloadUrl.trim().isNotEmpty;

  bool get podePublicar {
    return versao.trim().isNotEmpty &&
        nomeArquivo.trim().isNotEmpty &&
        storagePath.trim().isNotEmpty &&
        downloadUrl.trim().isNotEmpty &&
        tamanhoBytes > 0;
  }

  String get tamanhoFormatado {
    if (tamanhoBytes <= 0) return '0 MB';

    final mb = tamanhoBytes / 1024 / 1024;

    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(2)} GB';
    }

    return '${mb.toStringAsFixed(2)} MB';
  }

  String get statusLabel {
    if (!publicada) return 'Rascunho';
    if (obrigatoria) return 'Obrigatória';
    return 'Opcional';
  }

  static String gerarVersionId(String versao) {
    final limpa = versao.trim();

    if (limpa.isEmpty) return '';

    return limpa
        .replaceAll('.', '_')
        .replaceAll('-', '_')
        .replaceAll('+', '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  }

  static String gerarNomeArquivo(String versao) {
    return 'uai_capoeira_${versao.trim()}.apk';
  }

  static String gerarStoragePath(String versao) {
    return 'apks/${gerarNomeArquivo(versao)}';
  }

  static bool versaoValida(String versao) {
    return RegExp(r'^\d+\.\d+\.\d+$').hasMatch(versao.trim());
  }

  static int compararVersoes(String atual, String nova) {
    try {
      final atualParts = atual.split('.').map(int.parse).toList();
      final novaParts = nova.split('.').map(int.parse).toList();

      final maxLength = atualParts.length > novaParts.length
          ? atualParts.length
          : novaParts.length;

      for (int i = 0; i < maxLength; i++) {
        final atualValue = i < atualParts.length ? atualParts[i] : 0;
        final novaValue = i < novaParts.length ? novaParts[i] : 0;

        if (novaValue > atualValue) return 1;
        if (novaValue < atualValue) return -1;
      }

      return 0;
    } catch (_) {
      return 0;
    }
  }

  static bool precisaAtualizar({
    required String versaoLocal,
    required String versaoRemota,
  }) {
    return compararVersoes(versaoLocal, versaoRemota) == 1;
  }

  static String _asString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;

    if (value is int) return value;

    if (value is double) return value.round();

    return int.tryParse(value.toString()) ?? fallback;
  }

  static bool _asBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;

    if (value is bool) return value;

    final text = value.toString().trim().toLowerCase();

    if (text == 'true' || text == '1' || text == 'sim') return true;
    if (text == 'false' || text == '0' || text == 'nao' || text == 'não') {
      return false;
    }

    return fallback;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) return value.toDate();

    if (value is DateTime) return value;

    return DateTime.tryParse(value.toString());
  }

  static List<String> _asStringList(dynamic value) {
    if (value == null) return const [];

    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    final text = value.toString().trim();

    if (text.isEmpty) return const [];

    return text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
