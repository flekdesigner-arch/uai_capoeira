import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:xml/xml.dart' as xml;

class EditarGraduacaoScreen extends StatefulWidget {
  final String? graduacaoId;

  const EditarGraduacaoScreen({super.key, this.graduacaoId});

  @override
  _EditarGraduacaoScreenState createState() => _EditarGraduacaoScreenState();
}

class _EditarGraduacaoScreenState extends State<EditarGraduacaoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _tituloController = TextEditingController();
  final _nivelController = TextEditingController();
  final _idadeMinimaController = TextEditingController();
  final _fraseController = TextEditingController();
  final _cordaController = TextEditingController();

  String? _tipoPublico = 'ADULTO';
  String? _tipoDocumento = 'CERTIFICADO';

  Color _cor1 = Colors.grey;
  Color _cor2 = Colors.grey;
  Color _corPonta1 = Colors.grey;
  Color _corPonta2 = Colors.grey;

  String? _svgContent;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSvg();
    if (widget.graduacaoId != null) {
      _loadGraduacaoData();
    }
  }

  Future<void> _loadSvg() async {
    final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
    if (mounted) setState(() => _svgContent = content);
  }

  Future<void> _loadGraduacaoData() async {
    setState(() => _isLoading = true);

    final doc = await FirebaseFirestore.instance.collection('graduacoes').doc(widget.graduacaoId).get();
    final data = doc.data();

    if (data != null) {
      _nomeController.text = data['nome_graduacao'] ?? '';
      _tituloController.text = data['titulo_graduacao'] ?? '';
      _nivelController.text = data['nivel_graduacao']?.toString() ?? '';
      _idadeMinimaController.text = data['idade_minima']?.toString() ?? '';
      _fraseController.text = data['frase'] ?? '';
      _cordaController.text = data['corda'] ?? '';

      setState(() {
        _tipoPublico = data['tipo_publico'] ?? 'ADULTO';
        _tipoDocumento = data['certificado_ou_diploma'] ?? 'CERTIFICADO';
        _cor1 = _colorFromHex(data['hex_cor1']);
        _cor2 = _colorFromHex(data['hex_cor2']);
        _corPonta1 = _colorFromHex(data['hex_ponta1']);
        _corPonta2 = _colorFromHex(data['hex_ponta2']);
        _isLoading = false;
      });
    }
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.length < 7) return Colors.grey;
    return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  void _pickColor(Function(Color) onColorChanged) {
    Color pickedColor = Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Escolha uma cor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Campo HEX
                Container(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Código HEX',
                      hintText: '#RRGGBB',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      try {
                        if (value.length >= 7) {
                          setState(() {
                            onColorChanged(_colorFromHex(value));
                          });
                        }
                      } catch (e) {}
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Color Picker
                ColorPicker(
                  pickerColor: pickedColor,
                  onColorChanged: (color) {
                    setState(() {
                      pickedColor = color;
                      onColorChanged(color);
                    });
                  },
                  pickerAreaHeightPercent: 0.8,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () {
                onColorChanged(pickedColor);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveGraduacao() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final data = {
        'nome_graduacao': _nomeController.text,
        'titulo_graduacao': _tituloController.text,
        'nivel_graduacao': int.tryParse(_nivelController.text) ?? 0,
        'idade_minima': int.tryParse(_idadeMinimaController.text) ?? 0,
        'tipo_publico': _tipoPublico,
        'certificado_ou_diploma': _tipoDocumento,
        'frase': _fraseController.text,
        'corda': _cordaController.text,
        'hex_cor1': _colorToHex(_cor1),
        'hex_cor2': _colorToHex(_cor2),
        'hex_ponta1': _colorToHex(_corPonta1),
        'hex_ponta2': _colorToHex(_corPonta2),
        'searchableName': _nomeController.text.toLowerCase(),
        'descricaoCompleta': '${_nomeController.text} - ${_cordaController.text}',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.graduacaoId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('graduacoes').add(data);
      } else {
        await FirebaseFirestore.instance.collection('graduacoes').doc(widget.graduacaoId).update(data);
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pop(true);
      }
    }
  }

  String? get _modifiedSvgContent {
    if (_svgContent == null) return null;
    final document = xml.XmlDocument.parse(_svgContent!);

    xml.XmlElement? findElementById(String id) {
      try {
        return document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere((e) => e.getAttribute('id') == id);
      } catch (e) {
        return null;
      }
    }

    void changeColor(String id, Color color) {
      final element = findElementById(id);
      if (element != null) {
        final style = element.getAttribute('style') ?? '';
        final hex = _colorToHex(color).toLowerCase();
        final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
        element.setAttribute('style', 'fill:$hex;$newStyle');
      }
    }

    changeColor('cor1', _cor1);
    changeColor('cor2', _cor2);
    changeColor('corponta1', _corPonta1);
    changeColor('corponta2', _corPonta2);

    return document.toXmlString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.graduacaoId == null ? 'Nova Graduação' : 'Editar Graduação'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                : const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveGraduacao,
          ),
        ],
      ),
      body: _isLoading && widget.graduacaoId != null
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview da Corda
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              color: Colors.grey[200],
              child: Column(
                children: [
                  Text("Preview da Corda", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _modifiedSvgContent != null
                      ? SvgPicture.string(_modifiedSvgContent!, height: 120)
                      : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                  const SizedBox(height: 24),
                  Text("Clique nos botões para editar as cores",
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildColorButton('Cor 1', _cor1, (c) => _cor1 = c),
                        const SizedBox(width: 20),
                        _buildColorButton('Cor 2', _cor2, (c) => _cor2 = c),
                        const SizedBox(width: 20),
                        _buildColorButton('Ponta 1', _corPonta1, (c) => _corPonta1 = c),
                        const SizedBox(width: 20),
                        _buildColorButton('Ponta 2', _corPonta2, (c) => _corPonta2 = c),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Formulário
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Graduação *',
                        border: OutlineInputBorder(),
                        hintText: 'Ex: 1° INFANTIL - CRUA',
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _cordaController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Corda *',
                        border: OutlineInputBorder(),
                        hintText: 'Ex: CRUA, AZUL / ROXO',
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _tituloController,
                      decoration: const InputDecoration(
                        labelText: 'Título *',
                        border: OutlineInputBorder(),
                        hintText: 'Ex: ALUNO INFANTIL, MONITOR',
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nivelController,
                            decoration: const InputDecoration(
                              labelText: 'Nível *',
                              border: OutlineInputBorder(),
                              hintText: 'Ex: 1',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _idadeMinimaController,
                            decoration: const InputDecoration(
                              labelText: 'Idade Mínima *',
                              border: OutlineInputBorder(),
                              hintText: 'Ex: 13',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _tipoPublico,
                            decoration: const InputDecoration(
                              labelText: 'Público *',
                              border: OutlineInputBorder(),
                            ),
                            items: ['ADULTO', 'INFANTIL'].map((String value) {
                              return DropdownMenuItem<String>(value: value, child: Text(value));
                            }).toList(),
                            onChanged: (newValue) => setState(() => _tipoPublico = newValue),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _tipoDocumento,
                            decoration: const InputDecoration(
                              labelText: 'Tipo Documento *',
                              border: OutlineInputBorder(),
                            ),
                            items: ['CERTIFICADO', 'DIPLOMA'].map((String value) {
                              return DropdownMenuItem<String>(value: value, child: Text(value));
                            }).toList(),
                            onChanged: (newValue) => setState(() => _tipoDocumento = newValue),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _fraseController,
                      decoration: const InputDecoration(
                        labelText: 'Frase do Certificado *',
                        border: OutlineInputBorder(),
                        hintText: 'Texto que aparecerá no certificado...',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorButton(String label, Color color, Function(Color) onColorChanged) {
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _pickColor(onColorChanged),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black54, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}