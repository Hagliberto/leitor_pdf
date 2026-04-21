# Deploy Web automatizado — Folhear

Este projeto possui dois workflows em `.github/workflows`:

- `github-pages.yml`: gera os arquivos estáticos em `build/web` e publica no GitHub Pages sempre que houver commit na `main`.
- `cloudflare-pages.yml`: gera os arquivos estáticos em `build/web` e publica no Cloudflare Pages sempre que houver commit na `main`.

## GitHub Pages

No GitHub, acesse:

`Settings > Pages > Source > GitHub Actions`

Depois, cada push na `main` executará:

```bash
flutter build web --release --base-href /leitor_pdf/
```

## Cloudflare Pages

Crie um projeto no Cloudflare Pages com o nome:

```text
leitor-pdf
```

No GitHub, cadastre os secrets:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
```

O workflow executará:

```bash
flutter build web --release --base-href /
```

A pasta estática publicada será:

```text
build/web
```
