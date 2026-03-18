# Template Conventions by Framework

Framework-specific guide for detecting codebase conventions before scaffolding. For each framework: what to search for, what patterns to detect, and what conventions to follow when generating.

---

## Next.js

### Determine Router Type First

This is the most critical detection step. Everything else follows from it.

```
Glob: app/**/page.tsx     -> App Router
Glob: pages/**/*.tsx      -> Pages Router
```

If both exist, the project may be mid-migration. Ask the user which to target.

### App Router Conventions

**What to Glob for:**
- `app/**/page.tsx` — page components
- `app/**/layout.tsx` — layout wrappers
- `app/**/loading.tsx` — loading UI (if project uses them)
- `app/**/error.tsx` — error boundaries (if project uses them)
- `app/**/not-found.tsx` — 404 handling
- `app/api/**/route.ts` — API route handlers
- `middleware.ts` — edge middleware at project root

**Patterns to Detect:**
- Server Components vs Client Components: Check for `"use client"` directives. Default is server component in App Router. Detect when the project adds the directive and why.
- Data fetching: Direct `async` components with `fetch`, or server actions, or a data layer abstraction.
- Metadata: `export const metadata` static objects vs `generateMetadata` async functions.
- Route groups: `(group)` directories for layout organization without URL impact.
- Parallel routes: `@slot` directories for simultaneous route rendering.
- Dynamic routes: `[param]` vs `[...catchAll]` vs `[[...optional]]` naming.

**Conventions to Follow:**
- Place `page.tsx` at the correct route depth
- Include `layout.tsx` only if the route needs its own layout (check siblings)
- Match the project's data fetching pattern exactly
- Use the same metadata export style as other pages
- Respect `"use client"` boundary — keep it as low in the tree as possible

### Pages Router Conventions

**What to Glob for:**
- `pages/**/*.tsx` — page components
- `pages/_app.tsx` — app wrapper
- `pages/_document.tsx` — HTML document customization
- `pages/api/**/*.ts` — API routes

**Patterns to Detect:**
- Data fetching: `getServerSideProps` vs `getStaticProps` vs `getStaticPaths` — which do existing pages use?
- API routes: Handler signature, response format, middleware wrapping
- Custom `_app.tsx` providers and wrappers

**Conventions to Follow:**
- File name = route path (kebab-case is standard)
- Match the dominant data fetching method
- Follow the same prop drilling or state hydration pattern

---

## React (Standalone)

### What to Glob for

```
src/components/**/*.tsx        — component files
src/components/**/index.ts     — barrel exports
src/hooks/**/*.ts              — custom hooks
src/context/**/*.tsx           — context providers
src/styles/**                  — global styles
*.stories.tsx                  — Storybook files
```

### Patterns to Detect

**Component Structure:**
- Single file vs directory per component (`Button.tsx` vs `Button/Button.tsx` with index)
- Props definition: inline `{ prop: type }` vs separate `interface ButtonProps` vs `type ButtonProps`
- Children handling: `PropsWithChildren`, explicit `children: ReactNode`, or no children
- Ref forwarding: Does the project use `forwardRef` on leaf components?

**Hook Patterns:**
- Custom hook naming: `useXxx` convention (check for consistency)
- Hook return types: tuple `[value, setter]` vs object `{ value, setValue }`
- Dependency arrays: strict exhaustive deps or intentional omissions with ESLint comments

**Context Patterns:**
- Provider + hook pattern: `XxxProvider` component + `useXxx` hook
- Context splitting: separate contexts for state and dispatch, or combined
- Default values: `null` with runtime check vs meaningful defaults

**Styling Approach:**
- CSS Modules: `*.module.css` or `*.module.scss` files alongside components
- Tailwind: `className` strings with Tailwind utilities, `cn()` or `clsx()` helper
- Styled-components/Emotion: `styled.div` or `css` prop usage
- Vanilla CSS: global stylesheets with BEM or other naming

**Conventions to Follow:**
- Match the exact component directory structure
- Use the same props definition pattern
- Follow the project's styling approach without introducing alternatives
- If the project uses a component library (Radix, Shadcn, MUI), scaffold using its primitives

---

## Express / Fastify

### What to Glob for

```
src/routes/**/*.ts             — route definitions
src/controllers/**/*.ts        — controller logic (if separated from routes)
src/middleware/**/*.ts          — middleware functions
src/validators/**/*.ts         — request validation schemas
src/services/**/*.ts           — business logic layer
src/types/**/*.ts              — request/response type definitions
```

### Patterns to Detect

**Route Organization:**
- Flat routes: all route files in `src/routes/`
- Nested routes: `src/routes/users/`, `src/routes/orders/`
- Controller pattern: routes delegate to controller classes/functions
- Route registration: manual `app.use()`, auto-discovery, or decorator-based

**Middleware Patterns:**
- Authentication: where and how auth middleware is applied (per-route, per-router, global)
- Validation: Zod/Joi/Yup middleware wrapping, or manual validation in handler
- Error handling: centralized error handler, custom error classes, error response format
- Logging: request logging middleware, correlation IDs

**Express-Specific:**
- Middleware signature: `(req, res, next)` with typed `Request<Params, ResBody, ReqBody, Query>`
- Error middleware: `(err, req, res, next)` four-argument signature
- Router creation: `express.Router()` patterns and mounting

**Fastify-Specific:**
- Plugin system: `fastify.register()` for route encapsulation
- Schema validation: Fastify's built-in JSON Schema or TypeBox
- Decorators: `fastify.decorate()` for shared utilities
- Hooks: `onRequest`, `preHandler`, `onSend` lifecycle hooks

**Conventions to Follow:**
- Match the route file structure exactly (flat vs nested)
- Use the same validation library and pattern
- Follow the existing response envelope format
- Include the same middleware chain that similar routes use
- Register routes in the same way as existing routes

---

## Vue 3

### What to Glob for

```
src/components/**/*.vue        — single-file components
src/composables/**/*.ts        — composable functions (Vue's "hooks")
src/views/**/*.vue             — page/view components
src/stores/**/*.ts             — Pinia stores
src/router/**/*.ts             — route definitions
```

### Patterns to Detect

**Component Structure:**
- `<script setup>` (modern) vs `<script>` with `defineComponent` (traditional)
- TypeScript usage: `<script setup lang="ts">`
- Prop definitions: `defineProps<{ ... }>()` with TypeScript vs `defineProps({ ... })` with runtime validation
- Emit definitions: `defineEmits<{ ... }>()` typed vs `defineEmits(['event'])`

**Composable Patterns:**
- Naming: `useXxx` convention matching React hooks naming
- Return type: object with reactive refs and methods
- Lifecycle hooks: `onMounted`, `onUnmounted` usage within composables
- Dependency injection: `inject`/`provide` patterns

**State Management:**
- Pinia stores: Setup stores (function) vs Option stores (object)
- Store organization: one file per store, typed getters, actions
- Composable-based state: shared state via composables without Pinia

**Styling:**
- `<style scoped>` — scoped CSS (most common)
- `<style module>` — CSS Modules within SFCs
- Tailwind in templates
- Preprocessor: `<style lang="scss">` or `<style lang="less">`

**Conventions to Follow:**
- Match `<script setup>` vs traditional `defineComponent` exactly
- Use the same prop/emit definition style
- Follow the project's composable return patterns
- Place components in the correct directory (components vs views)
- Match the SFC section ordering (`<script>`, `<template>`, `<style>` order varies by project)

---

## Django

### What to Glob for

```
*/models.py or */models/*.py   — model definitions
*/views.py or */views/*.py     — view functions/classes
*/serializers.py               — DRF serializers
*/urls.py                      — URL configuration
*/admin.py                     — admin registration
*/tests/ or */tests.py         — test files
*/forms.py                     — form classes
*/signals.py                   — signal handlers
*/tasks.py                     — Celery tasks
*/management/commands/*.py     — management commands
```

### Patterns to Detect

**App Structure:**
- Flat: `models.py`, `views.py`, `urls.py` as single files
- Split: `models/` directory with `__init__.py` importing from sub-modules
- Detect by checking if existing apps use files or directories

**Model Patterns:**
- Abstract base models: `class TimeStampedModel(models.Model)` with `class Meta: abstract = True`
- Custom managers: `objects = CustomManager()`
- Field conventions: `created_at`/`updated_at` vs `date_created`/`date_modified`
- String representation: `__str__` method patterns

**View Patterns:**
- Function-based views (FBV) vs class-based views (CBV)
- Django REST Framework: `APIView` vs `ViewSet` vs `ModelViewSet`
- Permissions: per-view permission classes
- Serialization: DRF serializers vs manual serialization

**URL Patterns:**
- `path()` vs `re_path()` usage
- Namespace conventions
- API versioning: `/api/v1/` prefix pattern
- Router registration for ViewSets

**Test Patterns:**
- `TestCase` vs `APITestCase` vs `pytest-django`
- Factory libraries: `factory_boy`, `model_bakery`, or manual fixtures
- Test organization: one test file per app vs split test files

**Conventions to Follow:**
- Match the app structure exactly (flat files vs directories)
- Use the same model base classes and field patterns
- Follow the dominant view pattern (FBV vs CBV)
- Register URLs in the same style as existing apps
- Include admin registration if other models have it
- Match the test framework and factory pattern

---

## Go

### What to Glob for

```
**/*.go                        — all Go files
**/handler*.go                 — HTTP handlers
**/service*.go                 — service layer
**/repository*.go              — data access layer
**/model*.go or **/types*.go   — type definitions
**/*_test.go                   — test files
cmd/*/main.go                  — entry points
internal/**/*.go               — internal packages
pkg/**/*.go                    — public packages
```

### Patterns to Detect

**Package Layout:**
- Standard layout: `cmd/`, `internal/`, `pkg/` separation
- Flat layout: everything in root or minimal packages
- Domain-driven: packages named by domain concept (`user/`, `order/`)

**Interface Patterns:**
- Interface definition location: same package as implementation, or separate `ports`/`interfaces` package
- Interface naming: `Reader`, `UserService`, `Repository` (Go convention: single-method interfaces named by method)
- Accept interfaces, return structs pattern
- Mock generation: `mockgen`, `moq`, `counterfeiter`, or hand-written mocks

**Handler Patterns:**
- Standard library `net/http`: `http.HandlerFunc` signature
- Chi router: `r.Get("/path", handler)` pattern
- Gin: `c *gin.Context` parameter
- Echo: `c echo.Context` parameter
- Fiber: `c *fiber.Ctx` parameter

**Error Handling:**
- Sentinel errors: `var ErrNotFound = errors.New("not found")`
- Custom error types: `type AppError struct { ... }`
- Error wrapping: `fmt.Errorf("context: %w", err)`
- Error response format: how errors are returned in HTTP responses

**Dependency Injection:**
- Constructor injection: `NewUserService(repo UserRepository) *UserService`
- Wire/fx: automatic DI via code generation
- Manual wiring: `main.go` creates and connects dependencies

**Conventions to Follow:**
- Match the package layout exactly
- Follow the same interface patterns (location, naming)
- Use the same HTTP framework and handler signature
- Match error handling patterns (sentinel vs custom types)
- Follow constructor naming: `New{Type}` convention
- Test files must be in the same package: `{file}_test.go`
- Match the project's approach to table-driven tests vs individual test functions

---

## Cross-Framework Detection Tips

Regardless of framework, always check these project-level conventions:

1. **Linter configuration**: `.eslintrc`, `biome.json`, `golangci-lint.yml` — these encode naming and style rules
2. **Formatter configuration**: `.prettierrc`, `gofmt`/`goimports`, `black`/`ruff` — these dictate formatting
3. **Git hooks**: `.husky/`, `.pre-commit-config.yaml` — these reveal required checks
4. **CI configuration**: `.github/workflows/`, `Jenkinsfile` — these reveal required test and lint passes
5. **Editor configuration**: `.editorconfig`, `.vscode/settings.json` — these reveal team preferences
6. **Package manager**: `package-lock.json` vs `yarn.lock` vs `pnpm-lock.yaml` — use the correct one for install commands
