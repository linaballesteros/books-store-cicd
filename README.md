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

| Nombre | Usuario de GitHub | Rol |
|---|---|---|
| Lina Sofía Ballesteros | [@linaballesteros](https://github.com/linaballesteros) | Propietaria del repositorio |
| Quinnie Nastasja Villareal | [@quinnie9](https://github.com/quinnie9) | Colaboradora |
| Alejandro Ríos Muñoz | [@alejoriosm04](https://github.com/alejoriosm04) | Colaborador |

`AUTOR`: `Lina Sofía Ballesteros | Quinnie Nastasja Villareal | Alejandro Ríos Muñoz`

## Arquitectura

```text
.
├── frontend/      # React + Vite + Nginx
├── backend/       # API Node.js/Express + PostgreSQL
├── database/      # schema.sql, seed.sql y bootstrap de RDS
├── compose.yaml   # entorno local completo
└── VERSION        # versión de las imágenes publicadas
```

## Ejecución local

Requiere Docker y Docker Compose.

```bash
cp .env.example .env
docker compose up --build
```

La aplicación queda disponible en `http://localhost:8080` (o en el puerto
definido en `FRONTEND_HOST_PORT`).

### Usuario de prueba

El entorno instruccional usa autenticación simplificada. Usuario disponible en
los datos iniciales (no requiere contraseña):

```text
synthetic.customer.0008@bookstore.test
```

## Pipeline CI/CD

En construcción. El diseño del pipeline, las pruebas y la estrategia de
despliegue se documentan en esta sección a medida que se implementan.
