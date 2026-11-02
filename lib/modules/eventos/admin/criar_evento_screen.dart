import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_identidade_service.dart';

import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/widgets/portfolio_cover_image.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/widgets/portfolio_cover_cropper.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_service.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_participantes_cache_service.dart';
import 'package:uai_capoeira/modules/eventos/widgets/evento_certificado_config_dialog.dart';

class CriarEventoScreen extends StatefulWidget {
  final EventoModel? evento;

  const CriarEventoScreen({super.key, this.evento});

  @override
  State<CriarEventoScreen> createState() => _CriarEventoScreenState();
}

class _CriarEventoScreenState extends State<CriarEventoScreen> {
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  final GlobalKey _dadosKey = GlobalKey();
  final GlobalKey _bannerKey = GlobalKey();
  final GlobalKey _financeiroKey = GlobalKey();
  final GlobalKey _camisaKey = GlobalKey();
  final GlobalKey _certificadoKey = GlobalKey();
  final GlobalKey _webKey = GlobalKey();
  final GlobalKey _linksKey = GlobalKey();

  final EventoService _eventoService = EventoService();
  final EventoParticipantesCacheService _cacheService =
      EventoParticipantesCacheService();
  final PermissaoService _permissaoService = PermissaoService();
  late final PermissionAccessGuard _accessGuard = PermissionAccessGuard(
    service: _permissaoService,
  );

  bool _carregandoPermissoes = true;
  bool _podeCriarEvento = false;
  bool _podeEditarEvento = false;

  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _tipoController = TextEditingController();
  final _dataController = TextEditingController();
  final _horarioController = TextEditingController();
  final _localController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _organizadoresController = TextEditingController();
  final _linkFotosController = TextEditingController();
  final _linkPreviaController = TextEditingController();
  final _linkPlaylistController = TextEditingController();

  final _valorCamisaMangaController = TextEditingController();
  final _valorCamisaMangaLongaController = TextEditingController();
  final _valorCamisaRegataController = TextEditingController();

  Uint8List? _bannerBytes;
  String? _bannerContentType;
  String? _bannerUrl;
  bool _isUploadingBanner = false;
  double _portfolioCoverPositionX = 0;
  double _portfolioCoverPositionY = 0;
  double _portfolioCoverScale = 1;

  double _valorInscricao = 0;
  int _maxParcelas = 1;
  int _descontoAVista = 0;
  bool _permiteParcelamento = false;
  DateTime? _dataLimitePrimeiraParcela;

  bool _temCamisa = false;
  bool _temControleGastos = false;
  bool _temPatrocinadores = false;
  bool _auditoriaVisivelGestores = false;
  bool _temRelatorioFinanceiro = false;
  bool _temCobrancaInscricao = false;
  bool _linksHabilitados = false;
  // Seções expansíveis inspiradas na edição de alunos.
  String? _secaoEventoAberta;
  Set<String> _gestoresSelecionados = {};
  bool _gestoresPersonalizados = false;

  // Compatibilidade antiga: continua existindo como valor padrão da camisa.
  // Na prática, ele será sincronizado com o valor de MANGA.
  double _valorCamisa = 0;

  // Novo controle financeiro da confecção:
  // cada tipo de camisa pode ter um valor unitário diferente.
  Map<String, double> _valoresPorTipoCamisa = {
    'MANGA': 0,
    'MANGA_LONGA': 0,
    'REGATA': 0,
  };

  bool _camisaObrigatoria = false;

  static const String _modelagemNormal = 'NORMAL';
  static const String _modelagemBabyLook = 'BABY_LOOK';

  static const String _tipoManga = 'MANGA';
  static const String _tipoMangaLonga = 'MANGA_LONGA';
  static const String _tipoRegata = 'REGATA';

  final List<String> _todosTamanhos = [
    '1A',
    '2A',
    '4A',
    '6A',
    '8A',
    '10A',
    '12A',
    '14A',
    'PP',
    'P',
    'M',
    'G',
    'GG',
    'EGG',
  ];

  final List<String> _todasModelagensCamisa = [
    _modelagemNormal,
    _modelagemBabyLook,
  ];

  final List<String> _todosTiposCamisa = [
    _tipoManga,
    _tipoMangaLonga,
    _tipoRegata,
  ];

  List<String> _tamanhosSelecionados = [];
  List<String> _modelagensCamisaSelecionadas = [
    _modelagemNormal,
    _modelagemBabyLook,
  ];
  List<String> _tiposCamisaSelecionados = [
    _tipoManga,
    _tipoMangaLonga,
    _tipoRegata,
  ];

  bool _temCertificado = false;
  ConfiguracoesCertificadoEvento _configCertificado =
      ConfiguracoesCertificadoEvento.padrao();
  bool _mostrarNoPortfolioWeb = false;

  String _status = 'andamento';
  bool _isLoading = false;

  final List<String> _tiposEvento = [
    'BATIZADO & TROCA DE CORDAS',
    'ALUNO DESTAQUE',
    'EVENTO EM OUTRA CIDADE',
    'CONFRATERNIZAÇÃO',
    'RODAS',
    'AULÃO',
    'CAMPEONATO',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.evento != null) {
      _preencherFormulario();
    }
    _verificarPermissoes();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _tipoController.dispose();
    _dataController.dispose();
    _horarioController.dispose();
    _localController.dispose();
    _cidadeController.dispose();
    _organizadoresController.dispose();
    _linkFotosController.dispose();
    _linkPreviaController.dispose();
    _linkPlaylistController.dispose();
    _valorCamisaMangaController.dispose();
    _valorCamisaMangaLongaController.dispose();
    _valorCamisaRegataController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _modoEdicao => widget.evento != null;

  bool get _podeSalvarEvento {
    if (_modoEdicao) return _podeEditarEvento;
    return _podeCriarEvento;
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  String _normalizarModelagemCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return _modelagemBabyLook;
    }

    return _modelagemNormal;
  }

  String _normalizarTipoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'MANGA_LONGA' ||
        clean == 'LONGA' ||
        clean == 'MANGA_COMPRIDA') {
      return _tipoMangaLonga;
    }

    if (clean == 'REGATA') {
      return _tipoRegata;
    }

    return _tipoManga;
  }

  String _modelagemCamisaLabel(String value) {
    switch (_normalizarModelagemCamisa(value)) {
      case _modelagemBabyLook:
        return 'Baby Look';
      case _modelagemNormal:
      default:
        return 'Normal';
    }
  }

  String _tipoCamisaLabel(String value) {
    switch (_normalizarTipoCamisa(value)) {
      case _tipoMangaLonga:
        return 'Manga Longa';
      case _tipoRegata:
        return 'Regata';
      case _tipoManga:
      default:
        return 'Manga';
    }
  }

  List<String> _normalizarListaModelagens(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarModelagemCamisa(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) {
      return List<String>.from(_todasModelagensCamisa);
    }

    result.sort((a, b) {
      final ordem = {_modelagemNormal: 0, _modelagemBabyLook: 1};

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  List<String> _normalizarListaTiposCamisa(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarTipoCamisa(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) {
      return List<String>.from(_todosTiposCamisa);
    }

    result.sort((a, b) {
      final ordem = {_tipoManga: 0, _tipoMangaLonga: 1, _tipoRegata: 2};

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  double _parseValorMoeda(String value) {
    final clean = value
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    if (clean.isEmpty) return 0;

    return double.tryParse(clean) ?? 0;
  }

  String _formatarValorCampo(double value) {
    if (value <= 0) return '';
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  Map<String, double> _normalizarValoresPorTipoCamisa(
    dynamic raw, {
    double fallback = 0,
  }) {
    final result = <String, double>{
      _tipoManga: fallback,
      _tipoMangaLonga: fallback,
      _tipoRegata: fallback,
    };

    if (raw is Map) {
      raw.forEach((key, value) {
        final tipo = _normalizarTipoCamisa(key);
        final valor = value is num
            ? value.toDouble()
            : double.tryParse(
                    value?.toString().replaceAll(',', '.').trim() ?? '',
                  ) ??
                  fallback;

        result[tipo] = valor;
      });
    }

    return result;
  }

  void _sincronizarControllersValoresCamisa() {
    _valorCamisaMangaController.text = _formatarValorCampo(
      _valoresPorTipoCamisa[_tipoManga] ?? _valorCamisa,
    );
    _valorCamisaMangaLongaController.text = _formatarValorCampo(
      _valoresPorTipoCamisa[_tipoMangaLonga] ?? _valorCamisa,
    );
    _valorCamisaRegataController.text = _formatarValorCampo(
      _valoresPorTipoCamisa[_tipoRegata] ?? _valorCamisa,
    );
  }

  void _sincronizarMapaValoresCamisa() {
    final manga = _parseValorMoeda(_valorCamisaMangaController.text);
    final mangaLonga = _parseValorMoeda(_valorCamisaMangaLongaController.text);
    final regata = _parseValorMoeda(_valorCamisaRegataController.text);

    _valoresPorTipoCamisa = {
      _tipoManga: manga,
      _tipoMangaLonga: mangaLonga,
      _tipoRegata: regata,
    };

    // Compatibilidade com telas antigas: o valor da Manga continua sendo
    // salvo também no campo antigo valorCamisa.
    _valorCamisa = manga;
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final permissoes = await Future.wait<bool>([
        _permissaoService.temPermissao('pode_criar_evento'),
        _permissaoService.temPermissao('pode_editar_evento'),
      ]);

      if (!mounted) return;

      setState(() {
        _podeCriarEvento = permissoes[0];
        _podeEditarEvento = permissoes[1];
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint(
        'Erro ao verificar permissões de criação/edição de evento: $e',
      );
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  void _showSnack(String message, {required _SnackType type}) {
    final t = context.uai;

    final color = switch (type) {
      _SnackType.success => t.success,
      _SnackType.error => t.error,
      _SnackType.warning => t.warning,
      _SnackType.info => t.info,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarSemPermissao([
    String mensagem = 'Você não tem permissão para criar ou editar eventos.',
  ]) {
    if (!mounted) return;
    _showSnack(mensagem, type: _SnackType.error);
  }

  void _preencherFormulario() {
    final e = widget.evento!;

    _nomeController.text = e.nome;
    _descricaoController.text = e.descricao;
    _tipoController.text = e.tipo;
    _dataController.text = e.dataFormatada;
    _horarioController.text = e.horario;
    _localController.text = e.local;
    _cidadeController.text = e.cidade;
    _organizadoresController.text = e.organizadores.join(', ');
    _bannerUrl = e.linkBanner;
    _portfolioCoverPositionX = e.portfolioCoverPositionX;
    _portfolioCoverPositionY = e.portfolioCoverPositionY;
    _portfolioCoverScale = e.portfolioCoverScale;
    _linkFotosController.text = e.linkFotosVideos ?? '';
    _linkPreviaController.text = e.previaVideo ?? '';
    _linkPlaylistController.text = e.linkPlaylist ?? '';

    _valorInscricao = e.valorInscricao;
    _permiteParcelamento = e.permiteParcelamento;
    _maxParcelas = e.maxParcelas;
    _descontoAVista = e.descontoAVista;
    _dataLimitePrimeiraParcela = e.dataLimitePrimeiraParcela;

    _temCamisa = e.temCamisa;
    _temControleGastos = e.temControleGastos;
    _temPatrocinadores = e.temPatrocinadores;
    _temRelatorioFinanceiro = e.temRelatorioFinanceiro;
    _auditoriaVisivelGestores = e.auditoriaVisivelGestores;
    _temCobrancaInscricao = e.temCobrancaInscricao;
    _linksHabilitados = e.linksHabilitados;
    _gestoresPersonalizados = e.gestoresAutorizadosUids != null;
    _gestoresSelecionados = {...?e.gestoresAutorizadosUids};
    _valorCamisa = e.valorCamisa ?? 0;
    _valoresPorTipoCamisa = _normalizarValoresPorTipoCamisa(
      e.valoresPorTipoCamisa,
      fallback: _valorCamisa,
    );
    _sincronizarControllersValoresCamisa();
    _tamanhosSelecionados = List.from(e.tamanhosDisponiveis);
    _modelagensCamisaSelecionadas = _normalizarListaModelagens(
      e.modelagensCamisaDisponiveis,
    );
    _tiposCamisaSelecionados = _normalizarListaTiposCamisa(
      e.tiposCamisaDisponiveis,
    );
    _camisaObrigatoria = e.camisaObrigatoria;

    _temCertificado = e.temCertificado;
    _configCertificado = e.configuracoesCertificadoEvento;
    _mostrarNoPortfolioWeb = e.mostrarNoPortfolioWeb;
    _status = e.status;
  }

  Future<void> _selecionarData() async {
    final DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );

    if (data != null) {
      setState(() {
        _dataController.text =
            '${data.day.toString().padLeft(2, '0')}/'
            '${data.month.toString().padLeft(2, '0')}/'
            '${data.year}';
      });
    }
  }

  Future<void> _selecionarDataLimite() async {
    final DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );

    if (data != null) {
      setState(() => _dataLimitePrimeiraParcela = data);
    }
  }

  Future<void> _selecionarImagem() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar o banner.');
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;

        setState(() {
          _bannerBytes = bytes;
          _bannerContentType = image.mimeType ?? 'image/jpeg';
          _bannerUrl = null;
          _portfolioCoverPositionX = 0;
          _portfolioCoverPositionY = 0;
          _portfolioCoverScale = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao selecionar imagem: $e', type: _SnackType.error);
      }
    }
  }

  Future<void> _tirarFoto() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar o banner.');
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;

        setState(() {
          _bannerBytes = bytes;
          _bannerContentType = image.mimeType ?? 'image/jpeg';
          _bannerUrl = null;
          _portfolioCoverPositionX = 0;
          _portfolioCoverPositionY = 0;
          _portfolioCoverScale = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao tirar foto: $e', type: _SnackType.error);
      }
    }
  }

  Future<String?> _uploadBanner(Uint8List imageBytes, String eventoId) async {
    try {
      setState(() => _isUploadingBanner = true);

      final fileName =
          '${eventoId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('eventos')
          .child('banners')
          .child(fileName);

      await storageRef.putData(
        imageBytes,
        SettableMetadata(
          contentType: _bannerContentType ?? 'image/jpeg',
          customMetadata: {
            'uploaded_at': DateTime.now().toIso8601String(),
            'evento_id': eventoId,
          },
        ),
      );

      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Erro no upload: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingBanner = false);
    }
  }

  void _removerBanner() {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para remover o banner.');
      return;
    }

    if (widget.evento?.linkBanner != null && _bannerUrl != null) {
      _showConfirmDialog(
        title: 'Remover Banner',
        message: 'Deseja remover o banner permanentemente?',
        icon: Icons.delete_outline_rounded,
        color: context.uai.error,
        confirmLabel: 'REMOVER',
        onConfirm: () {
          setState(() {
            _bannerBytes = null;
            _bannerContentType = null;
            _bannerUrl = null;
          });
          _showSnack(
            'Banner será removido ao salvar',
            type: _SnackType.warning,
          );
        },
      );
    } else {
      setState(() {
        _bannerBytes = null;
        _bannerContentType = null;
        _bannerUrl = null;
      });
    }
  }

  void _mostrarOpcoesImagem() {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar o banner.');
      return;
    }

    final t = context.uai;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              boxShadow: t.cardShadow,
              border: Border.all(color: t.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                _dialogHandle(),
                const SizedBox(height: 8),
                _bottomOption(
                  icon: Icons.photo_library_rounded,
                  color: t.info,
                  title: 'Escolher da Galeria',
                  onTap: () {
                    Navigator.pop(context);
                    _selecionarImagem();
                  },
                ),
                _bottomOption(
                  icon: Icons.camera_alt_rounded,
                  color: t.success,
                  title: 'Tirar Foto',
                  onTap: () {
                    Navigator.pop(context);
                    _tirarFoto();
                  },
                ),
                if (_bannerBytes != null || _bannerUrl != null)
                  _bottomOption(
                    icon: Icons.delete_rounded,
                    color: t.error,
                    title: 'Remover Banner',
                    onTap: () {
                      Navigator.pop(context);
                      _removerBanner();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomOption({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selecionarTamanhos() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar tamanhos.');
      return;
    }

    List<String> tamanhosTemp = List.from(_tamanhosSelecionados);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final primary = _ensureVisible(t.primary, t.surface);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.cardRadius + 2),
                      border: Border.all(color: t.border),
                      boxShadow: t.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: primary.withAlpha(31),
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                                child: Icon(
                                  Icons.checkroom_rounded,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Tamanhos Disponíveis',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _todosTamanhos.length,
                            itemBuilder: (context, index) {
                              final tamanho = _todosTamanhos[index];
                              final isSelected = tamanhosTemp.contains(tamanho);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: isSelected
                                      ? Color.alphaBlend(
                                          primary.withAlpha(26),
                                          t.cardAlt,
                                        )
                                      : t.cardAlt,
                                  borderRadius: BorderRadius.circular(
                                    t.inputRadius,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        t.inputRadius,
                                      ),
                                      border: Border.all(
                                        color: isSelected
                                            ? primary.withAlpha(71)
                                            : t.border,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: isSelected,
                                      activeColor: primary,
                                      title: Text(
                                        tamanho,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: isSelected
                                              ? primary
                                              : t.textPrimary,
                                        ),
                                      ),
                                      onChanged: (selected) {
                                        setStateDialog(() {
                                          if (selected == true) {
                                            tamanhosTemp.add(tamanho);
                                          } else {
                                            tamanhosTemp.remove(tamanho);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.card,
                            border: Border(top: BorderSide(color: t.border)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: t.textPrimary,
                                    side: BorderSide(color: t.border),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.buttonRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text('CANCELAR'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _tamanhosSelecionados = tamanhosTemp;
                                    });
                                    Navigator.pop(dialogContext);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: t.primary,
                                    foregroundColor: _readableOn(t.primary),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.buttonRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'OK',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMultiSelectCard({
    required IconData icon,
    required String title,
    required String emptyText,
    required String values,
    required VoidCallback onTap,
  }) {
    final t = context.uai;

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: _ensureVisible(t.primary, t.cardAlt)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  values.trim().isEmpty ? emptyText : values,
                  style: TextStyle(
                    color: values.trim().isEmpty
                        ? t.textSecondary
                        : t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _selecionarModelagensCamisa() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar modelagens.');
      return;
    }

    final temp = List<String>.from(_modelagensCamisaSelecionadas);

    await _abrirDialogMultiSelecao(
      titulo: 'Modelagens Disponíveis',
      opcoes: _todasModelagensCamisa,
      selecionadosTemp: temp,
      labelBuilder: _modelagemCamisaLabel,
      onSalvar: (selecionados) {
        setState(() {
          _modelagensCamisaSelecionadas = selecionados.isEmpty
              ? List.from(_todasModelagensCamisa)
              : selecionados;
        });
      },
    );
  }

  void _selecionarTiposCamisa() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao(
        'Você não tem permissão para alterar tipos de camisa.',
      );
      return;
    }

    final temp = List<String>.from(_tiposCamisaSelecionados);

    await _abrirDialogMultiSelecao(
      titulo: 'Tipos de Camisa Disponíveis',
      opcoes: _todosTiposCamisa,
      selecionadosTemp: temp,
      labelBuilder: _tipoCamisaLabel,
      onSalvar: (selecionados) {
        setState(() {
          _tiposCamisaSelecionados = selecionados.isEmpty
              ? List.from(_todosTiposCamisa)
              : selecionados;
        });
      },
    );
  }

  Future<void> _abrirDialogMultiSelecao({
    required String titulo,
    required List<String> opcoes,
    required List<String> selecionadosTemp,
    required String Function(String) labelBuilder,
    required ValueChanged<List<String>> onSalvar,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final primary = _ensureVisible(t.primary, t.surface);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.cardRadius + 2),
                      border: Border.all(color: t.border),
                      boxShadow: t.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: primary.withAlpha(31),
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                                child: Icon(
                                  Icons.checkroom_rounded,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  titulo,
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: opcoes.length,
                            itemBuilder: (context, index) {
                              final item = opcoes[index];
                              final isSelected = selecionadosTemp.contains(
                                item,
                              );

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: isSelected
                                      ? Color.alphaBlend(
                                          primary.withAlpha(26),
                                          t.cardAlt,
                                        )
                                      : t.cardAlt,
                                  borderRadius: BorderRadius.circular(
                                    t.inputRadius,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        t.inputRadius,
                                      ),
                                      border: Border.all(
                                        color: isSelected
                                            ? primary.withAlpha(71)
                                            : t.border,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: isSelected,
                                      activeColor: primary,
                                      title: Text(
                                        labelBuilder(item),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: isSelected
                                              ? primary
                                              : t.textPrimary,
                                        ),
                                      ),
                                      onChanged: (selected) {
                                        setStateDialog(() {
                                          if (selected == true) {
                                            if (!selecionadosTemp.contains(
                                              item,
                                            )) {
                                              selecionadosTemp.add(item);
                                            }
                                          } else {
                                            selecionadosTemp.remove(item);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.card,
                            border: Border(top: BorderSide(color: t.border)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: t.textPrimary,
                                    side: BorderSide(color: t.border),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.buttonRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text('CANCELAR'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    onSalvar(
                                      List<String>.from(selecionadosTemp),
                                    );
                                    Navigator.pop(dialogContext);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: t.primary,
                                    foregroundColor: _readableOn(t.primary),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.buttonRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'OK',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showConfirmDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withAlpha(31),
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                          child: Icon(icon, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      style: TextStyle(color: t.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.textPrimary,
                              side: BorderSide(color: t.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  t.buttonRadius,
                                ),
                              ),
                            ),
                            child: const Text('CANCELAR'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              onConfirm();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: _readableOn(color),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  t.buttonRadius,
                                ),
                              ),
                            ),
                            child: Text(
                              confirmLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSemAcessoEvento() {
    final t = context.uai;
    final warning = _ensureVisible(t.warning, t.card);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.cardRadius),
                border: Border.all(color: warning.withAlpha(46)),
                boxShadow: t.softShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 64, color: warning),
                  const SizedBox(height: 12),
                  Text(
                    _modoEdicao ? 'Edição bloqueada' : 'Criação bloqueada',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _modoEdicao
                        ? 'Peça para o administrador liberar “Editar evento” nas suas permissões.'
                        : 'Peça para o administrador liberar “Criar evento” nas suas permissões.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textSecondary,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _verificarPermissoes,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Recarregar permissões'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ensureVisible(t.primary, t.card),
                      side: BorderSide(color: t.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required bool value,
    required IconData icon,
    required String title,
    required String activeText,
    required String inactiveText,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(
      value ? activeColor : t.textSecondary,
      t.card,
    );

    return Material(
      color: value ? Color.alphaBlend(accent.withAlpha(20), t.card) : t.card,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.inputRadius),
          border: Border.all(
            color: value ? accent.withAlpha(66) : t.border,
            width: value ? 1.4 : 1,
          ),
        ),
        child: SwitchListTile(
          value: value,
          activeThumbColor: accent,
          onChanged: onChanged,
          secondary: Icon(icon, color: accent),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: value ? accent : t.textPrimary,
            ),
          ),
          subtitle: Text(
            value ? activeText : inactiveText,
            style: TextStyle(
              fontSize: 12,
              color: value ? accent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrirConfigCertificado() async {
    final permitido = await _accessGuard.revalidate(
      context,
      permission: 'pode_configurar_certificados_evento',
      message: 'Você não tem permissão para configurar certificados do evento.',
    );
    if (!mounted || !permitido) return;

    final resultado = await EventoCertificadoConfigDialog.show(
      context: context,
      configuracaoInicial: _configCertificado.copyWith(ativo: _temCertificado),
    );

    if (resultado == null || !mounted) return;

    setState(() {
      _configCertificado = resultado;
      _temCertificado = resultado.ativo;
    });

    _showSnack(
      'Configurações do certificado atualizadas. Salve o evento para gravar.',
      type: _SnackType.success,
    );
  }

  Widget _buildCertificadoResumoCard() {
    final t = context.uai;
    final config = _configCertificado;
    final assinaturas = config.assinaturasValidas;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    final success = _ensureVisible(t.success, t.cardAlt);
    final warning = _ensureVisible(t.warning, t.cardAlt);

    String modeloLabel() {
      switch (config.modeloPadrao) {
        case 'CERTIFICADO':
          return 'Certificado simples';
        case 'CERTIFICADOCOMCPF':
          return 'Certificado com CPF';
        case 'DIPLOMA':
          return 'Diploma';
        case ConfiguracoesCertificadoEvento.modeloAutomatico:
        default:
          return 'Automático pela graduação';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(
          color: _temCertificado ? success.withAlpha(51) : t.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (_temCertificado ? success : warning).withAlpha(28),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                child: Icon(
                  _temCertificado
                      ? Icons.verified_rounded
                      : Icons.info_outline_rounded,
                  color: _temCertificado ? success : warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _temCertificado
                          ? 'Certificados configurados'
                          : 'Certificados desativados',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _temCertificado
                          ? '${assinaturas.length} assinatura(s) • ${modeloLabel()}'
                          : 'Ative para configurar assinaturas e modelo.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.7,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_temCertificado) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _certificadoChip(
                  icon: Icons.auto_awesome_rounded,
                  label: modeloLabel(),
                  color: primary,
                ),
                _certificadoChip(
                  icon: Icons.location_city_rounded,
                  label: config.usarCidadeDoEvento
                      ? 'Cidade do evento'
                      : 'Cidade personalizada',
                  color: t.info,
                ),
                _certificadoChip(
                  icon: Icons.calendar_month_rounded,
                  label: config.usarDataDoEvento
                      ? 'Data do evento'
                      : 'Data personalizada',
                  color: t.warning,
                ),
                _certificadoChip(
                  icon: Icons.format_size_rounded,
                  label: '${config.textos.length} texto(s) 2.0',
                  color: t.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...assinaturas.take(5).map((assinatura) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.draw_rounded, color: t.textMuted, size: 16),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${assinatura.nome}  •  ${assinatura.apelido}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _abrirConfigCertificado,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                _temCertificado
                    ? 'ABRIR ESTÚDIO DO CERTIFICADO'
                    : 'ATIVAR ESTÚDIO',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withAlpha(77)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _certificadoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificadoSimples() {
    return _buildToggleCard(
      value: _temCertificado,
      icon: Icons.card_membership_rounded,
      title: 'Certificados',
      activeText: 'Este evento terá certificados',
      inactiveText: 'Este evento NÃO terá certificados',
      activeColor: context.uai.success,
      onChanged: (value) {
        setState(() {
          _temCertificado = value;
          _configCertificado = _configCertificado.copyWith(ativo: value);
        });
      },
    );
  }

  Widget _buildPortfolioWebSimples() {
    return _buildToggleCard(
      value: _mostrarNoPortfolioWeb,
      icon: Icons.web_rounded,
      title: 'Mostrar no Portfólio Web',
      activeText: 'Este evento aparecerá no site',
      inactiveText: 'Este evento NÃO aparecerá no site',
      activeColor: context.uai.info,
      onChanged: (value) {
        setState(() => _mostrarNoPortfolioWeb = value);
      },
    );
  }

  String _nomeGestor(Map<String, dynamic> data) {
    for (final campo in ['nome_completo', 'nome', 'name', 'displayName']) {
      final valor = (data[campo] ?? '').toString().trim();
      if (valor.isNotEmpty) return valor;
    }
    return (data['email'] ?? 'Usuário sem nome').toString();
  }

  String? _fotoGestor(Map<String, dynamic> data) {
    for (final campo in [
      'foto_url',
      'fotoUrl',
      'photoURL',
      'photoUrl',
      'url_foto',
      'imagem_url',
      'imagemUrl',
      'foto_perfil',
      'foto_perfil_url',
      'fotoPerfilUrl',
      'foto_perfil_aluno',
      'avatar',
      'avatar_url',
    ]) {
      final valor = (data[campo] ?? '').toString().trim();
      if (valor.startsWith('https://') || valor.startsWith('http://')) {
        return valor;
      }
    }
    return null;
  }

  Future<void> _configurarGestoresEvento() async {
    if (!await _permissaoService.usuarioAtualEhAdmin()) {
      if (mounted) {
        _showSnack(
          'Somente administradores podem definir gestores por evento.',
          type: _SnackType.error,
        );
      }
      return;
    }
    try {
      final usuarios = await FirebaseFirestore.instance
          .collection('usuarios')
          .get();
      if (!mounted) return;
      // Mesma identidade da tela Gerenciar Usuários, mas só contas de gestão.
      // Nunca listar identidades que são apenas da Área do Aluno.
      final itens =
          usuarios.docs.where((doc) {
            final data = doc.data();
            return UsuarioIdentidadeService.deveExibirNaGestao(data) &&
                UsuarioIdentidadeService.temAcessoGestao(data) &&
                (data['status_conta'] ?? '').toString().toLowerCase() !=
                    'bloqueada' &&
                (data['status_conta'] ?? '').toString().toLowerCase() !=
                    'inativa';
          }).toList()..sort(
            (a, b) => _nomeGestor(
              a.data(),
            ).toLowerCase().compareTo(_nomeGestor(b.data()).toLowerCase()),
          );
      final selecionados = {..._gestoresSelecionados};
      var personalizado = _gestoresPersonalizados;
      var busca = '';
      final resultado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, atualizar) {
            final filtrados = itens.where((doc) {
              final data = doc.data();
              return _nomeGestor(data).toLowerCase().contains(busca) ||
                  (data['email'] ?? '').toString().toLowerCase().contains(
                    busca,
                  ) ||
                  (data['tipo'] ?? '').toString().toLowerCase().contains(busca);
            }).toList();
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 500,
                  maxHeight: 620,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFFCE8E8),
                            child: Icon(
                              Icons.admin_panel_settings_rounded,
                              color: Color(0xFFBD1E1E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Acesso à gestão',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Escolha quem poderá gerenciar este evento',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          title: const Text(
                            'Restringir gestores',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            personalizado
                                ? 'Somente selecionados e administradores podem gerir.'
                                : 'Permissões gerais continuam valendo.',
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: personalizado,
                          onChanged: (v) => atualizar(() => personalizado = v),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (personalizado) ...[
                        TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Buscar nome, e-mail ou função',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onChanged: (v) =>
                              atualizar(() => busca = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${selecionados.length} selecionado(s) · ${filtrados.length} usuário(s) de gestão',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Flexible(
                        child: personalizado
                            ? filtrados.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Text(
                                          'Nenhum usuário de gestão encontrado.',
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filtrados.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 7),
                                      itemBuilder: (context, index) {
                                        final doc = filtrados[index];
                                        final data = doc.data();
                                        final nome = _nomeGestor(data);
                                        final foto = _fotoGestor(data);
                                        final selecionado = selecionados
                                            .contains(doc.id);
                                        final email = (data['email'] ?? '')
                                            .toString();
                                        final tipo = (data['tipo'] ?? 'Gestão')
                                            .toString()
                                            .toUpperCase();
                                        return Material(
                                          color: selecionado
                                              ? const Color(0xFFFFF0F0)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            onTap: () => atualizar(() {
                                              if (selecionado) {
                                                selecionados.remove(doc.id);
                                              } else {
                                                selecionados.add(doc.id);
                                              }
                                            }),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: selecionado
                                                      ? const Color(0xFFCB2424)
                                                      : Theme.of(context)
                                                            .dividerColor
                                                            .withAlpha(90),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 20,
                                                    backgroundColor:
                                                        const Color(0xFFF4E4E4),
                                                    backgroundImage:
                                                        foto == null
                                                        ? null
                                                        : CachedNetworkImageProvider(
                                                            foto,
                                                          ),
                                                    child: foto != null
                                                        ? null
                                                        : Text(
                                                            nome.isNotEmpty
                                                                ? nome[0]
                                                                      .toUpperCase()
                                                                : '?',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Color(
                                                                    0xFFAD2020,
                                                                  ),
                                                                ),
                                                          ),
                                                  ),
                                                  const SizedBox(width: 9),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          nome,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                        Text(
                                                          email,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                              ),
                                                        ),
                                                        Text(
                                                          tipo,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Color(
                                                                  0xFFC12424,
                                                                ),
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Checkbox(
                                                    value: selecionado,
                                                    activeColor: const Color(
                                                      0xFFBB1D1D,
                                                    ),
                                                    onChanged: (v) =>
                                                        atualizar(() {
                                                          if (v == true) {
                                                            selecionados.add(
                                                              doc.id,
                                                            );
                                                          } else {
                                                            selecionados.remove(
                                                              doc.id,
                                                            );
                                                          }
                                                        }),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    )
                            : const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Todos os usuários com permissão geral poderão acessar.',
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('CANCELAR'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('CONFIRMAR'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (resultado == true && mounted) {
        setState(() {
          _gestoresPersonalizados = personalizado;
          _gestoresSelecionados = selecionados;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Não foi possível carregar os usuários: $e',
          type: _SnackType.error,
        );
      }
    }
  }

  Widget _seletorGestoresEvento() => Card(
    child: ListTile(
      leading: const Icon(Icons.admin_panel_settings_outlined),
      title: const Text('Gestores autorizados'),
      subtitle: Text(
        _gestoresPersonalizados
            ? '${_gestoresSelecionados.length} usuário(s) selecionado(s) · sujeito às permissões individuais'
            : 'Permissões gerais (compatibilidade com eventos existentes)',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _configurarGestoresEvento,
    ),
  );

  Future<void> _salvar() async {
    final permitido = await _accessGuard.revalidate(
      context,
      permission: _modoEdicao ? 'pode_editar_evento' : 'pode_criar_evento',
      message: _modoEdicao
          ? 'Você não tem permissão para editar eventos.'
          : 'Você não tem permissão para criar eventos.',
    );
    if (!mounted || !permitido) {
      return;
    }

    if (_status == 'finalizado' &&
        !await _accessGuard.revalidate(
          context,
          permission: 'pode_finalizar_evento',
          message: 'Você não tem permissão para finalizar eventos.',
        )) {
      return;
    }

    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final partesData = _dataController.text.split('/');
      final data = DateTime(
        int.parse(partesData[2]),
        int.parse(partesData[1]),
        int.parse(partesData[0]),
      );

      final organizadores = _organizadoresController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final tipo = _tipoController.text;
      final alteraGraduacao =
          tipo.contains('BATIZADO') || tipo.contains('CAMPEONATO');
      final geraCertificado = _temCertificado;

      final bool bannerFoiRemovido =
          widget.evento?.linkBanner != null &&
          _bannerUrl == null &&
          _bannerBytes == null;

      if (bannerFoiRemovido && widget.evento?.linkBanner != null) {
        try {
          final oldBannerRef = FirebaseStorage.instance.refFromURL(
            widget.evento!.linkBanner!,
          );
          await oldBannerRef.delete();
          debugPrint('Banner antigo removido do Storage');
        } catch (e) {
          debugPrint('Erro ao remover banner antigo: $e');
        }
      }

      String? novaBannerUrl = _bannerUrl;

      if (_bannerBytes != null) {
        if (widget.evento?.linkBanner != null &&
            widget.evento!.linkBanner != _bannerUrl) {
          try {
            final oldBannerRef = FirebaseStorage.instance.refFromURL(
              widget.evento!.linkBanner!,
            );
            await oldBannerRef.delete();
            debugPrint('Banner antigo removido antes do upload');
          } catch (e) {
            debugPrint('Erro ao remover banner antigo: $e');
          }
        }

        final tempEventoId =
            widget.evento?.id ??
            DateTime.now().millisecondsSinceEpoch.toString();
        novaBannerUrl = await _uploadBanner(_bannerBytes!, tempEventoId);

        if (novaBannerUrl == null) {
          throw Exception('Erro ao fazer upload do banner');
        }
      } else if (bannerFoiRemovido) {
        novaBannerUrl = null;
      }

      _sincronizarMapaValoresCamisa();

      final evento = EventoModel(
        id: widget.evento?.id,
        nome: _nomeController.text.trim(),
        descricao: _descricaoController.text.trim(),
        tipo: tipo,
        data: data,
        horario: _horarioController.text.trim(),
        local: _localController.text.trim(),
        cidade: _cidadeController.text.trim(),
        organizadores: organizadores,
        status: _status,
        valorInscricao: _valorInscricao,
        permiteParcelamento: _permiteParcelamento,
        maxParcelas: _maxParcelas,
        descontoAVista: _descontoAVista,
        dataLimitePrimeiraParcela: _dataLimitePrimeiraParcela,
        temControleGastos: _temControleGastos,
        temPatrocinadores: _temPatrocinadores,
        temRelatorioFinanceiro: _temRelatorioFinanceiro,
        auditoriaVisivelGestores: _auditoriaVisivelGestores,
        temCobrancaInscricao: _temCobrancaInscricao,
        linksHabilitados: _linksHabilitados,
        gestoresAutorizadosUids: _gestoresPersonalizados
            ? _gestoresSelecionados.toList()
            : null,
        temCamisa: _temCamisa,
        valorCamisa: _valorCamisa,
        valoresPorTipoCamisa: _valoresPorTipoCamisa,
        tamanhosDisponiveis: _tamanhosSelecionados,
        modelagensCamisaDisponiveis: _modelagensCamisaSelecionadas,
        tiposCamisaDisponiveis: _tiposCamisaSelecionados,
        camisaObrigatoria: _camisaObrigatoria,
        alteraGraduacao: alteraGraduacao,
        geraCertificado: geraCertificado,
        tipoPublico: 'todos',
        linkBanner: novaBannerUrl,
        portfolioCoverPositionX: _portfolioCoverPositionX,
        portfolioCoverPositionY: _portfolioCoverPositionY,
        portfolioCoverScale: _portfolioCoverScale,
        linkFotosVideos: _linkFotosController.text.isNotEmpty
            ? _linkFotosController.text.trim()
            : null,
        previaVideo: _linkPreviaController.text.isNotEmpty
            ? _linkPreviaController.text.trim()
            : null,
        linkPlaylist: _linkPlaylistController.text.isNotEmpty
            ? _linkPlaylistController.text.trim()
            : null,
        temCertificado: _temCertificado,
        configuracoesCertificado: _configCertificado.toMap(),
        modeloCertificadoId: _temCertificado
            ? _configCertificado.modeloPadrao
            : null,
        modeloCertificadoPath: null,
        criadoEm: null,
        atualizadoEm: null,
        mostrarNoPortfolioWeb: _mostrarNoPortfolioWeb,
      );

      final eventoId = await _eventoService.salvarEvento(evento);

      if (eventoId == null) {
        throw Exception('Erro ao salvar evento: ID não gerado');
      }

      if (_bannerBytes != null &&
          novaBannerUrl != null &&
          widget.evento?.id == null) {
        try {
          final storageRef = FirebaseStorage.instance.refFromURL(novaBannerUrl);
          final newPath =
              'eventos/banners/$eventoId-${DateTime.now().millisecondsSinceEpoch}.jpg';
          final newRef = FirebaseStorage.instance.ref().child(newPath);

          await newRef.putData(
            _bannerBytes!,
            SettableMetadata(
              contentType: _bannerContentType ?? 'image/jpeg',
              customMetadata: {
                'uploaded_at': DateTime.now().toIso8601String(),
                'evento_id': eventoId,
              },
            ),
          );
          final finalUrl = await newRef.getDownloadURL();

          await _eventoService.atualizarBanner(eventoId, finalUrl);
          await storageRef.delete();
        } catch (e) {
          debugPrint('Erro ao renomear banner: $e');
        }
      }

      if (widget.evento != null && _status == 'finalizado') {
        try {
          await _cacheService.reconstruirCacheParticipantes(
            eventoId,
            forceServer: true,
          );
        } catch (e) {
          debugPrint('Erro ao reconstruir cache após salvar evento: $e');
        }
      }

      if (mounted) {
        _showSnack(
          widget.evento == null
              ? 'Evento criado com sucesso!'
              : 'Evento atualizado com sucesso!',
          type: _SnackType.success,
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro: $e', type: _SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: primary),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obrigatorio = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: context.uai.textPrimary),
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(
        label: label + (obrigatorio ? ' *' : ''),
        icon: icon,
        hint: hint,
      ).copyWith(alignLabelWithHint: maxLines > 1),
      validator:
          validator ??
          (obrigatorio
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Campo obrigatório';
                  }
                  return null;
                }
              : null),
    );
  }

  Widget _valoresPorTipoCamisaCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.price_change_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Valores por tipo de camisa',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Defina o preço unitário usado no cadastro e no PDF de confecção.',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;

              final fields = [
                _valorTipoField(
                  controller: _valorCamisaMangaController,
                  label: 'Manga',
                  tipo: _tipoManga,
                  icon: Icons.checkroom_rounded,
                ),
                _valorTipoField(
                  controller: _valorCamisaMangaLongaController,
                  label: 'Manga Longa',
                  tipo: _tipoMangaLonga,
                  icon: Icons.accessibility_new_rounded,
                ),
                _valorTipoField(
                  controller: _valorCamisaRegataController,
                  label: 'Regata',
                  tipo: _tipoRegata,
                  icon: Icons.sports_martial_arts_rounded,
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 10),
                    fields[1],
                    const SizedBox(height: 10),
                    fields[2],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _infoBox(
            icon: Icons.info_outline_rounded,
            color: t.info,
            text:
                'O valor de Manga também será salvo como valor padrão da camisa para manter compatibilidade com eventos antigos.',
          ),
        ],
      ),
    );
  }

  Widget _valorTipoField({
    required TextEditingController controller,
    required String label,
    required String tipo,
    required IconData icon,
  }) {
    final t = context.uai;

    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
      decoration: _inputDecoration(
        label: '$label (R\$)',
        icon: icon,
        hint: '0,00',
      ),
      onChanged: (_) {
        _sincronizarMapaValoresCamisa();
        setState(() {});
      },
      validator: _temCamisa
          ? (value) {
              final valor = _parseValorMoeda(value ?? '');
              if (valor < 0) return 'Valor inválido';
              return null;
            }
          : null,
    );
  }

  Widget _numberField({
    required String label,
    required IconData icon,
    required num initialValue,
    required ValueChanged<String> onChanged,
    bool obrigatorio = false,
    String? suffixText,
  }) {
    final t = context.uai;

    return TextFormField(
      initialValue: initialValue.toString(),
      keyboardType: TextInputType.number,
      style: TextStyle(color: t.textPrimary),
      decoration: _inputDecoration(
        label: label + (obrigatorio ? ' *' : ''),
        icon: icon,
      ).copyWith(suffixText: suffixText),
      onChanged: onChanged,
      validator: obrigatorio
          ? (value) {
              if (value == null || value.isEmpty) return 'Campo obrigatório';
              if (double.tryParse(value) == null) return 'Valor inválido';
              return null;
            }
          : null,
    );
  }

  List<Widget> _orderedEventSections(List<Widget> children) {
    final active = <Widget>[];
    final inactive = <Widget>[];
    final fixed = <Widget>[];
    final admin = <Widget>[];
    for (final child in children) {
      if (child is SizedBox) continue;
      final key = child.key;
      bool? enabled;
      if (key == _financeiroKey) enabled = _temCobrancaInscricao;
      if (key == const ValueKey('Módulos financeiros do evento')) {
        enabled =
            _temControleGastos || _temPatrocinadores || _temRelatorioFinanceiro;
      }
      if (key == _camisaKey) enabled = _temCamisa;
      if (key == _certificadoKey) enabled = _temCertificado;
      if (key == _webKey) enabled = _mostrarNoPortfolioWeb;
      if (key == _linksKey) enabled = _linksHabilitados;
      if (key == const ValueKey('Auditoria do evento')) {
        enabled = _auditoriaVisivelGestores;
      }
      if (key == const ValueKey('gestores')) {
        admin.add(child);
      } else if (enabled == true) {
        active.add(child);
      } else if (enabled == false) {
        inactive.add(child);
      } else {
        fixed.add(child);
      }
    }
    Widget heading(String text) => Padding(
      key: ValueKey('grupo_$text'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          color: context.uai.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
    return [
      for (final child in fixed) ...[child, const SizedBox(height: 14)],
      if (active.isNotEmpty) heading('SEÇÕES ATIVAS'),
      for (final child in active) ...[child, const SizedBox(height: 14)],
      if (inactive.isNotEmpty) heading('SEÇÕES DESATIVADAS'),
      for (final child in inactive) ...[child, const SizedBox(height: 14)],
      if (admin.isNotEmpty) heading('ADMINISTRAÇÃO'),
      ...admin,
    ];
  }

  Widget _sectionCard({
    Key? sectionKey,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
    bool dense = false,
    bool expandable = true,
    bool enabled = true,
  }) {
    final t = context.uai;
    final accent = enabled ? _ensureVisible(color, t.card) : t.textMuted;
    final aberta = !expandable || _secaoEventoAberta == title;

    return KeyedSubtree(
      key: sectionKey ?? ValueKey(title),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(dense ? 13 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: accent.withAlpha(36)),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: expandable
                    ? () => setState(
                        () => _secaoEventoAberta = aberta ? null : title,
                      )
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: _sectionHeader(
                        icon: enabled ? icon : Icons.tune_rounded,
                        title: title,
                        subtitle: enabled ? subtitle : "$subtitle • desativado",
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (expandable)
                      Icon(
                        aberta
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: t.textSecondary,
                      ),
                  ],
                ),
              ),
              // Mantém os controles vivos: recolher não descarta alterações.
              Visibility(
                visible: aberta,
                maintainState: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withAlpha(31),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: color.withAlpha(41)),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.8,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final iconBox = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withAlpha(36),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withAlpha(41)),
            ),
            child: Icon(
              _modoEdicao
                  ? Icons.edit_calendar_rounded
                  : Icons.event_available_rounded,
              color: onPrimary,
              size: 33,
            ),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                _modoEdicao ? 'Editar Evento' : 'Criar Evento',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure dados, banner, taxas, camisa, certificados e portfólio web.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withAlpha(209),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.event_rounded, _status.toUpperCase()),
                  if (_temCamisa) _heroChip(Icons.checkroom_rounded, 'Camisa'),
                  if (_temCertificado)
                    _heroChip(Icons.card_membership_rounded, 'Certificado'),
                  if (_mostrarNoPortfolioWeb)
                    _heroChip(Icons.public_rounded, 'Site'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [iconBox, const SizedBox(height: 14), text],
            );
          }

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirAjusteBanner() async {
    final ImageProvider? provider = _bannerBytes != null
        ? MemoryImage(_bannerBytes!)
        : (_bannerUrl != null && _bannerUrl!.trim().isNotEmpty
              ? NetworkImage(_bannerUrl!)
              : null);
    if (provider == null) {
      _mostrarOpcoesImagem();
      return;
    }
    final result = await showPortfolioCoverCropper(
      context: context,
      imageProvider: provider,
      positionX: _portfolioCoverPositionX,
      positionY: _portfolioCoverPositionY,
      scale: _portfolioCoverScale,
      title: 'Ajustar banner do evento',
    );
    if (!mounted || result == null) return;
    setState(() {
      _portfolioCoverPositionX = result.positionX;
      _portfolioCoverPositionY = result.positionY;
      _portfolioCoverScale = result.scale;
    });
  }

  Widget _buildBannerPreview() {
    final t = context.uai;
    final hasBanner =
        _bannerBytes != null ||
        (_bannerUrl != null && _bannerUrl!.trim().isNotEmpty);

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasBanner ? _abrirAjusteBanner : _mostrarOpcoesImagem,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_bannerBytes != null)
                  ClipRect(
                    child: Transform.scale(
                      scale: _portfolioCoverScale.clamp(1.0, 2.5).toDouble(),
                      alignment: Alignment(
                        _portfolioCoverPositionX,
                        _portfolioCoverPositionY,
                      ),
                      child: Image.memory(
                        _bannerBytes!,
                        fit: BoxFit.cover,
                        alignment: Alignment(
                          _portfolioCoverPositionX,
                          _portfolioCoverPositionY,
                        ),
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stack) =>
                            _bannerFallback(
                              icon: Icons.broken_image_rounded,
                              text: 'Erro ao carregar imagem',
                            ),
                      ),
                    ),
                  )
                else if (_bannerUrl != null && _bannerUrl!.trim().isNotEmpty)
                  PortfolioCoverImage(
                    url: _bannerUrl!,
                    positionX: _portfolioCoverPositionX,
                    positionY: _portfolioCoverPositionY,
                    scale: _portfolioCoverScale,
                    placeholder: _bannerFallback(
                      icon: Icons.broken_image_rounded,
                      text: 'Erro ao carregar imagem',
                    ),
                  )
                else
                  _bannerFallback(
                    icon: Icons.add_photo_alternate_rounded,
                    text: 'Toque para adicionar um banner',
                  ),
                if (hasBanner)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.crop_free_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Toque para ajustar a capa',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bannerFallback({required IconData icon, required String text}) {
    final t = context.uai;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 50, color: t.textMuted),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildPortfolioBannerFramingEditor() {
    final t = context.uai;
    final hasBanner =
        _bannerBytes != null ||
        (_bannerUrl != null && _bannerUrl!.trim().isNotEmpty);
    if (!hasBanner) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 430;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enquadramento do portfólio',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'O mesmo recorte 16:9 será usado na timeline e nos cards.',
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              ],
            );
            final action = FilledButton.tonalIcon(
              onPressed: _abrirAjusteBanner,
              icon: const Icon(Icons.crop_free_rounded),
              label: const Text('AJUSTAR CAPA'),
            );
            return narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [info, const SizedBox(height: 10), action],
                  )
                : Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 12),
                      action,
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget _buildBannerActions() {
    final hasBanner = _bannerBytes != null || _bannerUrl != null;
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;

        final alterar = OutlinedButton.icon(
          onPressed: _mostrarOpcoesImagem,
          icon: Icon(hasBanner ? Icons.edit_rounded : Icons.add_rounded),
          label: Text(hasBanner ? 'Alterar' : 'Adicionar Banner'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ensureVisible(t.info, t.card),
            side: BorderSide(color: t.border),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        );

        final remover = OutlinedButton.icon(
          onPressed: _removerBanner,
          icon: const Icon(Icons.delete_rounded),
          label: const Text('Remover'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ensureVisible(t.error, t.card),
            side: BorderSide(color: t.border),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        );

        if (!hasBanner) {
          return SizedBox(width: double.infinity, child: alterar);
        }

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [alterar, const SizedBox(height: 10), remover],
          );
        }

        return Row(
          children: [
            Expanded(child: alterar),
            const SizedBox(width: 12),
            Expanded(child: remover),
          ],
        );
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required String emptyText,
    required String value,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Material(
      color: enabled ? t.cardAlt : t.card,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value.isEmpty ? emptyText : value,
                  style: TextStyle(
                    color: value.isEmpty ? t.textSecondary : t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withAlpha(41)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogHandle() {
    final t = context.uai;

    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: t.border,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          widget.evento == null ? 'Criar Evento' : 'Editar Evento',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: _carregandoPermissoes
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : (!_podeSalvarEvento)
          ? _buildSemAcessoEvento()
          : _isLoading
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 112),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _orderedEventSections([
                          _buildHero(),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _dadosKey,
                            icon: Icons.event_rounded,
                            title: 'Dados Básicos',
                            subtitle:
                                'Nome, descrição, tipo, data, local e organizadores.',
                            color: t.primary,
                            child: Column(
                              children: [
                                _formField(
                                  controller: _nomeController,
                                  label: 'Nome do Evento',
                                  icon: Icons.event_rounded,
                                  obrigatorio: true,
                                ),
                                const SizedBox(height: 12),
                                _formField(
                                  controller: _descricaoController,
                                  label: 'Descrição do Evento',
                                  icon: Icons.description_rounded,
                                  hint: 'Descreva os detalhes do evento...',
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: _tipoController.text.isNotEmpty
                                      ? _tipoController.text
                                      : null,
                                  isExpanded: true,
                                  dropdownColor: t.surface,
                                  style: TextStyle(color: t.textPrimary),
                                  decoration: _inputDecoration(
                                    label: 'Tipo do Evento *',
                                    icon: Icons.category_rounded,
                                  ),
                                  items: _tiposEvento.map((tipo) {
                                    return DropdownMenuItem<String>(
                                      value: tipo,
                                      child: Text(
                                        tipo,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: t.textPrimary),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _tipoController.text = value ?? '';
                                    });
                                  },
                                  validator: (value) {
                                    return value == null
                                        ? 'Campo obrigatório'
                                        : null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final narrow = constraints.maxWidth < 560;

                                    final data = _buildDateField(
                                      label: 'Data *',
                                      emptyText: 'Selecione a data',
                                      value: _dataController.text,
                                      onTap: _selecionarData,
                                    );

                                    final horario = _formField(
                                      controller: _horarioController,
                                      label: 'Horário',
                                      icon: Icons.access_time_rounded,
                                      hint: 'HH:MM',
                                      obrigatorio: true,
                                    );

                                    if (narrow) {
                                      return Column(
                                        children: [
                                          data,
                                          const SizedBox(height: 12),
                                          horario,
                                        ],
                                      );
                                    }

                                    return Row(
                                      children: [
                                        Expanded(child: data),
                                        const SizedBox(width: 12),
                                        Expanded(child: horario),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final narrow = constraints.maxWidth < 560;

                                    final local = _formField(
                                      controller: _localController,
                                      label: 'Local',
                                      icon: Icons.location_on_rounded,
                                      obrigatorio: true,
                                    );

                                    final cidade = _formField(
                                      controller: _cidadeController,
                                      label: 'Cidade',
                                      icon: Icons.location_city_rounded,
                                      obrigatorio: true,
                                    );

                                    if (narrow) {
                                      return Column(
                                        children: [
                                          local,
                                          const SizedBox(height: 12),
                                          cidade,
                                        ],
                                      );
                                    }

                                    return Row(
                                      children: [
                                        Expanded(child: local),
                                        const SizedBox(width: 12),
                                        Expanded(child: cidade),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                _formField(
                                  controller: _organizadoresController,
                                  label: 'Organizadores separados por vírgula',
                                  icon: Icons.people_rounded,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _bannerKey,
                            icon: Icons.image_rounded,
                            title: 'Banner do Evento',
                            subtitle:
                                'Adicione, troque ou remova a imagem do evento.',
                            color: t.info,
                            child: Column(
                              children: [
                                _buildBannerPreview(),
                                if (_isUploadingBanner) ...[
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(color: t.primary),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Enviando banner...',
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _buildBannerActions(),
                                _buildPortfolioBannerFramingEditor(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _financeiroKey,
                            icon: Icons.payments_rounded,
                            title: 'Configurações de Taxa',
                            subtitle: 'Valor, parcelamento e desconto à vista.',
                            color: t.success,
                            enabled: _temCobrancaInscricao,
                            child: Column(
                              children: [
                                _buildToggleCard(
                                  value: _temCobrancaInscricao,
                                  icon: Icons.payments_rounded,
                                  title: 'Cobrança de inscrições',
                                  activeText:
                                      'Inscrições com cobrança habilitada.',
                                  inactiveText:
                                      'Participação sem cobrança de inscrição.',
                                  activeColor: t.success,
                                  onChanged: (value) => setState(
                                    () => _temCobrancaInscricao = value,
                                  ),
                                ),
                                if (_temCobrancaInscricao) ...[
                                  const SizedBox(height: 12),
                                  _numberField(
                                    label: 'Valor da inscrição (R\$)',
                                    icon: Icons.attach_money_rounded,
                                    initialValue: _valorInscricao,
                                    obrigatorio: _temCobrancaInscricao,
                                    onChanged: (value) {
                                      _valorInscricao =
                                          double.tryParse(value) ?? 0;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _buildToggleCard(
                                    value: _permiteParcelamento,
                                    icon: Icons.receipt_long_rounded,
                                    title: 'Permite parcelamento?',
                                    activeText:
                                        'O evento permite parcelamento.',
                                    inactiveText:
                                        'O evento não permite parcelamento.',
                                    activeColor: t.success,
                                    onChanged: (value) {
                                      setState(() {
                                        _permiteParcelamento = value;
                                      });
                                    },
                                  ),
                                  if (_permiteParcelamento) ...[
                                    const SizedBox(height: 8),
                                    _numberField(
                                      label: 'Máximo de parcelas',
                                      icon: Icons.format_list_numbered_rounded,
                                      initialValue: _maxParcelas,
                                      onChanged: (value) {
                                        _maxParcelas = int.tryParse(value) ?? 1;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  _numberField(
                                    label: 'Desconto à vista',
                                    icon: Icons.percent_rounded,
                                    suffixText: '%',
                                    initialValue: _descontoAVista,
                                    onChanged: (value) {
                                      _descontoAVista =
                                          int.tryParse(value) ?? 0;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _buildDateField(
                                    label: 'Data limite 1ª parcela',
                                    emptyText: 'Não definido',
                                    value: _dataLimitePrimeiraParcela == null
                                        ? ''
                                        : '${_dataLimitePrimeiraParcela!.day}/${_dataLimitePrimeiraParcela!.month}/${_dataLimitePrimeiraParcela!.year}',
                                    enabled: _permiteParcelamento,
                                    onTap: _selecionarDataLimite,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            icon: Icons.tune_rounded,
                            title: 'Módulos financeiros do evento',
                            subtitle:
                                'Habilite apenas os controles utilizados neste evento.',
                            color: t.success,
                            enabled:
                                _temCobrancaInscricao ||
                                _temRelatorioFinanceiro ||
                                _temControleGastos ||
                                _temPatrocinadores ||
                                _temCamisa,
                            child: Column(
                              children: [
                                _buildToggleCard(
                                  value: _temControleGastos,
                                  icon: Icons.receipt_long_rounded,
                                  title: 'Controle de gastos',
                                  activeText:
                                      'Permitir registro de gastos e relatório financeiro.',
                                  inactiveText:
                                      'Sem controle de gastos neste evento.',
                                  activeColor: t.error,
                                  onChanged: (value) => setState(
                                    () => _temControleGastos = value,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _buildToggleCard(
                                  value: _temRelatorioFinanceiro,
                                  icon: Icons.assessment_rounded,
                                  title: 'Relatório financeiro',
                                  activeText:
                                      'Exibir relatório e permitir exportação conforme permissões e módulos do evento.',
                                  inactiveText:
                                      'Ocultar acesso ao relatório financeiro deste evento.',
                                  activeColor: t.info,
                                  onChanged: (value) => setState(
                                    () => _temRelatorioFinanceiro = value,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _buildToggleCard(
                                  value: _temPatrocinadores,
                                  icon: Icons.volunteer_activism_rounded,
                                  title: 'Patrocinadores',
                                  activeText: 'Permitir gestão de patrocínios.',
                                  inactiveText: 'Sem patrocínios neste evento.',
                                  activeColor: t.success,
                                  onChanged: (value) => setState(
                                    () => _temPatrocinadores = value,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _camisaKey,
                            icon: Icons.checkroom_rounded,
                            title: 'Configurações de Camisa',
                            subtitle:
                                'Defina camisa, valores por tipo, tamanhos e modelagens.',
                            color: t.warning,
                            enabled: _temCamisa,
                            child: Column(
                              children: [
                                _buildToggleCard(
                                  value: _temCamisa,
                                  icon: Icons.checkroom_rounded,
                                  title: 'Evento terá camisa?',
                                  activeText:
                                      'Este evento terá camisa disponível.',
                                  inactiveText: 'Este evento não terá camisa.',
                                  activeColor: t.warning,
                                  onChanged: (value) {
                                    setState(() {
                                      _temCamisa = value;
                                      if (value) {
                                        if (_valoresPorTipoCamisa.isEmpty) {
                                          _valoresPorTipoCamisa = {
                                            _tipoManga: _valorCamisa,
                                            _tipoMangaLonga: _valorCamisa,
                                            _tipoRegata: _valorCamisa,
                                          };
                                          _sincronizarControllersValoresCamisa();
                                        }
                                        if (_tamanhosSelecionados.isEmpty) {
                                          _tamanhosSelecionados = List.from(
                                            _todosTamanhos,
                                          );
                                        }
                                        if (_modelagensCamisaSelecionadas
                                            .isEmpty) {
                                          _modelagensCamisaSelecionadas =
                                              List.from(_todasModelagensCamisa);
                                        }
                                        if (_tiposCamisaSelecionados.isEmpty) {
                                          _tiposCamisaSelecionados = List.from(
                                            _todosTiposCamisa,
                                          );
                                        }
                                      }
                                    });
                                  },
                                ),
                                if (_temCamisa) ...[
                                  const SizedBox(height: 12),
                                  _valoresPorTipoCamisaCard(),
                                  const SizedBox(height: 12),
                                  Material(
                                    color: t.cardAlt,
                                    borderRadius: BorderRadius.circular(
                                      t.inputRadius,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: _selecionarTamanhos,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            t.inputRadius,
                                          ),
                                          border: Border.all(color: t.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.checkroom_rounded,
                                              color: _ensureVisible(
                                                t.primary,
                                                t.cardAlt,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                _tamanhosSelecionados.isEmpty
                                                    ? 'Nenhum tamanho selecionado'
                                                    : _tamanhosSelecionados
                                                          .join(', '),
                                                style: TextStyle(
                                                  color:
                                                      _tamanhosSelecionados
                                                          .isEmpty
                                                      ? t.textSecondary
                                                      : t.textPrimary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: t.textSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildMultiSelectCard(
                                    icon: Icons.style_rounded,
                                    title: 'Modelagens disponíveis',
                                    emptyText: 'Nenhuma modelagem selecionada',
                                    values: _modelagensCamisaSelecionadas
                                        .map(_modelagemCamisaLabel)
                                        .join(', '),
                                    onTap: _selecionarModelagensCamisa,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildMultiSelectCard(
                                    icon: Icons.design_services_rounded,
                                    title: 'Tipos de camisa disponíveis',
                                    emptyText: 'Nenhum tipo selecionado',
                                    values: _tiposCamisaSelecionados
                                        .map(_tipoCamisaLabel)
                                        .join(', '),
                                    onTap: _selecionarTiposCamisa,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildToggleCard(
                                    value: _camisaObrigatoria,
                                    icon: Icons.priority_high_rounded,
                                    title: 'Camisa obrigatória?',
                                    activeText:
                                        'A camisa será obrigatória neste evento.',
                                    inactiveText:
                                        'A camisa será opcional neste evento.',
                                    activeColor: t.error,
                                    onChanged: (value) {
                                      setState(() {
                                        _camisaObrigatoria = value;
                                      });
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _certificadoKey,
                            icon: Icons.card_membership_rounded,
                            title: 'Certificados',
                            subtitle:
                                'Defina se este evento terá certificados.',
                            color: t.success,
                            enabled: _temCertificado,
                            child: Column(
                              children: [
                                _buildCertificadoSimples(),
                                if (_temCertificado) ...[
                                  const SizedBox(height: 10),
                                  _buildCertificadoResumoCard(),
                                ],
                                if (_temCertificado) ...[
                                  const SizedBox(height: 10),
                                  _infoBox(
                                    icon: Icons.info_rounded,
                                    color: t.success,
                                    text:
                                        'Os certificados serão gerados usando as assinaturas configuradas aqui e os dados reais do evento.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _webKey,
                            icon: Icons.public_rounded,
                            title: 'Portfólio Web',
                            subtitle:
                                'Controle se este evento será exibido no site institucional.',
                            color: t.info,
                            enabled: _mostrarNoPortfolioWeb,
                            child: Column(
                              children: [
                                _buildPortfolioWebSimples(),
                                if (_mostrarNoPortfolioWeb) ...[
                                  const SizedBox(height: 10),
                                  _infoBox(
                                    icon: Icons.language_rounded,
                                    color: t.info,
                                    text:
                                        'Este evento aparecerá na página de portfólio do site.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            icon: Icons.manage_search_rounded,
                            title: 'Auditoria do evento',
                            subtitle:
                                'Controle se a auditoria será exibida nas ações de gestão.',
                            color: t.info,
                            enabled: _auditoriaVisivelGestores,
                            child: Column(
                              children: [
                                _buildToggleCard(
                                  value: _auditoriaVisivelGestores,
                                  icon: Icons.shield_outlined,
                                  title: 'Mostrar auditoria do evento',
                                  activeText:
                                      'O card da auditoria aparecerá em Gerenciar Evento para usuários autorizados.',
                                  inactiveText:
                                      'A auditoria continua registrando operações, mas o atalho fica oculto.',
                                  activeColor: t.info,
                                  onChanged: (value) => setState(
                                    () => _auditoriaVisivelGestores = value,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'A visibilidade do card não concede permissão de leitura. Professores e monitores precisam de autorização validada no Firestore.',
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          KeyedSubtree(
                            key: const ValueKey('gestores'),
                            child: _seletorGestoresEvento(),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            sectionKey: _linksKey,
                            icon: Icons.link_rounded,
                            title: 'Links',
                            subtitle:
                                'Fotos, vídeos, prévia e playlist do evento.',
                            color: t.associacao,
                            enabled: _linksHabilitados,
                            child: Column(
                              children: [
                                _buildToggleCard(
                                  value: _linksHabilitados,
                                  icon: Icons.link_rounded,
                                  title: 'Exibir links do evento',
                                  activeText:
                                      'Links publicados nas informações do evento.',
                                  inactiveText:
                                      'Links ocultos; endereços anteriores preservados.',
                                  activeColor: t.associacao,
                                  onChanged: (value) =>
                                      setState(() => _linksHabilitados = value),
                                ),
                                if (_linksHabilitados) ...[
                                  const SizedBox(height: 12),
                                  _formField(
                                    controller: _linkFotosController,
                                    label: 'Link de Fotos/Vídeos',
                                    icon: Icons.photo_library_rounded,
                                    keyboardType: TextInputType.url,
                                  ),
                                  const SizedBox(height: 12),
                                  _formField(
                                    controller: _linkPreviaController,
                                    label: 'Link da Prévia',
                                    icon: Icons.play_circle_rounded,
                                    keyboardType: TextInputType.url,
                                  ),
                                  const SizedBox(height: 12),
                                  _formField(
                                    controller: _linkPlaylistController,
                                    label: 'Link da Playlist',
                                    icon: Icons.playlist_play_rounded,
                                    keyboardType: TextInputType.url,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: (!_podeSalvarEvento || _carregandoPermissoes)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(top: BorderSide(color: t.border)),
                  boxShadow: t.softShadow,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.textPrimary,
                          side: BorderSide(color: t.border),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            (_isLoading ||
                                _isUploadingBanner ||
                                !_podeSalvarEvento)
                            ? null
                            : _salvar,
                        icon: _isLoading || _isUploadingBanner
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _readableOn(t.primary),
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          widget.evento == null ? 'CRIAR EVENTO' : 'ATUALIZAR',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: _readableOn(t.primary),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

enum _SnackType { success, error, warning, info }
