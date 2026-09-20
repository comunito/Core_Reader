# Core Reader MVP plan

## Diagnóstico inicial

- Base: VReader, Swift 6, SwiftUI, SwiftData, Readium Swift Toolkit.
- Target actual: iOS/iPadOS 17, familias de dispositivo iPhone+iPad; no hay target
  de macOS ni Android dentro del target iOS.
- EPUB: ya existe importación desde Files, biblioteca, apertura, lector Readium,
  navegación paginada/scroll y restauración local.
- Posición: `ReadingPosition` persiste un `Locator` y un `VReaderLocator` que puede
  contener el locator Readium serializado. `ReaderPositionService` debouncea los
  cambios y `ReadiumEPUBHost` guarda los relocates del navigator. Esta será la única
  fuente de verdad para lectura visual y seguimiento TTS.
- TTS: ya existe `TTSProvider`, segmentación por frases, caché en disco,
  `HTTPSpeechSynthesizer`, audio por chunks, pausa/resume y seguimiento del texto.
  La configuración actual soporta Azure/custom, pero no Google Cloud TTS.
- Seguridad: el patrón existente guarda configuración no sensible en UserDefaults y
  la API key separada en Keychain. Se reutilizará para Google sin introducir secretos
  en código o preferencias.
- CloudKit/iCloud: no se implementará en este sprint.
- Validación: el repositorio se clonó y está limpio. No fue posible ejecutar
  `xcodebuild`/los tests porque la máquina sólo tiene Command Line Tools; falta
  Xcode con el SDK de iOS y un simulador.

## Archivos a modificar

- `vreader/Services/TTS/HTTPTTSConfig.swift`: añadir Google Cloud como proveedor,
  validación y valores por defecto.
- `vreader/Services/TTS/HTTPTTSProvider.swift`: construir la petición Google
  `text.synthesize`, con respuesta MP3 y autenticación por query key.
- `vreader/Views/Settings/HTTPTTSSettingsView.swift`: selector Google, voz inicial
  `es-US-Wavenet-B` y endpoint derivado sin exponer la clave.
- `vreader/Services/TTS/HTTPTTSConfigStore.swift`: conservar la separación de
  configuración/API key y compatibilidad con configuraciones existentes.
- `.gitignore`: reforzar exclusión de archivos locales de secretos/configuración.
- tests existentes de TTS: cubrir request Google, voz por defecto y caché.

## Archivos nuevos

No se necesitan archivos nuevos para el primer corte. Se reutilizan los seams y
adaptadores existentes para evitar duplicar el pipeline de audio y posición.

## Orden de implementación

1. Añadir el tipo Google al modelo de configuración, manteniendo Azure/custom.
2. Añadir el contrato HTTP de Google y su respuesta MP3 al proveedor existente.
3. Hacer que Settings pueda guardar Google y seleccionar voz/velocidad sin guardar
   la API key fuera de Keychain.
4. Alinear la identidad de caché con proveedor+voz+texto; mantener limpieza manual
   fuera del MVP.
5. Añadir pruebas unitarias de configuración, request, segmentación y caché.
6. Revisar el flujo Readium: relocates visuales y los relocates derivados de TTS
   deben seguir usando el mismo `ReadingPosition`; no añadir una posición de audio.
7. Ejecutar build y tests en Xcode/simulador cuando el entorno disponga del SDK.

## Riesgos

- Google Cloud TTS requiere que la API key tenga habilitado el servicio y facturación;
  el MVP no puede verificar esas credenciales sin una clave real.
- La API key en una app cliente puede extraerse del dispositivo; Keychain reduce la
  exposición accidental, pero no convierte una clave BYOK en un secreto de servidor.
- WaveNet devuelve audio sin timestamps por palabra; el progreso seguirá siendo por
  rango de chunk, que es la precisión definida para Sprint 1.
- El build no puede certificarse en esta máquina sin Xcode/iOS Simulator.
- El volumen actual de VReader incluye funcionalidades fuera del MVP; se mantienen
  ocultas por configuración existente y no se hace una reescritura destructiva.

## Definición de terminado

- Un EPUB importado se abre en Readium y restaura su posición local.
- Play sintetiza desde el locator actual; Pause/Resume conserva el avance y el lector
  vuelve cerca del rango donde terminó el audio.
- Google Cloud TTS funciona con API key en Keychain, voz seleccionable y velocidad.
- Los chunks se cachean localmente y no repiten llamadas para la misma identidad.
- El audio continúa con la app en background mediante la sesión existente.
- No hay CloudKit, Android, web ni API keys en git/UserDefaults.
- Tests unitarios verdes y build instalable verificado en Xcode/simulador.

## Preparación sin Xcode

- `ReadingProgressStore` es la fachada única para cargar/guardar progreso y
  resolver un registro más reciente por `updatedAt`.
- `ReadingProgressRecord` deja el progreso en una forma Codable transportable a
  CloudKit sin activar entitlements ni llamadas de red.
- `TextChunk`, `AudioCacheKey`, `AudioCache` y `AudioPlaybackService` separan
  segmentación, identidad de caché, filesystem y reproducción.
- La identidad de libro existente (`DocumentFingerprint`) ya usa SHA-256 de los
  bytes y tamaño; se conserva como `bookID` estable.
- Se añadió un fixture EPUB sintético generado desde strings (`MigrationFixtures`)
  con dos capítulos, diálogos, acentos, `ñ`, `¿?` y `¡!`, sin contenido con copyright.
- El detalle de sincronización futura está en `docs/cloudkit-sync-design.md` y
  el límite de producto en `docs/vreader-scope.md`.
