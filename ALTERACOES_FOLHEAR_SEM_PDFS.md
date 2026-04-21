# Folhear — versão sem PDFs embarcados

Versão: `1.1.4+32`  
Data da versão: `21/04/2026`

## Alterações principais

- Renomeia o aplicativo de **Normativos** para **Folhear**.
- Adiciona badge visual **PDF** ao lado do nome do aplicativo na tela inicial.
- Remove PDFs embarcados da pasta `assets/pdfs`.
- Remove a declaração de `assets/pdfs/` no `pubspec.yaml`.
- Mantém apenas `assets/icon.png` e `assets/icon.gif` como assets do app.
- A biblioteca inicial passa a carregar apenas PDFs importados pelo usuário.
- Adiciona data da versão na área **Mais**.
- Altera a importação de pasta para modo **não recursivo** no desktop.
- No Android/iOS, a importação de pasta é bloqueada e o usuário é orientado a importar PDFs por seleção de arquivos.

## Observação sobre Android

O `file_picker` não se comporta bem para seleção de diretórios no Android. Por isso, nesta versão, o fluxo recomendado no celular é:

1. Abrir o aplicativo.
2. Tocar em importar PDFs.
3. Selecionar um ou mais arquivos `.pdf`.

A importação por pasta fica disponível apenas em desktop, sem varrer subpastas.
