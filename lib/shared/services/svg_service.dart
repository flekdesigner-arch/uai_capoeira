import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

class SvgService {
  static String? _svgContent;

  static Future<String?> getSvgContent(BuildContext context) async {
    if (_svgContent != null) return _svgContent;

    try {
      _svgContent = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      return _svgContent;
    } catch (e) {
      debugPrint('Erro ao carregar SVG: $e');
      return null;
    }
  }

  static String? getModifiedSvg({
    required String? svgContent,
    required Color cor1,
    required Color cor2,
    required Color ponta1,
    required Color ponta2,
  }) {
    if (svgContent == null) return null;

    try {
      final document = xml.XmlDocument.parse(svgContent);

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants.whereType<xml.XmlElement>().firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );
        if (element.name.local.isNotEmpty) {
          final style = element.getAttribute('style') ?? '';
          final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
          final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
          element.setAttribute('style', 'fill:$hex;$newStyle');
        }
      }

      changeColor('cor1', cor1);
      changeColor('cor2', cor2);
      changeColor('corponta1', ponta1);
      changeColor('corponta2', ponta2);

      return document.toXmlString();
    } catch (e) {
      debugPrint('Erro ao modificar SVG: $e');
      return null;
    }
  }
}