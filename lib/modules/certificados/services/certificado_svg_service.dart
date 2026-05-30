import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/modules/certificados/data/certificado_template_assets.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_slot_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';

/// Serviço responsável por carregar e manipular os SVGs de certificado.
///
/// PONTO IMPORTANTE:
/// A partir desta versão, a coloração do SVG final é feita por substituição
/// de texto nos elementos com id `cor1`, `cor2` e `contornocorda`.
///
/// Motivo:
/// O SVG exportado do Corel tem muitos paths grandes, gradientes e linhas
/// pontilhadas no grupo `fixo`. Quando a gente parseia o SVG inteiro e salva
/// novamente com XML, alguns renderizadores podem interpretar diferente.
/// Então preservamos o SVG original praticamente intacto e trocamos somente
/// os fills dos ids dinâmicos.
class CertificadoSvgService {
  const CertificadoSvgService();

  Future<String> carregarTemplate(CertificadoTemplateTipo tipo) {
    return rootBundle.loadString(CertificadoTemplateAssets.templatePath(tipo));
  }

  Future<String> carregarGuia(CertificadoTemplateTipo tipo) {
    return rootBundle.loadString(CertificadoTemplateAssets.guiaPath(tipo));
  }

  Future<String> gerarPreviewColorido({
    required CertificadoTemplateTipo tipo,
    required Color cor1,
    required Color cor2,
    Color? corContorno,
  }) async {
    final svg = await carregarTemplate(tipo);

    return colorirSvg(
      svg,
      cor1: cor1,
      cor2: cor2,
      corContorno: corContorno ?? const Color(0xFF373435),
    );
  }

  String colorirSvg(
      String svg, {
        required Color cor1,
        required Color cor2,
        required Color corContorno,
      }) {
    if (svg.trim().isEmpty) return svg;

    var result = svg;

    result = _replaceFillById(result, 'cor1', _colorToHex(cor1));
    result = _replaceFillById(result, 'cor2', _colorToHex(cor2));
    result = _replaceFillById(result, 'contornocorda', _colorToHex(corContorno));

    return result;
  }

  /// Troca o fill apenas do elemento que tem o id informado.
  ///
  /// Exemplo:
  /// <path id="cor1" ... fill="#FFF212"/>
  ///
  /// vira:
  /// <path id="cor1" ... fill="#0000FF"/>
  ///
  /// O restante do SVG fica intacto.
  String _replaceFillById(String svg, String id, String hex) {
    final regex = RegExp(
      r'(<[a-zA-Z][^>]*\bid="' + RegExp.escape(id) + r'"[^>]*)(/?>)',
      multiLine: true,
    );

    return svg.replaceFirstMapped(regex, (match) {
      var tagStart = match.group(1) ?? '';
      final tagEnd = match.group(2) ?? '>';

      tagStart = _upsertXmlAttribute(tagStart, 'fill', hex);

      // Se este elemento tiver stroke próprio, acompanha a mesma cor.
      // Se não tiver, não criamos stroke para não alterar arte original.
      if (RegExp(r'\bstroke="[^"]*"').hasMatch(tagStart)) {
        tagStart = _upsertXmlAttribute(tagStart, 'stroke', hex);
      }

      // Se tiver style com fill/stroke, também troca dentro do style.
      tagStart = _upsertStylePaintIfExists(tagStart, 'fill', hex);
      tagStart = _upsertStylePaintIfExists(tagStart, 'stroke', hex);

      return '$tagStart$tagEnd';
    });
  }

  String _upsertXmlAttribute(String tagStart, String attr, String value) {
    final attrRegex = RegExp(r'\b' + RegExp.escape(attr) + r'="[^"]*"');

    if (attrRegex.hasMatch(tagStart)) {
      return tagStart.replaceFirst(attrRegex, '$attr="$value"');
    }

    return '$tagStart $attr="$value"';
  }

  String _upsertStylePaintIfExists(String tagStart, String property, String value) {
    final styleRegex = RegExp(r'style="([^"]*)"');

    return tagStart.replaceFirstMapped(styleRegex, (match) {
      final style = match.group(1) ?? '';
      final updated = _upsertStyleProperty(style, property, value);
      return 'style="$updated"';
    });
  }

  Future<Map<String, CertificadoSlotModel>> carregarSlotsDoGuia(
      CertificadoTemplateTipo tipo,
      ) async {
    final guiaSvg = await carregarGuia(tipo);
    return extrairSlotsDoGuia(guiaSvg);
  }

  Map<String, CertificadoSlotModel> extrairSlotsDoGuia(String guiaSvg) {
    final slots = <String, CertificadoSlotModel>{};

    if (guiaSvg.trim().isEmpty) return slots;

    try {
      final document = xml.XmlDocument.parse(guiaSvg);

      for (final id in CertificadoSlotIds.todos) {
        final element = _findElementById(document, id);
        if (element == null) continue;

        final slot = _slotFromElement(element);
        if (slot != null && slot.isValid) {
          slots[id] = slot;
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao extrair slots do SVG guia: $e');
    }

    return slots;
  }

  CertificadoSlotModel? _slotFromElement(xml.XmlElement element) {
    final id = element.getAttribute('id');
    if (id == null || id.trim().isEmpty) return null;

    final local = element.name.local.toLowerCase();

    if (local == 'rect') {
      final x = _parseSvgNumber(element.getAttribute('x'));
      final y = _parseSvgNumber(element.getAttribute('y'));
      final width = _parseSvgNumber(element.getAttribute('width'));
      final height = _parseSvgNumber(element.getAttribute('height'));

      return CertificadoSlotModel(
        id: id,
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }

    if (local == 'polygon' || local == 'polyline') {
      return _slotFromPoints(id, element.getAttribute('points'));
    }

    if (local == 'path') {
      return _slotFromPathData(id, element.getAttribute('d'));
    }

    if (local == 'g') {
      for (final child in element.descendants.whereType<xml.XmlElement>()) {
        final childSlot = _slotFromElementWithForcedId(child, id);
        if (childSlot != null && childSlot.isValid) return childSlot;
      }
    }

    return null;
  }

  CertificadoSlotModel? _slotFromElementWithForcedId(
      xml.XmlElement element,
      String forcedId,
      ) {
    final local = element.name.local.toLowerCase();

    if (local == 'rect') {
      final x = _parseSvgNumber(element.getAttribute('x'));
      final y = _parseSvgNumber(element.getAttribute('y'));
      final width = _parseSvgNumber(element.getAttribute('width'));
      final height = _parseSvgNumber(element.getAttribute('height'));

      return CertificadoSlotModel(
        id: forcedId,
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }

    if (local == 'polygon' || local == 'polyline') {
      return _slotFromPoints(forcedId, element.getAttribute('points'));
    }

    if (local == 'path') {
      return _slotFromPathData(forcedId, element.getAttribute('d'));
    }

    return null;
  }

  CertificadoSlotModel? _slotFromPoints(String id, String? points) {
    if (points == null || points.trim().isEmpty) return null;

    final numbers = _extractNumbers(points);
    if (numbers.length < 4) return null;

    final xs = <double>[];
    final ys = <double>[];

    for (var i = 0; i + 1 < numbers.length; i += 2) {
      xs.add(numbers[i]);
      ys.add(numbers[i + 1]);
    }

    if (xs.isEmpty || ys.isEmpty) return null;

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    return CertificadoSlotModel(
      id: id,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  CertificadoSlotModel? _slotFromPathData(String id, String? d) {
    if (d == null || d.trim().isEmpty) return null;

    final numbers = _extractNumbers(d);
    if (numbers.length < 4) return null;

    final xs = <double>[];
    final ys = <double>[];

    for (var i = 0; i + 1 < numbers.length; i += 2) {
      xs.add(numbers[i]);
      ys.add(numbers[i + 1]);
    }

    if (xs.isEmpty || ys.isEmpty) return null;

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    return CertificadoSlotModel(
      id: id,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  List<double> _extractNumbers(String value) {
    final regex = RegExp(
      r'-?\d+(?:[\.,]\d+)?(?:e[-+]?\d+)?',
      caseSensitive: false,
    );

    return regex
        .allMatches(value)
        .map((match) => _parseSvgNumber(match.group(0)))
        .toList();
  }

  xml.XmlElement? _findElementById(xml.XmlDocument document, String id) {
    try {
      return document.rootElement.descendants
          .whereType<xml.XmlElement>()
          .firstWhere((element) => element.getAttribute('id') == id);
    } catch (_) {
      return null;
    }
  }

  String _upsertStyleProperty(String style, String property, String value) {
    final parts = style
        .split(';')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    var found = false;

    final updated = parts.map((item) {
      final splitIndex = item.indexOf(':');
      if (splitIndex <= 0) return item;

      final key = item.substring(0, splitIndex).trim();

      if (key == property) {
        found = true;
        return '$property:$value';
      }

      return item;
    }).toList();

    if (!found) {
      updated.insert(0, '$property:$value');
    }

    return updated.join(';');
  }

  double _parseSvgNumber(String? value) {
    if (value == null) return 0.0;

    final cleaned = value
        .trim()
        .replaceAll(',', '.')
        .replaceAll('mm', '')
        .replaceAll('px', '');

    return double.tryParse(cleaned) ?? 0.0;
  }

  String _colorToHex(Color color) {
    final value = color.value.toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }

  Color colorFromHex(
      String? hex, {
        Color fallback = const Color(0xFF9E9E9E),
      }) {
    final raw = hex?.trim();
    if (raw == null || raw.isEmpty) return fallback;

    try {
      final cleaned = raw.replaceAll('#', '').toUpperCase();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }
}
