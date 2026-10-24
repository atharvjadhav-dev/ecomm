import { loadEnv, defineConfig } from '@medusajs/framework/utils'

loadEnv(process.env.NODE_ENV || 'development', process.cwd())

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL,
    databaseDriverOptions: {
      connection: {
        ssl:
          process.env.DATABASE_SSL === "true"
            ? {
                rejectUnauthorized:
                  process.env.DATABASE_SSL_REJECT_UNAUTHORIZED !== "false",
              }
            : false,
      },
    },
    redisUrl: process.env.REDIS_URL,

    cookieOptions: {
      sameSite: "lax",
      secure:
        process.env.COOKIE_SECURE !== undefined
          ? process.env.COOKIE_SECURE === "true"
          : process.env.NODE_ENV === "production",
      httpOnly: true,
    },

    http: {
      storeCors: process.env.STORE_CORS!,
      adminCors: process.env.ADMIN_CORS!,
      authCors: process.env.AUTH_CORS!,
      jwtSecret: process.env.JWT_SECRET,
      cookieSecret: process.env.COOKIE_SECRET,
    },
  },
  modules: [
    ...(process.env.REDIS_URL
      ? [
          {
            resolve: "@medusajs/medusa/event-bus-redis",
            options: {
              redisUrl: process.env.REDIS_URL,
            },
          },
          {
            resolve: "@medusajs/medusa/workflow-engine-redis",
            options: {
              redis: {
                redisUrl: process.env.REDIS_URL,
                url: process.env.REDIS_URL,
              },
            },
          },
        ]
      : []),
  ],
})
