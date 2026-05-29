import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Services
import 'package:uai_capoeira/modules/turmas/services/academia_cache_service.dart';

// Telas
import 'package:uai_capoeira/modules/turmas/screens/turmas_academia_screen.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final AcademiaCacheService _cacheService = AcademiaCacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userDataStream;
  late Future<List<Map<String, dynamic>>> _academiasFuture;

  bool _jaMostrouAvisoOffline = false;

  @override
  void initState() {
    super.initState();
    _inicializarStreams();
  }

  void _inicializarStreams() {
    if (currentUser != null) {
      _userDataStream = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser!.uid)
          .snapshots(includeMetadataChanges: true);
    } else {
      _userDataStream = Stream.empty();
    }

    // IMPORTANTE:
    // Antes isso começava como Future.value([]), então a Home podia mostrar
    // "Você não está vinculado..." antes da busca real terminar.
    _academiasFuture = _carregarAcademias();
  }

  Future<List<Map<String, dynamic>>> _carregarAcademias() async {
    final uid = currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      debugPrint('⚠️ HomePage: usuário nulo ao carregar academias.');
      return [];
    }

    final temInternet = await _cacheService.temInternet();

    if (!temInternet && mounted && !_jaMostrouAvisoOffline) {
      _jaMostrouAvisoOffline = true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🌐 Modo offline - usando dados salvos'),
          backgroundColor: context.uai.warning,
          duration: Duration(seconds: 2),
        ),
      );
    }

    final academias = await _cacheService.carregarAcademiasComAlunos(uid);

    debugPrint('🏫 HomePage: academias carregadas: ${academias.length}');

    return academias;
  }

  Future<void> _recarregarAcademias() async {
    setState(() {
      _academiasFuture = _carregarAcademias();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _recarregarAcademias();

              if (currentUser != null) {
                try {
                  await FirebaseFirestore.instance
                      .collection('usuarios')
                      .doc(currentUser!.uid)
                      .get(GetOptions(source: Source.server));
                } catch (e) {
                  debugPrint('Erro ao forçar atualização: $e');
                }
              }
            },
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 500),
                  child: Column(
                    children: [
                      SizedBox(height: 30),
                      _buildPerfilStream(theme),
                      SizedBox(height: 30),
                      _buildLogo(),
                      SizedBox(height: 30),
                      _buildAcademiasFuture(),
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
  Widget _buildPerfilStream(ThemeData theme) {
    if (currentUser == null) {
      return _buildPerfilOffline();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDataStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return _buildSkeletonPerfil(theme);
        }

        if (snapshot.hasError) {
          debugPrint('Erro no stream do usuário: ${snapshot.error}');
          return _buildPerfilComFallback(theme);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildPerfilVazio(theme);
        }

        final userData = snapshot.data!.data() ?? {};
        final String displayName = userData['nome_completo'] ?? 'Usuário';
        final String? photoUrl = userData['foto_url'] as String?;

        debugPrint('🔄 Perfil atualizado: $displayName');

        return Column(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: context.uai.cardAlt,
              child: ClipOval(
                child: _buildAvatarImageHome(
                  photoUrl: photoUrl,
                  displayName: displayName,
                ),
              ),
            ),
            SizedBox(height: 15),
            Text(
              displayName.toUpperCase(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.uai.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 5),
            Text(
              'SEJA BEM VINDO(A) AO APP!',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }

  Widget _buildPerfilComFallback(ThemeData theme) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser?.uid)
          .get(GetOptions(source: Source.cache)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() ?? {};
          return _buildPerfilComDados(userData);
        }

        return _buildPerfilVazio(theme);
      },
    );
  }

  Widget _buildPerfilComDados(Map<String, dynamic> userData) {
    final String displayName = userData['nome_completo'] ?? 'Usuário';
    final String? photoUrl = userData['foto_url'] as String?;

    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: context.uai.cardAlt,
          child: ClipOval(
            child: _buildAvatarImageHome(
              photoUrl: photoUrl,
              displayName: displayName,
            ),
          ),
        ),
        SizedBox(height: 15),
        Text(
          displayName.toUpperCase(),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.uai.textPrimary),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 5),
        Text(
          'SEJA BEM VINDO(A) AO APP!',
          style: TextStyle(color: context.uai.textSecondary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPerfilVazio(ThemeData theme) {
    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: context.uai.cardAlt,
          child: Icon(Icons.person_off, size: 60, color: context.uai.textMuted),
        ),
        SizedBox(height: 15),
        Text(
          'USUÁRIO NÃO IDENTIFICADO',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 5),
        Text(
          'Faça login novamente',
          style: TextStyle(color: context.uai.textSecondary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPerfilOffline() {
    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: context.uai.cardAlt,
          child: Icon(Icons.person_off, size: 60, color: context.uai.textMuted),
        ),
        SizedBox(height: 15),
        Text(
          'AGUARDANDO LOGIN...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLogo() {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: FutureBuilder<String>(
        future: rootBundle.loadString('assets/images/logo_uai_tema.svg'),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final svg = _aplicarTemaNoLogoUai(snapshot.data!, t);

            return SvgPicture.string(
              svg,
              height: 150,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => SizedBox(
                height: 150,
                child: Center(
                  child: CircularProgressIndicator(color: t.primary),
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Container(
              height: 150,
              width: 230,
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius: BorderRadius.circular(t.cardRadius),
                border: Border.all(color: t.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sports_martial_arts,
                    size: 58,
                    color: t.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Logo SVG não encontrada',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }

          return SizedBox(
            height: 150,
            child: Center(
              child: CircularProgressIndicator(color: t.primary),
            ),
          );
        },
      ),
    );
  }

  String _aplicarTemaNoLogoUai(String svg, dynamic t) {
    final isTemaClassico = _isTemaClassicoUai(t);

    final uaiColor = _colorToHex(t.primary);

    // Pedido especial:
    // Somente no tema UAI Clássico, a faixa da logo fica preta
    // e o texto "CAPOEIRA" fica branco, igual ajustamos no site público.
    // Nos outros temas, a logo continua reagindo normalmente ao tema atual.
    final faixaColor = isTemaClassico ? '#111111' : _colorToHex(t.cardAlt);
    final textoColor =
    isTemaClassico ? '#FFFFFF' : _colorToHex(_readableOn(t.cardAlt));
    final strokeColor = isTemaClassico ? '#111111' : _colorToHex(t.border);

    var result = svg;

    // Solução segura:
    // O asset precisa ter cores reais válidas como fallback.
    // Depois a Home troca essas cores reais pelas cores do tema.
    // Assim, se o replace falhar, a logo ainda aparece normal.
    final replacements = <String, String>{
      '#FF0000': uaiColor,
      '#ff0000': uaiColor,
      'red': uaiColor,
      '#373435': faixaColor,
      '#FEFEFE': textoColor,
      '#fefefe': textoColor,
    };

    replacements.forEach((from, to) {
      result = result.replaceAll(from, to);
    });

    // A faixa e o stroke usam a mesma cor original #373435.
    // Depois do replace geral, garantimos a borda pelo id="faixa".
    result = result.replaceFirstMapped(
      RegExp(r'(<polygon[^>]*id="faixa"[^>]*)(/?>)', caseSensitive: false),
          (match) {
        var tag = match.group(1) ?? '';
        final close = match.group(2) ?? '>';

        if (RegExp(r'\sstroke="[^"]*"').hasMatch(tag)) {
          tag = tag.replaceFirst(
            RegExp(r'\sstroke="[^"]*"'),
            ' stroke="$strokeColor"',
          );
        } else {
          tag = '$tag stroke="$strokeColor"';
        }

        return '$tag$close';
      },
    );

    return result;
  }

  bool _isTemaClassicoUai(dynamic t) {
    // Mantém o ajuste independente do AppThemeController.
    // O UAI Clássico usa o vermelho #B71C1C e fundo claro.
    final primaryHex = _colorToHex(t.primary).toUpperCase();
    final backgroundIsLight = t.background.computeLuminance() > 0.55;

    return backgroundIsLight && primaryHex == '#B71C1C';
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  Widget _buildAcademiasFuture() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _academiasFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingAcademias();
        }

        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error.toString());
        }

        final academias = snapshot.data ?? [];

        if (academias.isEmpty) {
          return _buildEmptyAcademias();
        }

        return _buildAcademiasList(academias);
      },
    );
  }

  Widget _buildSkeletonPerfil(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: context.uai.border,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(height: 15),
        Container(
          width: 200,
          height: 24,
          color: context.uai.border,
        ),
        SizedBox(height: 5),
        Container(
          width: 150,
          height: 16,
          color: context.uai.border,
        ),
      ],
    );
  }

  Widget _buildLoadingAcademias() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Card(
        elevation: 1,
        color: context.uai.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uai.cardRadius)),
        child: Padding(
          padding: EdgeInsets.all(25),
          child: Column(
            children: [
              CircularProgressIndicator(color: context.uai.primary),
              SizedBox(height: 16),
              Text(
                'Carregando suas academias...',
                style: TextStyle(fontSize: 15, color: context.uai.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 50, color: context.uai.error),
          SizedBox(height: 15),
          Text(
            'Erro ao carregar academias',
            style: TextStyle(fontSize: 16, color: context.uai.error),
          ),
          SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _recarregarAcademias,
            icon: Icon(Icons.refresh),
            label: Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAcademias() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 2,
        color: context.uai.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uai.cardRadius)),
        child: Padding(
          padding: EdgeInsets.all(25),
          child: Column(
            children: [
              Icon(Icons.location_off, size: 60, color: context.uai.textMuted),
              SizedBox(height: 15),
              Text(
                'Você não está vinculado a nenhuma academia',
                style: TextStyle(fontSize: 16, color: context.uai.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                'Entre em contato com o administrador',
                style: TextStyle(fontSize: 14, color: context.uai.textMuted),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _recarregarAcademias,
                icon: Icon(Icons.refresh),
                label: Text('Atualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcademiasList(List<Map<String, dynamic>> academias) {
    int totalAlunos = 0;

    for (var academia in academias) {
      totalAlunos += (academia['alunos_count'] ?? 0) as int;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MINHAS ACADEMIAS (${academias.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.uai.textSecondary,
                    ),
                  ),
                  Text(
                    'Total de alunos: $totalAlunos',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.uai.textSecondary,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _recarregarAcademias,
                icon: Icon(Icons.refresh),
                color: context.uai.textSecondary,
                iconSize: 20,
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        ...academias.map((academia) => _buildCardAcademia(academia)).toList(),
        SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCardAcademia(Map<String, dynamic> academia) {
    final theme = Theme.of(context);
    final t = context.uai;

    return Card(
      elevation: 0,
      color: t.card,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        side: BorderSide(color: t.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.uai.cardRadius - 6),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TurmasAcademiaScreen(
                academiaId: academia['id'],
                academiaNome: academia['nome'],
                academiaCidade: academia['cidade'],
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  color: t.primary.withOpacity(0.10),
                  border: Border.all(color: t.primary.withOpacity(0.25)),
                ),
                child: academia['logo_url'] != null &&
                    academia['logo_url'].toString().isNotEmpty
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: academia['logo_url'],
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        CircularProgressIndicator(color: context.uai.primary),
                    errorWidget: (context, url, error) =>
                        Icon(Icons.error),
                  ),
                )
                    : Icon(Icons.location_on, color: t.primary, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academia['nome'] ?? 'Academia',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (academia['cidade']?.toString().isNotEmpty ?? false)
                      Text(
                        academia['cidade'],
                        style: TextStyle(
                          fontSize: 12,
                          color: context.uai.textSecondary,
                        ),
                      ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        _buildBadge(
                          icon: Icons.people,
                          text: '${academia['alunos_count'] ?? 0}',
                          color: context.uai.info,
                        ),
                        SizedBox(width: 8),
                        if ((academia['turmas_count'] ?? 0) > 0)
                          _buildBadge(
                            icon: Icons.class_,
                            text: '${academia['turmas_count']}',
                            color: context.uai.success,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImageHome({
    required String? photoUrl,
    required String displayName,
  }) {
    final theme = Theme.of(context);

    if (photoUrl == null || photoUrl.isEmpty) {
      return Icon(Icons.person, size: 60, color: context.uai.primary);
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: 120,
      height: 120,
      placeholder: (context, url) => CircularProgressIndicator(color: context.uai.primary),
      errorWidget: (context, url, error) =>
          Icon(Icons.person, size: 60, color: context.uai.primary),
    );
  }
}

