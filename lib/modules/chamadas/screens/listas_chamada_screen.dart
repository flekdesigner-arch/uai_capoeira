import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}

Color _onCard(BuildContext context) => _readableOn(context.uai.card);
Color _onCardMuted(BuildContext context) => _onCard(context).withOpacity(0.68);
Color _onPrimary(BuildContext context) => _readableOn(context.uai.primary);


class ListasChamadaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const ListasChamadaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<ListasChamadaScreen> createState() => _ListasChamadaScreenState();
}

class _ListasChamadaScreenState extends State<ListasChamadaScreen> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard([BuildContext? c]) => _readableOn((c ?? context).uai.card);
  Color _onCardMuted([BuildContext? c]) => _onCard(c ?? context).withOpacity(0.68);
  Color _onPrimary([BuildContext? c]) => _readableOn((c ?? context).uai.primary);


  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _buscaController = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chamadas = [];
  DocumentSnapshot? _ultimoDocumento;
  bool _isLoading = true;
  bool _isLoadingMais = false;
  bool _hasError = false;
  bool _temMaisChamadas = true;
  bool _carregandoBuscaCompleta = false;
  String _erroDetalhe = '';

  // 🔥 CACHE INTELIGENTE DO CALENDÁRIO
  // Evita ficar lendo o Firebase toda vez que abrir/trocar o mês.
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _cacheChamadasPorMes = {};
  final Set<String> _mesesCalendarioCarregando = {};

  // 🔥 CACHE DE BUSCA OTIMIZADO
  // Evita recalcular textos grandes em todo build e evita carregar histórico infinito.
  final Map<String, String> _cacheTextoBuscaChamadas = {};
  bool _buscaHistoricoParcialCarregado = false;
  static const int _limiteMaximoBuscaHistorico = 60;

  static const int _limitePorPagina = 10;

  Map<String, dynamic> _permissoes = {};
  String _busca = '';
  String _filtroTipo = 'TODOS';
  String _filtroStatus = 'TODOS';
  DateTime? _dataSelecionadaCalendario;
  Timer? _buscaDebounce;

  final List<String> _tiposAula = const [
    'TODOS',
    'OBJETIVA',
    'RODA',
    'INSTRUMENTAÇÃO',
    'ESPECIAL',
    'EVENTO',
    'BATIZADO',
  ];

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_onBuscaChanged);
    _carregarPermissoes();
    _carregarPrimeirasChamadas();
  }

  @override
  void dispose() {
    _buscaDebounce?.cancel();
    _scrollController.dispose();
    _buscaController.dispose();
    super.dispose();
  }


  void _onBuscaChanged() {
    _buscaDebounce?.cancel();
    _buscaDebounce = Timer(const Duration(milliseconds: 380), () async {
      if (!mounted) return;

      final termo = _buscaController.text.trim();
      setState(() => _busca = termo);

      // 🔥 Busca leve:
      // Não carrega histórico infinito. Carrega só algumas páginas extras uma vez.
      // Se quiser ver tudo, o usuário ainda pode tocar em "Carregar mais chamadas".
      if (termo.isNotEmpty &&
          _temMaisChamadas &&
          !_carregandoBuscaCompleta &&
          !_buscaHistoricoParcialCarregado) {
        await _carregarHistoricoParcialParaBusca();
      }
    });
  }

  Future<void> _carregarHistoricoParcialParaBusca() async {
    if (_carregandoBuscaCompleta || !_temMaisChamadas) return;

    setState(() => _carregandoBuscaCompleta = true);

    try {
      int carregadasAgora = 0;

      while (mounted &&
          _temMaisChamadas &&
          _ultimoDocumento != null &&
          _chamadas.length < _limiteMaximoBuscaHistorico) {
        final querySnapshot = await _queryBaseChamadas()
            .startAfterDocument(_ultimoDocumento!)
            .limit(_limitePorPagina)
            .get(const GetOptions(source: Source.server));

        if (!mounted) return;

        final docsNovos = querySnapshot.docs;
        carregadasAgora += docsNovos.length;

        setState(() {
          if (docsNovos.isNotEmpty) {
            _chamadas.addAll(docsNovos);
            _ultimoDocumento = docsNovos.last;
          }

          _temMaisChamadas = docsNovos.length == _limitePorPagina;
        });

        if (docsNovos.isEmpty) break;

        // Pequena folga para celulares mais fracos respirarem.
        await Future.delayed(const Duration(milliseconds: 16));
      }

      if (mounted) {
        setState(() {
          _buscaHistoricoParcialCarregado = true;
        });

        if (_temMaisChamadas && _buscaController.text.trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Busca otimizada: pesquisando nas chamadas carregadas. Use "Carregar mais" para ampliar o histórico.',
              ),
              backgroundColor: context.uai.cardAlt,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      debugPrint('🔎 Busca parcial carregou $carregadasAgora chamadas extras.');
    } catch (e) {
      debugPrint('Erro ao carregar histórico parcial para busca: $e');
    } finally {
      if (mounted) setState(() => _carregandoBuscaCompleta = false);
    }
  }

  Future<void> _abrirCalendarioChamadas() async {
    FocusScope.of(context).unfocus();

    DateTime mesVisivel = _dataSelecionadaCalendario ?? DateTime.now();

    // 🔥 Carrega somente o mês que será exibido, usando cache por mês.
    await _carregarChamadasDoMesCalendario(mesVisivel);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final chamadasDoMes = _chamadasDoMes(mesVisivel);
            final carregandoMes = _calendarioMesEstaCarregando(mesVisivel);

            final primeiraSemana = DateTime(mesVisivel.year, mesVisivel.month, 1);
            final primeiroDiaGrade = primeiraSemana.subtract(
              Duration(days: primeiraSemana.weekday - 1),
            );

            final diasGrade = List.generate(
              42,
                  (index) => DateTime(
                primeiroDiaGrade.year,
                primeiroDiaGrade.month,
                primeiroDiaGrade.day + index,
              ),
            );

            Future<void> trocarMes(int delta) async {
              final novoMes = DateTime(
                mesVisivel.year,
                mesVisivel.month + delta,
                1,
              );

              setDialogState(() {
                mesVisivel = novoMes;
              });

              await _carregarChamadasDoMesCalendario(novoMes);

              if (mounted) {
                setDialogState(() {});
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(12),
              backgroundColor: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = MediaQuery.of(context).size.height * 0.90;

                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.uai.surface,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.22),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: EdgeInsets.fromLTRB(16, 18, 16, 16),
                              decoration: BoxDecoration(
                                gradient: context.uai.primaryGradient,
                              ),
                              child: SafeArea(
                                bottom: false,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: context.uai.card.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(15),
                                          ),
                                          child: Icon(
                                            Icons.calendar_month_rounded,
                                            color: _readableOn(context.uai.primary),
                                            size: 26,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Calendário de Chamadas',
                                            style: TextStyle(
                                              color: _readableOn(context.uai.primary),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => Navigator.pop(dialogContext),
                                          icon: Icon(
                                            Icons.close_rounded,
                                            color: _readableOn(context.uai.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    Row(
                                      children: [
                                        IconButton(
                                          onPressed: carregandoMes ? null : () => trocarMes(-1),
                                          icon: Icon(
                                            Icons.chevron_left_rounded,
                                            color: _onCard(context),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                DateFormat('MMMM yyyy', 'pt_BR')
                                                    .format(mesVisivel)
                                                    .toUpperCase(),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: _onCard(context),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                carregandoMes
                                                    ? 'Carregando chamadas do mês...'
                                                    : '${chamadasDoMes.length} chamada${chamadasDoMes.length == 1 ? '' : 's'} no mês',
                                                style: TextStyle(
                                                  color: context.uai.card.withOpacity(0.78),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: carregandoMes ? null : () => trocarMes(1),
                                          icon: Icon(
                                            Icons.chevron_right_rounded,
                                            color: _onCard(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(14, 14, 14, 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (carregandoMes) ...[
                                      LinearProgressIndicator(
                                        minHeight: 3,
                                        backgroundColor: context.uai.error.withOpacity(0.10),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          context.uai.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    Row(
                                      children: [
                                        const _DiaSemanaHeader('S'),
                                        const _DiaSemanaHeader('T'),
                                        const _DiaSemanaHeader('Q'),
                                        const _DiaSemanaHeader('Q'),
                                        const _DiaSemanaHeader('S'),
                                        const _DiaSemanaHeader('S'),
                                        const _DiaSemanaHeader('D'),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 7,
                                        crossAxisSpacing: 5,
                                        mainAxisSpacing: 5,
                                        childAspectRatio: 0.94,
                                      ),
                                      itemCount: diasGrade.length,
                                      itemBuilder: (context, index) {
                                        final dia = diasGrade[index];
                                        final chamadasDia = _chamadasDoDia(dia);

                                        return _buildDiaCalendario(
                                          dia: dia,
                                          mesAtual: dia.month == mesVisivel.month,
                                          chamadasDia: chamadasDia,
                                          onTap: chamadasDia.isEmpty
                                              ? null
                                              : () => _abrirChamadasDoDiaCalendario(
                                            dialogContext: dialogContext,
                                            dia: dia,
                                            chamadasDia: chamadasDia,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    _buildLegendaCalendario(),
                                    if (chamadasDoMes.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      _buildResumoCalendarioMes(chamadasDoMes),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _dataSelecionadaCalendario = null;
                                              });
                                              Navigator.pop(dialogContext);
                                            },
                                            icon: Icon(
                                              Icons.filter_alt_off_rounded,
                                              size: 16,
                                            ),
                                            label: Text('Limpar data'),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => Navigator.pop(dialogContext),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                                              foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                                            ),
                                            icon: const Icon(Icons.check_rounded, size: 16),
                                            label: const Text('Concluir'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _carregarPermissoes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final permissoesDoc = await _firestore
          .collection('usuarios')
          .doc(user.uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (!mounted) return;
      if (permissoesDoc.exists) {
        setState(() => _permissoes = permissoesDoc.data() ?? {});
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissões: $e');
    }
  }

  bool _temPermissao(String permissao) => _permissoes[permissao] == true;

  Query<Map<String, dynamic>> _queryBaseChamadas() {
    return _firestore
        .collection('chamadas')
        .where('turma_id', isEqualTo: widget.turmaId)
        .where('academia_id', isEqualTo: widget.academiaId)
        .orderBy('data_chamada', descending: true);
  }

  String _chaveMes(DateTime data) => DateFormat('yyyy-MM').format(data);

  DateTime _inicioDoMes(DateTime data) {
    return DateTime(data.year, data.month, 1);
  }

  DateTime _inicioDoProximoMes(DateTime data) {
    return DateTime(data.year, data.month + 1, 1);
  }

  Future<void> _carregarChamadasDoMesCalendario(
      DateTime mes, {
        bool forceRefresh = false,
      }) async {
    final chave = _chaveMes(mes);

    if (!forceRefresh && _cacheChamadasPorMes.containsKey(chave)) return;
    if (_mesesCalendarioCarregando.contains(chave)) return;

    if (mounted) {
      setState(() => _mesesCalendarioCarregando.add(chave));
    } else {
      _mesesCalendarioCarregando.add(chave);
    }

    try {
      final inicio = _inicioDoMes(mes);
      final fim = _inicioDoProximoMes(mes);

      final snapshot = await _firestore
          .collection('chamadas')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('academia_id', isEqualTo: widget.academiaId)
          .where('data_chamada', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data_chamada', isLessThan: Timestamp.fromDate(fim))
          .orderBy('data_chamada', descending: true)
          .get(const GetOptions(source: Source.server));

      if (!mounted) return;

      setState(() {
        _cacheChamadasPorMes[chave] = snapshot.docs;

        final idsAtuais = _chamadas.map((doc) => doc.id).toSet();
        for (final doc in snapshot.docs) {
          if (!idsAtuais.contains(doc.id)) {
            _chamadas.add(doc);
            idsAtuais.add(doc.id);
          }
        }

        _chamadas.sort((a, b) {
          final dataA = a.data()['data_chamada'];
          final dataB = b.data()['data_chamada'];

          final dtA = dataA is Timestamp ? dataA.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final dtB = dataB is Timestamp ? dataB.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

          return dtB.compareTo(dtA);
        });
      });
    } catch (e) {
      debugPrint('Erro ao carregar mês do calendário: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar chamadas do mês: $e'),
            backgroundColor: context.uai.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mesesCalendarioCarregando.remove(chave));
      } else {
        _mesesCalendarioCarregando.remove(chave);
      }
    }
  }

  bool _calendarioMesEstaCarregando(DateTime mes) {
    return _mesesCalendarioCarregando.contains(_chaveMes(mes));
  }

  Future<void> _carregarPrimeirasChamadas() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _erroDetalhe = '';
      _chamadas = [];
      _ultimoDocumento = null;
      _temMaisChamadas = true;
      _cacheChamadasPorMes.clear();
      _mesesCalendarioCarregando.clear();
      _cacheTextoBuscaChamadas.clear();
      _buscaHistoricoParcialCarregado = false;
    });

    try {
      final querySnapshot = await _queryBaseChamadas()
          .limit(_limitePorPagina)
          .get(const GetOptions(source: Source.server));

      if (!mounted) return;
      setState(() {
        _chamadas = querySnapshot.docs;
        _ultimoDocumento = querySnapshot.docs.isNotEmpty
            ? querySnapshot.docs.last
            : null;
        _temMaisChamadas = querySnapshot.docs.length == _limitePorPagina;
      });
    } catch (e) {
      debugPrint('Erro ao carregar chamadas: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _erroDetalhe = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _carregarMaisChamadas() async {
    if (_isLoadingMais || !_temMaisChamadas || _ultimoDocumento == null) return;

    setState(() => _isLoadingMais = true);

    try {
      final querySnapshot = await _queryBaseChamadas()
          .startAfterDocument(_ultimoDocumento!)
          .limit(_limitePorPagina)
          .get(const GetOptions(source: Source.server));

      if (!mounted) return;
      setState(() {
        if (querySnapshot.docs.isNotEmpty) {
          _chamadas.addAll(querySnapshot.docs);
          _ultimoDocumento = querySnapshot.docs.last;
        }
        _temMaisChamadas = querySnapshot.docs.length == _limitePorPagina;
      });
    } catch (e) {
      debugPrint('Erro ao carregar mais chamadas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar mais chamadas: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMais = false);
    }
  }

  String _textoBuscaChamada(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final cached = _cacheTextoBuscaChamadas[doc.id];
    if (cached != null) return cached;

    final data = doc.data();
    final tipo = (data['tipo_aula'] ?? '').toString().toUpperCase();
    final professor = (data['professor_nome'] ?? '').toString();
    final dataFmt = (data['data_formatada'] ?? '').toString();
    final presentes = _parseInt(data['presentes']);
    final total = _parseInt(data['total_alunos']);
    final alunos = (data['alunos'] as List?) ?? [];
    final dataChamada = data['data_chamada'];

    final dataBusca = dataChamada is Timestamp
        ? '${DateFormat('dd/MM/yyyy').format(dataChamada.toDate())} '
        '${DateFormat('EEEE', 'pt_BR').format(dataChamada.toDate())} '
        '${DateFormat('MMMM', 'pt_BR').format(dataChamada.toDate())}'
        : '';

    final buffer = StringBuffer()
      ..write('$tipo $professor $dataFmt $dataBusca ')
      ..write('${data['turma_nome'] ?? ''} ${data['academia_nome'] ?? ''} ')
      ..write('$presentes presentes ${total - presentes} ausentes $total alunos ');

    for (final aluno in alunos) {
      if (aluno is Map) {
        final nome = (aluno['aluno_nome'] ?? '').toString();
        final obs = (aluno['observacao'] ?? '').toString();
        final status = aluno['presente'] == true ? 'presente' : 'ausente';
        buffer.write('$nome $obs $status ');
      }
    }

    final normalizado = _normalizar(buffer.toString());
    _cacheTextoBuscaChamadas[doc.id] = normalizado;
    return normalizado;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _chamadasFiltradas {
    final termo = _busca.isEmpty ? '' : _normalizar(_busca);
    final dataSelecionadaFmt = _dataSelecionadaCalendario == null
        ? null
        : DateFormat('yyyy-MM-dd').format(_dataSelecionadaCalendario!);

    return _chamadas.where((doc) {
      final data = doc.data();
      final tipo = (data['tipo_aula'] ?? '').toString().toUpperCase();
      final dataFmt = (data['data_formatada'] ?? '').toString();
      final presentes = _parseInt(data['presentes']);
      final total = _parseInt(data['total_alunos']);

      if (_filtroTipo != 'TODOS' && tipo != _filtroTipo) return false;

      if (_filtroStatus == 'COM_FALTA' && presentes >= total) return false;
      if (_filtroStatus == '100' && presentes != total) return false;
      if (_filtroStatus == 'VAZIA' && presentes != 0) return false;

      if (dataSelecionadaFmt != null && dataFmt != dataSelecionadaFmt) {
        return false;
      }

      if (termo.isEmpty) return true;

      return _textoBuscaChamada(doc).contains(termo);
    }).toList();
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _normalizar(String text) {
    const withAccents = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ';
    const withoutAccents = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUCnN';
    var normalized = text;
    for (int i = 0; i < withAccents.length; i++) {
      normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return normalized.toLowerCase().trim();
  }


  bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chamadasDoDia(DateTime dia) {
    final dataFmt = DateFormat('yyyy-MM-dd').format(dia);

    return _chamadas.where((doc) {
      final data = doc.data();
      final dataFormatada = data['data_formatada']?.toString();

      if (dataFormatada != null && dataFormatada.isNotEmpty) {
        return dataFormatada == dataFmt;
      }

      final timestamp = data['data_chamada'];
      if (timestamp is Timestamp) {
        return _mesmoDia(timestamp.toDate(), dia);
      }

      return false;
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chamadasDoMes(DateTime mes) {
    final cached = _cacheChamadasPorMes[_chaveMes(mes)];
    final origem = cached ?? _chamadas;

    return origem.where((doc) {
      final data = doc.data();
      final timestamp = data['data_chamada'];
      DateTime? dataChamada;

      if (timestamp is Timestamp) {
        dataChamada = timestamp.toDate();
      } else {
        final dataFormatada = data['data_formatada']?.toString();
        if (dataFormatada != null && dataFormatada.length >= 7) {
          dataChamada = DateTime.tryParse(dataFormatada);
        }
      }

      if (dataChamada == null) return false;

      return dataChamada.year == mes.year && dataChamada.month == mes.month;
    }).toList();
  }

  Widget _buildDiaCalendario({
    required DateTime dia,
    required bool mesAtual,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> chamadasDia,
    required VoidCallback? onTap,
  }) {
    final hoje = DateTime.now();
    final isHoje = _mesmoDia(dia, hoje);
    final isSelecionado = _dataSelecionadaCalendario != null &&
        _mesmoDia(dia, _dataSelecionadaCalendario!);
    final temChamada = chamadasDia.isNotEmpty;
    final tipoPrincipal = temChamada
        ? chamadasDia.first.data()['tipo_aula']?.toString() ?? 'OUTRO'
        : 'OUTRO';
    final corTipo = _getTipoAulaColor(tipoPrincipal);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelecionado
                ? context.uai.primary
                : temChamada
                ? corTipo.withOpacity(0.12)
                : mesAtual
                ? context.uai.background
                : context.uai.cardAlt.withOpacity(0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelecionado
                  ? context.uai.primary
                  : isHoje
                  ? context.uai.error.withOpacity(0.70)
                  : temChamada
                  ? corTipo.withOpacity(0.55)
                  : context.uai.border,
              width: isHoje || isSelecionado ? 1.4 : 1,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxHeight < 42;

              return FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 28,
                    maxWidth: 46,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${dia.day}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: compacto ? 12 : 13,
                          height: 1.0,
                          color: isSelecionado
                              ? Colors.white
                              : mesAtual
                              ? context.uai.textPrimary
                              : context.uai.textMuted,
                        ),
                      ),
                      SizedBox(height: compacto ? 2 : 3),
                      if (temChamada)
                        Container(
                          width: 20,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelecionado ? Colors.white : corTipo,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        )
                      else
                        SizedBox(
                          width: 20,
                          height: 5,
                          child: isHoje
                              ? Center(
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: context.uai.primaryDark,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                              : null,
                        ),
                      if (chamadasDia.length > 1) ...[
                        const SizedBox(height: 1),
                        Text(
                          '+${chamadasDia.length - 1}',
                          style: TextStyle(
                            fontSize: 7.5,
                            height: 1.0,
                            fontWeight: FontWeight.bold,
                            color: isSelecionado ? Colors.white : corTipo,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _abrirChamadasDoDiaCalendario({
    required BuildContext dialogContext,
    required DateTime dia,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> chamadasDia,
  }) {
    if (chamadasDia.isEmpty) return;

    setState(() {
      _dataSelecionadaCalendario = dia;
      _buscaController.clear();
      _busca = '';
    });

    if (chamadasDia.length == 1) {
      final chamada = chamadasDia.first;
      final data = chamada.data();

      Navigator.pop(dialogContext);

      Future.microtask(() {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetalhesChamadaScreen(
              chamadaId: chamada.id,
              data: data,
              turmaNome: widget.turmaNome,
            ),
          ),
        );
      });

      return;
    }

    Navigator.pop(dialogContext);

    Future.microtask(() {
      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: Container(
              margin: EdgeInsets.all(12),
              padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.uai.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.event_note_rounded, color: context.uai.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Chamadas de ${DateFormat('dd/MM/yyyy').format(dia)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: chamadasDia.length,
                      itemBuilder: (context, index) {
                        final chamada = chamadasDia[index];
                        final data = chamada.data();
                        final tipo = data['tipo_aula']?.toString() ?? 'OUTRO';
                        final professor = data['professor_nome']?.toString() ?? 'Professor';
                        final presentes = _parseInt(data['presentes']);
                        final total = _parseInt(data['total_alunos']);
                        final cor = _getTipoAulaColor(tipo);

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cor.withOpacity(0.18)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cor,
                              child: Icon(
                                _getTipoAulaIcon(tipo),
                                color: _onCard(context),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              tipo,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cor,
                              ),
                            ),
                            subtitle: Text(
                              'Prof. ${professor.split(' ').first} • $presentes/$total presentes',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.pop(context);

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DetalhesChamadaScreen(
                                    chamadaId: chamada.id,
                                    data: data,
                                    turmaNome: widget.turmaNome,
                                  ),
                                ),
                              );
                            },
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
    });
  }

  Widget _buildLegendaCalendario() {
    final tipos = _tiposAula.where((t) => t != 'TODOS').toList();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.uai.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.uai.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tipos.map((tipo) {
          final cor = _getTipoAulaColor(tipo);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(width: 5),
              Text(
                tipo,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cor,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResumoCalendarioMes(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> chamadasDoMes,
      ) {
    final porTipo = <String, int>{};

    for (final chamada in chamadasDoMes) {
      final tipo = chamada.data()['tipo_aula']?.toString().toUpperCase() ?? 'OUTRO';
      porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.uai.error.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.uai.error.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo do mês',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: context.uai.primary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: porTipo.entries.map((e) {
              final cor = _getTipoAulaColor(e.key);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cor.withOpacity(0.18)),
                ),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: TextStyle(
                    color: cor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _editarChamada(QueryDocumentSnapshot<Map<String, dynamic>> chamada) async {
    if (!_temPermissao('pode_editar_chamada')) {
      _mostrarSnackBarSemPermissao();
      return;
    }

    final data = chamada.data();
    final alunos = (data['alunos'] as List? ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditarChamadaDialog(
        chamadaId: chamada.id,
        chamadaData: data,
        alunos: alunos,
        turmaNome: widget.turmaNome,
        onChamadaEditada: _carregarPrimeirasChamadas,
      ),
    );
  }

  void _mostrarSnackBarSemPermissao() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.lock, color: _onCard(context), size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Você não tem permissão para editar chamadas')),
          ],
        ),
        backgroundColor: context.uai.primaryDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return 'Data não informada';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chamadaDay = DateTime(date.year, date.month, date.day);

    if (chamadaDay == today) return 'Hoje • ${DateFormat('HH:mm').format(date)}';
    if (chamadaDay == today.subtract(const Duration(days: 1))) {
      return 'Ontem • ${DateFormat('HH:mm').format(date)}';
    }
    return DateFormat("dd/MM/yyyy • HH:mm").format(date);
  }

  Color _getStatusColor(double percentual) {
    if (percentual >= 0.8) return context.uai.success;
    if (percentual >= 0.6) return context.uai.warning;
    return context.uai.primaryDark;
  }

  Color _getTipoAulaColor(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'OBJETIVA':
        return context.uai.info;
      case 'RODA':
        return context.uai.warning;
      case 'INSTRUMENTAÇÃO':
      case 'INSTRUMENTACAO':
        return context.uai.associacao;
      case 'ESPECIAL':
        return context.uai.inscricoes;
      case 'EVENTO':
        return context.uai.warning;
      case 'BATIZADO':
        return context.uai.primaryDark;
      default:
        return context.uai.cardAlt;
    }
  }

  IconData _getTipoAulaIcon(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'OBJETIVA':
        return Icons.flag_rounded;
      case 'RODA':
        return Icons.groups_rounded;
      case 'INSTRUMENTAÇÃO':
      case 'INSTRUMENTACAO':
        return Icons.music_note_rounded;
      case 'ESPECIAL':
        return Icons.auto_awesome_rounded;
      case 'EVENTO':
        return Icons.event_available_rounded;
      case 'BATIZADO':
        return Icons.emoji_events_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  Widget _buildHeaderResumo() {
    final chamadas = _chamadasFiltradas;
    final totalChamadas = chamadas.length;
    final totalAlunosSomados = chamadas.fold<int>(0, (s, d) => s + _parseInt(d.data()['total_alunos']));
    final totalPresentes = chamadas.fold<int>(0, (s, d) => s + _parseInt(d.data()['presentes']));
    final media = totalAlunosSomados > 0 ? (totalPresentes / totalAlunosSomados) : 0.0;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.25),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.uai.card.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.assignment_turned_in_rounded, color: _onPrimary(context), size: 26),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico de Chamadas',
                      style: TextStyle(color: _onPrimary(context), fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 3),
                    Text(
                      widget.turmaNome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _onPrimary(context).withOpacity(0.76), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.uai.card.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(media * 100).round()}%',
                  style: TextStyle(color: _onPrimary(context), fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              _buildResumoMini('Chamadas', '$totalChamadas', Icons.list_alt_rounded),
              _buildResumoMini('Presentes', '$totalPresentes', Icons.check_circle_rounded),
              _buildResumoMini('Média', '${(media * 100).round()}%', Icons.trending_up_rounded),
            ],
          ),
          SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: media,
              minHeight: 8,
              backgroundColor: _onPrimary(context).withOpacity(0.20),
              valueColor: AlwaysStoppedAnimation<Color>(_onPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoMini(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: _onPrimary(context).withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _onPrimary(context).withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _onPrimary(context), size: 18),
            SizedBox(height: 5),
            Text(value, style: TextStyle(color: _onPrimary(context), fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 2),
            Text(label, style: TextStyle(color: _onPrimary(context).withOpacity(0.76), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    final dataSelecionadaTexto = _dataSelecionadaCalendario == null
        ? null
        : DateFormat('dd/MM/yyyy').format(_dataSelecionadaCalendario!);

    return Container(
      color: context.uai.surface,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _buscaController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar aluno, professor, data, observação...',
              prefixIcon: Icon(Icons.search_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_carregandoBuscaCompleta)
                    Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.uai.primary,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Abrir calendário de chamadas',
                    icon: Icon(
                      Icons.calendar_month_rounded,
                      color: _dataSelecionadaCalendario == null
                          ? context.uai.primary
                          : context.uai.success,
                    ),
                    onPressed: _abrirCalendarioChamadas,
                  ),
                  if (_busca.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.close_rounded),
                      onPressed: () => _buscaController.clear(),
                    ),
                ],
              ),
              filled: true,
              fillColor: context.uai.card,
              hintStyle: TextStyle(color: context.uai.textMuted),
              prefixIconColor: context.uai.primary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.uai.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.uai.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.uai.primary, width: 1.4),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          if (dataSelecionadaTexto != null) ...[
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: context.uai.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.uai.success.withOpacity(0.16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_available_rounded, color: context.uai.success, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filtrando chamadas de $dataSelecionadaTexto',
                      style: TextStyle(
                        color: context.uai.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _dataSelecionadaCalendario = null),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 18, color: context.uai.success),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._tiposAula.map((tipo) => _buildFiltroChip(
                  label: tipo == 'TODOS' ? 'Todos tipos' : tipo,
                  selected: _filtroTipo == tipo,
                  icon: tipo == 'TODOS' ? Icons.category_rounded : _getTipoAulaIcon(tipo),
                  color: tipo == 'TODOS' ? context.uai.primary : _getTipoAulaColor(tipo),
                  onTap: () => setState(() => _filtroTipo = tipo),
                )),
                _buildFiltroChip(
                  label: 'Com falta',
                  selected: _filtroStatus == 'COM_FALTA',
                  icon: Icons.warning_amber_rounded,
                  color: context.uai.warning,
                  onTap: () => setState(() => _filtroStatus = _filtroStatus == 'COM_FALTA' ? 'TODOS' : 'COM_FALTA'),
                ),
                _buildFiltroChip(
                  label: '100%',
                  selected: _filtroStatus == '100',
                  icon: Icons.verified_rounded,
                  color: context.uai.success,
                  onTap: () => setState(() => _filtroStatus = _filtroStatus == '100' ? 'TODOS' : '100'),
                ),
                _buildFiltroChip(
                  label: 'Vazia',
                  selected: _filtroStatus == 'VAZIA',
                  icon: Icons.person_off_rounded,
                  color: context.uai.primaryDark,
                  onTap: () => setState(() => _filtroStatus = _filtroStatus == 'VAZIA' ? 'TODOS' : 'VAZIA'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip({
    required String label,
    required bool selected,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.uai.primary : context.uai.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? context.uai.primary : context.uai.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: selected ? Colors.white : context.uai.textSecondary),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : context.uai.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardChamada(QueryDocumentSnapshot<Map<String, dynamic>> chamada, int index) {
    final data = chamada.data();
    final dataChamada = data['data_chamada'] as Timestamp?;
    final presentes = _parseInt(data['presentes']);
    final ausentes = _parseInt(data['ausentes']);
    final totalAlunos = _parseInt(data['total_alunos']);
    final alunos = data['alunos'] as List? ?? [];
    final percentualPresenca = totalAlunos > 0 ? (presentes / totalAlunos) : 0.0;
    final tipoAula = data['tipo_aula']?.toString() ?? 'Não informado';
    final professorNome = data['professor_nome']?.toString() ?? 'Não informado';
    final podeEditar = _temPermissao('pode_editar_chamada');
    final statusColor = _getStatusColor(percentualPresenca);
    final tipoColor = _getTipoAulaColor(tipoAula);

    return Container(
      margin: EdgeInsets.fromLTRB(16, index == 0 ? 12 : 7, 16, 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.10),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Card(
        color: context.uai.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: statusColor.withOpacity(0.12)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.fromLTRB(16, 12, 12, 12),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            leading: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: CircularProgressIndicator(
                      value: percentualPresenca,
                      strokeWidth: 5,
                      backgroundColor: context.uai.border,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${(percentualPresenca * 100).toInt()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                      Text('$presentes/$totalAlunos', style: TextStyle(fontSize: 8, color: _onCardMuted(context))),
                    ],
                  ),
                ],
              ),
            ),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatarData(dataChamada),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _onCard(context)),
                      ),
                      SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          _buildTag(tipoAula, _getTipoAulaIcon(tipoAula), tipoColor),
                          _buildTag('Prof. ${professorNome.split(' ').first}', Icons.person_rounded, context.uai.associacao),
                        ],
                      ),
                    ],
                  ),
                ),
                if (podeEditar)
                  Container(
                    margin: EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: context.uai.info.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.uai.info.withOpacity(0.16)),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.tune_rounded, size: 19, color: context.uai.info),
                      onPressed: () => _editarChamada(chamada),
                      tooltip: 'Editar chamada completa',
                      padding: EdgeInsets.all(8),
                      constraints: BoxConstraints(),
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  _buildMiniStatItem(icon: Icons.check_circle_rounded, value: presentes.toString(), color: context.uai.success, label: 'Presentes'),
                  SizedBox(width: 12),
                  _buildMiniStatItem(icon: Icons.cancel_rounded, value: ausentes.toString(), color: _ensureVisible(context.uai.error, context.uai.card), label: 'Ausentes'),
                ],
              ),
            ),
            children: [
              Divider(height: 20, color: context.uai.border),
              Row(
                children: [
                  Icon(Icons.people_alt_rounded, size: 16, color: _onCardMuted(context)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lista de Alunos (${alunos.length})',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _onCard(context)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editarChamada(chamada),
                    icon: Icon(Icons.edit_rounded, size: 15),
                    label: Text('Editar tudo'),
                  ),
                ],
              ),
              SizedBox(height: 10),
              ...alunos.take(8).map((aluno) {
                final alunoMap = Map<String, dynamic>.from(aluno as Map);
                return _buildAlunoResumoLinha(alunoMap);
              }),
              if (alunos.length > 8)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('+ ${alunos.length - 8} alunos restantes', style: TextStyle(fontSize: 12, color: _onCardMuted(context))),
                ),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DetalhesChamadaScreen(
                            chamadaId: chamada.id,
                            data: data,
                            turmaNome: widget.turmaNome,
                          ),
                        ),
                      ),
                      icon: Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text('Detalhes'),
                    ),
                  ),
                  if (podeEditar) ...[
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _editarChamada(chamada),
                        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary, foregroundColor: Colors.white),
                        icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                        label: const Text('Editar'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, IconData icon, Color color) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildAlunoResumoLinha(Map<String, dynamic> alunoMap) {
    final nome = alunoMap['aluno_nome']?.toString() ?? 'Sem nome';
    final presente = alunoMap['presente'] == true;
    final observacao = alunoMap['observacao']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.only(bottom: 7),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend((presente ? context.uai.success : context.uai.error).withOpacity(0.08), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (presente ? context.uai.success : context.uai.error).withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: presente ? context.uai.success : context.uai.primaryDark),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _onCard(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (observacao.isNotEmpty)
                  Text(observacao, style: TextStyle(fontSize: 10, color: context.uai.warning, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(
            presente ? 'PRESENTE' : 'AUSENTE',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: presente ? context.uai.success : context.uai.primaryDark),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatItem({required IconData icon, required String value, required Color color, required String label}) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: accent.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accent)),
          SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: accent.withOpacity(0.90))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chamadasFiltradas = _chamadasFiltradas;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Listas de Chamada', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(widget.turmaNome, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: (Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary)).withOpacity(0.72))),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        actions: [
          IconButton(
            onPressed: _carregarPrimeirasChamadas,
            icon: Container(
              decoration: BoxDecoration(color: context.uai.card.withOpacity(0.1), shape: BoxShape.circle),
              padding: EdgeInsets.all(6),
              child: Icon(Icons.refresh_rounded, size: 20),
            ),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : _hasError
          ? _buildErrorScreen()
          : _chamadas.isEmpty
          ? _buildEmptyScreen()
          : RefreshIndicator(
        onRefresh: _carregarPrimeirasChamadas,
        color: context.uai.primary,
        backgroundColor: context.uai.surface,
        displacement: 40,
        child: CustomScrollView(
          controller: _scrollController,
          physics: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _buildHeaderResumo()),
            SliverToBoxAdapter(child: _buildFiltros()),
            if (chamadasFiltradas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 70, color: context.uai.textMuted),
                        SizedBox(height: 12),
                        Text('Nenhuma chamada nesse filtro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.uai.textSecondary)),
                        SizedBox(height: 6),
                        Text('Limpe a busca ou altere os filtros.', textAlign: TextAlign.center, style: TextStyle(color: context.uai.textMuted)),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    if (index == chamadasFiltradas.length) return _buildLoadingMaisItem();
                    return _buildCardChamada(chamadasFiltradas[index], index);
                  },
                  childCount: chamadasFiltradas.length + (_temMaisChamadas ? 1 : 0),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
      floatingActionButton: _chamadas.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(0, duration: Duration(milliseconds: 450), curve: Curves.easeInOut);
          }
        },
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.arrow_upward_rounded),
        label: Text('Topo'),
      )
          : null,
    );
  }

  Widget _buildLoadingMaisItem() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: _isLoadingMais
            ? Column(
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            SizedBox(height: 8),
            Text('Carregando mais chamadas...', style: TextStyle(fontSize: 12, color: context.uai.textSecondary)),
          ],
        )
            : ElevatedButton.icon(
          onPressed: _carregarMaisChamadas,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.uai.surface,
            foregroundColor: context.uai.primary,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: Icon(Icons.history_rounded, size: 16),
          label: Text('Carregar mais chamadas'),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(context.uai.primary),
                      backgroundColor: context.uai.error.withOpacity(0.16),
                    ),
                  ),
                ),
                Center(child: Icon(Icons.list_alt_rounded, size: 32, color: context.uai.primary)),
              ],
            ),
          ),
          SizedBox(height: 20),
          Text('Carregando chamadas...', style: TextStyle(fontSize: 16, color: _onCard(context), fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('Organizando dados da turma', style: TextStyle(fontSize: 12, color: context.uai.textMuted)),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(color: context.uai.error.withOpacity(0.10), shape: BoxShape.circle),
              child: Icon(Icons.error_outline_rounded, size: 54, color: context.uai.error.withOpacity(0.70)),
            ),
            SizedBox(height: 20),
            Text('Ops! Algo deu errado', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: context.uai.error)),
            SizedBox(height: 12),
            Text(
              _erroDetalhe.isEmpty ? 'Não foi possível carregar as listas de chamada.' : _erroDetalhe,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.uai.textSecondary),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _carregarPrimeirasChamadas,
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary, foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary), padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13)),
              icon: Icon(Icons.refresh_rounded, size: 18),
              label: Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(color: context.uai.error.withOpacity(0.16), shape: BoxShape.circle),
              child: Icon(Icons.list_alt_rounded, size: 62, color: context.uai.primary),
            ),
            SizedBox(height: 24),
            Text('Nenhuma chamada registrada', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.uai.textPrimary)),
            SizedBox(height: 10),
            Text(
              'Esta turma ainda não possui registros de chamada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _onCardMuted(context), height: 1.45),
            ),
            SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary, foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13)),
              icon: Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('Voltar para turma'),
            ),
          ],
        ),
      ),
    );
  }
}


class _DiaSemanaHeader extends StatelessWidget {
  final String label;

  const _DiaSemanaHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _onCardMuted(context),
          ),
        ),
      ),
    );
  }
}

class _EditarChamadaDialog extends StatefulWidget {
  final String chamadaId;
  final Map<String, dynamic> chamadaData;
  final List<Map<String, dynamic>> alunos;
  final String turmaNome;
  final VoidCallback onChamadaEditada;

  const _EditarChamadaDialog({
    required this.chamadaId,
    required this.chamadaData,
    required this.alunos,
    required this.turmaNome,
    required this.onChamadaEditada,
  });

  @override
  State<_EditarChamadaDialog> createState() => _EditarChamadaDialogState();
}


class _EditarChamadaDialogState extends State<_EditarChamadaDialog> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _buscaController = TextEditingController();
  final TextEditingController _professorController = TextEditingController();

  late List<Map<String, dynamic>> _alunosOriginal;
  late List<Map<String, dynamic>> _alunosEdit;
  late Map<String, TextEditingController> _observacaoControllers;
  late DateTime _dataChamadaOriginal;
  late DateTime _dataChamadaEdit;
  late String _tipoAulaOriginal;
  late String _tipoAulaEdit;
  late String _professorNomeOriginal;
  late String _professorIdOriginal;

  bool _isSaving = false;
  bool _isDeleting = false;
  bool _mostrarProgresso = false;
  String _operacaoAtual = 'Preparando...';
  String _detalheOperacao = '';
  int _etapaAtual = 0;
  int _totalEtapas = 1;
  String _buscaAluno = '';
  String _filtroAluno = 'TODOS';

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _tiposAula = const [
    'OBJETIVA',
    'RODA',
    'INSTRUMENTAÇÃO',
    'ESPECIAL',
    'EVENTO',
    'BATIZADO',
    'OUTRO',
  ];

  @override
  void initState() {
    super.initState();

    _alunosOriginal = widget.alunos.map((a) => Map<String, dynamic>.from(a)).toList();
    _alunosEdit = widget.alunos.map((a) => Map<String, dynamic>.from(a)).toList();
    _observacaoControllers = {};

    for (var aluno in _alunosEdit) {
      final alunoId = aluno['aluno_id']?.toString() ?? aluno['id']?.toString() ?? '';
      aluno['aluno_id'] = alunoId;
      aluno['aluno_nome'] = aluno['aluno_nome']?.toString() ?? aluno['nome']?.toString() ?? 'Sem nome';
      aluno['presente'] = aluno['presente'] == true;
      _observacaoControllers[alunoId] = TextEditingController(text: aluno['observacao']?.toString() ?? '');
    }

    _dataChamadaOriginal = (widget.chamadaData['data_chamada'] as Timestamp?)?.toDate() ?? DateTime.now();
    _dataChamadaEdit = _dataChamadaOriginal;
    _tipoAulaOriginal = widget.chamadaData['tipo_aula']?.toString() ?? 'OBJETIVA';
    _tipoAulaEdit = _tiposAula.contains(_tipoAulaOriginal.toUpperCase()) ? _tipoAulaOriginal.toUpperCase() : 'OUTRO';
    _professorNomeOriginal = widget.chamadaData['professor_nome']?.toString() ?? 'Professor';
    _professorIdOriginal = widget.chamadaData['professor_id']?.toString() ?? '';
    _professorController.text = _professorNomeOriginal;

    _buscaController.addListener(() {
      setState(() => _buscaAluno = _buscaController.text.trim());
    });

    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _buscaController.dispose();
    _professorController.dispose();
    for (var controller in _observacaoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _alunosFiltrados {
    return _alunosEdit.where((a) {
      final presente = a['presente'] == true;
      if (_filtroAluno == 'PRESENTES' && !presente) return false;
      if (_filtroAluno == 'AUSENTES' && presente) return false;
      if (_filtroAluno == 'COM_OBS' && (_observacaoControllers[a['aluno_id']]?.text.trim().isEmpty ?? true)) return false;

      if (_buscaAluno.isEmpty) return true;
      final termo = _normalizar(_buscaAluno);
      final nome = _normalizar(a['aluno_nome']?.toString() ?? '');
      final obs = _normalizar(_observacaoControllers[a['aluno_id']]?.text ?? '');
      return nome.contains(termo) || obs.contains(termo);
    }).toList();
  }

  String _normalizar(String text) {
    const withAccents = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ';
    const withoutAccents = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUCnN';
    var normalized = text;
    for (int i = 0; i < withAccents.length; i++) {
      normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return normalized.toLowerCase().trim();
  }

  String _dataFormatada(DateTime data) => DateFormat('yyyy-MM-dd').format(data);
  String _mesKey(DateTime data) => DateFormat('yyyy-MM').format(data);

  String _semanaKey(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final yearStart = DateTime.utc(thursday.year, 1, 1);
    final week = ((thursday.difference(yearStart).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  String _diaSemanaAbrev(DateTime data) {
    switch (data.weekday) {
      case DateTime.monday: return 'seg';
      case DateTime.tuesday: return 'ter';
      case DateTime.wednesday: return 'qua';
      case DateTime.thursday: return 'qui';
      case DateTime.friday: return 'sex';
      case DateTime.saturday: return 'sab';
      case DateTime.sunday: return 'dom';
      default: return 'seg';
    }
  }

  bool _mesAtual(DateTime data) {
    final now = DateTime.now();
    return data.year == now.year && data.month == now.month;
  }

  bool _semanaAtual(DateTime data) {
    final now = DateTime.now();
    return _semanaKey(data) == _semanaKey(now);
  }

  Map<String, dynamic> _materializarIncrements(
      Map<String, dynamic> raw, {
        bool incrementContext = false,
      }) {
    final result = <String, dynamic>{};

    raw.forEach((key, value) {
      final shouldIncrementThisInt = incrementContext ||
          key == 'total' ||
          key == 'mes' ||
          key == 'semana';

      final childIncrementContext = incrementContext ||
          key == 'porAno' ||
          key == 'porMes' ||
          key == 'porSemana' ||
          key == 'contadores';

      if (value is int) {
        if (shouldIncrementThisInt) {
          if (value != 0) result[key] = FieldValue.increment(value);
        } else {
          result[key] = value;
        }
      } else if (value is Map<String, dynamic>) {
        final child = _materializarIncrements(
          value,
          incrementContext: childIncrementContext,
        );
        if (child.isNotEmpty) result[key] = child;
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  void _addNestedDelta(Map<String, dynamic> map, List<String> path, int delta) {
    if (delta == 0 || path.isEmpty) return;
    if (path.length == 1) {
      final key = path.first;
      final atual = map[key];
      if (atual is int) {
        map[key] = atual + delta;
      } else {
        map[key] = delta;
      }
      return;
    }
    final key = path.first;
    final child = Map<String, dynamic>.from((map[key] as Map?) ?? {});
    map[key] = child;
    _addNestedDelta(child, path.sublist(1), delta);
  }

  void _aplicarDeltaContador(Map<String, dynamic> contador, DateTime data, int delta) {
    if (delta == 0) return;
    final ano = data.year.toString();
    final mes = _mesKey(data);
    final semana = _semanaKey(data);

    _addNestedDelta(contador, ['total'], delta);
    _addNestedDelta(contador, ['porAno', ano], delta);
    _addNestedDelta(contador, ['porMes', mes], delta);
    _addNestedDelta(contador, ['porSemana', semana], delta);

    if (_mesAtual(data)) _addNestedDelta(contador, ['mes'], delta);
    if (_semanaAtual(data)) _addNestedDelta(contador, ['semana'], delta);
  }

  Map<String, dynamic> _montarLogData(Map<String, dynamic> aluno, DateTime dataChamada, String chamadaId) {
    final alunoId = aluno['aluno_id']?.toString() ?? '';
    return {
      'log_id': 'log_${widget.chamadaData['turma_id']}_${alunoId}_${_dataFormatada(dataChamada)}',
      'chamada_id': chamadaId,
      'aluno_id': alunoId,
      'aluno_nome': aluno['aluno_nome']?.toString() ?? 'Sem nome',
      'turma_id': widget.chamadaData['turma_id'],
      'turma_nome': widget.chamadaData['turma_nome'],
      'academia_id': widget.chamadaData['academia_id'],
      'academia_nome': widget.chamadaData['academia_nome'],
      'data_aula': Timestamp.fromDate(dataChamada),
      'data_formatada': _dataFormatada(dataChamada),
      'dia_semana_abrev': _diaSemanaAbrev(dataChamada),
      'presente': aluno['presente'] == true,
      'tipo_aula': _tipoAulaEdit,
      'observacao': _observacaoControllers[alunoId]?.text.trim() ?? '',
      'professor_id': _professorIdOriginal,
      'professor_nome': _professorController.text.trim().isEmpty ? 'Professor' : _professorController.text.trim(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'tipo_registro': 'chamada_turma_editada',
    };
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataChamadaEdit,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (data == null) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dataChamadaEdit),
    );

    setState(() {
      _dataChamadaEdit = DateTime(
        data.year,
        data.month,
        data.day,
        hora?.hour ?? _dataChamadaEdit.hour,
        hora?.minute ?? _dataChamadaEdit.minute,
      );
    });
  }

  void _marcarTodos(bool presente) {
    setState(() {
      for (final aluno in _alunosFiltrados) {
        aluno['presente'] = presente;
      }
    });
  }

  void _inverterFiltrados() {
    setState(() {
      for (final aluno in _alunosFiltrados) {
        aluno['presente'] = !(aluno['presente'] == true);
      }
    });
  }

  Future<bool> _confirmarAlteracoesImportantes() async {
    final mudouData = _dataFormatada(_dataChamadaEdit) != _dataFormatada(_dataChamadaOriginal);
    final mudouTipo = _tipoAulaEdit != _tipoAulaOriginal.toUpperCase();
    final mudouProfessor = _professorController.text.trim() != _professorNomeOriginal;
    int mudancasAlunos = 0;

    final originalPorId = {for (final a in _alunosOriginal) (a['aluno_id'] ?? '').toString(): a};
    for (final aluno in _alunosEdit) {
      final id = aluno['aluno_id']?.toString() ?? '';
      final original = originalPorId[id];
      final obsNova = _observacaoControllers[id]?.text.trim() ?? '';
      final obsAntiga = original?['observacao']?.toString() ?? '';
      if ((original?['presente'] == true) != (aluno['presente'] == true) || obsNova != obsAntiga) {
        mudancasAlunos++;
      }
    }

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar edição da chamada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Serão atualizados:'),
            SizedBox(height: 12),
            if (mudouData) _buildBulletPoint('Data/hora da chamada'),
            if (mudouTipo) _buildBulletPoint('Tipo da aula'),
            if (mudouProfessor) _buildBulletPoint('Professor registrado'),
            _buildBulletPoint('$mudancasAlunos aluno(s) com presença/observação alterada'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.uai.warning.withOpacity(0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: context.uai.warning.withOpacity(0.28))),
              child: Text(
                'Os logs e contadores de frequência serão ajustados automaticamente.',
                style: TextStyle(color: context.uai.warning, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary, foregroundColor: Colors.white),
            child: const Text('Salvar edição'),
          ),
        ],
      ),
    ) ??
        false;
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Future<void> _salvarEdicaoCompleta() async {
    if (_isSaving || _isDeleting) return;

    final confirmar = await _confirmarAlteracoesImportantes();
    if (!confirmar) return;

    setState(() {
      _isSaving = true;
      _mostrarProgresso = true;
      _operacaoAtual = 'Preparando edição completa...';
      _detalheOperacao = 'Ajustando chamada, logs e contadores';
      _etapaAtual = 0;
      _totalEtapas = _alunosEdit.length + 3;
    });
    _animationController.forward();

    try {
      for (var aluno in _alunosEdit) {
        final alunoId = aluno['aluno_id']?.toString() ?? '';
        aluno['observacao'] = _observacaoControllers[alunoId]?.text.trim() ?? '';
      }

      final presentes = _alunosEdit.where((a) => a['presente'] == true).length;
      final totalAlunos = _alunosEdit.length;
      final ausentes = totalAlunos - presentes;
      final porcentagem = totalAlunos > 0 ? ((presentes / totalAlunos) * 100).round() : 0;
      final dataFormatadaNova = _dataFormatada(_dataChamadaEdit);
      final dataFormatadaAntiga = _dataFormatada(_dataChamadaOriginal);
      final turmaId = widget.chamadaData['turma_id']?.toString() ?? '';

      final batch = _firestore.batch();
      final chamadaRef = _firestore.collection('chamadas').doc(widget.chamadaId);
      final originalPorId = {for (final a in _alunosOriginal) (a['aluno_id'] ?? '').toString(): a};

      batch.update(chamadaRef, {
        'data_chamada': Timestamp.fromDate(_dataChamadaEdit),
        'data_formatada': dataFormatadaNova,
        'dia_semana_abrev': _diaSemanaAbrev(_dataChamadaEdit),
        'tipo_aula': _tipoAulaEdit,
        'professor_nome': _professorController.text.trim().isEmpty ? 'Professor' : _professorController.text.trim(),
        'professor_id': _professorIdOriginal,
        'alunos': _alunosEdit,
        'presentes': presentes,
        'ausentes': ausentes,
        'total_alunos': totalAlunos,
        'porcentagem_frequencia': porcentagem,
        'atualizado_em': FieldValue.serverTimestamp(),
        'editado_em': FieldValue.serverTimestamp(),
      });

      setState(() {
        _etapaAtual = 1;
        _operacaoAtual = 'Chamada principal atualizada';
      });

      final Set<String> alunosAfetados = {};

      for (int i = 0; i < _alunosEdit.length; i++) {
        final aluno = _alunosEdit[i];
        final alunoId = aluno['aluno_id']?.toString() ?? '';
        if (alunoId.isEmpty) continue;
        alunosAfetados.add(alunoId);

        setState(() {
          _etapaAtual = i + 2;
          _operacaoAtual = 'Atualizando aluno ${i + 1}/$_totalEtapas';
          _detalheOperacao = aluno['aluno_nome']?.toString() ?? 'Aluno';
        });

        final original = originalPorId[alunoId];
        final presenteAntes = original?['presente'] == true;
        final presenteDepois = aluno['presente'] == true;

        final contadorRaw = <String, dynamic>{
          'aluno_id': alunoId,
          'aluno_nome': aluno['aluno_nome']?.toString() ?? 'Sem nome',
          'turma_id_atual': turmaId,
          'turma_nome_atual': widget.chamadaData['turma_nome'],
          'academia_id_atual': widget.chamadaData['academia_id'],
          'academia_nome_atual': widget.chamadaData['academia_nome'],
          'cache_versao': 5,
          'atualizado_em': FieldValue.serverTimestamp(),
          'ultima_sync_logs': FieldValue.serverTimestamp(),
          'periodo_mes_atual': _mesKey(DateTime.now()),
          'periodo_semana_atual': _semanaKey(DateTime.now()),
        };

        final legacyRaw = <String, dynamic>{};

        if (presenteAntes) {
          _aplicarDeltaContador(contadorRaw, _dataChamadaOriginal, -1);
          _addNestedDelta(legacyRaw, ['contadores', _mesKey(_dataChamadaOriginal)], -1);
        }
        if (presenteDepois) {
          _aplicarDeltaContador(contadorRaw, _dataChamadaEdit, 1);
          _addNestedDelta(legacyRaw, ['contadores', _mesKey(_dataChamadaEdit)], 1);
        }

        final contadorUpdate = _materializarIncrements(contadorRaw);
        if (contadorUpdate.isNotEmpty) {
          batch.set(
            _firestore.collection('alunos').doc(alunoId).collection('contadores').doc('frequencia_dashboard'),
            contadorUpdate,
            SetOptions(merge: true),
          );
        }

        final legacyUpdate = _materializarIncrements(legacyRaw);
        if (legacyUpdate.isNotEmpty) {
          batch.set(_firestore.collection('alunos').doc(alunoId), legacyUpdate, SetOptions(merge: true));
        }

        final logsAntigos = await _firestore
            .collection('log_presenca_alunos')
            .where('turma_id', isEqualTo: turmaId)
            .where('aluno_id', isEqualTo: alunoId)
            .where('data_formatada', isEqualTo: dataFormatadaAntiga)
            .get();

        final logData = _montarLogData(aluno, _dataChamadaEdit, widget.chamadaId);

        if (logsAntigos.docs.isNotEmpty) {
          batch.set(logsAntigos.docs.first.reference, logData, SetOptions(merge: true));
          for (final extra in logsAntigos.docs.skip(1)) {
            batch.delete(extra.reference);
          }
        } else {
          final logId = 'log_${turmaId}_${alunoId}_$dataFormatadaNova';
          batch.set(_firestore.collection('log_presenca_alunos').doc(logId), {
            ...logData,
            'registrado_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      setState(() {
        _etapaAtual = _totalEtapas - 1;
        _operacaoAtual = 'Gravando alterações no Firebase...';
        _detalheOperacao = 'Quase pronto';
      });

      await batch.commit();

      setState(() {
        _operacaoAtual = 'Recalculando últimas presenças...';
        _detalheOperacao = 'Conferindo histórico dos alunos';
      });

      for (final alunoId in alunosAfetados) {
        await _recalcularUltimosDoAluno(alunoId);
      }

      if (!mounted) return;
      setState(() {
        _operacaoAtual = '✅ Chamada atualizada com sucesso!';
        _detalheOperacao = 'Logs, contadores e chamada foram sincronizados';
        _etapaAtual = _totalEtapas;
      });
      await Future.delayed(const Duration(milliseconds: 700));

      if (mounted) {
        widget.onChamadaEditada();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: context.uai.card),
                SizedBox(width: 8),
                Expanded(child: Text('Chamada atualizada com logs e contadores!')),
              ],
            ),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar edição completa: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _mostrarProgresso = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar edição: $e'), backgroundColor: context.uai.error, duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _mostrarProgresso = false;
        });
      }
    }
  }

  Future<void> _recalcularUltimosDoAluno(String alunoId) async {
    try {
      final alunoRef = _firestore.collection('alunos').doc(alunoId);
      final contadorRef = alunoRef.collection('contadores').doc('frequencia_dashboard');

      final ultimaPresencaQuery = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: alunoId)
          .where('presente', isEqualTo: true)
          .orderBy('data_aula', descending: true)
          .limit(1)
          .get();

      final ultimaChamadaQuery = await _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: alunoId)
          .orderBy('data_aula', descending: true)
          .limit(1)
          .get();

      final updatesAluno = <String, dynamic>{};
      final updatesContador = <String, dynamic>{};

      if (ultimaPresencaQuery.docs.isNotEmpty) {
        final d = ultimaPresencaQuery.docs.first.data();
        updatesAluno['ultima_presenca'] = d['data_aula'];
        updatesAluno['ultimo_dia_presente'] = d['data_formatada'];
        updatesContador['ultima_presenca'] = d['data_aula'];
        updatesContador['ultimo_dia_presente'] = d['data_formatada'];
      } else {
        updatesAluno['ultima_presenca'] = null;
        updatesAluno['ultimo_dia_presente'] = null;
        updatesContador['ultima_presenca'] = null;
        updatesContador['ultimo_dia_presente'] = null;
      }

      if (ultimaChamadaQuery.docs.isNotEmpty) {
        final d = ultimaChamadaQuery.docs.first.data();
        updatesAluno['ultima_chamada'] = d['data_aula'];
        updatesAluno['ultima_chamada_por'] = d['professor_nome'];
        updatesAluno['ultima_chamada_por_id'] = d['professor_id'];
      } else {
        updatesAluno['ultima_chamada'] = null;
        updatesAluno['ultima_chamada_por'] = null;
        updatesAluno['ultima_chamada_por_id'] = null;
      }

      updatesAluno['atualizado_em'] = FieldValue.serverTimestamp();
      updatesContador['atualizado_em'] = FieldValue.serverTimestamp();
      updatesContador['ultima_sync_logs'] = FieldValue.serverTimestamp();

      await alunoRef.set(updatesAluno, SetOptions(merge: true));
      await contadorRef.set(updatesContador, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao recalcular aluno $alunoId: $e');
    }
  }

  Future<void> _mostrarPreviewExclusao() async {
    final dataChamada = _dataChamadaOriginal;
    final presentes = widget.alunos.where((a) => a['presente'] == true).length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prévia da exclusão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Esta ação irá:'),
            SizedBox(height: 12),
            _buildBulletPoint('Deletar a chamada do dia ${DateFormat('dd/MM/yyyy').format(dataChamada)}'),
            _buildBulletPoint('Remover os logs da chamada'),
            _buildBulletPoint('Decrementar contadores dos $presentes alunos presentes'),
            _buildBulletPoint('Recalcular última presença e última chamada'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.uai.error.withOpacity(0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: context.uai.error.withOpacity(0.28))),
              child: Text('Atenção: esta operação não pode ser desfeita.', style: TextStyle(color: context.uai.primaryDark, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmarExclusao();
            },
            style: ElevatedButton.styleFrom(backgroundColor: context.uai.primaryDark, foregroundColor: Colors.white),
            child: Text('Continuar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarExclusao() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar exclusão'),
        content: Text('Tem certeza absoluta que deseja excluir esta chamada?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: context.uai.primaryDark, foregroundColor: Colors.white),
            child: const Text('Sim, excluir'),
          ),
        ],
      ),
    );

    if (confirmar == true) _excluirChamadaComAnimacao();
  }

  Future<void> _excluirChamadaComAnimacao() async {
    setState(() {
      _mostrarProgresso = true;
      _isDeleting = true;
      _operacaoAtual = 'Enviando para exclusão...';
      _detalheOperacao = 'A Cloud Function irá reverter logs e contadores';
      _etapaAtual = 0;
      _totalEtapas = 3;
    });
    _animationController.forward();

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('excluirChamada');
      await callable.call({
        'chamadaId': widget.chamadaId,
        'turmaId': widget.chamadaData['turma_id'],
      });

      if (!mounted) return;
      setState(() {
        _etapaAtual = 3;
        _operacaoAtual = '✅ Exclusão concluída!';
        _detalheOperacao = 'Chamada, logs e contadores foram revertidos';
      });
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        widget.onChamadaEditada();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.delete_forever, color: context.uai.card),
                SizedBox(width: 8),
                Expanded(child: Text('Chamada excluída com sucesso!')),
              ],
            ),
            backgroundColor: context.uai.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao excluir chamada: $e');
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _mostrarProgresso = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: context.uai.error, duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _mostrarProgresso = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentes = _alunosEdit.where((a) => a['presente'] == true).length;
    final ausentes = _alunosEdit.length - presentes;

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _mostrarProgresso
          ? FadeTransition(opacity: _fadeAnimation, child: SlideTransition(position: _slideAnimation, child: _buildProgressScreen()))
          : _buildEditScreen(presentes, ausentes),
    );
  }

  Widget _buildEditScreen(int presentes, int ausentes) {
    final percentual = _alunosEdit.isNotEmpty ? presentes / _alunosEdit.length : 0.0;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            gradient: context.uai.primaryGradient,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: context.uai.card.withOpacity(0.35), borderRadius: BorderRadius.circular(2)))),
                SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(color: context.uai.card.withOpacity(0.16), borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.edit_calendar_rounded, color: _onCard(context), size: 26),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Editar chamada completa', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: context.uai.card)),
                          SizedBox(height: 4),
                          Text(widget.turmaNome, style: TextStyle(fontSize: 13, color: context.uai.card.withOpacity(0.78))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_rounded, color: context.uai.card),
                      onPressed: _isSaving || _isDeleting ? null : _mostrarPreviewExclusao,
                      tooltip: 'Excluir chamada',
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: context.uai.card),
                      onPressed: _isSaving || _isDeleting ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    _buildHeaderStat('Presentes', '$presentes', Icons.check_circle_rounded, context.uai.success.withOpacity(0.55)),
                    SizedBox(width: 8),
                    _buildHeaderStat('Ausentes', '$ausentes', Icons.cancel_rounded, context.uai.error.withOpacity(0.28)),
                    SizedBox(width: 8),
                    _buildHeaderStat('Frequência', '${(percentual * 100).round()}%', Icons.trending_up_rounded, context.uai.warning.withOpacity(0.65)),
                  ],
                ),
                SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: percentual,
                    minHeight: 7,
                    backgroundColor: context.uai.card.withOpacity(0.20),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(16),
            children: [
              _buildInfoCard(),
              SizedBox(height: 14),
              _buildAcoesRapidas(),
              SizedBox(height: 14),
              _buildBuscaEFiltrosAluno(),
              SizedBox(height: 12),
              ..._alunosFiltrados.map(_buildAlunoEditCard),
              if (_alunosFiltrados.isEmpty)
                Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: Text('Nenhum aluno encontrado no filtro.', style: TextStyle(color: context.uai.textSecondary))),
                ),
            ],
          ),
        ),
        _buildRodapeAcoes(),
      ],
    );
  }

  Widget _buildHeaderStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: context.uai.card.withOpacity(0.13), borderRadius: BorderRadius.circular(16), border: Border.all(color: context.uai.card.withOpacity(0.12))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: context.uai.card.withOpacity(0.76), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.uai.background, borderRadius: BorderRadius.circular(18), border: Border.all(color: context.uai.border)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _selecionarData,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _onCard(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: context.uai.border)),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: context.uai.primary),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Data e hora', style: TextStyle(fontSize: 10, color: context.uai.textSecondary)),
                              Text(DateFormat('dd/MM/yyyy HH:mm').format(_dataChamadaEdit), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _tipoAulaEdit,
            decoration: InputDecoration(
              labelText: 'Tipo de aula',
              prefixIcon: Icon(Icons.school_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: context.uai.card,
            ),
            items: _tiposAula.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: _isSaving || _isDeleting ? null : (v) => setState(() => _tipoAulaEdit = v ?? 'OBJETIVA'),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _professorController,
            enabled: !_isSaving && !_isDeleting,
            decoration: InputDecoration(
              labelText: 'Professor registrado',
              prefixIcon: Icon(Icons.person_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: context.uai.card,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcoesRapidas() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildActionChip('Marcar filtrados', Icons.check_circle_rounded, context.uai.success, () => _marcarTodos(true)),
        _buildActionChip('Desmarcar filtrados', Icons.cancel_rounded, context.uai.error, () => _marcarTodos(false)),
        _buildActionChip('Inverter filtrados', Icons.swap_horiz_rounded, context.uai.info, _inverterFiltrados),
      ],
    );
  }

  Widget _buildActionChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: _isSaving || _isDeleting ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.25))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildBuscaEFiltrosAluno() {
    return Column(
      children: [
        TextField(
          controller: _buscaController,
          decoration: InputDecoration(
            hintText: 'Buscar aluno ou observação...',
            prefixIcon: Icon(Icons.search_rounded),
            suffixIcon: _buscaAluno.isEmpty ? null : IconButton(icon: Icon(Icons.close), onPressed: () => _buscaController.clear()),
            filled: true,
            fillColor: context.uai.cardAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        SizedBox(height: 10),
        Row(
          children: [
            _buildAlunoFilter('TODOS', 'Todos'),
            _buildAlunoFilter('PRESENTES', 'Presentes'),
            _buildAlunoFilter('AUSENTES', 'Ausentes'),
            _buildAlunoFilter('COM_OBS', 'Com obs.'),
          ],
        ),
      ],
    );
  }

  Widget _buildAlunoFilter(String value, String label) {
    final selected = _filtroAluno == value;
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 10)),
          selected: selected,
          onSelected: (_) => setState(() => _filtroAluno = value),
          selectedColor: context.uai.error.withOpacity(0.16),
          backgroundColor: context.uai.cardAlt,
        ),
      ),
    );
  }

  Widget _buildAlunoEditCard(Map<String, dynamic> aluno) {
    final alunoId = aluno['aluno_id']?.toString() ?? '';
    final nome = aluno['aluno_nome']?.toString() ?? 'Sem nome';
    final presente = aluno['presente'] == true;

    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: presente ? context.uai.success.withOpacity(0.10).withOpacity(0.70) : context.uai.error.withOpacity(0.10).withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: presente ? context.uai.success.withOpacity(0.28) : context.uai.error.withOpacity(0.16)),
      ),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Switch(
                  value: presente,
                  activeColor: context.uai.success,
                  onChanged: _isSaving || _isDeleting ? null : (v) => setState(() => aluno['presente'] = v),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: presente ? context.uai.success : context.uai.primary), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(presente ? 'Presente' : 'Ausente', style: TextStyle(fontSize: 11, color: presente ? context.uai.success : context.uai.primaryDark)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.note_add_rounded, color: context.uai.warning),
                  onPressed: _isSaving || _isDeleting
                      ? null
                      : () {
                    setState(() {
                      final atual = _observacaoControllers[alunoId]?.text ?? '';
                      if (atual.isEmpty) _observacaoControllers[alunoId]?.text = '';
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 8),
            TextField(
              controller: _observacaoControllers[alunoId],
              enabled: !_isSaving && !_isDeleting,
              decoration: InputDecoration(
                hintText: 'Observação do aluno...',
                prefixIcon: Icon(Icons.note_rounded, size: 18, color: context.uai.warning),
                filled: true,
                fillColor: context.uai.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.uai.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.uai.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.uai.info)),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              style: TextStyle(fontSize: 13),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRodapeAcoes() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.card,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: (_isSaving || _isDeleting) ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text('Cancelar', style: TextStyle(fontSize: 15, color: context.uai.textSecondary)),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: (_isSaving || _isDeleting) ? null : _salvarEdicaoCompleta,
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary, foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary), padding: EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: _isSaving ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.uai.card)) : Icon(Icons.save_rounded),
              label: Text(_isSaving ? 'Salvando...' : 'Salvar tudo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressScreen() {
    final progress = _totalEtapas > 0 ? (_etapaAtual / _totalEtapas).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [context.uai.primary, context.uai.primaryDark]),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: context.uai.card.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
                SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(color: context.uai.card.withOpacity(0.18), borderRadius: BorderRadius.circular(16)),
                      child: Icon(_isDeleting ? Icons.delete_sweep_rounded : Icons.sync_rounded, color: _onCard(context), size: 30),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isDeleting ? 'Excluindo chamada' : 'Atualizando chamada', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: context.uai.card)),
                          SizedBox(height: 4),
                          Text(widget.turmaNome, style: TextStyle(fontSize: 13, color: context.uai.card.withOpacity(0.80))),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: context.uai.card.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                      child: Text('$_etapaAtual/$_totalEtapas', style: TextStyle(color: _onCard(context), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: progress, backgroundColor: context.uai.card.withOpacity(0.2), valueColor: AlwaysStoppedAnimation<Color>(Colors.white), minHeight: 9),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(26),
                    decoration: BoxDecoration(color: context.uai.error.withOpacity(0.10), shape: BoxShape.circle),
                    child: Icon(_operacaoAtual.startsWith('✅') ? Icons.check_circle_rounded : Icons.cloud_sync_rounded, color: _operacaoAtual.startsWith('✅') ? context.uai.success : context.uai.primary, size: 72),
                  ),
                  SizedBox(height: 24),
                  Text(_operacaoAtual, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.uai.textPrimary)),
                  SizedBox(height: 8),
                  Text(_detalheOperacao, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.uai.textSecondary)),
                  SizedBox(height: 24),
                  if (!_operacaoAtual.startsWith('✅')) CircularProgressIndicator(color: context.uai.primary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DetalhesChamadaScreen extends StatelessWidget {
  final String chamadaId;
  final Map<String, dynamic> data;
  final String turmaNome;

  const DetalhesChamadaScreen({
    super.key,
    required this.chamadaId,
    required this.data,
    required this.turmaNome,
  });

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return 'Data não registrada';
    final date = timestamp.toDate();
    return DateFormat("EEEE, dd 'de' MMMM 'de' yyyy 'às' HH:mm", 'pt_BR').format(date);
  }

  Color _getStatusColor(BuildContext context, double percentual) {
    if (percentual >= 0.8) return context.uai.success;
    if (percentual >= 0.6) return context.uai.warning;
    return context.uai.primaryDark;
  }

  @override
  Widget build(BuildContext context) {
    final dataChamada = data['data_chamada'] as Timestamp?;
    final presentes = data['presentes'] ?? 0;
    final ausentes = data['ausentes'] ?? 0;
    final totalAlunos = data['total_alunos'] ?? 0;
    final alunos = data['alunos'] as List? ?? [];
    final percentual = totalAlunos > 0 ? (presentes / totalAlunos) : 0.0;
    final tipoAula = data['tipo_aula']?.toString() ?? 'Não informado';
    final professorNome = data['professor_nome']?.toString() ?? 'Não informado';

    final alunosPresentes = alunos.where((a) => (a['presente'] ?? false)).toList();
    final alunosAusentes = alunos.where((a) => !(a['presente'] ?? false)).toList();

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detalhes da Chamada', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(turmaNome, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: (Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary)).withOpacity(0.72))),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      body: CustomScrollView(
        physics: BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: EdgeInsets.all(16),
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: context.uai.primaryGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: context.uai.primary.withOpacity(0.25), blurRadius: 16, offset: Offset(0, 7))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chamada Registrada', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: context.uai.card)),
                            SizedBox(height: 5),
                            Text(_formatarData(dataChamada), style: TextStyle(fontSize: 12, color: context.uai.card.withOpacity(0.78))),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(color: context.uai.card.withOpacity(0.15), shape: BoxShape.circle),
                        child: Icon(Icons.assignment_turned_in_rounded, size: 28, color: context.uai.card),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildInfoPill(context, Icons.school_rounded, tipoAula, Colors.white)),
                      SizedBox(width: 10),
                      Expanded(child: _buildInfoPill(context, Icons.person_rounded, 'Prof. $professorNome', Colors.white)),
                    ],
                  ),
                  SizedBox(height: 22),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 126,
                        height: 126,
                        child: CircularProgressIndicator(value: percentual, strokeWidth: 12, backgroundColor: context.uai.card.withOpacity(0.22), valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(context, percentual))),
                      ),
                      Column(
                        children: [
                          Text('${(percentual * 100).toInt()}%', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: context.uai.card)),
                          Text('Presença', style: TextStyle(fontSize: 12, color: context.uai.card.withOpacity(0.75))),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSimpleStatDetail(context: context, value: presentes.toString(), label: 'Presentes', color: context.uai.success.withOpacity(0.55), icon: Icons.check_circle_rounded),
                      _buildSimpleStatDetail(context: context, value: ausentes.toString(), label: 'Ausentes', color: context.uai.error.withOpacity(0.28), icon: Icons.cancel_rounded),
                      _buildSimpleStatDetail(context: context, value: totalAlunos.toString(), label: 'Total', color: context.uai.info.withOpacity(0.16), icon: Icons.people_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(child: _buildSectionTitle('Alunos Presentes', alunosPresentes.length, context.uai.success)),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final aluno = alunosPresentes[index];
                return _buildAlunoTile(
                  context: context,
                  nome: aluno['aluno_nome']?.toString() ?? 'Sem nome',
                  presente: true,
                  observacao: aluno['observacao']?.toString() ?? '',
                );
              },
              childCount: alunosPresentes.length,
            ),
          ),
          if (alunosAusentes.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(child: _buildSectionTitle('Alunos Ausentes', alunosAusentes.length, context.uai.primaryDark)),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final aluno = alunosAusentes[index];
                  return _buildAlunoTile(
                    context: context,
                    nome: aluno['aluno_nome']?.toString() ?? 'Sem nome',
                    presente: false,
                    observacao: aluno['observacao']?.toString() ?? '',
                  );
                },
                childCount: alunosAusentes.length,
              ),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context),
        backgroundColor: context.uai.surface,
        foregroundColor: context.uai.primary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.arrow_back_rounded),
        label: Text('Voltar'),
      ),
    );
  }

  Widget _buildInfoPill(BuildContext context, IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: context.uai.card.withOpacity(0.13), borderRadius: BorderRadius.circular(14), border: Border.all(color: context.uai.card.withOpacity(0.12))),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int total, Color color) {
    return Row(
      children: [
        Text('$title ($total)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const Expanded(child: Divider(indent: 12)),
      ],
    );
  }

  Widget _buildSimpleStatDetail({required BuildContext context, required String value, required String label, required Color color, required IconData icon}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(padding: EdgeInsets.all(9), decoration: BoxDecoration(color: context.uai.card.withOpacity(0.14), shape: BoxShape.circle), child: Icon(icon, size: 20, color: color)),
        SizedBox(height: 5),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: context.uai.card.withOpacity(0.70), fontWeight: FontWeight.w500), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildAlunoTile({required BuildContext context, required String nome, required bool presente, required String observacao}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: presente ? context.uai.success.withOpacity(0.10) : context.uai.error.withOpacity(0.10), shape: BoxShape.circle), child: Icon(presente ? Icons.check_rounded : Icons.close_rounded, color: presente ? context.uai.success : context.uai.primaryDark, size: 20)),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _onCard(context), decoration: !presente ? TextDecoration.lineThrough : null)),
                    if (observacao.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.note_rounded, size: 12, color: context.uai.warning),
                            SizedBox(width: 4),
                            Expanded(child: Text(observacao, style: TextStyle(fontSize: 11, color: context.uai.warning, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: presente ? context.uai.success.withOpacity(0.10) : context.uai.error.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
                child: Text(presente ? 'PRESENTE' : 'AUSENTE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: presente ? context.uai.success : context.uai.primaryDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
