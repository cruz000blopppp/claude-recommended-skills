# Scaffolding Decision Matrix

This matrix maps user intent to scaffold type, detection targets, generated output, and common pitfalls.

## How to Use This Matrix

1. Match the user's request to a **User Says** trigger phrase
2. Identify the **Scaffold Type**
3. Use **Files to Detect** to find existing conventions via Glob/Read
4. Generate all files listed in **Files to Generate** and **Companion Files**
5. Review **Common Pitfalls** before finalizing

---

## React Component

| Field | Details |
|---|---|
| **User Says** | "create a new component", "scaffold a widget", "new form component", "add a card component", "create a modal", "new layout component" |
| **Scaffold Type** | React functional component with props interface, hooks, and styling |
| **Files to Detect** | `src/components/**/*.tsx`, `src/components/**/index.ts`, `src/components/**/*.test.tsx`, `src/components/**/*.module.css`, `src/components/**/*.stories.tsx` |
| **Files to Generate** | `ComponentName.tsx` (component), `ComponentName.types.ts` (props/types if project separates types) |
| **Companion Files** | `ComponentName.test.tsx` (test stub), `ComponentName.module.css` or styled file (if project uses them), `ComponentName.stories.tsx` (if Storybook present), `index.ts` (barrel export — create or update) |
| **Common Pitfalls** | Generating default exports when project uses named exports. Missing `forwardRef` when component wraps native elements. Forgetting to update parent barrel file. Generating CSS Modules when project uses Tailwind (or vice versa). |

---

## Next.js Page / Route

| Field | Details |
|---|---|
| **User Says** | "create a new page", "add a new route", "scaffold a page", "new Next.js page", "add a dashboard page" |
| **Scaffold Type** | Next.js page component with data fetching, layout, loading, and error handling |
| **Files to Detect** | `app/**/page.tsx` or `pages/**/*.tsx` (determines App Router vs Pages Router), `app/**/layout.tsx`, `app/**/loading.tsx`, `app/**/error.tsx`, `app/**/not-found.tsx` |
| **Files to Generate** | `page.tsx` (App Router) or `PageName.tsx` (Pages Router), `layout.tsx` (if route needs its own layout) |
| **Companion Files** | `loading.tsx` (if project uses loading states), `error.tsx` (if project uses error boundaries), `not-found.tsx` (if appropriate), `page.test.tsx` (test stub), `opengraph-image.tsx` (if project generates OG images) |
| **Common Pitfalls** | Mixing App Router and Pages Router conventions. Generating `getServerSideProps` in an App Router project. Forgetting `"use client"` directive when component uses hooks. Not matching the project's metadata/SEO pattern. Placing files at wrong nesting depth in route hierarchy. |

---

## API Endpoint (Express / Fastify / Next.js)

| Field | Details |
|---|---|
| **User Says** | "create a new endpoint", "add a new API route", "scaffold a REST endpoint", "new CRUD endpoint", "add a new route handler" |
| **Scaffold Type** | Route handler with validation, error handling, and response formatting |
| **Files to Detect** | `src/routes/**/*.ts`, `src/controllers/**/*.ts`, `app/api/**/route.ts`, `src/middleware/**/*.ts`, `src/validators/**/*.ts` |
| **Files to Generate** | Route handler file (matching project's controller/route pattern), validation schema (Zod/Joi/Yup matching project's choice) |
| **Companion Files** | `*.test.ts` (integration test with supertest/inject), `*.types.ts` (request/response types), validation schema file (if project separates validation), middleware file (if endpoint needs specific middleware) |
| **Common Pitfalls** | Not matching the project's response envelope format (`{ data, error, meta }` vs raw). Forgetting authentication middleware that other routes use. Generating Express patterns in a Fastify project. Not registering the route in the router/app setup file. Missing rate limiting or other standard middleware. |

---

## Database Model + Migration

| Field | Details |
|---|---|
| **User Says** | "create a new model", "add a database table", "scaffold a migration", "new entity", "add a schema" |
| **Scaffold Type** | ORM model definition with migration, types, and optional seed data |
| **Files to Detect** | `src/models/**/*.ts`, `prisma/schema.prisma`, `src/entities/**/*.ts`, `drizzle/**/*.ts`, `migrations/**/*.ts`, `src/db/schema.ts` |
| **Files to Generate** | Model/entity definition (Prisma model, Drizzle schema, TypeORM entity, etc.), migration file (with timestamp prefix if project uses them) |
| **Companion Files** | `*.types.ts` (derived types if project separates them), seed file stub, repository/service file (if project uses repository pattern), validation schema matching model fields |
| **Common Pitfalls** | Using wrong ORM syntax (Prisma vs Drizzle vs TypeORM). Forgetting to add relations/foreign keys. Not matching the project's timestamp vs integer ID pattern. Missing indexes that similar models have. Generating migration without checking if model changes would conflict with existing migrations. Not updating the schema barrel file (e.g., `schema/index.ts`). |

---

## Service / Repository Class

| Field | Details |
|---|---|
| **User Says** | "set up a new service", "create a service class", "scaffold a repository", "new business logic layer", "add a service" |
| **Scaffold Type** | Service or repository class with interface, dependency injection, and error handling |
| **Files to Detect** | `src/services/**/*.ts`, `src/repositories/**/*.ts`, `src/interfaces/**/*.ts`, dependency injection container config |
| **Files to Generate** | Service/repository class with constructor injection matching project pattern, interface definition (if project uses them) |
| **Companion Files** | `*.test.ts` (unit test with mocked dependencies), `*.types.ts` (input/output DTOs), interface file (if project separates interfaces), DI container registration update |
| **Common Pitfalls** | Not matching existing dependency injection pattern (constructor injection vs module injection vs none). Generating a class when project uses functional patterns. Forgetting to register service in DI container. Missing error handling that other services implement (custom error classes, logging patterns). |

---

## CLI Command

| Field | Details |
|---|---|
| **User Says** | "add a CLI command", "scaffold a new command", "create a subcommand", "new CLI action" |
| **Scaffold Type** | CLI command with argument parsing, help text, and error handling |
| **Files to Detect** | `src/commands/**/*.ts`, `src/cli/**/*.ts`, `bin/**`, `package.json` (for `bin` field), commander/yargs/oclif config |
| **Files to Generate** | Command file matching framework pattern (Commander command, yargs module, oclif command class) |
| **Companion Files** | `*.test.ts` (test with mocked stdin/stdout), help text or man page (if project generates them), command registration/index update |
| **Common Pitfalls** | Not matching the CLI framework the project uses. Forgetting to register the command in the command index. Missing `--help` flag handling. Not matching existing error output format (colored output, exit codes). Generating interactive prompts without checking if project uses a prompt library. |

---

## Background Worker / Job

| Field | Details |
|---|---|
| **User Says** | "create a background job", "scaffold a worker", "new queue handler", "add a cron job", "create a task processor" |
| **Scaffold Type** | Job handler with queue integration, retry logic, and error handling |
| **Files to Detect** | `src/jobs/**/*.ts`, `src/workers/**/*.ts`, `src/queues/**/*.ts`, queue configuration files (BullMQ, Agenda, etc.) |
| **Files to Generate** | Job handler file with queue-specific patterns (processor function, job data types) |
| **Companion Files** | `*.test.ts` (test with mocked queue), job data types file, queue registration/configuration update, retry policy definition |
| **Common Pitfalls** | Not matching the queue framework (BullMQ vs Agenda vs custom). Missing retry/backoff configuration that other jobs use. Forgetting dead letter queue handling. Not including logging/tracing that other workers implement. Missing graceful shutdown handling. |

---

## Middleware

| Field | Details |
|---|---|
| **User Says** | "create middleware", "add a middleware", "scaffold an interceptor", "new request handler", "add a guard" |
| **Scaffold Type** | Middleware function with proper request/response typing and next() handling |
| **Files to Detect** | `src/middleware/**/*.ts`, `src/interceptors/**/*.ts`, `src/guards/**/*.ts`, middleware registration files |
| **Files to Generate** | Middleware function matching framework pattern (Express middleware, Fastify hook, NestJS guard/interceptor) |
| **Companion Files** | `*.test.ts` (test with mocked request/response), type definitions for extended request properties, middleware registration update |
| **Common Pitfalls** | Forgetting to call `next()` in all code paths. Not matching async error handling pattern (Express requires `next(error)`, Fastify uses async/await). Placing middleware in wrong order in the chain. Not extending request types when middleware adds properties. Missing the framework-specific middleware signature. |

---

## Hook / Utility Function

| Field | Details |
|---|---|
| **User Says** | "create a hook", "scaffold a utility", "new helper function", "add a custom hook", "create a util" |
| **Scaffold Type** | Reusable hook or utility with TypeScript generics and proper typing |
| **Files to Detect** | `src/hooks/**/*.ts`, `src/utils/**/*.ts`, `src/helpers/**/*.ts`, `src/lib/**/*.ts` |
| **Files to Generate** | Hook/utility function with full TypeScript typing, JSDoc comments matching project style |
| **Companion Files** | `*.test.ts` (unit test with edge cases), type exports (if project centralizes types), barrel file update |
| **Common Pitfalls** | Generating a React hook outside of a React project. Not using generics when the utility should be generic. Missing memoization patterns (`useMemo`, `useCallback`) that other hooks use. Forgetting cleanup in `useEffect` hooks. Not matching the project's approach to pure functions vs side effects. |

---

## Test Suite

| Field | Details |
|---|---|
| **User Says** | "create tests for", "scaffold test file", "add unit tests", "generate test suite", "stub out tests" |
| **Scaffold Type** | Test file with describe/it blocks, setup/teardown, and mock patterns |
| **Files to Detect** | `**/*.test.ts`, `**/*.spec.ts`, `**/__tests__/**`, `jest.config.*`, `vitest.config.*`, `playwright.config.*`, test utilities and fixtures |
| **Files to Generate** | Test file with structure matching project conventions (describe nesting, assertion style, mock setup) |
| **Companion Files** | Test fixtures/factories (if project uses them), mock files in `__mocks__/` (if needed), test utility helpers |
| **Common Pitfalls** | Using Jest syntax in a Vitest project (or vice versa). Not matching `describe`/`it` vs `test` convention. Forgetting test setup that other test files import (custom render, test utils). Missing `afterEach(cleanup)` when testing React components. Generating integration tests when unit tests were requested. Not matching the project's mock strategy (manual mocks vs auto-mocks vs dependency injection). |

---

## Quick Reference: Detection Glob Patterns

Use these patterns to quickly find existing conventions:

```
# React / Next.js components
src/components/**/*.tsx
app/**/page.tsx
pages/**/*.tsx

# API routes and handlers
src/routes/**/*.ts
src/controllers/**/*.ts
app/api/**/route.ts

# Models and database
src/models/**/*.ts
prisma/schema.prisma
src/entities/**/*.ts
drizzle/**/*.ts

# Services and business logic
src/services/**/*.ts
src/repositories/**/*.ts

# Tests
**/*.test.ts
**/*.test.tsx
**/*.spec.ts
**/__tests__/**

# Configuration and tooling
plopfile.*
.hygen/**
turbo/generators/**
```
