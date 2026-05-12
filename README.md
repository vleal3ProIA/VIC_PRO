# myapp

Aplicación Flutter Web enterprise con **Clean Architecture**, **BLoC** y **inyección de dependencias** vía `get_it` + `injectable`.

---

## Stack tecnológico

| Capa | Herramientas |
|------|--------------|
| **State management** | flutter_bloc, bloc, equatable |
| **DI** | get_it, injectable |
| **Routing** | go_router |
| **Networking** | dio, retrofit, pretty_dio_logger, connectivity_plus |
| **Errores funcionales** | dartz, fpdart |
| **Persistencia** | shared_preferences, flutter_secure_storage, hive |
| **Serialización** | json_serializable, freezed |
| **UI** | flex_color_scheme, google_fonts, responsive_framework, flutter_svg |
| **Forms** | formz, reactive_forms |
| **i18n** | flutter_localizations, intl |
| **Lint** | very_good_analysis |
| **Tests** | flutter_test, bloc_test, mocktail, golden_toolkit, integration_test |

---

## Estructura del proyecto

```
myapp/
├── lib/
│   ├── core/                    # Código transversal
│   │   ├── config/              # Configuración por entorno
│   │   ├── constants/           # Constantes globales
│   │   ├── di/                  # get_it + injectable
│   │   ├── errors/              # Failures, exceptions
│   │   ├── extensions/          # Dart/Flutter extensions
│   │   ├── network/             # Dio, interceptors
│   │   ├── router/              # go_router config
│   │   ├── storage/             # Hive, secure storage
│   │   ├── theme/               # ThemeData, tokens
│   │   ├── usecases/            # UseCase base abstracto
│   │   └── utils/               # Helpers
│   ├── features/                # Feature-first organization
│   │   └── <feature>/
│   │       ├── data/
│   │       │   ├── datasources/ # Remote / Local
│   │       │   ├── models/      # DTOs
│   │       │   └── repositories/# Implementaciones
│   │       ├── domain/
│   │       │   ├── entities/    # Modelos puros
│   │       │   ├── repositories/# Contratos abstractos
│   │       │   └── usecases/    # Casos de uso
│   │       └── presentation/
│   │           ├── bloc/        # BLoC / Cubit
│   │           ├── pages/       # Screens
│   │           └── widgets/     # Widgets de la feature
│   ├── l10n/                    # Archivos .arb
│   ├── shared/                  # Widgets, modelos, servicios compartidos
│   └── main.dart
├── test/                        # Unit & widget tests (espejo de lib/)
├── integration_test/            # Tests end-to-end
├── assets/                      # images, icons, fonts, translations
├── web/                         # Configuración Flutter Web
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

### Principios de arquitectura

- **Domain** no depende de nada externo: entidades, contratos y use cases puros.
- **Data** implementa contratos de domain y traduce DTOs ↔ entidades.
- **Presentation** consume use cases vía BLoC; nunca toca `data` directamente.
- **Flujo de errores**: `DataSource → throw Exception → Repository → Either<Failure, T> → UseCase → BLoC`.

---

## Requisitos

- Flutter `>= 3.22.0`
- Dart `>= 3.4.0`
- Navegador Chromium para `flutter run -d chrome`

```powershell
flutter --version
flutter doctor
```

---

## Puesta en marcha

```powershell
# 1. Clonar e instalar dependencias
cd C:\VIC_PRO\myapp
flutter pub get

# 2. Generar código (freezed, json_serializable, injectable, retrofit, hive)
dart run build_runner build --delete-conflicting-outputs

# 3. Crear archivo de entorno
Copy-Item .env.example .env   # editar valores

# 4. Ejecutar en Chrome
flutter run -d chrome
```

### Generación continua durante desarrollo

```powershell
dart run build_runner watch --delete-conflicting-outputs
```

---

## Scripts útiles

```powershell
# Análisis estático
flutter analyze

# Formateo
dart format --set-exit-if-changed lib test

# Tests unitarios + cobertura
flutter test --coverage

# Tests de integración (web)
flutter test integration_test -d chrome

# Build producción web
flutter build web --release --web-renderer canvaskit
```

---

## Entornos

| Entorno | Comando |
|---------|---------|
| Development | `flutter run -d chrome --dart-define=ENV=dev` |
| Staging | `flutter run -d chrome --dart-define=ENV=staging` |
| Production | `flutter build web --release --dart-define=ENV=prod` |

Variables sensibles en `.env` (ignorado por git). Plantilla en `.env.example`.

---

## Convenciones

- **Lint**: `very_good_analysis` + reglas estrictas en `analysis_options.yaml`.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `chore:`).
- **Branching**: `main` (estable), `develop` (integración), `feature/*`, `fix/*`, `release/*`.
- **PRs**: Squash merge + descripción que enlace el ticket.
- **Tests**: cobertura mínima objetivo 80% en `domain/` y `data/`.

---

## Estructura de tests

```
test/
├── core/                 # Tests de infraestructura
├── features/<feature>/
│   ├── data/             # Repositories + datasources
│   ├── domain/           # Use cases
│   └── presentation/     # BLoCs + widgets
└── helpers/              # Fixtures, mocks, matchers
```

---

## Roadmap inicial

- [ ] Configurar entorno (`.env.example`, `--dart-define`).
- [ ] Implementar feature `auth` (login, refresh token, logout).
- [ ] Implementar `core/network` con interceptors de auth y errores.
- [ ] Configurar `go_router` con guards.
- [ ] Pipeline CI: `analyze`, `test`, `build web`.

---

## Licencia

Propietaria. Todos los derechos reservados.
