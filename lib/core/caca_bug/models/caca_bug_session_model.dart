import 'package:cloud_firestore/cloud_firestore.dart';

class CacaBugSessionModel {
  final String sessaoId;
  final String uid;
  final String? email;
  final String? nome;
  final DateTime inicioEm;
  final DateTime? fimEm;
  final DateTime? ultimoEventoEm;
  final bool ativo;
  final String plataforma;
  final String appVersion;
  final String buildNumber;
  final Map<String, dynamic> deviceInfo;
  final String? userAgent;
  final int eventosCount;
  final int errosCount;
  final String? ultimaTela;
  final String? ultimoArquivo;
  final String? ultimoEventoResumo;
  final bool arquivada;
  final DateTime? arquivadaEm;
  final String? finalizadaPor;

  const CacaBugSessionModel({
    required this.sessaoId,
    required this.uid,
    this.email,
    this.nome,
    required this.inicioEm,
    this.fimEm,
    this.ultimoEventoEm,
    required this.ativo,
    required this.plataforma,
    required this.appVersion,
    required this.buildNumber,
    required this.deviceInfo,
    this.userAgent,
    required this.eventosCount,
    required this.errosCount,
    this.ultimaTela,
    this.ultimoArquivo,
    this.ultimoEventoResumo,
    this.arquivada = false,
    this.arquivadaEm,
    this.finalizadaPor,
  });

  factory CacaBugSessionModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? toDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final fimEm = toDate(map['fimEm']);

    return CacaBugSessionModel(
      sessaoId: map['sessaoId']?.toString() ?? id,
      uid: map['uid']?.toString() ?? '',
      email: map['email']?.toString(),
      nome: map['nome']?.toString(),
      inicioEm: toDate(map['inicioEm']) ?? DateTime.now(),
      fimEm: fimEm,
      ultimoEventoEm: toDate(map['ultimoEventoEm']),
      ativo: map['ativo'] == true && fimEm == null,
      plataforma: map['plataforma']?.toString() ?? 'desconhecida',
      appVersion: map['appVersion']?.toString() ?? '',
      buildNumber: map['buildNumber']?.toString() ?? '',
      deviceInfo: Map<String, dynamic>.from(
        map['deviceInfo'] as Map? ?? const {},
      ),
      userAgent: map['userAgent']?.toString(),
      eventosCount: map['eventosCount'] is num
          ? (map['eventosCount'] as num).toInt()
          : 0,
      errosCount: map['errosCount'] is num
          ? (map['errosCount'] as num).toInt()
          : 0,
      ultimaTela: map['ultimaTela']?.toString(),
      ultimoArquivo: map['ultimoArquivo']?.toString(),
      ultimoEventoResumo: map['ultimoEventoResumo']?.toString(),
      arquivada: map['arquivada'] == true,
      arquivadaEm: toDate(map['arquivadaEm']),
      finalizadaPor: map['finalizadaPor']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessaoId': sessaoId,
      'uid': uid,
      'email': email,
      'nome': nome,
      'inicioEm': Timestamp.fromDate(inicioEm),
      'fimEm': fimEm == null ? null : Timestamp.fromDate(fimEm!),
      'ultimoEventoEm': ultimoEventoEm == null
          ? null
          : Timestamp.fromDate(ultimoEventoEm!),
      'ativo': ativo,
      'plataforma': plataforma,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'deviceInfo': deviceInfo,
      'userAgent': userAgent,
      'eventosCount': eventosCount,
      'errosCount': errosCount,
      'ultimaTela': ultimaTela,
      'ultimoArquivo': ultimoArquivo,
      'ultimoEventoResumo': ultimoEventoResumo,
      'arquivada': arquivada,
      'arquivadaEm': arquivadaEm == null
          ? null
          : Timestamp.fromDate(arquivadaEm!),
      'finalizadaPor': finalizadaPor,
      'criadoEm': Timestamp.fromDate(inicioEm),
    };
  }
}
