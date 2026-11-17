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
| Quinnie Nastasja Villareal | [@quinnie9](https://github.com/quinnie9) |
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
| Análisis estático y Quality Gate | SonarCloud |
| Empaquetado (artefacto) | Docker |

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

## Pruebas

| Nivel | Componente | Herramienta | Qué valida |
|---|---|---|---|
| Unitarias | Backend | `node:test` | Lógica de autenticación (JWT), errores de dominio, middleware de autenticación y validación de entrada de órdenes. |

Las pruebas unitarias del backend se ejecutan con:

```bash
cd backend
npm install
npm test
npm run test:coverage   # con reporte de cobertura
```

## Estado

El pipeline de Integración Continua del backend está operativo (pruebas,
cobertura, análisis con SonarCloud y build de la imagen Docker). Las pruebas de
integración con base de datos, la Integración Continua del frontend y el
Despliegue Continuo a AWS están en desarrollo.
