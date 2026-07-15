import { FastifyInstance } from 'fastify'
import { randomUUID } from 'crypto'
import { requireApiKey } from '../plugins/auth'

function generateTrackingCode(): string {
  return 'GL-' + Math.random().toString(36).substring(2, 10).toUpperCase()
}

const STATUSES = ['CREATED', 'IN_TRANSIT', 'DELIVERED']

export async function parcelRoutes(app: FastifyInstance) {
  app.post('/', {
    preHandler: requireApiKey,
    schema: {
      body: {
        type: 'object',
        required: ['sender', 'recipient_email', 'destination_lat', 'destination_lng'],
        properties: {
          sender: { type: 'string', minLength: 1, maxLength: 200 },
          recipient_email: { type: 'string', format: 'email' },
          destination_lat: { type: 'number', minimum: -90, maximum: 90 },
          destination_lng: { type: 'number', minimum: -180, maximum: 180 }
        }
      }
    }
  }, async (request, reply) => {
    const { sender, recipient_email, destination_lat, destination_lng } = request.body as {
      sender: string
      recipient_email: string
      destination_lat: number
      destination_lng: number
    }

    const parcel = await app.prisma.parcel.create({
      data: {
        id: randomUUID(),
        tracking_code: generateTrackingCode(),
        sender,
        recipient_email,
        destination_lat,
        destination_lng,
        status: 'CREATED',
        events: {
          create: { id: randomUUID(), status: 'CREATED', message: 'Colis créé' }
        }
      }
    })

    return reply.status(201).send(parcel)
  })

  app.get('/', async (_request, reply) => {
    // Dashboard public : pas de PII (sender/recipient_email) dans la liste en masse
    const parcels = await app.prisma.parcel.findMany({
      orderBy: { created_at: 'desc' },
      select: {
        id: true,
        tracking_code: true,
        destination_lat: true,
        destination_lng: true,
        status: true,
        created_at: true
      }
    })

    const positions: Record<string, { lat: number; lng: number; ts: string; driver_id: string }> = {}
    try {
      const keys = await app.redis.keys('driver:*:pos')
      for (const key of keys) {
        const raw = await app.redis.get(key)
        if (!raw) continue
        const pos = JSON.parse(raw) as { lat: number; lng: number; ts: string; parcel_id: string }
        positions[pos.parcel_id] = { lat: pos.lat, lng: pos.lng, ts: pos.ts, driver_id: key.split(':')[1] }
      }
    } catch {
      // Redis unavailable — no position data
    }

    return reply.send(parcels.map((p) => ({ ...p, position: positions[p.id] ?? null })))
  })

  app.get('/:trackingCode', async (request, reply) => {
    const { trackingCode } = request.params as { trackingCode: string }
    const parcel = await app.prisma.parcel.findUnique({
      where: { tracking_code: trackingCode },
      include: { events: { orderBy: { timestamp: 'asc' } } }
    })
    if (!parcel) return reply.status(404).send({ error: 'Parcel not found' })
    return parcel
  })

  app.patch('/:id/status', {
    preHandler: requireApiKey,
    schema: {
      body: {
        type: 'object',
        required: ['status'],
        properties: {
          status: { type: 'string', enum: STATUSES }
        }
      }
    }
  }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const { status } = request.body as { status: string }

    const existing = await app.prisma.parcel.findUnique({ where: { id } })
    if (!existing) return reply.status(404).send({ error: 'Parcel not found' })

    const parcel = await app.prisma.parcel.update({
      where: { id },
      data: {
        status,
        events: {
          create: { id: randomUUID(), status, message: `Statut mis à jour : ${status}` }
        }
      }
    })
    return parcel
  })

  app.get('/:trackingCode/position', async (request, reply) => {
    const { trackingCode } = request.params as { trackingCode: string }

    const parcel = await app.prisma.parcel.findUnique({ where: { tracking_code: trackingCode } })
    if (!parcel) return reply.status(404).send({ error: 'Parcel not found' })

    try {
      const keys = await app.redis.keys('driver:*:pos')
      for (const key of keys) {
        const raw = await app.redis.get(key)
        if (!raw) continue
        const pos = JSON.parse(raw) as { lat: number; lng: number; ts: string; parcel_id: string }
        if (pos.parcel_id === parcel.id) {
          const driver_id = key.split(':')[1]
          return { lat: pos.lat, lng: pos.lng, ts: pos.ts, driver_id }
        }
      }
    } catch {
      // Redis unavailable — no position data
    }

    return reply.status(204).send()
  })
}
