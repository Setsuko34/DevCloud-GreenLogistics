import fp from 'fastify-plugin'
import { FastifyPluginAsync } from 'fastify'
import { PrismaClient } from '@prisma/client'

declare module 'fastify' {
  interface FastifyInstance {
    prisma: PrismaClient
  }
}

const prismaPlugin: FastifyPluginAsync = fp(async (app) => {
  const prisma = new PrismaClient()
  await prisma.$connect()
  app.decorate('prisma', prisma)
  app.addHook('onClose', async () => { await prisma.$disconnect() })
})

export default prismaPlugin
