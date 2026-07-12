# Fase 2F3 - Midias e UX admin dos Estudos/Fundamentos

## Foco da capa

Foram adicionados campos opcionais e compatíveis com documentos antigos:

Ciclos:

- `capaFocoX`
- `capaFocoY`

Estudos:

- `capaFocoX`
- `capaFocoY`

O valor padrão e `0.5 / 0.5`, que representa o centro da imagem. Os valores são limitados entre `0.0` e `1.0`.

Quando uma capa usa `BoxFit.cover`, a tela calcula o alinhamento assim:

```dart
Alignment((capaFocoX * 2) - 1, (capaFocoY * 2) - 1)
```

O admin pode ajustar o foco por seletor 3x3 e sliders X/Y. A imagem não e recortada fisicamente; o foco ? apenas metadata para exibiáo.

## Upload multiplo de imagens

O upload de imagens internas do estudo agora permite selecionar várias imagens de uma vez com `file_picker`.

Cada arquivo e processado individualmente:

- validaáo de tipo `jpg/jpeg/png/webp`;
- limite de até 15 MB por arquivo;
- redimensionamento para no maximo 1600px de largura;
- conversão para JPG;
- compressão conforme seletor do admin;
- upload sequencial para Firebase Storage.

Se uma imagem falhar, as demais continuam. O resumo informa selecionadas, enviadas, falhas, tamanho original total, tamanho final total e reduáo aproximada.

Imagens internas continuam opcionais: `imagensUrls` pode ficar vazio.

## Navegacao admin

- Clicar no card do ciclo abre `GerenciarEstudosScreen` filtrada pelo ciclo.
- Clicar no card do estudo continua abrindo o detalhe admin do estudo, onde ficam as perguntas vinculadas.
- Botoes de editar, duplicar, arquivar, apagar e status mantem suas acoes proprias.

## Auto numeracao de ciclo

Ao criar novo ciclo, o formulario sugere:

- `numero = max(numero existente) + 1`;
- `ordem = max(ordem existente) + 1`.

Se não houver ciclos, sugere `1 / 1`. Edição de ciclo existente preserva numero e ordem atuais.

Sugestao automatica de numero/ordem para novo estudo dentro de ciclo fica para fase futura.

## Seguranca e compatibilidade

- Rules não foram alteradas.
- Storage Rules não foram alteradas.
- Functions não foram alteradas.
- `pubspec.yaml` não foi alterado.
- Aluno continua apenas visualizando imagens.
- Upload permanece restrito ao painel admin.
- Estudos e ciclos antigos sem foco continuam carregando com foco central.
- URLs manuais continuam permitidas e podem não ter `storagePath` correspondente.

## Limitaáes

- O processamento e sequencial para reduzir risco de travamento por concorrencia alta.
- Imagens muito grandes ainda podem levar alguns segundos para comprimir no Web.
- Remocao fisica individual de imagem no Storage não foi adicionada nesta fase; a limpeza real continua ocorrendo na exclusão de estudo/ciclo.

## Validaáo

Rodar:

```bash
dart analyze lib/modules/estudos_fundamentos
```

## Confirmaáo

Nenhum deploy foi executado.
Nenhum APK foi gerado.
Rules não foram alteradas.
Storage Rules não foram alteradas.
Functions não foram alteradas.
pubspec.yaml não foi alterado.
