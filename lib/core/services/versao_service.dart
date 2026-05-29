import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show debugPrint; // 🔥 1. Import do debugPrint
import 'dart:io' show Platform; // 🔥 2. Import do Platform

class VersaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 Buscar versão atual no Firebase
  Future<String> getVersaoFirebase() async {
    try {
      final doc = await _firestore
          .collection('configuracoes')
          .doc('app')
          .get(const GetOptions(source: Source.server));

      if (doc.exists) {
        final data = doc.data();
        // 🔥 6. Tratamento de null corrigido
        if (data != null && data.containsKey('versao_atual')) {
          return data['versao_atual'] as String;
        }
      }
      return '1.0.0';
    } catch (e) {
      debugPrint('❌ Erro ao buscar versão: $e');
      return '1.0.0';
    }
  }

  // 📱 Buscar versão local do app
  Future<String> getVersaoLocal() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      debugPrint('❌ Erro ao buscar versão local: $e');
      return '1.0.0';
    }
  }

  // 🔍 Comparar versões
  Future<bool> precisaAtualizar() async {
    final versaoFirebase = await getVersaoFirebase();
    final versaoLocal = await getVersaoLocal();

    debugPrint('📱 Versão local: $versaoLocal');
    debugPrint('☁️ Versão Firebase: $versaoFirebase');

    return _compararVersoes(versaoLocal, versaoFirebase);
  }

  bool _compararVersoes(String local, String firebase) {
    try {
      final List<int> localParts = local.split('.').map(int.parse).toList();
      final List<int> firebaseParts = firebase.split('.').map(int.parse).toList();

      for (int i = 0; i < firebaseParts.length; i++) {
        if (i >= localParts.length) return true;
        if (firebaseParts[i] > localParts[i]) return true;
        if (firebaseParts[i] < localParts[i]) return false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Erro ao comparar versões: $e');
      return false;
    }
  }

  // 🚀 Abrir loja para atualizar
  Future<void> abrirLoja() async {
    // 🔥 5. Corrigido o ID do pacote (substitua pelo seu)
    final String packageName = 'com.example.uai_capoeira'; // Mude para seu ID real!

    final Uri url = Platform.isAndroid
        ? Uri.parse('market://details?id=$packageName')
        : Uri.parse('https://apps.apple.com/app/idSEU_ID'); // Substitua pelo ID da Apple

    final Uri fallbackUrl = Platform.isAndroid
        ? Uri.parse('https://play.google.com/store/apps/details?id=$packageName')
        : Uri.parse('https://apps.apple.com/app/idSEU_ID');

    try {
      // 🔥 3 e 4. canLaunchUrl e launchUrl corrigidos
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(fallbackUrl)) {
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('❌ Não foi possível abrir nenhuma loja');
      }
    } catch (e) {
      debugPrint('❌ Erro ao abrir loja: $e');
    }
  }

  // 🆕 Método extra para debug
  Future<Map<String, String>> getInfoVersoes() async {
    return {
      'local': await getVersaoLocal(),
      'firebase': await getVersaoFirebase(),
      'precisaAtualizar': (await precisaAtualizar()).toString(),
    };
  }
}