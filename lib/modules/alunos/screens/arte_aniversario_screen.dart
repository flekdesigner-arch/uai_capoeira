import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/shared/widgets/uai_dynamic_logo.dart';
import 'package:uai_capoeira/modules/alunos/models/mensagem_aniversario_model.dart';
import 'package:uai_capoeira/modules/alunos/services/birthday_settings_service.dart';
import 'package:uai_capoeira/modules/alunos/services/mensagem_aniversario_service.dart';
import 'package:uai_capoeira/modules/alunos/widgets/birthday_poster_people.dart';


/// Fecha o sheet antes de abrir a galeria, mantendo o feedback no contexto pai.
Future<void> abrirGaleriaAposFecharSheet(
  BuildContext sheetContext, BuildContext parentContext,
  Future<void> Function() abrirGaleria,
) async {
  Navigator.of(sheetContext).pop();
  try {
    await abrirGaleria();
  } catch (_) {
    if (parentContext.mounted) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('Arte salva em Downloads/Pictures')),
      );
    }
  }
}

class BirthdayArtPerson {
  const BirthdayArtPerson({required this.nome, this.fotoUrl, this.idade, this.sexo});

  final String nome;
  final String? fotoUrl;
  final int? idade;
  final String? sexo;
}

enum BirthdayThemeProfile { feminine, masculine, neutral }

class BirthdayThemeSelection {
  const BirthdayThemeSelection._();

  static BirthdayThemeProfile profileOf(Iterable<BirthdayArtPerson> people) {
    final values = people.map((person) {
      final value = (person.sexo ?? '').trim().toLowerCase();
      if (const {'f', 'feminino', 'feminina', 'mulher'}.contains(value)) {
        return BirthdayThemeProfile.feminine;
      }
      if (const {'m', 'masculino', 'masculina', 'homem'}.contains(value)) {
        return BirthdayThemeProfile.masculine;
      }
      return BirthdayThemeProfile.neutral;
    }).toSet();
    if (values.length == 1 && !values.contains(BirthdayThemeProfile.neutral)) {
      return values.single;
    }
    return BirthdayThemeProfile.neutral;
  }
}

class BirthdayArtTheme {
  const BirthdayArtTheme(
    this.id,
    this.nome,
    this.colors,
    this.accent,
    this.icon,
    [this.profile = BirthdayThemeProfile.neutral]
  );

  final String id;
  final String nome;
  final List<Color> colors;
  final Color accent;
  final IconData icon;
  final BirthdayThemeProfile profile;

  static const all = <BirthdayArtTheme>[
    BirthdayArtTheme(
      'classic_uai',
      'Clássico UAI',
      [Color(0xFF080B13), Color(0xFF94152A), Color(0xFF05060A)],
      Color(0xFFFF5169),
      Icons.shield_rounded,
    ),
    BirthdayArtTheme(
      'elegant',
      'Festa elegante',
      [Color(0xFF1B101B), Color(0xFF6A2245), Color(0xFFD9A85B)],
      Color(0xFFF6D88F),
      Icons.auto_awesome,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'kids',
      'Infantil colorido',
      [Color(0xFF174CB1), Color(0xFFB62B97), Color(0xFFFFBD45)],
      Color(0xFFFFF0A8),
      Icons.celebration_rounded,
    ),
    BirthdayArtTheme(
      'clean',
      'Premium clean',
      [Color(0xFF252B35), Color(0xFF495D6B), Color(0xFF181D2B)],
      Color(0xFFF3F6FF),
      Icons.diamond_outlined,
    ),
    BirthdayArtTheme(
      'capoeira',
      'Capoeira energia',
      [Color(0xFF0D302B), Color(0xFF151A24), Color(0xFFBD2338)],
      Color(0xFFFFD267),
      Icons.sports_martial_arts_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'neon',
      'Noite neon',
      [Color(0xFF10072E), Color(0xFF5820B8), Color(0xFF072D55)],
      Color(0xFF6CF7FF),
      Icons.bolt_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'gold',
      'Luxo dourado',
      [Color(0xFF100D0C), Color(0xFF574322), Color(0xFF0C0C11)],
      Color(0xFFFFD88A),
      Icons.workspace_premium_rounded,
    ),
    BirthdayArtTheme(
      'tropical',
      'Tropical festa',
      [Color(0xFF006B65), Color(0xFF15A790), Color(0xFFE88B4B)],
      Color(0xFFFFDC72),
      Icons.wb_sunny_rounded,
    ),
    BirthdayArtTheme(
      'confetti',
      'Céu de confetes',
      [Color(0xFF194D85), Color(0xFF3A81B2), Color(0xFF8048A5)],
      Color(0xFFF9E570),
      Icons.celebration,
    ),
    BirthdayArtTheme(
      'modern',
      'Studio moderno',
      [Color(0xFF151A2B), Color(0xFF3A344D), Color(0xFF803F52)],
      Color(0xFFF7AFC0),
      Icons.auto_fix_high_rounded,
    ),
    BirthdayArtTheme(
      'candy',
      'Doce infantil',
      [Color(0xFFA34E91), Color(0xFF7C73B9), Color(0xFF3A87A7)],
      Color(0xFFFFF0B0),
      Icons.favorite_rounded,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'group',
      'Homenagem coletiva',
      [Color(0xFF5A1429), Color(0xFFC3263C), Color(0xFF1C142B)],
      Color(0xFFFFD890),
      Icons.groups_rounded,
    ),
    BirthdayArtTheme(
      'aurora',
      'Aurora premium',
      [Color(0xFF051937), Color(0xFF004D7A), Color(0xFF00BF72)],
      Color(0xFF9FFFE0),
      Icons.blur_on_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'sunset_royal',
      'Sunset royal',
      [Color(0xFF300230), Color(0xFF8E244D), Color(0xFFFF8A3D)],
      Color(0xFFFFE2A3),
      Icons.sunny,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'ice_glow',
      'Ice glow',
      [Color(0xFF10223B), Color(0xFF2F5E86), Color(0xFF88C0D0)],
      Color(0xFFEAF9FF),
      Icons.ac_unit_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'velvet_party',
      'Velvet party',
      [Color(0xFF20081C), Color(0xFF5C123F), Color(0xFFC53D6B)],
      Color(0xFFFFD6E4),
      Icons.local_bar_rounded,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'garden',
      'Garden premium',
      [Color(0xFF0C3322), Color(0xFF2D7D57), Color(0xFFC8A449)],
      Color(0xFFF6E6A7),
      Icons.local_florist_rounded,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'rose_gold', 'Rose Gold',
      [Color(0xFF402136), Color(0xFFB66A90), Color(0xFFF6C4A6)],
      Color(0xFFFFF1D6), Icons.diamond_rounded,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'orchid', 'Orquídea imperial',
      [Color(0xFF21133A), Color(0xFF744DAB), Color(0xFFCA83CF)],
      Color(0xFFF7D4FF), Icons.local_florist_rounded,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'pearl', 'Pérola delicada',
      [Color(0xFF45405A), Color(0xFFAD8CB8), Color(0xFFE6B6BB)],
      Color(0xFFFFF6ED), Icons.auto_awesome_rounded,
      BirthdayThemeProfile.feminine,
    ),
    BirthdayArtTheme(
      'ocean', 'Oceano profundo',
      [Color(0xFF06182B), Color(0xFF07497B), Color(0xFF1590AD)],
      Color(0xFF91EAFF), Icons.waves_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'steel', 'Aço premium',
      [Color(0xFF121B22), Color(0xFF36505A), Color(0xFF647887)],
      Color(0xFFE0F4FF), Icons.bolt_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'emerald', 'Esmeralda royal',
      [Color(0xFF071D1A), Color(0xFF166452), Color(0xFF21A47B)],
      Color(0xFFC5FFE3), Icons.verified_rounded,
      BirthdayThemeProfile.masculine,
    ),
    BirthdayArtTheme(
      'champagne', 'Champagne premium',
      [Color(0xFF332A30), Color(0xFF7D6666), Color(0xFFB59A74)],
      Color(0xFFFFE6B4), Icons.celebration_rounded,
    ),
    BirthdayArtTheme(
      'cosmos', 'Cosmos estrelado',
      [Color(0xFF111233), Color(0xFF3B3679), Color(0xFF4265A0)],
      Color(0xFFFFEAA3), Icons.stars_rounded,
    ),
    BirthdayArtTheme(
      'festival', 'Festival de luzes',
      [Color(0xFF41224C), Color(0xFF9C426B), Color(0xFFEF9558)],
      Color(0xFFFFFFC3), Icons.celebration_rounded,
    ),
  ];

  static BirthdayArtTheme byId(String? id) => all.firstWhere(
        (e) => e.id == id,
        orElse: () => all.first,
      );
}

class ArteAniversarioScreen extends StatefulWidget {
  const ArteAniversarioScreen({
    super.key,
    required this.alunoId,
    required this.nomeAluno,
    this.fotoUrl,
    this.sexoAluno,
    this.participantes = const [],
  });

  final String alunoId;
  final String nomeAluno;
  final String? fotoUrl;
  final String? sexoAluno;
  final List<BirthdayArtPerson> participantes;

  @override
  State<ArteAniversarioScreen> createState() => _ArteAniversarioScreenState();
}

class _ArteAniversarioScreenState extends State<ArteAniversarioScreen> {
  final GlobalKey _repaintKey = GlobalKey();

  MensagemAniversario? _mensagemAtual;
  String? _fallbackMessage;
  int _messageSequence = 0;
  BirthdayArtTheme _tema = BirthdayArtTheme.all.first;
  bool _carregando = true;
  bool _baixando = false;
  bool _themeLoaded = false;
  bool _permiteTrocarTema = true;
  String _themeSelectionMode = BirthdaySettingsService.modeUserChoice;

  bool get _coletiva => widget.participantes.length > 1;

  List<BirthdayArtPerson> get _pessoas => _coletiva
      ? widget.participantes
      : [BirthdayArtPerson(nome: widget.nomeAluno, fotoUrl: widget.fotoUrl, sexo: widget.sexoAluno)];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    _carregarNovaMensagem();
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    try {
      final settings = await BirthdaySettingsService.instance.ref.get();
      if (!mounted || _themeLoaded) return;
      final values = settings.data() ?? <String, dynamic>{};
      final mode = BirthdaySettingsService.themeSelectionMode(values);
      final defaultTheme = BirthdayArtTheme.byId(
        values['defaultArtTheme']?.toString(),
      );
      setState(() {
        _themeSelectionMode = mode;
        _permiteTrocarTema =
            BirthdaySettingsService.userCanChooseTheme(values);
        _tema = mode == BirthdaySettingsService.modeRandom
            ? _pickAutomaticTheme()
            : defaultTheme;
        _themeLoaded = true;
      });
    } catch (_) {
      if (!mounted || _themeLoaded) return;
      setState(() {
        _themeSelectionMode = BirthdaySettingsService.modeUserChoice;
        _permiteTrocarTema = true;
        _themeLoaded = true;
      });
    }
  }

  BirthdayArtTheme _pickAutomaticTheme({bool avoidCurrent = false}) {
    final available = BirthdayArtTheme.all
        .where((theme) => _coletiva || theme.id != 'group')
        .where((theme) => theme.profile == BirthdayThemeSelection.profileOf(_pessoas))
        .where((theme) => !avoidCurrent || theme.id != _tema.id)
        .toList();
    // O sorteio não deve usar uma semente diária: o botão de atualizar
    // precisa produzir outra opção a cada toque, quando houver alternativas.
    final candidates = available.isNotEmpty
        ? available
        : BirthdayArtTheme.all.where((theme) =>
            theme.profile == BirthdayThemeSelection.profileOf(_pessoas) &&
            (_coletiva || theme.id != 'group')).toList();
    return candidates[math.Random().nextInt(candidates.length)];
  }

  Future<void> _carregarNovaMensagem({bool refreshTheme = false}) async {
    if (_carregando && _themeLoaded) return;
    setState(() => _carregando = true);
    try {
      final mensagens =
          await MensagemAniversarioService().getMensagensAtivas();
      final elegiveis = mensagens
          .where((item) => BirthdayMessageComposer.compatible(
                item,
                collective: _coletiva,
              ))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final sequence = _messageSequence++;
      // Evita repetir a mensagem anterior quando houver alternativas.
      final alternatives = elegiveis.length > 1
          ? elegiveis.where((item) => item.id != _mensagemAtual?.id).toList()
          : elegiveis;
      final mensagem = alternatives.isEmpty
          ? null
          : alternatives[math.Random().nextInt(alternatives.length)];
      if (!mounted) return;
      setState(() {
        _mensagemAtual = mensagem;
        _fallbackMessage = _coletiva
            ? BirthdayMessageComposer.collectiveFallback(sequence)
            : BirthdayMessageComposer.individualFallback(sequence);
        if (refreshTheme &&
            _themeSelectionMode == BirthdaySettingsService.modeRandom) {
          _tema = _pickAutomaticTheme(avoidCurrent: true);
        }
        _carregando = false;
      });
    } catch (_) {
      // Não impede nova tentativa, nem descarta a mensagem já exibida.
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  Future<Uint8List> _renderPng() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Prévia não está pronta.');
    }
    final image = await boundary.toImage(pixelRatio: 3.0);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Não foi possível gerar a arte.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _baixarArte() async {
    if (_baixando) return;
    setState(() => _baixando = true);
    try {
      final png = await _renderPng();
      await FileSaver.instance.saveFile(
        name: 'uai_aniversario_${DateTime.now().millisecondsSinceEpoch}',
        bytes: png,
        ext: 'png',
        mimeType: MimeType.png,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arte exportada com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _baixando = false);
      }
    }
  }

  Future<void> _compartilharPreview() async {
    if (_baixando) return;
    setState(() => _baixando = true);
    try {
      final png = await _renderPng();
      await Share.shareXFiles(
        [
          XFile.fromData(
            png,
            mimeType: 'image/png',
            name: 'uai_aniversario.png',
          ),
        ],
        fileNameOverrides: const ['uai_aniversario.png'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível compartilhar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _baixando = false);
      }
    }
  }

  // Tipografia editorial por tema, sem alterar as fontes globais do app.
  String _titleFont(BirthdayArtTheme tema) {
    if (const {'elegant', 'gold', 'garden', 'velvet_party', 'sunset_royal'}
        .contains(tema.id)) {
      return 'BirthdayNotoSerif';
    }
    if (const {'kids', 'candy', 'confetti', 'tropical', 'group'}
        .contains(tema.id)) {
      return 'BirthdayLato';
    }
    return 'BirthdayInterDisplay';
  }

  String _nameFont(BirthdayArtTheme tema) {
    if (const {'elegant', 'gold', 'garden'}.contains(tema.id)) {
      return 'BirthdayNotoSerif';
    }
    return 'BirthdayInterDisplay';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.card,
      appBar: AppBar(
        title: Text(
          _coletiva ? 'Arte Coletiva' : 'Arte de Aniversário',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _carregarNovaMensagem(refreshTheme: true),
            tooltip: 'Atualizar arte e mensagem',
          ),
        ],
      ),
      body: _carregando
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: context.uai.error),
                  const SizedBox(height: 18),
                  Text(
                    'Montando uma arte especial...',
                    style: TextStyle(color: context.uai.textSecondary),
                  ),
                ],
              ),
            )
          : _buildArte(),
    );
  }

  Widget _buildArte() {
    final pessoas = _pessoas;
    final primeiroNome = pessoas.first.nome.trim().split(RegExp(r'\s+')).first;
    final mensagem = BirthdayMessageComposer.compose(
      _mensagemAtual?.texto ?? _fallbackMessage ?? '',
      collective: _coletiva,
      firstName: primeiroNome,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _coletiva ? 'Homenagem coletiva' : 'Sua arte de aniversário',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pessoas.length} aniversariante(s) • ${_tema.nome}',
                    style: TextStyle(
                      color: context.uai.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _permiteTrocarTema
                        ? 'Tema livre: o usuário pode trocar o fundo.'
                        : 'Tema automático: o app escolhe uma opção premium.',
                    style: TextStyle(
                      color: _permiteTrocarTema
                          ? context.uai.textSecondary
                          : context.uai.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (_permiteTrocarTema)
              IconButton(
                onPressed: _escolherTema,
                tooltip: 'Trocar fundo',
                icon: const Icon(Icons.palette_outlined),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, bounds) {
          final previewWidth = math.min(420.0, bounds.maxWidth);
          return Center(
            child: SizedBox(
              width: previewWidth,
              height: previewWidth * 4 / 3,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 420,
                  height: 560,
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: _buildPoster(pessoas, mensagem),
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
        _buildStudioPanel(),
      ],
    );
  }

  Widget _buildStudioPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.uai.border.withAlpha(120)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fundos premium',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: context.uai.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _permiteTrocarTema
                ? 'Escolha o visual da arte e gere novas combinações quando quiser.'
                : 'O tema foi definido automaticamente pelas configurações do módulo.',
            style: TextStyle(
              fontSize: 12,
              color: context.uai.textSecondary,
            ),
          ),
          if (_permiteTrocarTema) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: BirthdayArtTheme.all.length,
              separatorBuilder: (context, index) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final tema = BirthdayArtTheme.all[index];
                final selected = tema.id == _tema.id;
                return Opacity(
                  opacity: _permiteTrocarTema || selected ? 1 : 0.55,
                  child: InkWell(
                    onTap: _permiteTrocarTema
                        ? () => setState(() => _tema = tema)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 112,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: tema.colors),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : tema.accent.withAlpha(95),
                          width: selected ? 2.2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(tema.icon, color: tema.accent, size: 24),
                          const SizedBox(height: 7),
                          Text(
                            tema.nome,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_permiteTrocarTema)
                FilledButton.icon(
                  onPressed: _escolherTema,
                  icon: const Icon(Icons.wallpaper),
                  label: const Text('Trocar fundo'),
                ),
              OutlinedButton.icon(
                onPressed: () => _carregarNovaMensagem(refreshTheme: true),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Nova mensagem'),
              ),
              FilledButton.icon(
                onPressed: _baixando ? null : _baixarArte,
                icon: const Icon(Icons.download),
                label: Text(_baixando ? 'Salvando...' : 'Baixar arte'),
              ),
              OutlinedButton.icon(
                onPressed: _baixando ? null : _compartilharPreview,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartilhar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Prévia em formato retrato. Logo, foto e marca UAI permanecem na exportação.',
            style: TextStyle(fontSize: 11, color: context.uai.textSecondary),
          ),
        ],
      ),
    );
  }

  void _escolherTema() {
    if (!_permiteTrocarTema) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Escolher fundo premium',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.05,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: BirthdayArtTheme.all.length,
                    itemBuilder: (context, index) {
                      final tema = BirthdayArtTheme.all[index];
                      return InkWell(
                        onTap: () {
                          setState(() => _tema = tema);
                          Navigator.pop(sheet);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: tema.colors),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: tema.accent, width: 1.5),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(tema.icon, color: tema.accent, size: 29),
                              const SizedBox(height: 5),
                              Text(
                                '${tema.nome} · ${tema.profile == BirthdayThemeProfile.feminine ? 'Feminino' : tema.profile == BirthdayThemeProfile.masculine ? 'Masculino' : 'Neutro'}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPoster(List<BirthdayArtPerson> pessoas, String mensagem) {
    final tema = _tema;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final scale = width / 420;
          final collective = pessoas.length > 1;
          final posterText = mensagem;

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: tema.colors,
                  ),
                ),
              ),
              Positioned(
                top: -width * .18,
                right: -width * .22,
                child: Container(
                  width: width * .72,
                  height: width * .72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tema.accent.withAlpha(65),
                      width: 24 * scale,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -width * .30,
                left: -width * .24,
                child: Container(
                  width: width * .80,
                  height: width * .80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withAlpha(16),
                      width: 36 * scale,
                    ),
                  ),
                ),
              ),
              if (const {'kids', 'party', 'group', 'sunset', 'garden'}.contains(tema.id)) ...[
                Positioned(top: 25, right: 20, child: Opacity(opacity: .20,
                  child: SvgPicture.asset('assets/images/birthday_balloon_uai.svg',
                    width: 57, colorFilter: ColorFilter.mode(tema.accent, BlendMode.srcIn)))),
                Positioned(bottom: 58, left: 17, child: Opacity(opacity: .14,
                  child: SvgPicture.asset('assets/images/birthday_balloon_uai.svg',
                    width: 37, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)))),
              ],
              // Ornamentos discretos variam de acordo com a linguagem do tema.
              if (tema.profile == BirthdayThemeProfile.feminine) ...[
                Positioned(top: 94 * scale, right: 12 * scale,
                  child: Icon(Icons.spa_outlined, size: 90 * scale,
                    color: tema.accent.withAlpha(29))),
                Positioned(bottom: 64 * scale, left: 2 * scale,
                  child: Icon(Icons.auto_awesome, size: 56 * scale,
                    color: tema.accent.withAlpha(31))),
              ] else if (tema.profile == BirthdayThemeProfile.masculine) ...[
                Positioned(top: 94 * scale, right: 14 * scale,
                  child: Transform.rotate(angle: .42,
                    child: Icon(Icons.hexagon_outlined, size: 104 * scale,
                      color: tema.accent.withAlpha(27)))),
                Positioned(bottom: 72 * scale, left: 8 * scale,
                  child: Icon(Icons.bolt_outlined, size: 70 * scale,
                    color: tema.accent.withAlpha(30))),
              ],
              Positioned.fill(
                child: Opacity(
                  opacity: 0.10,
                  child: Padding(
                    padding: EdgeInsets.all(12 * scale),
                    child: Image.asset(
                      'assets/images/birthday_uai_watermark.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < 16; i++)
                Positioned(
                  left: ((i * 61 + 27) % 400) / 420 * width,
                  top: ((i * 79 + 24) % 500) / 560 * height,
                  child: Transform.rotate(
                    angle: i * .37,
                    child: Icon(
                      i.isEven ? Icons.circle : Icons.star_rounded,
                      color: (i % 3 == 0 ? tema.accent : Colors.white)
                          .withAlpha(95),
                      size: (i % 4 + 2) * 3.1 * scale,
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  22 * scale,
                  18 * scale,
                  22 * scale,
                  18 * scale,
                ),
                child: Column(
                  children: [
                    UaiDynamicLogo(
                      height: 54 * scale,
                      width: 108 * scale,
                      padding: EdgeInsets.zero,
                      showFallbackText: true,
                      themeOverride: context.uai.copyWith(
                        primary: tema.accent,
                        cardAlt: tema.colors.first,
                        border: tema.accent,
                      ),
                    ),
                    SizedBox(height: 10 * scale),
                    Text(
                      collective ? 'PARABÉNS, TURMA!' : 'FELIZ ANIVERSÁRIO!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: (collective ? 23 : 27) * scale,
                        fontFamily: _titleFont(tema),
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.1,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 12),
                        ],
                      ),
                    ),
                    SizedBox(height: 7 * scale),
                    Container(
                      height: 3.2 * scale,
                      width: 96 * scale,
                      decoration: BoxDecoration(
                        color: tema.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    SizedBox(height: 10 * scale),
                    Expanded(
                      child: _buildPeopleGrid(pessoas, scale, tema),
                    ),
                    SizedBox(height: 8 * scale),
                    SizedBox(
                      height: (collective ? 48 : 58) * scale,
                      child: Center(child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(width: 355 * scale, child: Text(
                      posterText,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: (collective ? 12.6 : 14.2) * scale,
                        fontFamily: 'BirthdayLato',
                        height: 1.2,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                    ))),
                    )),
                    SizedBox(height: 8 * scale),
                    Text(
                      'UAI CAPOEIRA • BOCAIÚVA - MG',
                      style: TextStyle(
                        color: tema.accent,
                        fontSize: 10 * scale,
                        fontFamily: 'BirthdayInterDisplay',
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPeopleGrid(
    List<BirthdayArtPerson> pessoas,
    double scale,
    BirthdayArtTheme tema,
  ) {
    return BirthdayPosterPeople(
      people: pessoas.map((p) => BirthdayPosterPerson(p.nome, p.fotoUrl, p.idade)).toList(),
      accent: tema.accent,
      nameFont: _nameFont(tema),
      photoBuilder: (context, person, radius) => _buildPhotoCard(
        BirthdayArtPerson(nome: person.name, fotoUrl: person.photoUrl, idade: person.age),
        tema, scale, radius: radius,
      ),
    );
  }

  Widget _buildPhotoCard(
    BirthdayArtPerson pessoa,
    BirthdayArtTheme tema,
    double scale, {
    required double radius,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tema.accent, width: 2.3 * scale),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.white.withAlpha(20)),
          _foto(pessoa.fotoUrl),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withAlpha(26),
                  ],
                ),
              ),
            ),
          ),
          // Moldura superior: cobre o encontro entre o recorte e a foto,
          // sem sobrepor o conteúdo central nem deformar a imagem.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white.withAlpha(175),
                    width: 1.1 * scale),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.all(1.8 * scale),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(math.max(0.0, radius - 2.0 * scale)),
                    border: Border.all(color: tema.accent.withAlpha(190),
                      width: 1.0 * scale),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _foto(String? url) {
    if (url == null || url.trim().isEmpty) {
      return _buildFotoPlaceholder();
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      imageBuilder: (context, imageProvider) {
        return DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.18),
              filterQuality: FilterQuality.high,
            ),
          ),
        );
      },
      placeholder: (context, url) => _buildFotoPlaceholder(showLoader: true),
      errorWidget: (context, url, error) => _buildFotoPlaceholder(),
    );
  }

  Widget _buildFotoPlaceholder({bool showLoader = false}) {
    return Container(
      color: Colors.black.withAlpha(24),
      child: Center(
        child: showLoader
            ? const CircularProgressIndicator(strokeWidth: 2)
            : const Icon(Icons.person, color: Colors.white70, size: 44),
      ),
    );
  }


}
