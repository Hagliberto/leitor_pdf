# Correção APK Android — segunda revisão

Esta versão corrige também a falha `:app:checkReleaseAarMetadata`, causada por dependências AndroidX exigindo Android Gradle Plugin 8.9.1 ou superior.

## Ajustes aplicados

- `android/settings.gradle`: `com.android.application` atualizado de `8.3.2` para `8.9.1`.
- `android/settings.gradle`: `org.jetbrains.kotlin.android` atualizado de `1.9.24` para `2.1.0`.
- `android/app/build.gradle`: plugin Kotlin ajustado para `org.jetbrains.kotlin.android`.
- `android/gradle/wrapper/gradle-wrapper.properties`: Gradle Wrapper mantido em `gradle-8.11.1-all.zip`.
- Incluído `build_apk_release.ps1` para tentar localizar automaticamente o Java do Android Studio e executar o build.

## Rodar

```powershell
.\build_apk_release.ps1
```

Ou manualmente:

```powershell
flutter clean
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build\symbols --tree-shake-icons --build-name=2026.4.20 --build-number=32
```

## Sobre JAVA_HOME

Se `cd android; .\gradlew.bat --version` reclamar de JAVA_HOME, defina temporariamente:

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
```
