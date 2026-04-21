# Build APK Release - Leitor PDF Flutter
$ErrorActionPreference = "Stop"

Write-Host "==> Verificando Java/JDK..." -ForegroundColor Cyan

$possibleJavaHomes = @(
  "$env:ProgramFiles\Android\Android Studio\jbr",
  "$env:ProgramFiles\Android\Android Studio\jre",
  "$env:ProgramFiles\Java\jdk-17",
  "$env:ProgramFiles\Eclipse Adoptium\jdk-17*"
)

if (-not $env:JAVA_HOME) {
  foreach ($candidate in $possibleJavaHomes) {
    $resolved = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved -and (Test-Path (Join-Path $resolved.FullName "bin\java.exe"))) {
      $env:JAVA_HOME = $resolved.FullName
      $env:Path = "$env:JAVA_HOME\bin;$env:Path"
      Write-Host "JAVA_HOME definido temporariamente para: $env:JAVA_HOME" -ForegroundColor Green
      break
    }
  }
}

if (-not $env:JAVA_HOME) {
  Write-Host "JAVA_HOME não está definido. O Flutter pode usar o Java embutido do Android Studio, mas o gradlew direto pode falhar." -ForegroundColor Yellow
} else {
  & "$env:JAVA_HOME\bin\java.exe" -version
}

flutter clean
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build\symbols --tree-shake-icons --build-name=2026.4.20 --build-number=32

Write-Host "Build finalizado. Verifique: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
