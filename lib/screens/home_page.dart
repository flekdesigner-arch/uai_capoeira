import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services
import '../services/academia_cache_service.dart';

// Telas
import 'package:uai_capoeira/turmas_academia_screen.dart';

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
        const SnackBar(
          content: Text('🌐 Modo offline - usando dados salvos'),
          backgroundColor: Colors.orange,
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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await _recarregarAcademias();

          if (currentUser != null) {
            try {
              await FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(currentUser!.uid)
                  .get(const GetOptions(source: Source.server));
            } catch (e) {
              debugPrint('Erro ao forçar atualização: $e');
            }
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  _buildPerfilStream(theme),
                  const SizedBox(height: 30),
                  _buildLogo(),
                  const SizedBox(height: 30),
                  _buildAcademiasFuture(),
                ],
              ),
            ),
          ),
        ),
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
              backgroundColor: Colors.grey.shade200,
              child: ClipOval(
                child: _buildAvatarImageHome(
                  photoUrl: photoUrl,
                  displayName: displayName,
                ),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              displayName.toUpperCase(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            const Text(
              'SEJA BEM VINDO(A) AO APP!',
              style: TextStyle(
                color: Colors.grey,
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
          .get(const GetOptions(source: Source.cache)),
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
          backgroundColor: Colors.grey.shade200,
          child: ClipOval(
            child: _buildAvatarImageHome(
              photoUrl: photoUrl,
              displayName: displayName,
            ),
          ),
        ),
        const SizedBox(height: 15),
        Text(
          displayName.toUpperCase(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        const Text(
          'SEJA BEM VINDO(A) AO APP!',
          style: TextStyle(color: Colors.grey, fontSize: 14),
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
          backgroundColor: Colors.grey.shade200,
          child: Icon(Icons.person_off, size: 60, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 15),
        const Text(
          'USUÁRIO NÃO IDENTIFICADO',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        const Text(
          'Faça login novamente',
          style: TextStyle(color: Colors.grey, fontSize: 14),
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
          backgroundColor: Colors.grey.shade200,
          child: Icon(Icons.person_off, size: 60, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 15),
        const Text(
          'AGUARDANDO LOGIN...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Image.asset(
        'assets/images/logo_uai.png',
        height: 150,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 150,
            width: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sports_martial_arts,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 10),
                Text(
                  'Logo não encontrada',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
            color: Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 15),
        Container(
          width: 200,
          height: 24,
          color: Colors.grey.shade300,
        ),
        const SizedBox(height: 5),
        Container(
          width: 150,
          height: 16,
          color: Colors.grey.shade300,
        ),
      ],
    );
  }

  Widget _buildLoadingAcademias() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(25),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Carregando suas academias...',
                style: TextStyle(fontSize: 15, color: Colors.grey),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 50, color: Colors.red.shade300),
          const SizedBox(height: 15),
          const Text(
            'Erro ao carregar academias',
            style: TextStyle(fontSize: 16, color: Colors.red),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _recarregarAcademias,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAcademias() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            children: [
              Icon(Icons.location_off, size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 15),
              const Text(
                'Você não está vinculado a nenhuma academia',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Entre em contato com o administrador',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _recarregarAcademias,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    'Total de alunos: $totalAlunos',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _recarregarAcademias,
                icon: const Icon(Icons.refresh),
                color: Colors.grey.shade600,
                iconSize: 20,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...academias.map((academia) => _buildCardAcademia(academia)).toList(),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCardAcademia(Map<String, dynamic> academia) {
    final theme = Theme.of(context);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: theme.primaryColor.withOpacity(0.1),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                ),
                child: academia['logo_url'] != null &&
                    academia['logo_url'].toString().isNotEmpty
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: academia['logo_url'],
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                    const CircularProgressIndicator(),
                    errorWidget: (context, url, error) =>
                    const Icon(Icons.error),
                  ),
                )
                    : Icon(Icons.location_on, color: theme.primaryColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academia['nome'] ?? 'Academia',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (academia['cidade']?.toString().isNotEmpty ?? false)
                      Text(
                        academia['cidade'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildBadge(
                          icon: Icons.people,
                          text: '${academia['alunos_count'] ?? 0}',
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        if ((academia['turmas_count'] ?? 0) > 0)
                          _buildBadge(
                            icon: Icons.class_,
                            text: '${academia['turmas_count']}',
                            color: Colors.green.shade700,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
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
      return Icon(Icons.person, size: 60, color: theme.primaryColor);
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: 120,
      height: 120,
      placeholder: (context, url) => const CircularProgressIndicator(),
      errorWidget: (context, url, error) =>
          Icon(Icons.person, size: 60, color: theme.primaryColor),
    );
  }
}
