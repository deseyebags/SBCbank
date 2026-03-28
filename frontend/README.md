# SBCbank Frontend

React + TypeScript + Vite frontend for local SBCbank development.

## Routes

- `/login`: login screen for admin or user
- `/admin`: admin-only operations view
- `/app`: user-only account view

Route access is protected by authenticated session state and backend authorization.

## Authentication

The frontend calls account-service auth endpoints:

- `POST /auth/login/admin`
- `POST /auth/login/user`
- `GET /auth/me`

Default local admin credentials:

- Username: `admin`
- Password: `admin123`

User login requires:

- Account ID
- Matching account email

## Development

```bash
npm install
npm run dev
```

## Validation

```bash
npm run lint
npm run build
```

## API Proxy

Vite dev server proxies requests to backend services through `/api/*` routes in `vite.config.ts`.
