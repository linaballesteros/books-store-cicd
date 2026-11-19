# books-store-cicd

Proyecto final del curso de CI/CD. Implementa un pipeline completo de
Integración y Despliegue Continuo (CI/CD) sobre **BookStore Co.**, una
aplicación de complejidad media con tres componentes:

- **Frontend**: SPA en React 19 + Vite, servida con Nginx.
- **Backend**: API REST en Node.js 24 + Express 5, con autenticación JWT.
- **Base de datos**: PostgreSQL (esquema, datos iniciales y bootstrap).

La aplicación base proviene de un proyecto existente y se reutiliza como
artefacto de software; el aporte de este repositorio es el pipeline de CI/CD,
las pruebas, la infraestructura como código y la estrategia de despliegue.

## Integrantes

| Nombre | Usuario de GitHub |
|---|---|
| Lina Sofía Ballesteros | [@linaballesteros](https://github.com/linaballesteros) |
| Quinnie Nastasja Villarreal Aragon | [@quinnie9](https://github.com/quinnie9) |
| Alejandro Ríos Muñoz | [@alejoriosm04](https://github.com/alejoriosm04) |

Propietaria del repositorio: [@linaballesteros](https://github.com/linaballesteros).

## Arquitectura del repositorio

```text
.
├── frontend/              # React + Vite + Nginx
├── backend/               # API Node.js/Express + PostgreSQL
├── database/              # schema.sql, seed.sql y bootstrap de RDS
├── .github/workflows/     # pipelines de GitHub Actions
├── compose.yaml           # entorno local completo
└── VERSION                # versión de las imágenes publicadas
```

## Ejecución local

Requiere Docker y Docker Compose.

```bash
cp .env.example .env
docker compose up --build
```

La aplicación queda disponible en `http://localhost:8080` (o en el puerto
definido en `FRONTEND_HOST_PORT`).

El entorno instruccional usa autenticación simplificada. Usuario disponible en
los datos iniciales (no requiere contraseña):

```text
synthetic.customer.0008@bookstore.test
```

## Estrategia de versionamiento

Se usa **Trunk-Based Development**: ramas de vida corta (`feature/...`,
`docs/...`) que se integran a `main` mediante Pull Request. `main` se mantiene
siempre en estado desplegable.

Se eligió por sus ventajas para CI/CD: integración continua real (cambios
pequeños y frecuentes), menos conflictos de merge, un lead time corto hacia el
despliegue y una única rama principal siempre lista para liberar.

La rama `main` está protegida (ruleset `proteger-main`):

- No se permite push directo; todo cambio entra por Pull Request.
- Se exige al menos una aprobación de otro integrante.
- Se exige que el check de integración continua (`backend`) esté en verde.

## Pipeline CI/CD

El pipeline vive en `.github/workflows/` y se apoya en las siguientes
herramientas por etapa:

| Etapa | Herramienta |
|---|---|
| Control de versiones y disparo | Git + GitHub Actions |
| Build / dependencias | Node.js 24, npm |
| Pruebas unitarias y cobertura | `node:test` (runner nativo de Node) |
| Pruebas de componente del frontend | Vitest + Testing Library, con entorno jsdom |
| Análisis estático y Quality Gate | SonarCloud |
| Empaquetado (artefacto) | Docker |
| Publicación multiplataforma | Docker Buildx + QEMU + Docker Hub |

### Integración de la estrategia con el pipeline

- En cada **Pull Request** hacia `main` se ejecuta la Integración Continua
  (pruebas, cobertura, análisis y build de la imagen). El merge se bloquea si
  algo falla.
- En cada **push a `main`** (tras el merge) se vuelve a ejecutar el pipeline
  sobre la rama integrada.
- `workflow_dispatch` permite ejecuciones manuales.

### Análisis estático y cobertura (SonarCloud)

El análisis se lanza **desde el pipeline** (no con el análisis automático de
SonarCloud). El paso usa `sonar.qualitygate.wait=true`, de modo que si el
Quality Gate falla, el job falla y el merge queda bloqueado.

La definición de "código nuevo" en SonarCloud es **Previous version**, para que
el Quality Gate evalúe la cobertura y la calidad del código que incorpora el
equipo y no de la base heredada. La cobertura exigida (80%) se mide sobre la
lógica con pruebas; la configuración está en `sonar-project.properties`.

Las GitHub Actions se referencian por **SHA de commit** (no por etiqueta de
versión) como medida de seguridad de cadena de suministro.

El frontend y el backend se validan en paralelo. El job `sonar` espera sus dos
reportes LCOV y el resultado de integración, y ejecuta un único análisis para
evitar que una ejecución sobrescriba la cobertura de la otra. Los PR no publican
imágenes. En `main`, tras pasar todos los controles, `publish-backend` y
`publish-frontend` publican imágenes para `linux/amd64` y `linux/arm64` y verifican
las dos arquitecturas en el manifiesto del registro.

### Configuración de publicación

La propietaria configura en **Settings → Secrets and variables → Actions**:

- Variable `DOCKERHUB_USERNAME`: cuenta o namespace que alojará ambas imágenes.
- Secreto `DOCKERHUB_TOKEN`: token con permiso de escritura en ese namespace.
- Se mantienen `SONAR_TOKEN` y `SONAR_HOST_URL` del análisis existente.

Los nombres publicados son `<namespace>/bookstore-backend:<sha>` y
`<namespace>/bookstore-frontend:<sha>`. El artefacto `release-manifest` contiene
`release.json` con el commit, los digests exactos y las plataformas de ambas
imágenes. CD debe consumir esos digests para promover la misma pareja de
artefactos a Staging y Producción. Si falla una publicación, no se genera la
release conjunta.

Al incorporar estos jobs, actualizar los checks obligatorios del ruleset para
incluir `frontend`, `backend-integration` y `sonar`, además de `backend`.

## Pruebas

| Nivel | Componente | Herramienta | Qué valida |
|---|---|---|---|
| Unitarias | Backend | `node:test` | Lógica de autenticación (JWT), errores de dominio, middleware de autenticación y validación de entrada de órdenes. |
| Integración | Backend + PostgreSQL | `node:test` + service container | Flujo de órdenes contra una base de datos real: creación de la orden y descuento de stock, y el rechazo por stock insuficiente, cliente inexistente o libro inexistente. |
| Unitarias y de componente | Frontend | Vitest + Testing Library | Carrito e inventario disponible, aislamiento entre clientes, contratos de API, errores, formato, inicio de sesión, compra y protección de rutas. |

Las pruebas unitarias del backend no necesitan base de datos:

```bash
cd backend
npm install
npm test
npm run test:coverage   # con reporte de cobertura
```

Las pruebas de integración se ejecutan contra una base de datos PostgreSQL con
el esquema y los datos iniciales cargados. En el pipeline, esa base se levanta
como *service container*. Se activan con la variable `RUN_DB_TESTS=1`:

```bash
RUN_DB_TESTS=1 npm run test:integration
```

Las pruebas del frontend no necesitan AWS ni una base de datos. Se ejecutan con
Node.js 24:

```bash
cd frontend
npm ci --ignore-scripts
npm run lint
npm run test:coverage
```

El umbral es 80% en líneas, sentencias, funciones y ramas del alcance definido
en `frontend/vitest.config.js`. Se miden la lógica del carrito, servicios de
cliente, errores, formato, hooks de sesión/carrito y los componentes Login,
CartScreen y ProtectedRoute. No representa cobertura de todas las pantallas
heredadas. El reporte HTML queda en `frontend/coverage/index.html`; el LCOV
se integra con el backend en SonarCloud.

Para compilar sin Docker, configurar las variables de
`frontend/.env.example` antes de ejecutar `npm run build`.

## Estado

El backend conserva sus pruebas unitarias y de integración con PostgreSQL.
La contribución del frontend añade su suite, lint, build, cobertura conjunta en
SonarCloud y publicación de ambas imágenes en Docker Hub. La primera publicación
requiere la variable y el secreto descritos arriba. El Despliegue Continuo a AWS
se desarrolla en el frente de infraestructura del equipo.
