# Normativos — Flutter

Aplicativo Flutter multiplataforma para leitura de documentos PDF locais em `assets/pdfs/`, com foco em Web, Android e iOS.

## Recursos

- Home mobile com Material 3, cards, pills e navegação inferior.
- Busca na lista de documentos e busca indexada dentro dos PDFs.
- Visualização Web via iframe nativo do navegador.
- Visualização Android/iOS/Desktop via Syncfusion PDF Viewer.
- Favoritos de documentos e favoritos por página com prévia textual.
- Duplo toque para favoritar a página atual.
- Pressão longa para abrir ações rápidas.
- Compartilhamento como arquivo:
  - página atual como PDF único;
  - documento completo como PDF.
- Barra de busca inferior ajustada para subir com o teclado do celular.
- Ícone do app em `assets/icon.png`.

## Assets

```txt
assets/
├── icon.png
└── pdfs/
    ├── acordo.pdf
    ├── manual.pdf
    ├── norma.pdf
    ├── catalog.json
    └── pdf_text_index.json
```

## Rodar no navegador

```powershell
flutter clean
flutter pub get
flutter run -d edge
```

Caso a pasta Web ainda não exista no seu ambiente local:

```powershell
flutter create . --platforms=web
flutter pub get
flutter run -d edge
```

## Recriar Android e gerar APK

Se aparecer erro de Gradle/Android não suportado, recrie a pasta Android:

```powershell
cd "C:\Users\Hagliberto\Desktop\leitor de pdf\leitor_pdf_flutter"

if (Test-Path android) {
    Rename-Item android android_backup
}

flutter create . --platforms=android,web
flutter pub get
```

Ajuste o nome exibido no Android para **Normativos**:

```powershell
(Get-Content android\app\src\main\AndroidManifest.xml) `
  -replace 'android:label="[^"]+"', 'android:label="Normativos"' |
  Set-Content android\app\src\main\AndroidManifest.xml
```

Gerar os ícones do app usando `assets/icon.png`:

```powershell
dart run flutter_launcher_icons
```

Gerar APK release:

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

APK final:

```txt
build\app\outputs\flutter-apk\app-release.apk
```

APK menor por arquitetura:

```powershell
flutter build apk --split-per-abi --release
```

Saída:

```txt
build\app\outputs\flutter-apk\
```

## Atualização v10

- Compartilhamento da página atual com escolha entre **PDF** e **PNG**.
- Compartilhamento do documento completo como PDF.
- Modais com fechamento por toque fora da área da folha inferior, inclusive no Flutter Web com iframe.
- Busca inferior transformada em botão flutuante de lupa no canto inferior direito; o campo aparece acima da navbar.
- Navbar simplificada sem item de pesquisa.
- Home com alternância entre visualização em cards de prévia e visualização em miniatura da página inicial.
- Área “Mais” com criador da aplicação, motivação, versão do app e versões dos PDFs.

## Comandos principais

```powershell
flutter clean
flutter pub get
flutter run -d edge
```

Gerar APK:

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

Gerar APKs por arquitetura:

```powershell
flutter build apk --split-per-abi --release
```


## Atualização v11

- A busca inferior agora fecha ao tocar fora do campo, voltando a exibir somente a lupa.
- A descrição do criador foi ajustada para primeira pessoa.
- A biblioteca reconhece automaticamente PDFs declarados dentro da pasta `assets/`, inclusive `assets/pdfs/`, usando o `AssetManifest.json`.
- PDFs novos que não estejam no `catalog.json` recebem título automático a partir do nome do arquivo, versão padrão `v1.0` e contagem de páginas extraída do próprio PDF.
- A busca também tenta extrair texto dinamicamente de PDFs novos quando eles ainda não estiverem no `pdf_text_index.json`.

## Atualização v13 — correção de assets no Flutter Web

Esta versão não depende apenas do `AssetManifest` do Flutter Web. Ela usa também:

```txt
assets/pdfs/pdf_manifest.json
web/assets/pdfs/pdf_manifest.json
web/assets/pdfs/*.pdf
```

Isso corrige a tela vazia causada por erros como:

```txt
assets/assets/pdfs/catalog.json 404
assets/AssetManifest.bin.json 404
```

### Sempre que adicionar novos PDFs

Coloque o PDF em uma destas pastas:

```txt
assets/
assets/pdfs/
```

Depois execute:

```powershell
dart run tool/refresh_pdf_assets.dart
flutter clean
flutter pub get
flutter run -d edge
```

### Se o Windows não deixar limpar build/.dart_tool

Feche Edge, VS Code/Android Studio e rode:

```powershell
Get-Process dart,flutter,msedge -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -Recurse -Force build,.dart_tool -ErrorAction SilentlyContinue
flutter pub get
flutter run -d edge
```

## Atualização v14 — PDFs automáticos

A Home agora mescla os PDFs encontrados no `pdf_manifest.json` com os PDFs declarados no `AssetManifest` do Flutter. Assim, quando novos arquivos `.pdf` forem colocados em `assets/` ou `assets/pdfs/`, eles aparecem mesmo que o `pdf_manifest.json` ainda esteja desatualizado.

Mesmo assim, para o Flutter Web funcionar de forma mais estável com o iframe, recomenda-se rodar:

```powershell
dart run tool/refresh_pdf_assets.dart
flutter clean
flutter pub get
flutter run -d edge
```


## v17 — Pastas, importação e post-its

Esta versão adiciona organização por pastas e hierarquia simples:

- criar pastas a partir do botão `+` ou do menu `Mais`;
- selecionar pastas na Home para visualizar os PDFs vinculados;
- ativar visualização em árvore no menu `Mais`;
- pressionar uma pasta para renomear;
- pressionar um PDF para mover/adicionar a uma pasta;
- importar PDFs do dispositivo com o seletor de arquivos;
- adicionar post-it por página no menu `Mais` do leitor;
- toast com tema azul claro.

Observação: no Android/iOS, os PDFs importados são copiados para a pasta interna do aplicativo. No Flutter Web, a importação persistente por caminho físico depende das limitações do navegador.


## v19 - Organização, post-its e segurança

- Arraste o PDF para a direita para favoritar/desfavoritar.
- Arraste o PDF para a esquerda para excluir, com modal de confirmação e desfazer por 5 segundos.
- As ferramentas de edição do PDF foram migradas para a engrenagem no leitor.
- O menu Mais do leitor agora tem lista de post-its do documento.
- Post-it da página ganhou título, cores rápidas e atalhos de formatação.
- Reset da Home abre modal explicativo e permite escolher quais PDFs manter visíveis.
- Toast crítico usa tema azul claro e exibe temporizador/ação por 5 segundos.

Observação técnica: PDFs empacotados nos assets são somente leitura. Marcações e post-its ficam salvos na aplicação; para distribuição definitiva com anotações gravadas no arquivo, use as opções de exportação/compartilhamento anotado quando disponíveis.

## Versão v20 — organização, pastas e anotações

A versão v20 reorganiza a experiência da Home e do leitor:

- o card superior Biblioteca/Favoritos foi removido para ganhar espaço;
- a AppBar ficou mais compacta;
- o painel de pastas/árvore agora abre e fecha pelo ícone de pasta na AppBar;
- pastas podem ser criadas, renomeadas, coloridas e excluídas;
- o reset permite escolher quais PDFs e quais pastas manter;
- as ferramentas de marcação do PDF ficam na engrenagem do leitor;
- as marcações passam a ser salvas localmente por documento e página, reaparecendo ao voltar ao PDF;
- a lista de post-its pode ser aberta pelo menu do PDF;
- o post-it ganhou atalhos de formatação, lista, alerta, tarefa e referência de imagem;
- arrastar PDF na Home para a direita favorita/desfavorita; para a esquerda abre confirmação de exclusão;
- ações críticas mostram toast azul claro com tempo de 5 segundos e opção de desfazer quando aplicável.

> Observação: PDFs em `assets/` são somente leitura em tempo de execução. Por isso, marcações e post-its são salvos como camada local do aplicativo por documento/página. Para gerar um arquivo PDF final com as marcações embutidas, use uma rotina de exportação de PDF anotado em versão posterior.

## Versão v27

- Removida a funcionalidade de formatação visual sobre o PDF, pois ela não altera fisicamente o arquivo.
- Removida a engrenagem do topo do leitor.
- O botão `+` agora abre uma fileira rápida de ícones, sem modal, com: orientação, ajustar largura, tela cheia, adicionar post-it, lista de post-its, favoritar página e compartilhar.
- Ícone de compartilhamento atualizado para um símbolo mais direto.

Observação: para edição física de PDF, será necessário implementar uma rotina futura de exportação/gravação de PDF anotado.


## Versão v28

- Importação de PDFs por arquivo individual ou por pasta no desktop, com varredura recursiva de subpastas.
- Exclusão de PDF com animação de arrastar e confirmação.
- Toasts padronizados no tema azul claro.
- Post-it com seleção de texto: negrito, itálico e sublinhado aplicam no trecho selecionado.
- Botão de galeria de ícones no post-it.
- Removido o botão de tarefa do editor do post-it.
