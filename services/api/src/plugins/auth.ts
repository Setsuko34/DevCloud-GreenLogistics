import { FastifyReply, FastifyRequest } from 'fastify'

// ponytail: single static API key, per-route header check — swap for real
// user auth (JWT/OAuth) if this API ever gets multiple clients/roles.
export async function requireApiKey(request: FastifyRequest, reply: FastifyReply) {
  const key = request.headers['x-api-key']
  if (!key || key !== process.env.API_KEY) {
    return reply.status(401).send({ error: 'Unauthorized' })
  }
}
