import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_preview_widget.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/screens/preview_certificado_participante_screen.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_evento_mapper_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_lote_impressao_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_zip_share_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/gerador_certificado_evento_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_pdf_direto_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/widgets/certificado_evento_toolbar.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/widgets/certificado_lote_status_card.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/widgets/certificado_participante_card.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

class GeradorCertificadosEventoScreen extends StatefulWidget {
  final EventoModel evento;

  const GeradorCertificadosEventoScreen({
    super.key,
    required this.evento,
  });

  @override
  State<GeradorCertificadosEventoScreen> createState() =>
      _GeradorCertificadosEventoScreenState();
}

class _GeradorCertificadosEventoScreenState
    extends State<GeradorCertificadosEventoScreen> {
  final CertificadoEventoMapperService _mapperService =
  CertificadoEventoMapperService();
  final GeradorCertificadoEventoService _geradorService =
  GeradorCertificadoEventoService();
  final CertificadoLoteImpressaoService _loteService =
  CertificadoLoteImpressaoService();
  final CertificadoPdfDiretoService _pdfDiretoService =
  CertificadoPdfDiretoService();
  final CertificadoSvgService _svgService = const CertificadoSvgService();
  final CertificadoZipShareService _zipShareService =
  const CertificadoZipShareService();


  final GlobalKey _batchExportKey = GlobalKey();

  late CertificadoEventoData _eventoData;

  bool _carregando = true;
  bool _processandoLote = false;
  String? _erro;
  String? _statusProcessamento;
  final List<String> _logsProcessamento = <String>[];

  static const Duration _cacheParticipantesDuracao = Duration(minutes: 3);
  static final Map<String, List<CertificadoParticipanteData>>
  _participantesCacheGlobal = <String, List<CertificadoParticipanteData>>{};
  static final Map<String, DateTime> _participantesCacheGlobalTimestamp =
  <String, DateTime>{};

  DateTime? _ultimoCarregamentoParticipantes;
  int _progressoAtual = 0;
  int _progressoTotal = 0;

  CertificadoParticipanteData? _renderParticipante;

  String _busca = '';
  CertificadoFiltroParticipantes _filtro =
      CertificadoFiltroParticipantes.todos;

  List<CertificadoParticipanteData> _participantes = [];
  final Set<String> _selecionados = {};
  final Set<String> _processando = {};

  @override
  void initState() {
    super.initState();
    debugPrint('🧾 [GeradorCertificados] initState - evento: ${widget.evento.nome}');
    _eventoData = CertificadoEventoData.fromEvento(widget.evento);

    _hidratarCacheGlobalInicial();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🧾 [GeradorCertificados] primeiro frame - vai validar participantes');
      if (mounted) {
        _carregarParticipantes();
      }
    });
  }

  String get _cacheKeyParticipantes => _eventoData.eventoId;

  bool get _existeCacheGlobalValido {
    final timestamp = _participantesCacheGlobalTimestamp[_cacheKeyParticipantes];
    final participantes = _participantesCacheGlobal[_cacheKeyParticipantes];

    if (timestamp == null || participantes == null || participantes.isEmpty) {
      return false;
    }

    return DateTime.now().difference(timestamp) < _cacheParticipantesDuracao;
  }

  void _hidratarCacheGlobalInicial() {
    final timestamp = _participantesCacheGlobalTimestamp[_cacheKeyParticipantes];
    final participantes = _participantesCacheGlobal[_cacheKeyParticipantes];

    if (timestamp == null || participantes == null || participantes.isEmpty) {
      return;
    }

    if (DateTime.now().difference(timestamp) >= _cacheParticipantesDuracao) {
      return;
    }

    _participantes = List<CertificadoParticipanteData>.from(participantes);
    _ultimoCarregamentoParticipantes = timestamp;
    _carregando = false;
    _erro = null;

    debugPrint(
      '🧾 [GeradorCertificados] tela iniciou usando cache global: ${_participantes.length} participantes',
    );
  }

  void _salvarCacheGlobalParticipantes(
      List<CertificadoParticipanteData> participantes,
      ) {
    final timestamp = DateTime.now();

    _participantesCacheGlobal[_cacheKeyParticipantes] =
    List<CertificadoParticipanteData>.from(participantes);
    _participantesCacheGlobalTimestamp[_cacheKeyParticipantes] = timestamp;
    _ultimoCarregamentoParticipantes = timestamp;
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  List<CertificadoParticipanteData> get _filtrados {
    final busca = _busca.trim().toLowerCase();

    return _participantes.where((item) {
      var passaFiltro = true;

      switch (_filtro) {
        case CertificadoFiltroParticipantes.todos:
          passaFiltro = true;
          break;
        case CertificadoFiltroParticipantes.quitados:
          passaFiltro = item.estaQuitado;
          break;
        case CertificadoFiltroParticipantes.presentes:
          passaFiltro = item.presente;
          break;
        case CertificadoFiltroParticipantes.semCertificado:
          passaFiltro = !item.temCertificadoGerado;
          break;
        case CertificadoFiltroParticipantes.comCertificado:
          passaFiltro = item.temCertificadoGerado;
          break;
        case CertificadoFiltroParticipantes.naoImpressos:
          passaFiltro = !item.certificadoImpresso;
          break;
      }

      if (!passaFiltro) return false;
      if (busca.isEmpty) return true;

      final alvo = [
        item.alunoNome,
        item.graduacaoNova,
        item.certificadoOuDiploma,
        item.statusPagamento,
        item.certificadoStatus,
      ].join(' ').toLowerCase();

      return alvo.contains(busca);
    }).toList();
  }

  List<CertificadoParticipanteData> get _participantesSelecionados {
    return _participantes
        .where((item) => _selecionados.contains(item.participacaoId))
        .toList();
  }

  int get _totalGerados {
    return _participantes.where((item) => item.temCertificadoGerado).length;
  }

  int get _totalImpressos {
    return _participantes.where((item) => item.certificadoImpresso).length;
  }

  int get _totalIncluidosZip {
    return _participantes.where((item) => item.certificadoIncluidoZip).length;
  }

  int get _totalPendentes {
    return _participantes.length - _totalGerados;
  }

  bool get _todosFiltradosSelecionados {
    final filtrados = _filtrados;
    if (filtrados.isEmpty) return false;

    return filtrados.every((item) => _selecionados.contains(item.participacaoId));
  }


  bool get _cacheParticipantesValido {
    final ultimo = _ultimoCarregamentoParticipantes;
    if (ultimo != null && _participantes.isNotEmpty) {
      return DateTime.now().difference(ultimo) < _cacheParticipantesDuracao;
    }

    return _existeCacheGlobalValido;
  }

  String get _cacheParticipantesTexto {
    final ultimo = _ultimoCarregamentoParticipantes;
    if (ultimo == null) return 'Ainda não atualizado nesta sessão.';

    final idade = DateTime.now().difference(ultimo);

    if (idade.inSeconds < 60) {
      return 'Atualizado há ${idade.inSeconds}s';
    }

    return 'Atualizado há ${idade.inMinutes}min';
  }

  Future<void> _atualizarDoServidor() {
    return _carregarParticipantes(forcarServidor: true);
  }

  Future<void> _carregarParticipantes({
    bool forcarServidor = false,
  }) async {
    if (_processandoLote) return;

    if (!forcarServidor && _cacheParticipantesValido) {
      final cacheGlobal = _participantesCacheGlobal[_cacheKeyParticipantes];
      final cacheGlobalTimestamp =
      _participantesCacheGlobalTimestamp[_cacheKeyParticipantes];

      if (_participantes.isEmpty &&
          cacheGlobal != null &&
          cacheGlobalTimestamp != null) {
        _participantes = List<CertificadoParticipanteData>.from(cacheGlobal);
        _ultimoCarregamentoParticipantes = cacheGlobalTimestamp;
      }

      debugPrint(
        '🧾 [GeradorCertificados] cache válido: usando ${_participantes.length} participantes em memória/global',
      );

      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = null;
        });
      }

      return;
    }

    debugPrint(
      '🧾 [GeradorCertificados] carregando participantes do servidor | forcar=$forcarServidor',
    );

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final participantes = await _mapperService.carregarParticipantesDoEvento(
        evento: _eventoData,
      );

      if (!mounted) return;

      _salvarCacheGlobalParticipantes(participantes);

      setState(() {
        _participantes = participantes;
        _selecionados.removeWhere(
              (id) => participantes.every((item) => item.participacaoId != id),
        );
        _carregando = false;
      });

      debugPrint(
        '🧾 [GeradorCertificados] servidor retornou ${participantes.length} participantes',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  void _selecionarTodosFiltrados() {
    setState(() {
      for (final item in _filtrados) {
        if (item.participacaoId.trim().isNotEmpty) {
          _selecionados.add(item.participacaoId);
        }
      }
    });
  }

  void _limparSelecao() {
    setState(_selecionados.clear);
  }

  void _alternarSelecao(CertificadoParticipanteData participante, bool value) {
    setState(() {
      if (value) {
        _selecionados.add(participante.participacaoId);
      } else {
        _selecionados.remove(participante.participacaoId);
      }
    });
  }

  Future<void> _abrirPreview(CertificadoParticipanteData participante) async {
    // IMPORTANTE:
    // Ao voltar da prévia, não recarrega mais tudo do servidor automaticamente.
    // A tela do gerador mantém os dados em memória/cache para ficar instantânea.
    // Para atualizar de verdade, use o botão atualizar ou puxe a lista para baixo.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return PreviewCertificadoParticipanteScreen(
            evento: _eventoData,
            participante: participante,
          );
        },
      ),
    );

    if (!mounted) return;

    debugPrint(
      '🧾 [GeradorCertificados] voltou da prévia mantendo cache local: ${_participantes.length} participantes',
    );

    setState(() {
      _carregando = false;
      _erro = null;
    });
  }

  Future<void> _marcarImpresso(CertificadoParticipanteData participante) async {
    final novoStatus = !participante.certificadoImpresso;

    setState(() => _processando.add(participante.participacaoId));

    try {
      await _mapperService.marcarParticipanteImpresso(
        participacaoId: participante.participacaoId,
        impresso: novoStatus,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            novoStatus
                ? 'Certificado marcado como impresso.'
                : 'Certificado marcado como não impresso.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _carregarParticipantes(forcarServidor: true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar impressão: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processando.remove(participante.participacaoId));
      }
    }
  }

  Future<void> _aguardarRenderizacao() async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 90));
  }

  Future<CertificadoArquivoGerado> _renderizarCertificadoParaArquivo(
      CertificadoParticipanteData participante, {
        required bool incluirPdf,
        required double pixelRatio,
      }) async {
    setState(() {
      _renderParticipante = participante;
    });

    await _aguardarRenderizacao();

    final pngBytes = await _geradorService
        .capturarPngDaPreview(
      _batchExportKey,
      pixelRatio: pixelRatio,
    )
        .timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        throw Exception(
          'Tempo esgotado ao capturar ${participante.alunoNome}. '
              'Tente gerar menos certificados por vez.',
        );
      },
    );

    Uint8List? pdfBytes;

    final nomeArquivo = _geradorService.nomeArquivoBase(
      evento: _eventoData,
      participante: participante,
      extensao: incluirPdf ? 'pdf' : 'png',
    );

    if (incluirPdf) {
      final temp = CertificadoArquivoGerado(
        participante: participante,
        nomeArquivo: nomeArquivo,
        pngBytes: pngBytes,
      );

      pdfBytes = await _loteService.gerarPdfMultipaginaComPngs(
        certificados: [temp],
      );
    }

    return CertificadoArquivoGerado(
      participante: participante,
      nomeArquivo: nomeArquivo,
      pngBytes: pngBytes,
      pdfBytes: pdfBytes,
    );
  }


  Future<List<CertificadoArquivoGerado>> _renderizarSelecionados({
    required bool incluirPdf,
    double pixelRatio = 2.4,
  }) async {
    final selecionados = _participantesSelecionados;

    if (selecionados.isEmpty) {
      _mostrarInfo('Selecione pelo menos um participante.');
      return [];
    }

    final arquivos = <CertificadoArquivoGerado>[];

    setState(() {
      _processandoLote = true;
      _progressoAtual = 0;
      _progressoTotal = selecionados.length;
      _statusProcessamento = 'Preparando certificados...';
    });

    try {
      for (var i = 0; i < selecionados.length; i++) {
        final participante = selecionados[i];

        if (!participante.estaProntoParaGerar) {
          continue;
        }

        setState(() {
          _progressoAtual = i + 1;
          _statusProcessamento =
          'Renderizando ${i + 1}/${selecionados.length}: ${participante.alunoNome}';
        });

        final arquivo = await _renderizarCertificadoParaArquivo(
          participante,
          incluirPdf: incluirPdf,
          pixelRatio: pixelRatio,
        );

        arquivos.add(arquivo);
      }

      return arquivos;
    } finally {
      if (mounted) {
        setState(() {
          _renderParticipante = null;
        });
      }
    }
  }

  Future<void> _gerarSelecionadosEVincular() async {
    if (_processandoLote) return;

    final selecionados = _participantesSelecionados;

    if (selecionados.isEmpty) {
      _mostrarInfo('Selecione pelo menos um participante.');
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Gerar e vincular certificados?',
      mensagem:
      'O sistema vai gerar PDFs diretos, enviar para o Firebase Storage e vincular o novo link na participação. '
          'Se já existir certificado antigo no Firebase Storage, ele será removido. Links externos, como Drive, serão apenas substituídos.',
      confirmar: 'GERAR E VINCULAR',
    );

    if (confirmar != true) return;

    setState(() {
      _processandoLote = true;
      _progressoAtual = 0;
      _progressoTotal = selecionados.length;
      _statusProcessamento = 'Gerando e vinculando certificados...';
      _renderParticipante = null;
      _logsProcessamento.clear();
      _addLogProcessamentoSemSetState(
        'Iniciando geração direta de ${selecionados.length} certificado(s).',
      );
    });

    var gerados = 0;
    var pulados = 0;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await WidgetsBinding.instance.endOfFrame;

      for (var i = 0; i < selecionados.length; i++) {
        final participante = selecionados[i];

        if (!participante.estaProntoParaGerar) {
          pulados++;
          _addLogProcessamentoSemSetState(
            'Ignorado: ${participante.alunoNome} sem dados suficientes.',
          );
          continue;
        }

        if (!mounted) return;

        setState(() {
          _progressoAtual = i + 1;
          _statusProcessamento =
          'Gerando ${i + 1}/${selecionados.length}: ${participante.alunoNome}';
          _renderParticipante = null;
          _addLogProcessamentoSemSetState(
            'Gerando PDF direto: ${participante.alunoNome}',
          );
        });

        final pdfBytes = await _pdfDiretoService.gerarPdfParticipante(
          evento: _eventoData,
          participante: participante,
        );

        await _geradorService.uploadPdfDiretoERegistrar(
          pdfBytes: pdfBytes,
          evento: _eventoData,
          participante: participante,
        );

        gerados++;

        if (!mounted) return;

        setState(() {
          _statusProcessamento =
          'Vinculado ${i + 1}/${selecionados.length}: ${participante.alunoNome}';
          _addLogProcessamentoSemSetState(
            'PDF enviado e link vinculado: ${participante.alunoNome}',
          );
        });

        await Future<void>.delayed(const Duration(milliseconds: 45));
      }

      if (!mounted) return;

      setState(() {
        _statusProcessamento = 'Atualizando lista do servidor...';
        _addLogProcessamentoSemSetState(
          'Concluído. Gerados: $gerados • Ignorados: $pulados.',
        );
      });

      _mostrarInfo('Certificados gerados e vinculados: $gerados. Ignorados: $pulados.');
      _limparSelecao();
      await _carregarParticipantes(forcarServidor: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _addLogProcessamentoSemSetState('Erro ao gerar/vincular: $e');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar certificados: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processandoLote = false;
          _statusProcessamento = null;
          _progressoAtual = 0;
          _progressoTotal = 0;
          _renderParticipante = null;
        });
      }
    }
  }


  Future<void> _criarLotesImpressao() async {
    if (_processandoLote) return;

    final selecionados = _participantesSelecionados;

    if (selecionados.isEmpty) {
      _mostrarInfo('Selecione pelo menos um participante.');
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Criar lotes de impressão?',
      mensagem:
      'Serão gerados PDFs multipágina em lotes de 10 certificados. Exemplo: 70 certificados viram 7 arquivos com 10 páginas.',
      confirmar: 'CRIAR LOTES',
    );

    if (confirmar != true) return;

    try {
      final arquivos = await _renderizarSelecionados(
        incluirPdf: false,
        pixelRatio: 2.2,
      );

      if (arquivos.isEmpty) return;

      setState(() {
        _statusProcessamento = 'Montando PDFs multipágina em lotes de 10...';
      });

      final lotes = await _loteService.gerarLotesImpressao(
        evento: _eventoData,
        certificados: arquivos,
        tamanhoLote: 10,
        enviarStorage: false,
        registrarFirestore: true,
      );

      for (final lote in lotes) {
        await _loteService.baixarLotePdf(lote: lote);
      }

      if (!mounted) return;

      _mostrarInfo(
        '${lotes.length} lote(s) de impressão gerado(s) com sucesso.',
      );

      _limparSelecao();
      await _carregarParticipantes(forcarServidor: true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao criar lotes: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processandoLote = false;
          _statusProcessamento = null;
          _progressoAtual = 0;
          _progressoTotal = 0;
          _renderParticipante = null;
        });
      }
    }
  }


  String _nomeArquivoRelatorioGrafica() {
    final evento = _eventoData.eventoNome
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'[^A-Z0-9 _-]+'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();

    final base = evento.isEmpty ? 'EVENTO' : evento;

    return 'RELATORIO_CERTIFICADOS_GRAFICA_$base.pdf';
  }

  String _nomeArquivoAlunoRelatorio(
      CertificadoParticipanteData participante, {
        required Map<String, int> nomesUsados,
      }) {
    final base = participante.alunoNome
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'[^A-Z0-9 ]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final safeBase = base.isEmpty
        ? 'CERTIFICADO_${participante.participacaoId}'
        : base;

    final count = (nomesUsados[safeBase] ?? 0) + 1;
    nomesUsados[safeBase] = count;

    if (count == 1) return '$safeBase.pdf';
    return '${safeBase}_$count.pdf';
  }

  List<CertificadoPacoteGraficaItem> _montarItensRelatorioGrafica(
      List<CertificadoParticipanteData> participantes,
      ) {
    final nomesUsados = <String, int>{};
    final itens = <CertificadoPacoteGraficaItem>[];

    for (final participante in participantes) {
      if (!participante.estaProntoParaGerar) continue;

      itens.add(
        CertificadoPacoteGraficaItem(
          numero: itens.length + 1,
          participacaoId: participante.participacaoId,
          alunoNome: participante.alunoNome,
          graduacao: participante.graduacaoNova,
          modelo: participante.certificadoOuDiploma,
          nomeArquivo: _nomeArquivoAlunoRelatorio(
            participante,
            nomesUsados: nomesUsados,
          ),
        ),
      );
    }

    return itens;
  }

  Future<void> _gerarRelatorioGraficaSelecionados() async {
    if (_processandoLote) return;

    final selecionados = _participantesSelecionados;

    if (selecionados.isEmpty) {
      _mostrarInfo('Selecione pelo menos um participante.');
      return;
    }

    setState(() {
      _processandoLote = true;
      _progressoAtual = 0;
      _progressoTotal = selecionados.length;
      _statusProcessamento = 'Gerando relatório da gráfica...';
      _renderParticipante = null;
      _logsProcessamento.clear();
      _addLogProcessamentoSemSetState(
        'Preparando relatório com ${selecionados.length} participante(s).',
      );
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await WidgetsBinding.instance.endOfFrame;

      final itens = _montarItensRelatorioGrafica(selecionados);

      if (itens.isEmpty) {
        throw Exception(
          'Nenhum participante selecionado está pronto para entrar no relatório.',
        );
      }

      if (!mounted) return;

      setState(() {
        _progressoAtual = itens.length;
        _progressoTotal = itens.length;
        _statusProcessamento =
        'Montando PDF do relatório (${itens.length} itens)...';
        _addLogProcessamentoSemSetState(
          'Lista conferida. Gerando PDF do relatório...',
        );
      });

      final bytes = await _pdfDiretoService.gerarRelatorioGraficaPdf(
        evento: _eventoData,
        itens: itens,
        erros: const [],
      );

      if (!mounted) return;

      final nomeArquivo = _nomeArquivoRelatorioGrafica();
      final tamanhoMb = bytes.length / (1024 * 1024);

      setState(() {
        _statusProcessamento =
        'Relatório pronto: ${tamanhoMb.toStringAsFixed(1)} MB';
        _addLogProcessamentoSemSetState(
          'Relatório pronto para visualizar ou baixar.',
        );
      });

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;

      setState(() {
        _processandoLote = false;
        _statusProcessamento = null;
        _progressoAtual = 0;
        _progressoTotal = 0;
        _renderParticipante = null;
      });

      await _mostrarDialogRelatorioGraficaPronto(
        bytes: bytes,
        nomeArquivo: nomeArquivo,
        totalItens: itens.length,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _addLogProcessamentoSemSetState('Erro ao gerar relatório: $e');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar relatório da gráfica: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processandoLote = false;
          _statusProcessamento = null;
          _progressoAtual = 0;
          _progressoTotal = 0;
          _renderParticipante = null;
        });
      }
    }
  }

  Future<void> _mostrarDialogRelatorioGraficaPronto({
    required Uint8List bytes,
    required String nomeArquivo,
    required int totalItens,
  }) async {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tamanhoMb = bytes.length / (1024 * 1024);

        return AlertDialog(
          backgroundColor: t.card,
          title: Row(
            children: [
              Icon(Icons.assignment_rounded, color: primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Relatório pronto',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Relatório da gráfica gerado com $totalItens certificado(s).'
                '\nTamanho aproximado: ${tamanhoMb.toStringAsFixed(1)} MB'
                '\n\nVocê pode visualizar/imprimir ou baixar/compartilhar sem gerar o ZIP novamente.',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'FECHAR',
                style: TextStyle(color: t.textSecondary),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Printing.layoutPdf(
                  onLayout: (_) async => bytes,
                  name: nomeArquivo,
                  usePrinterSettings: true,
                  dynamicLayout: false,
                );
              },
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('VER'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withOpacity(0.30)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await Printing.sharePdf(
                  bytes: bytes,
                  filename: nomeArquivo,
                );
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('BAIXAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: _readableOn(primary),
              ),
            ),
          ],
        );
      },
    );
  }


  Future<void> _criarPacoteGrafica() async {
    if (_processandoLote) return;

    final selecionados = _participantesSelecionados;

    if (selecionados.isEmpty) {
      _mostrarInfo('Selecione pelo menos um participante.');
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Criar ZIP para gráfica?',
      mensagem:
      'Serão gerados PDFs individuais diretamente, sem captura de tela, e todos irão para um ZIP com o nome do aluno em cada arquivo. Esse modo é muito mais rápido e leve.',
      confirmar: 'CRIAR ZIP',
    );

    if (confirmar != true) return;

    setState(() {
      _processandoLote = true;
      _progressoAtual = 0;
      _progressoTotal = selecionados.length;
      _statusProcessamento = 'Preparando geração direta dos PDFs...';
      _renderParticipante = null;
      _logsProcessamento.clear();
      _addLogProcessamentoSemSetState(
        'Iniciando pacote ZIP com ${selecionados.length} certificado(s).',
      );
      _addLogProcessamentoSemSetState(
        'Carregando SVG, fontes e dados do evento...',
      );
    });

    try {
      // Deixa o overlay pintar antes de começar o processamento pesado.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await WidgetsBinding.instance.endOfFrame;

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await WidgetsBinding.instance.endOfFrame;

      final resultado = await _pdfDiretoService.gerarZipGraficaPdfsDireto(
        evento: _eventoData,
        participantes: selecionados,
        onProgress: (atual, total, alunoNome) {
          if (!mounted) return;

          setState(() {
            _progressoAtual = atual;
            _progressoTotal = total;
            _statusProcessamento = 'Gerando PDF $atual/$total: $alunoNome';
            _renderParticipante = null;

            _addLogProcessamentoSemSetState(
              'PDF $atual/$total gerado: $alunoNome',
            );

            if (atual == 1) {
              _addLogProcessamentoSemSetState(
                'Montando arquivos individuais com nome do aluno...',
              );
            }

            if (atual == total) {
              _addLogProcessamentoSemSetState(
                'Todos os PDFs foram processados. Compactando ZIP...',
              );
            }
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _statusProcessamento = 'Gerando relatório e preparando registro...';
        _addLogProcessamentoSemSetState(
          'ZIP montado com ${resultado.itens.length} PDF(s). Erros: ${resultado.erros.length}.',
        );
        _addLogProcessamentoSemSetState(
          'Registrando pacote no Firestore...',
        );
      });

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await WidgetsBinding.instance.endOfFrame;

      final pacote = await _loteService.montarResultadoPacoteGrafica(
        evento: _eventoData,
        zipBytes: resultado.zipBytes,
        relatorioBytes: resultado.relatorioBytes,
        relatorioNome: CertificadoPdfDiretoService.relatorioNomePadrao,
        itens: resultado.itens,
        registrarFirestore: true,
      );

      if (!mounted) return;

      final zipMb = pacote.zipBytes.length / (1024 * 1024);

      setState(() {
        _statusProcessamento =
        'ZIP pronto: ${zipMb.toStringAsFixed(1)} MB';
        _addLogProcessamentoSemSetState(
          'Pacote registrado. Tamanho: ${zipMb.toStringAsFixed(1)} MB.',
        );
        _addLogProcessamentoSemSetState(
          'Abrindo opções para salvar ou compartilhar...',
        );
      });

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;

      setState(() {
        _processandoLote = false;
        _statusProcessamento = null;
        _progressoAtual = 0;
        _progressoTotal = 0;
        _renderParticipante = null;
      });

      await _mostrarDialogZipPronto(
        pacote: pacote,
        totalPdfs: resultado.itens.length,
        totalErros: resultado.erros.length,
      );

      if (!mounted) return;

      _mostrarInfo(
        'ZIP criado com ${resultado.itens.length} PDF(s). Erros: ${resultado.erros.length}.',
      );

      _limparSelecao();
      await _carregarParticipantes(forcarServidor: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _addLogProcessamentoSemSetState('Erro ao criar ZIP: $e');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao criar ZIP para gráfica: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processandoLote = false;
          _statusProcessamento = null;
          _progressoAtual = 0;
          _progressoTotal = 0;
          _renderParticipante = null;
        });
      }
    }
  }



  void _addLogProcessamento(String mensagem) {
    final horario = DateTime.now();
    final hh = horario.hour.toString().padLeft(2, '0');
    final mm = horario.minute.toString().padLeft(2, '0');
    final ss = horario.second.toString().padLeft(2, '0');
    final linha = '[$hh:$mm:$ss] $mensagem';

    debugPrint('🧾 [GeradorCertificados] $linha');

    if (!mounted) return;

    setState(() {
      _logsProcessamento.add(linha);
      if (_logsProcessamento.length > 80) {
        _logsProcessamento.removeRange(0, _logsProcessamento.length - 80);
      }
    });
  }

  void _addLogProcessamentoSemSetState(String mensagem) {
    final horario = DateTime.now();
    final hh = horario.hour.toString().padLeft(2, '0');
    final mm = horario.minute.toString().padLeft(2, '0');
    final ss = horario.second.toString().padLeft(2, '0');
    final linha = '[$hh:$mm:$ss] $mensagem';

    debugPrint('🧾 [GeradorCertificados] $linha');

    _logsProcessamento.add(linha);
    if (_logsProcessamento.length > 80) {
      _logsProcessamento.removeRange(0, _logsProcessamento.length - 80);
    }
  }

  Future<void> _mostrarDialogZipPronto({
    required CertificadoPacoteGraficaGerado pacote,
    required int totalPdfs,
    required int totalErros,
  }) async {
    final t = context.uai;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final zipMb = pacote.zipBytes.length / (1024 * 1024);

        return AlertDialog(
          backgroundColor: t.card,
          title: Row(
            children: [
              Icon(Icons.inventory_2_rounded, color: t.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ZIP pronto',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Foram gerados $totalPdfs PDF(s) dentro do ZIP.'
                '\nErros: $totalErros'
                '\nTamanho aproximado: ${zipMb.toStringAsFixed(1)} MB'
                '\n\nAgora escolha o que fazer com o arquivo.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'FECHAR',
                style: TextStyle(color: t.textSecondary),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await _zipShareService.salvarOuCompartilharZip(
                    bytes: pacote.zipBytes,
                    nomeArquivo: pacote.nomeArquivoZip,
                    texto:
                    'Pacote de certificados do evento ${_eventoData.eventoNome}.',
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar ZIP: $e'),
                      backgroundColor: t.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('SALVAR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.primary,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await _zipShareService.compartilharZip(
                    bytes: pacote.zipBytes,
                    nomeArquivo: pacote.nomeArquivoZip,
                    texto:
                    'Pacote de certificados do evento ${_eventoData.eventoNome}.',
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao compartilhar ZIP: $e'),
                      backgroundColor: t.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('COMPARTILHAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmarAcao({
    required String titulo,
    required String mensagem,
    required String confirmar,
  }) {
    final t = context.uai;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.card,
          title: Text(
            titulo,
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            mensagem,
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'CANCELAR',
                style: TextStyle(color: t.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
              ),
              child: Text(confirmar),
            ),
          ],
        );
      },
    );
  }

  void _acaoPreviewParaSelecionados(String titulo) {
    final selecionados = _participantesSelecionados;

    if (selecionados.isEmpty) {
      _mostrarInfo('Selecione pelo menos um participante.');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _SelecaoAcaoSheet(
          titulo: titulo,
          participantes: selecionados,
          onAbrir: (participante) {
            Navigator.pop(context);
            _abrirPreview(participante);
          },
        );
      },
    );
  }

  void _mostrarInfo(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Gerador de Certificados',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed:
            (_carregando || _processandoLote) ? null : _atualizarDoServidor,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _processandoLote
          ? Stack(
        children: [
          Positioned.fill(
            child: Container(color: t.background),
          ),
          _buildProcessamentoOverlay(),
        ],
      )
          : _buildMainBody(),
    );
  }

  Widget _buildMainBody() {
    final t = context.uai;

    if (_carregando) {
      final primary = _ensureVisible(t.primary, t.card);
      final onPrimary = _readableOn(primary);

      return Container(
        width: double.infinity,
        height: double.infinity,
        color: t.background,
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(t.cardRadius + 4),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: primary.withOpacity(0.18)),
                      ),
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          color: primary,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Carregando participantes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Buscando dados do evento, participantes e certificados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.cardAlt,
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        border: Border.all(color: t.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _eventoData.eventoNome,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'ID: ${_eventoData.eventoId}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _atualizarDoServidor,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text(
                          'FORÇAR SERVIDOR',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary.withOpacity(0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: primary.withOpacity(0.14)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.offline_bolt_rounded,
                            color: primary,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Cache inteligente ativo por 3 minutos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
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
        ),
      );
    }

    if (_erro != null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFFFE4E6),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(22),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDC2626), width: 3),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x33000000),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFDC2626),
                size: 46,
              ),
              const SizedBox(height: 12),
              const Text(
                'ERRO AO CARREGAR PARTICIPANTES',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _erro!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _carregarParticipantes,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 620 ? 12.0 : 18.0;

        return RefreshIndicator(
          onRefresh: _processandoLote ? () async {} : _atualizarDoServidor,
          color: t.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildEventoHeader(),
                      const SizedBox(height: 14),
                      CertificadoLoteStatusCard(
                        totalParticipantes: _participantes.length,
                        selecionados: _selecionados.length,
                        gerados: _totalGerados,
                        impressos: _totalImpressos,
                        pendentes: _totalPendentes,
                        comErro: _participantes
                            .where(
                              (item) =>
                          item.certificadoStatus.toLowerCase() ==
                              'erro',
                        )
                            .length,
                        incluidosZip: _totalIncluidosZip,
                        carregando: _processandoLote,
                        mensagem: _processandoLote
                            ? (_statusProcessamento ??
                            'Processando certificados...')
                            : _eventoData.statusResumo,
                      ),
                      _buildCacheInfoCard(),
                      const SizedBox(height: 14),
                      CertificadoEventoToolbar(
                        filtro: _filtro,
                        onFiltroChanged: (value) {
                          setState(() => _filtro = value);
                        },
                        busca: _busca,
                        onBuscaChanged: (value) {
                          setState(() => _busca = value);
                        },
                        total: _filtrados.length,
                        selecionados: _selecionados.length,
                        todosSelecionados: _todosFiltradosSelecionados,
                        carregando: _processandoLote,
                        onRecarregar: _atualizarDoServidor,
                        onSelecionarTodos: _selecionarTodosFiltrados,
                        onLimparSelecao: _limparSelecao,
                        onGerarSelecionados: _gerarSelecionadosEVincular,
                        onCriarLotesImpressao: _criarLotesImpressao,
                        onGerarRelatorioGrafica: _gerarRelatorioGraficaSelecionados,
                        onCriarPacoteGrafica: _criarPacoteGrafica,
                      ),
                      const SizedBox(height: 14),
                      _buildContent(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCacheInfoCard() {
    final t = context.uai;
    final cacheValido = _cacheParticipantesValido;
    final accent = cacheValido ? t.success : t.warning;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.inputRadius),
        child: InkWell(
          onTap: _processandoLote ? null : _atualizarDoServidor,
          borderRadius: BorderRadius.circular(t.inputRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.07),
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: accent.withOpacity(0.18)),
            ),
            child: Row(
              children: [
                Icon(
                  cacheValido
                      ? Icons.offline_bolt_rounded
                      : Icons.sync_problem_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cacheValido
                        ? 'Cache inteligente ativo • $_cacheParticipantesTexto'
                        : 'Toque ou puxe para baixo para atualizar do servidor',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.refresh_rounded,
                  color: t.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRenderOculto() {
    final participante = _renderParticipante;
    if (participante == null) return const SizedBox.shrink();

    final tipo = participante.tipoTemplate(_eventoData);
    final data = participante.toPreviewData(_eventoData);

    return Positioned(
      left: -6000,
      top: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 1200,
              child: CertificadoPreviewWidget(
                tipo: tipo,
                cor1: _svgService.colorFromHex(participante.cor1),
                cor2: _svgService.colorFromHex(participante.cor2),
                corContorno: const Color(0xFF1A0202),
                data: data,
                exportKey: _batchExportKey,
                showHeader: false,
                showDebugInfo: false,
                showTextOverlay: true,
                maxHeight: 850,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _tituloProcessamentoOverlay {
    final status = (_statusProcessamento ?? '').toLowerCase();

    if (status.contains('zip') ||
        status.contains('pacote') ||
        status.contains('compactando')) {
      return 'Gerando pacote ZIP';
    }

    if (status.contains('relatório') || status.contains('relatorio')) {
      return 'Gerando relatório';
    }

    if (status.contains('vinculando') ||
        status.contains('vinculado') ||
        status.contains('salvando')) {
      return 'Gerando e vinculando';
    }

    if (status.contains('lote')) {
      return 'Criando lotes de impressão';
    }

    return 'Processando certificados';
  }

  Widget _buildProcessamentoOverlay() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final progress = _progressoTotal <= 0
        ? null
        : (_progressoAtual / _progressoTotal).clamp(0.0, 1.0);
    final percent = progress == null ? null : (progress * 100).toStringAsFixed(0);

    final ultimosLogs = _logsProcessamento.length <= 8
        ? _logsProcessamento
        : _logsProcessamento.sublist(_logsProcessamento.length - 8);

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withOpacity(0.58),
          child: Center(
            child: Container(
              width: 460,
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(t.cardRadius + 2),
                border: Border.all(color: t.border),
                boxShadow: t.cardShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: progress,
                          color: primary,
                          strokeWidth: 4,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _tituloProcessamentoOverlay,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _statusProcessamento ?? 'Aguarde...',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (percent != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: primary.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            '$percent%',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_progressoTotal > 0) ...[
                    const SizedBox(height: 13),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 9,
                        color: primary,
                        backgroundColor: t.border.withOpacity(0.40),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.picture_as_pdf_rounded,
                          color: primary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$_progressoAtual de $_progressoTotal PDFs processados',
                            style: TextStyle(
                              color: t.textMuted,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 176,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.cardAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.border),
                    ),
                    child: ultimosLogs.isEmpty
                        ? Text(
                      'Aguardando logs do processamento...',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                        : ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      itemCount: ultimosLogs.length,
                      itemBuilder: (context, index) {
                        final log = ultimosLogs[index];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.terminal_rounded,
                                color: primary,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  log,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 10.2,
                                    height: 1.12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tituloProcessamentoOverlay == 'Gerando pacote ZIP'
                        ? 'Não feche a tela até aparecer “ZIP pronto”.'
                        : 'Não feche a tela até o processamento terminar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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


  Widget _buildEventoHeader() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final onPrimary = _readableOn(primary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;

          final icon = Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: onPrimary,
              size: 32,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                _eventoData.eventoNome,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 20 : 24,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_eventoData.localData} • ${_eventoData.modeloPadraoLabel}',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 12),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    final t = context.uai;

    if (_carregando) {
      return _centerCard(
        icon: Icons.sync_rounded,
        title: 'Carregando participantes...',
        subtitle: 'Buscando participação, aluno e graduação no Firebase.',
        color: t.info,
        loading: true,
      );
    }

    if (_erro != null) {
      return _centerCard(
        icon: Icons.error_outline_rounded,
        title: 'Erro ao carregar participantes',
        subtitle: _erro!,
        color: t.error,
        actionLabel: 'Tentar novamente',
        onAction: _carregarParticipantes,
      );
    }

    if (!_eventoData.podeGerarCertificados) {
      return _centerCard(
        icon: Icons.lock_outline_rounded,
        title: 'Evento ainda não está pronto',
        subtitle:
        'Ative certificados e configure pelo menos uma assinatura na tela de criar/editar evento.',
        color: t.warning,
      );
    }

    final filtrados = _filtrados;

    if (filtrados.isEmpty) {
      return _centerCard(
        icon: Icons.search_off_rounded,
        title: 'Nenhum participante encontrado',
        subtitle: 'Tente mudar o filtro ou buscar por outro nome.',
        color: t.warning,
      );
    }

    return Column(
      children: filtrados.map((participante) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CertificadoParticipanteCard(
            evento: _eventoData,
            participante: participante,
            selecionado: _selecionados.contains(participante.participacaoId),
            processando: _processando.contains(participante.participacaoId) ||
                (_processandoLote &&
                    _renderParticipante?.participacaoId ==
                        participante.participacaoId),
            onSelecionar: (value) => _alternarSelecao(participante, value),
            onPreview: () => _abrirPreview(participante),
            onGerarPdf: () => _abrirPreview(participante),
            onGerarPng: () => _abrirPreview(participante),
            onImprimir: () => _abrirPreview(participante),
            onCompartilhar: () => _abrirPreview(participante),
            onMarcarImpresso: () => _marcarImpresso(participante),
          ),
        );
      }).toList(),
    );
  }

  Widget _centerCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool loading = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.11),
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: accent.withOpacity(0.14)),
            ),
            child: loading
                ? Padding(
              padding: const EdgeInsets.all(16),
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: accent,
              ),
            )
                : Icon(icon, color: accent, size: 32),
          ),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withOpacity(0.28)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelecaoAcaoSheet extends StatelessWidget {
  final String titulo;
  final List<CertificadoParticipanteData> participantes;
  final ValueChanged<CertificadoParticipanteData> onAbrir;

  const _SelecaoAcaoSheet({
    required this.titulo,
    required this.participantes,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Material(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: 46,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: t.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titulo,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  itemCount: participantes.length,
                  itemBuilder: (context, index) {
                    final item = participantes[index];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: t.card,
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          onTap: () => onAbrir(item),
                          leading: CircleAvatar(
                            backgroundColor: t.primary,
                            foregroundColor:
                            t.primary.computeLuminance() > 0.48
                                ? const Color(0xFF111827)
                                : Colors.white,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            item.alunoNome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            item.graduacaoNova,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.textSecondary),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
