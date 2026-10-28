# GYMSHERONSO

App Android (Flutter) para registrar entrenamientos. Todo se guarda **localmente** en el teléfono; no usa Internet.

> **Estado honesto:** el código fuente y las pruebas están escritos, pero **no se compilaron ni ejecutaron** en el entorno donde se generaron (sin Flutter/Android SDK). El APK se genera con GitHub Actions al subir el proyecto. Es probable que la primera compilación pida algún ajuste menor; el log de Actions lo indicará.

## Obtener el APK (lo más fácil: GitHub)
1. Crea un repositorio nuevo en GitHub y sube **todo el contenido de esta carpeta** (incluida `.github/`).
2. Ve a la pestaña **Actions → "Compilar APK GYMSHERONSO"** (se ejecuta solo con cada push; también puedes darle *Run workflow*).
3. Al terminar (≈10 min), abre la ejecución y descarga el artefacto **GYMSHERONSO-apk** (contiene `GYMSHERONSO.apk`).
4. Opcional: crea una etiqueta `v1.0.0` y el APK se adjunta automáticamente en **Releases**.

## Compilar en tu PC
```bash
flutter create . --platforms=android --org com.sheronso --project-name gymsheronso   # hace una copia de lib/ y pubspec.yaml antes si prefieres
python3 tool/patch_android.py      # permisos, receptores de notificaciones, desugaring, nombre de app
flutter pub get
flutter test
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
```
(`flutter create .` no pisa `lib/` ni `pubspec.yaml` existentes, pero haz copia por si acaso.)

## Instalar en el teléfono
1. Pasa `GYMSHERONSO.apk` al teléfono (cable, Drive, etc.).
2. Ábrelo y permite *"Instalar apps desconocidas"* para ese origen.
3. Al abrir la app, acepta el permiso de **notificaciones**.
4. Recomendado: en Ajustes de Android desactiva la optimización de batería para GYMSHERONSO, para que los avisos lleguen con la pantalla apagada.

## Manual breve
- **Entrenar**: botón *Entrenar* → añade ejercicios → ajusta peso/reps con +/− → ✓ para completar la serie. Se inicia el descanso y, al terminar, suena la alarma y **se añade sola la siguiente serie**. Cada ejercicio muestra *"Última vez: 3×8 con 40 kg"*.
- **Rutinas**: icono de marcador en el entrenamiento → *Guardar como rutina*. En Inicio, toca la rutina para cargarla con las series prellenadas.
- **Borrador**: si Android cierra la app, el entrenamiento en curso reaparece en Inicio.
- **Historial**: filtros por rango de fechas, ejercicio y grupo muscular; calendario con días entrenados; toca una sesión para editarla; desliza para borrar.
- **Progreso**: buscador de ejercicios, rango de fechas, gráficas de peso máx., 1RM (Epley) y volumen; frecuencia semanal; volumen por grupo muscular; Fitness/Fatiga; peso corporal, % grasa, cintura y brazo.
- **Racha 🔥**: días consecutivos entrenados; si faltas un día se reinicia.
- **Recordatorios**: si el lunes entrenaste "Día de pecho" a las 20:00, el siguiente lunes a las 15:00 llega el aviso.
- **Ajustes**: usuarios con foto, kg/lb, paso de incremento, descanso, colores/estética, ejercicios (favoritos/archivar), respaldos JSON, Excel, datos DEMO.

## Implementado
Usuarios y foto · editar/borrar sesiones · rutinas · última vez · importar/exportar JSON · borrador automático · alarma con sonido (en la app) y notificación programada (segundo plano) · PR y 1RM · filtros y calendario · frecuencia y volumen por grupo · tipo de serie y RPE (calentamiento excluido) · peso corporal y medidas · superseries (enlace visual) y notas por ejercicio · favoritos/recientes · kg/lb y pasos · botones +/− · pantalla encendida · archivar ejercicios · Excel y copia automática semanal · racha · recordatorios semanales · fitness/fatiga · filtros de Inicio (usuario/ejercicio/fecha) · temas y colores · pruebas unitarias.

## Pendiente / limitaciones
- No compilado ni probado en dispositivo real (ver aviso arriba).
- Persistencia en un archivo JSON versionado (`gymsheronso.json`), no SQLite/migraciones.
- Las fotos de perfil no viajan dentro del respaldo JSON (solo su ruta).
- Recordatorios semanales calculados sobre UTC: pueden desfasarse 1 h en países con cambio de horario.
- Las superseries solo enlazan ejercicios visualmente (sin descanso especial).
- Ícono de app por defecto de Flutter; sin firma de producción (APK firmado con clave de depuración).
