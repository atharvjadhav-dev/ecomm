import medusaError from "../medusa-error.ts"
import { isEmpty, isArray, isObject } from "../isEmpty.ts"

function assertEqual(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) {
    throw new Error(
      `Assertion failed [${label}]: expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`
    )
  }
}

function assertThrows(fn: () => unknown, expectedMessage: string, label: string) {
  let threw = false
  try {
    fn()
  } catch (err) {
    threw = true
    const message = err instanceof Error ? err.message : String(err)
    if (message !== expectedMessage) {
      throw new Error(
        `Assertion failed [${label}]: expected error message ${JSON.stringify(expectedMessage)}, received ${JSON.stringify(message)}`
      )
    }
  }
  if (!threw) {
    throw new Error(`Assertion failed [${label}]: expected function to throw`)
  }
}

function runStorefrontTests() {
  // 1. medusaError: structured API error response
  assertThrows(
    () =>
      medusaError({
        config: {
          url: "/store/carts/cart_123",
          baseURL: "http://localhost:9000",
        },
        response: {
          data: { message: "cart not found" },
          status: 404,
          headers: {},
        },
      }),
    "Cart not found.",
    "medusaError formats object response data"
  )

  // 2. medusaError: plain string error response
  assertThrows(
    () =>
      medusaError({
        config: {
          url: "/store/regions",
          baseURL: "http://localhost:9000",
        },
        response: {
          data: "unauthorized publishable key",
          status: 401,
          headers: {},
        },
      }),
    "Unauthorized publishable key.",
    "medusaError formats string response data"
  )

  // 3. medusaError: network request failure
  assertThrows(
    () =>
      medusaError({
        request: "ECONNREFUSED",
      }),
    "No response received: ECONNREFUSED",
    "medusaError formats request failure"
  )

  // 4. medusaError: request setup error
  assertThrows(
    () =>
      medusaError({
        message: "Invalid URL",
      }),
    "Error setting up the request: Invalid URL",
    "medusaError formats setup failure"
  )

  // 5. isEmpty / isArray / isObject helpers
  assertEqual(isEmpty(null), true, "isEmpty(null)")
  assertEqual(isEmpty(undefined), true, "isEmpty(undefined)")
  assertEqual(isEmpty("   "), true, "isEmpty(whitespace)")
  assertEqual(isEmpty([]), true, "isEmpty([])")
  assertEqual(isEmpty({}), true, "isEmpty({})")
  assertEqual(isEmpty("dk"), false, "isEmpty('dk')")
  assertEqual(isEmpty(["item"]), false, "isEmpty(['item'])")
  assertEqual(isEmpty({ id: "cart_1" }), false, "isEmpty({ id: 'cart_1' })")
  assertEqual(isArray(["item"]), true, "isArray(['item'])")
  assertEqual(isObject({ id: "cart_1" }), true, "isObject({ id: 'cart_1' })")

  console.info("PASS: Storefront unit tests (6/6 assertions suites passed)")
}

runStorefrontTests()
