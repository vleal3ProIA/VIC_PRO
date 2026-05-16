# myapp

[![CI](https://github.com/vleal3ProIA/VIC_PRO/actions/workflows/ci.yml/badge.svg)](https://github.com/vleal3ProIA/VIC_PRO/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vleal3ProIA/VIC_PRO/branch/main/graph/badge.svg)](https://codecov.io/gh/vleal3ProIA/VIC_PRO)

Aplicación Flutter Web enterprise con **Clean Architecture**, **BLoC** y **inyección de dependencias** vía `get_it` + `injectable`.

> 📊 La cobertura se mide en cada PR. Se sube `coverage/lcov.info` como
> artefacto en cada run y, si el repo está conectado con Codecov
> (`CODECOV_TOKEN` en Settings → Secrets), también se publica allí.
> Objetivo: **≥ 80 % en `domain/` y `data/`**. El umbral aún no se exige
> en CI; se irá subiendo cuando se añadan widget tests.

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

# Tests unitarios + cobertura (incluye goldens en local)
flutter test --coverage

# Solo unit / widget tests (sin goldens) — esto es lo que corre CI
flutter test --exclude-tags golden

# Regenerar goldens tras un cambio intencionado de UI
flutter test --update-goldens --tags golden

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

En cualquier entorno != `prod` la app muestra un **banner "DEV" o
"STAGING"** en la esquina superior derecha — diseñado para que sea
imposible confundirse de entorno antes de pulsar acciones destructivas.

### Cómo se resuelven las variables (`.env` vs `--dart-define`)

Cada variable de `EnvConfig` se lee con este **orden de prioridad**:

1. **`--dart-define=KEY=value`** pasado al build (lo usa CI/CD).
2. **`.env`** local cargado con `flutter_dotenv` (comodidad para devs).
3. **Fallback** documentado en el getter; o `StateError` si la variable
   es obligatoria (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).

Esto permite:

- **Local**: copias `.env.example` → `.env`, rellenas tus credenciales
  del proyecto Supabase dev y haces `flutter run`. No tocas nada más.
- **CI staging/prod**: el runner NO tiene `.env` en disco — las
  credenciales viajan como GitHub Secrets que el workflow inyecta:
  ```yaml
  - run: flutter build web --release \
      --dart-define=ENV=prod \
      --dart-define=SUPABASE_URL=${{ secrets.PROD_SUPABASE_URL }} \
      --dart-define=SUPABASE_ANON_KEY=${{ secrets.PROD_SUPABASE_ANON_KEY }} \
      --dart-define=SENTRY_DSN=${{ secrets.SENTRY_DSN }} \
      --dart-define=APP_VERSION=${{ github.ref_name }}
  ```
- **Local con override puntual**: si quieres probar contra otras
  credenciales sin tocar `.env`, pasas el `--dart-define` correspondiente
  — gana sobre el archivo.

Variables soportadas:

| Variable | Obligatoria | Origen típico |
|---|---|---|
| `SUPABASE_URL` | sí | `.env` (dev) · `--dart-define` (CI) |
| `SUPABASE_ANON_KEY` | sí | `.env` (dev) · `--dart-define` (CI) |
| `SENTRY_DSN` | no | `.env` (dev opcional) · `--dart-define` (CI) |
| `APP_VERSION` | no | `--dart-define=APP_VERSION=v1.2.3` (tag git) |
| `APP_NAME` | no | `.env` (default `myapp`) |
| `OTP_CODE_LENGTH` | no | `.env` (default `6`, debe coincidir con Supabase) |
| `ENABLE_LOGGING` | no | `.env` (default `true`) |
| `ENABLE_ANALYTICS` | no | `.env` (default `false`) |
| `STRUCTURED_LOGS` | no | `.env` (default `false`) |

`.env.example` lista todas con docs. **Nunca pongas el `service_role`
key de Supabase ni el `STRIPE_SECRET_KEY` en `.env`** — esos solo viven
en `Supabase Dashboard → Edge Functions → Secrets`.

### Observabilidad (opcional pero recomendada en staging/prod)

| Variable | Mecanismo | Descripción |
|---|---|---|
| `SENTRY_DSN` | `--dart-define=SENTRY_DSN=https://…` | Si está, errores del cliente se envían a Sentry. Si no, no-op silencioso. |
| `APP_VERSION` | `--dart-define=APP_VERSION=1.0.0+12` | Tag de release que se asocia a cada evento. |
| `STRUCTURED_LOGS` | `.env` (`true`/`false`) | Fuerza el modo JSON del logger en dev. Por defecto: pretty en dev, JSON en staging/prod. |
| `ENABLE_ANALYTICS` | `.env` (`true`/`false`) | Activa el `LoggingAnalyticsBackend` (logs JSON). Cuando se integre un SaaS real (PostHog, GA4) ese backend reemplaza al logging. |

Para las Edge Functions, configura `SENTRY_DSN` en *Supabase Dashboard → Edge Functions → Secrets*. Las funciones envueltas con `withSentry(...)` lo cogen automáticamente; sin DSN quedan en no-op.

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
