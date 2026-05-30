import 'dart:ui';

/// Representa uma área dinâmica marcada no SVG guia.
///
/// O Corel exporta a página A4 paisagem com viewBox 0 0 297 210.
/// Então x/y/width/height ficam na mesma escala do SVG:
/// largura 297 e altura 210.
class CertificadoSlotModel {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;

  const CertificadoSlotModel({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;
  Offset get center => Offset(x + (width / 2), y + (height / 2));

  bool get isValid => width > 0 && height > 0;

  CertificadoSlotModel scale({
    required double scaleX,
    required double scaleY,
  }) {
    return CertificadoSlotModel(
      id: id,
      x: x * scaleX,
      y: y * scaleY,
      width: width * scaleX,
      height: height * scaleY,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  factory CertificadoSlotModel.fromMap(Map<String, dynamic> map) {
    return CertificadoSlotModel(
      id: map['id']?.toString() ?? '',
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      width: _asDouble(map['width']),
      height: _asDouble(map['height']),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().trim().replaceAll(',', '.') ?? '';
    return double.tryParse(text) ?? 0.0;
  }

  @override
  String toString() {
    return 'CertificadoSlotModel(id: $id, x: $x, y: $y, width: $width, height: $height)';
  }
}

/// IDs dos slots que vamos procurar dentro dos SVGs guia.
///
/// Os nomes precisam bater com os ids dos retângulos exportados do Corel.
class CertificadoSlotIds {
  const CertificadoSlotIds._();

  static const String alunoNome = 'aluno_nome';
  static const String cpf = 'cpf';
  static const String graduacaoNova = 'graduacao_nova';
  static const String frase = 'frase';
  static const String localData = 'local_data';

  static const String assinatura1 = 'assinatura1';
  static const String apelido1 = 'apelido1';
  static const String assinatura2 = 'assinatura2';
  static const String apelido2 = 'apelido2';
  static const String assinatura3 = 'assinatura3';
  static const String apelido3 = 'apelido3';
  static const String assinatura4 = 'assinatura4';
  static const String apelido4 = 'apelido4';
  static const String assinatura5 = 'assinatura5';
  static const String apelido5 = 'apelido5';

  static const List<String> todos = [
    alunoNome,
    cpf,
    graduacaoNova,
    frase,
    localData,
    assinatura1,
    apelido1,
    assinatura2,
    apelido2,
    assinatura3,
    apelido3,
    assinatura4,
    apelido4,
    assinatura5,
    apelido5,
  ];
}
