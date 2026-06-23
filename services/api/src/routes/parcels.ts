import { FastifyInstance } from 'fastify'
import { randomUUID } from 'crypto'

function generateTrackingCode(): string {
  return 'GL-' + Math.random().toString(36).substring(2, 10).toUpperCase()
}

export async function parcelRoutes(app: FastifyInstance) {
  app.post('/', async (request, reply) => {
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

  app.get('/:id', async (request, reply) => {
    const { id } = request.params as { id: string }
    const parcel = await app.prisma.parcel.findUnique({
      where: { id },
      include: { events: { orderBy: { timestamp: 'asc' } } }
    })
    if (!parcel) return reply.status(404).send({ error: 'Parcel not found' })
    return parcel
  })
}
