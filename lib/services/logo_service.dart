import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class LogoService {
  static final LogoService _instance = LogoService._internal();
  factory LogoService() => _instance;
  LogoService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _cachedLogoUrl;
  DateTime? _lastFetch;
  static const Duration _cacheDuration = Duration(minutes: 30);

  Future<String?> getLogoUrl() async {
    // Se tem cache e ainda é válido, retorna cache
    if (_cachedLogoUrl != null && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _cacheDuration) {
        return _cachedLogoUrl;
      }
    }

    try {
      final doc = await _firestore.collection('configuracoes').doc('logo').get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _cachedLogoUrl = data['url'] as String?;
        _lastFetch = DateTime.now();
        return _cachedLogoUrl;
      }
    } catch (e) {
      debugPrint('Erro ao buscar logo: $e');
    }

    return null;
  }

  // 🔥 NOVO MÉTODO - LIMPAR CACHE
  void limparCache() {
    _cachedLogoUrl = null;
    _lastFetch = null;
    debugPrint('🧹 Cache da logo limpo');
  }

  // Salva nova URL da logo
  Future<bool> salvarLogoUrl(String url) async {
    try {
      await _firestore.collection('configuracoes').doc('logo').set({
        'url': url,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      // Atualiza cache
      _cachedLogoUrl = url;
      _lastFetch = DateTime.now();

      return true;
    } catch (e) {
      debugPrint('Erro ao salvar logo: $e');
      return false;
    }
  }

  Widget buildLogo({double height = 150, BoxFit fit = BoxFit.contain}) {
    return FutureBuilder<String?>(
      future: getLogoUrl(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return CachedNetworkImage(
            imageUrl: snapshot.data!,
            height: height,
            fit: fit,
            placeholder: (context, url) => Container(
              height: height,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => _buildFallbackLogo(height),
          );
        }
        return _buildFallbackLogo(height);
      },
    );
  }

  Widget _buildFallbackLogo(double height) {
    return Image.asset(
      'assets/images/logo_uai.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) {
        print('❌ ERRO AO CARREGAR LOGO: $error');
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_martial_arts,
              size: height * 0.6,
              color: Colors.red.shade900,
            ),
            const SizedBox(height: 8),
            Text(
              'UAI CAPOEIRA',
              style: TextStyle(
                fontSize: height * 0.15,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            Text(
              'Erro: $error',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        );
      },
    );
  }}