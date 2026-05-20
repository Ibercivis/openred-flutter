#!/bin/bash
set -e

echo "🚀 Desplegando Open-red a producción..."
echo ""

# Variables
SERVER="ubuntu@lostatnight.org"
TARGET_PATH="/home/ubuntu/openred-map/open-red.apk"
TARGET_DIR="/home/ubuntu/openred-map"
BUILD_DIR="build/app/outputs/flutter-apk"
APK_FILE="app-release.apk"
DOWNLOAD_PAGE="download_page.html"

# Compilar la app
echo "📦 Compilando APK en modo release..."
flutter build apk --release

# Verificar que se generó el APK
if [ ! -f "$BUILD_DIR/$APK_FILE" ]; then
    echo "❌ Error: No se generó el APK"
    exit 1
fi

# Mostrar tamaño del APK
APK_SIZE=$(du -h "$BUILD_DIR/$APK_FILE" | cut -f1)
echo "✅ APK compilado: $APK_SIZE"
echo ""

# Crear backup con timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BUILD_DIR/app-release-$TIMESTAMP.apk"
cp "$BUILD_DIR/$APK_FILE" "$BACKUP_FILE"
echo "💾 Backup local guardado: $BACKUP_FILE"
echo ""

# Subir al servidor
echo "📤 Subiendo al servidor $SERVER..."
scp "$BUILD_DIR/$APK_FILE" "$SERVER:$TARGET_PATH"
scp "$DOWNLOAD_PAGE" "$SERVER:$TARGET_DIR/index.html"

echo ""
echo "✅ Deploy completado exitosamente!"
echo "📱 APK disponible en: https://lostatnight.org/openred-map/open-red.apk"
echo "🌐 Página de descarga: https://lostatnight.org/openred-map/"
echo ""
echo "Para descargar en tu dispositivo:"
echo "   https://lostatnight.org/openred-map/"
