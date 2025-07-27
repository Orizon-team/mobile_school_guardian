

## 📋 Requisitos del Sistema

### Para Desarrollo General
- **Flutter SDK**: 3.0.0 o superior
- **Dart SDK**: 2.17.0 o superior

### Para iOS (Solo Mac) 🍎
- **macOS**: 10.15 (Catalina) o superior
- **Xcode**: 13.0 o superior
- **iOS Deployment Target**: 11.0+
- **CocoaPods**: Última versión
- **Cuenta Apple Developer** (para dispositivos físicos)

## 🛠️ Instalación

### 1. Clonar el Repositorio
```bash
git clone https://github.com/Orizon-team/mobile_school_guardian.git
cd mobile_school_guardian
```

### 2. Instalar Dependencias Flutter
```bash
flutter pub get
```

### 3. Configuración por Plataforma

#### Para Android 🤖
```bash
# Verificar configuración
flutter doctor

# Ejecutar en dispositivo/emulador Android
flutter run
```

#### Para iOS 🍎 (Solo en Mac)

**Paso 1: Instalar CocoaPods**
```bash
# Si no tienes CocoaPods instalado
sudo gem install cocoapods

# Navegar al directorio iOS
cd ios

# Instalar pods
pod install

# Regresar al directorio raíz
cd ..
```

