# Browser Testing Patterns with Playwright

Patterns for verifying product behavior through browser automation. Each pattern includes the scenario, when to use it, a code example, and common pitfalls.

All examples use TypeScript with `@playwright/test`.

---

## 1. Page Navigation

**When to use:** Verifying that routes load correctly, redirects work, and page content matches expectations. This is the foundation of every browser verification.

**Common pitfalls:**
- Checking the URL before navigation completes, causing flaky assertions.
- Not waiting for the page to fully hydrate in SPAs, so content checks fail on first render.

```typescript
import { test, expect } from '@playwright/test'

test('navigates to the product page and displays correct content', async ({ page }) => {
  // Navigate and wait for the page to fully load
  await page.goto('http://localhost:3000/products/42')
  await page.waitForLoadState('networkidle')

  // Verify the URL is correct (useful for redirect verification)
  expect(page.url()).toContain('/products/42')

  // Verify the page title
  await expect(page).toHaveTitle(/Product Details/)

  // Verify key content is visible
  await expect(page.locator('h1')).toContainText('Widget Pro')
  await expect(page.locator('[data-testid="price"]')).toContainText('$29.99')
})

test('redirects unauthenticated users to login', async ({ page }) => {
  await page.goto('http://localhost:3000/dashboard')

  // Wait for the redirect to complete
  await page.waitForURL('**/login**')
  expect(page.url()).toContain('/login')

  // Verify the login page rendered
  await expect(page.locator('form')).toBeVisible()
})
```

---

## 2. Form Submission

**When to use:** Verifying that forms accept input, validate correctly, submit data to the backend, and display appropriate success or error feedback.

**Common pitfalls:**
- Clicking submit before all fields are filled (race condition with autofill or slow rendering).
- Not verifying the actual outcome (checking for a success toast but not that the data persisted).
- Using `page.type()` instead of `page.fill()` — `fill()` clears the field first, which is usually what you want.

```typescript
test('submits the contact form successfully', async ({ page }) => {
  await page.goto('http://localhost:3000/contact')

  // Fill form fields
  await page.fill('[name="name"]', 'Jane Doe')
  await page.fill('[name="email"]', 'jane@example.com')
  await page.fill('[name="message"]', 'I have a question about your product.')

  // Submit the form
  await page.click('button[type="submit"]')

  // Verify success feedback
  await expect(page.locator('[data-testid="success-message"]')).toBeVisible()
  await expect(page.locator('[data-testid="success-message"]')).toContainText(
    'Message sent'
  )
})

test('displays validation errors for invalid input', async ({ page }) => {
  await page.goto('http://localhost:3000/contact')

  // Submit with empty required fields
  await page.click('button[type="submit"]')

  // Verify validation messages appear
  await expect(page.locator('[data-testid="error-name"]')).toContainText(
    'Name is required'
  )
  await expect(page.locator('[data-testid="error-email"]')).toContainText(
    'Email is required'
  )

  // Fill with invalid email
  await page.fill('[name="email"]', 'not-an-email')
  await page.click('button[type="submit"]')
  await expect(page.locator('[data-testid="error-email"]')).toContainText(
    'Enter a valid email'
  )
})
```

---

## 3. Authentication

**When to use:** Verifying login, logout, session persistence, and protected route access. Authentication is a critical path — bugs here block all other verification.

**Common pitfalls:**
- Logging in before every test instead of reusing auth state (slow test suite).
- Not clearing cookies/storage between tests, causing state leakage.
- Checking for redirect before the auth state is fully set in the browser.

```typescript
test('logs in with valid credentials', async ({ page }) => {
  await page.goto('http://localhost:3000/login')

  await page.fill('[name="email"]', 'user@example.com')
  await page.fill('[name="password"]', 'correct-password')
  await page.click('button[type="submit"]')

  // Wait for navigation to the authenticated area
  await page.waitForURL('**/dashboard')

  // Verify the user identity is displayed
  await expect(page.locator('[data-testid="user-name"]')).toContainText(
    'user@example.com'
  )
})

test('rejects invalid credentials with a generic error', async ({ page }) => {
  await page.goto('http://localhost:3000/login')

  await page.fill('[name="email"]', 'user@example.com')
  await page.fill('[name="password"]', 'wrong-password')
  await page.click('button[type="submit"]')

  // Verify error message is generic (no information leakage)
  await expect(page.locator('[data-testid="login-error"]')).toContainText(
    'Invalid credentials'
  )

  // Verify we are still on the login page
  expect(page.url()).toContain('/login')
})

test('persists session across page reloads', async ({ page }) => {
  // Log in first
  await page.goto('http://localhost:3000/login')
  await page.fill('[name="email"]', 'user@example.com')
  await page.fill('[name="password"]', 'correct-password')
  await page.click('button[type="submit"]')
  await page.waitForURL('**/dashboard')

  // Reload the page
  await page.reload()
  await page.waitForLoadState('networkidle')

  // Verify still authenticated
  await expect(page.locator('[data-testid="user-name"]')).toBeVisible()
})

test('logout invalidates session', async ({ page }) => {
  // Log in
  await page.goto('http://localhost:3000/login')
  await page.fill('[name="email"]', 'user@example.com')
  await page.fill('[name="password"]', 'correct-password')
  await page.click('button[type="submit"]')
  await page.waitForURL('**/dashboard')

  // Log out
  await page.click('[data-testid="logout-button"]')
  await page.waitForURL('**/login')

  // Verify accessing protected route redirects to login
  await page.goto('http://localhost:3000/dashboard')
  await page.waitForURL('**/login')
})
```

**Reusing auth state across tests** (for efficiency):

```typescript
// auth.setup.ts — run once, save state for other tests
import { test as setup } from '@playwright/test'

setup('authenticate', async ({ page }) => {
  await page.goto('http://localhost:3000/login')
  await page.fill('[name="email"]', 'user@example.com')
  await page.fill('[name="password"]', 'correct-password')
  await page.click('button[type="submit"]')
  await page.waitForURL('**/dashboard')

  // Save signed-in state to a file
  await page.context().storageState({ path: '.auth/user.json' })
})
```

```typescript
// playwright.config.ts — use saved state in test projects
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'authenticated',
      use: { storageState: '.auth/user.json' },
      dependencies: ['setup'],
    },
  ],
})
```

---

## 4. Async Operations

**When to use:** Verifying behavior that depends on API responses, WebSocket messages, background processing, or any operation that does not complete synchronously.

**Common pitfalls:**
- Using `page.waitForTimeout()` (fixed sleep) instead of explicit waits. This is the number one cause of flaky tests.
- Not handling the case where the async operation fails. Your test hangs instead of reporting a clear failure.
- Checking for content before the API response arrives.

```typescript
test('loads product list from API', async ({ page }) => {
  await page.goto('http://localhost:3000/products')

  // Wait for the API response that populates the list
  await page.waitForResponse(
    (response) =>
      response.url().includes('/api/products') && response.status() === 200
  )

  // Now verify the content that depends on the API data
  const items = page.locator('[data-testid="product-item"]')
  await expect(items).toHaveCount(10)
})

test('shows loading indicator during fetch', async ({ page }) => {
  // Slow down the API response to observe loading state
  await page.route('**/api/products', async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 1000))
    await route.continue()
  })

  await page.goto('http://localhost:3000/products')

  // Verify loading indicator appears
  await expect(page.locator('[data-testid="loading-spinner"]')).toBeVisible()

  // Wait for loading to complete
  await expect(page.locator('[data-testid="loading-spinner"]')).toBeHidden()

  // Verify content replaced the loading indicator
  await expect(page.locator('[data-testid="product-item"]').first()).toBeVisible()
})

test('handles search with debounced input', async ({ page }) => {
  await page.goto('http://localhost:3000/products')

  // Intercept the search API call
  const searchResponse = page.waitForResponse(
    (response) => response.url().includes('/api/products?q=widget')
  )

  // Type in the search box
  await page.fill('[data-testid="search-input"]', 'widget')

  // Wait for the debounced API call to complete
  await searchResponse

  // Verify filtered results
  await expect(page.locator('[data-testid="product-item"]')).toHaveCount(3)
})
```

---

## 5. Error States

**When to use:** Verifying that the application handles failures gracefully. Users should see helpful messages, not blank screens or raw stack traces.

**Common pitfalls:**
- Only testing the happy path. Errors are where users lose trust.
- Not simulating real failure modes (network down, 500 responses, malformed data).
- Forgetting to verify that error states are recoverable (user can retry or navigate away).

```typescript
test('displays error message when API fails', async ({ page }) => {
  // Simulate a server error
  await page.route('**/api/products', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ error: 'Internal server error' }),
    })
  )

  await page.goto('http://localhost:3000/products')

  // Verify user-friendly error message (not a raw error)
  await expect(page.locator('[data-testid="error-message"]')).toContainText(
    'Something went wrong'
  )

  // Verify retry button is available
  await expect(page.locator('[data-testid="retry-button"]')).toBeVisible()
})

test('recovers from network failure on retry', async ({ page }) => {
  let requestCount = 0

  // First request fails, second succeeds
  await page.route('**/api/products', (route) => {
    requestCount++
    if (requestCount === 1) {
      return route.abort('connectionrefused')
    }
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([{ id: 1, name: 'Widget' }]),
    })
  })

  await page.goto('http://localhost:3000/products')

  // Verify error state
  await expect(page.locator('[data-testid="error-message"]')).toBeVisible()

  // Click retry
  await page.click('[data-testid="retry-button"]')

  // Verify recovery
  await expect(page.locator('[data-testid="error-message"]')).toBeHidden()
  await expect(page.locator('[data-testid="product-item"]')).toHaveCount(1)
})

test('shows validation errors inline on form fields', async ({ page }) => {
  // Simulate a 422 validation error from the server
  await page.route('**/api/products', (route) => {
    if (route.request().method() === 'POST') {
      return route.fulfill({
        status: 422,
        contentType: 'application/json',
        body: JSON.stringify({
          errors: {
            name: 'Name must be at least 3 characters',
            price: 'Price must be a positive number',
          },
        }),
      })
    }
    return route.continue()
  })

  await page.goto('http://localhost:3000/products/new')
  await page.fill('[name="name"]', 'Wi')
  await page.fill('[name="price"]', '-5')
  await page.click('button[type="submit"]')

  // Verify inline field errors from server
  await expect(page.locator('[data-testid="error-name"]')).toContainText(
    'at least 3 characters'
  )
  await expect(page.locator('[data-testid="error-price"]')).toContainText(
    'positive number'
  )
})
```

---

## 6. Responsive Testing

**When to use:** Verifying that the UI renders and functions correctly across different screen sizes. Critical for any user-facing feature.

**Common pitfalls:**
- Only testing desktop. Mobile is often where layout breaks.
- Setting viewport size but not verifying that interactive elements are still reachable (hidden behind a hamburger menu, off-screen).
- Not testing touch interactions on mobile viewports (tap targets too small, hover-only interactions).

```typescript
const viewports = [
  { name: 'mobile', width: 375, height: 812 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'desktop', width: 1280, height: 720 },
]

for (const viewport of viewports) {
  test(`renders navigation correctly on ${viewport.name}`, async ({ page }) => {
    await page.setViewportSize({
      width: viewport.width,
      height: viewport.height,
    })
    await page.goto('http://localhost:3000')

    if (viewport.width < 768) {
      // Mobile: hamburger menu should be visible
      await expect(page.locator('[data-testid="hamburger-menu"]')).toBeVisible()
      await expect(page.locator('[data-testid="desktop-nav"]')).toBeHidden()

      // Verify the menu opens and contains navigation links
      await page.click('[data-testid="hamburger-menu"]')
      await expect(page.locator('[data-testid="mobile-nav"]')).toBeVisible()
      await expect(page.locator('[data-testid="mobile-nav"] a')).toHaveCount(5)
    } else {
      // Desktop/tablet: full navigation visible
      await expect(page.locator('[data-testid="desktop-nav"]')).toBeVisible()
      await expect(
        page.locator('[data-testid="hamburger-menu"]')
      ).toBeHidden()
    }
  })
}

test('data table scrolls horizontally on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.goto('http://localhost:3000/reports')

  const table = page.locator('[data-testid="data-table"]')
  await expect(table).toBeVisible()

  // Verify the table container is scrollable
  const scrollWidth = await table.evaluate(
    (el) => el.scrollWidth > el.clientWidth
  )
  expect(scrollWidth).toBe(true)
})
```

---

## 7. Screenshot Comparison

**When to use:** Verifying visual appearance when CSS changes, layout updates, or component redesigns are involved. Screenshots catch visual regressions that DOM-level assertions miss.

**Common pitfalls:**
- Screenshot tests are brittle. Dynamic content (timestamps, avatars, random data) causes false failures. Mask or freeze dynamic elements.
- Different OS font rendering produces different baselines. Run screenshot tests in CI with a consistent environment (Docker).
- Large full-page screenshots are hard to diff. Prefer component-level screenshots.

```typescript
test('product card matches visual baseline', async ({ page }) => {
  await page.goto('http://localhost:3000/products')
  await page.waitForLoadState('networkidle')

  // Screenshot a specific component, not the full page
  const productCard = page.locator('[data-testid="product-card"]').first()
  await expect(productCard).toHaveScreenshot('product-card.png')
})

test('captures full page screenshot for visual review', async ({ page }) => {
  // Freeze dynamic content to avoid false failures
  await page.route('**/api/products', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 1, name: 'Widget', price: 9.99 },
        { id: 2, name: 'Gadget', price: 19.99 },
      ]),
    })
  )

  await page.goto('http://localhost:3000/products')
  await page.waitForLoadState('networkidle')

  // Mask elements with dynamic content
  await expect(page).toHaveScreenshot('products-page.png', {
    mask: [page.locator('[data-testid="timestamp"]')],
    maxDiffPixelRatio: 0.01,
  })
})

test('captures screenshots at multiple viewports', async ({ page }) => {
  const sizes = [
    { width: 375, height: 812, name: 'mobile' },
    { width: 1280, height: 720, name: 'desktop' },
  ]

  for (const size of sizes) {
    await page.setViewportSize({ width: size.width, height: size.height })
    await page.goto('http://localhost:3000')
    await page.waitForLoadState('networkidle')

    await expect(page).toHaveScreenshot(`homepage-${size.name}.png`, {
      fullPage: true,
      maxDiffPixelRatio: 0.01,
    })
  }
})
```

**Updating baselines** when intentional changes are made:

```bash
# Regenerate baseline screenshots after an intentional visual change
npx playwright test --update-snapshots

# Review the updated screenshots in the snapshots directory
# Commit the new baselines alongside the code change
```

---

## General Tips

- **Use `data-testid` attributes** for selectors. They survive refactoring better than CSS classes or DOM structure.
- **Avoid `page.waitForTimeout()`** in all cases. Use `waitForSelector`, `waitForURL`, `waitForResponse`, or `waitForLoadState` instead.
- **Isolate tests** by using a fresh browser context or clearing state between tests. Shared state between tests is the top cause of flaky suites.
- **Run tests in headed mode** during development (`npx playwright test --headed`) to see what the browser is doing.
- **Use trace viewer** for debugging failures: `npx playwright test --trace on`, then `npx playwright show-trace trace.zip`.
- **Parallelize carefully** — tests that share database state or server-side resources may conflict when run in parallel.
